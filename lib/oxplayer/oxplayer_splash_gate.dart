import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/oxplayer/oxplayer_session_recovery_navigation.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Result of [oxplayerRunSplashSessionGate] (native OX builds only).
enum OxplayerSplashGateResult {
  /// Fresh API session applied; safe to open the home stack.
  proceedToDashboard,

  /// Telegram or token exchange failed; send the user to `/ox-login`.
  needTelegramLogin,
}

/// Failsafe only (no process kill). Hitting this usually means TDLib/HTTP is wedged; user can retry.
const Duration kOxplayerSplashSessionGateMaxWait = Duration(seconds: 90);

final oxplayerBackgroundSessionRefreshProvider = Provider<OxplayerBackgroundSessionRefresh>((ref) {
  return OxplayerBackgroundSessionRefresh(ref);
});

class OxplayerBackgroundSessionRefresh {
  OxplayerBackgroundSessionRefresh(this.ref);

  final Ref ref;
  Future<void>? _inFlight;

  Future<void> start() {
    final current = _inFlight;
    if (current != null) return current;

    final future = _run();
    _inFlight = future;
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<void> _run() async {
    if (!OxplayerConfig.isEnabled) {
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.online;
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.idle;
      return;
    }

    ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.connecting;

    try {
      final result = await _oxplayerRunSplashSessionGateImpl(ref).timeout(
        kOxplayerSplashSessionGateMaxWait,
      );
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          result == OxplayerSplashGateResult.proceedToDashboard
              ? OxplayerBackgroundAuthStatus.online
              : OxplayerBackgroundAuthStatus.error;
      if (result != OxplayerSplashGateResult.proceedToDashboard && OxplayerConfig.isEnabled) {
        final tg = ref.read(oxplayerTelegramSessionReadyProvider);
        oxplayerScheduleSessionRecoveryNavigation(
          ref,
          telegramTdlibAuthorized: tg,
        );
      }
    } catch (e) {
      ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = e;
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.error;
      if (OxplayerConfig.isEnabled) {
        final tg = ref.read(oxplayerTelegramSessionReadyProvider);
        oxplayerScheduleSessionRecoveryNavigation(
          ref,
          telegramTdlibAuthorized: tg,
        );
      }
    }
  }
}

/// Validates **Telegram (TDLib)** then obtains a **new API token** (`POST /auth/refresh` when possible,
/// otherwise WebApp initData + `POST /auth/telegram`) before the first Dashboard load.
///
/// Call only when `OxplayerConfig.isEnabled` and the user chose auto-login.
Future<OxplayerSplashGateResult> oxplayerRunSplashSessionGate(WidgetRef ref) async {
  if (!OxplayerConfig.isEnabled) {
    return OxplayerSplashGateResult.proceedToDashboard;
  }

  return _oxplayerRunSplashSessionGateImpl(ref).timeout(
    kOxplayerSplashSessionGateMaxWait,
    onTimeout: () {
      if (kDebugMode) {
        debugPrint(
          '[OX] oxplayerRunSplashSessionGate: exceeded $kOxplayerSplashSessionGateMaxWait',
        );
      }
      return OxplayerSplashGateResult.needTelegramLogin;
    },
  );
}

/// Prefer **`POST /auth/refresh` first** so returning from the Android back stack does not block on
/// TDLib ([ensureAuthorized] / 2FA / GetMe) when a refresh token is still valid.
Future<OxplayerSplashGateResult> _oxplayerRunSplashSessionGateImpl(dynamic ref) async {
  final api = OxplayerEnv.apiBaseUrl;
  final media = OxplayerEnv.effectiveMediaServerUrl;
  if (api == null || media == null) {
    return OxplayerSplashGateResult.needTelegramLogin;
  }
  FladderConfig.baseUrl = media;

  try {
    await ref.read(authProvider.notifier).initModel(clearUserState: false);
  } catch (_) {
    return OxplayerSplashGateResult.needTelegramLogin;
  }

  if (ref.read(authProvider).errorMessage != null) {
    return OxplayerSplashGateResult.needTelegramLogin;
  }

  final app = ref.read(applicationInfoProvider);
  final deviceName = '${app.name} / ${defaultTargetPlatform.name}';
  var saved = ref.read(sharedUtilityProvider).getActiveAccount();
  var refresh = saved?.credentials.oxRefreshToken.trim() ?? '';

  if (refresh.isNotEmpty) {
    try {
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.refreshing;
      final identity = await OxplayerTelegramTdSession.resolveDeviceIdentity(
        defaultDeviceName: deviceName,
      );
      final exchanged = await OxplayerTelegramAuthClient(apiBase: api).refreshAccessToken(
        refreshToken: refresh,
        deviceId: identity.deviceId,
      );
      await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
      ref.read(lockScreenActiveProvider.notifier).update((s) => false);
      return OxplayerSplashGateResult.proceedToDashboard;
    } catch (_) {
      // TDLib or initData exchange may still work.
    }
  }

  try {
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.connecting;
    final td = OxplayerTelegramTdSession();
    await OxplayerTelegramTdSession.initPlugin();
    await td.initClient();
    if (!await td.trySilentRestoreWithRestart()) {
      return OxplayerSplashGateResult.needTelegramLogin;
    }

    saved = ref.read(sharedUtilityProvider).getActiveAccount();
    refresh = saved?.credentials.oxRefreshToken.trim() ?? '';

    if (refresh.isNotEmpty) {
      try {
        ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.refreshing;
        final identity = await OxplayerTelegramTdSession.resolveDeviceIdentity(
          defaultDeviceName: deviceName,
        );
        final exchanged = await OxplayerTelegramAuthClient(apiBase: api).refreshAccessToken(
          refreshToken: refresh,
          deviceId: identity.deviceId,
        );
        await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
        ref.read(lockScreenActiveProvider.notifier).update((s) => false);
        return OxplayerSplashGateResult.proceedToDashboard;
      } catch (_) {}
    }

    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.refreshing;
    final exchanged = await td.authenticateWithOxApi(deviceName: deviceName);
    await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
    ref.read(lockScreenActiveProvider.notifier).update((s) => false);
    return OxplayerSplashGateResult.proceedToDashboard;
  } catch (_) {
    return OxplayerSplashGateResult.needTelegramLogin;
  }
}
