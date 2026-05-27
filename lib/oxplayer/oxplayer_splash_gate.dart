import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/oxplayer/oxplayer_session_refresh_coordinator.dart';
import 'package:fladder/oxplayer/oxplayer_session_recovery_navigation.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
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

/// Clears a half-finished Telegram sign-in and any saved Jellyfin/OX tokens so cold start
/// cannot open the home stack with [userProvider] set while TDLib or the API is unauthorized.
Future<void> oxplayerClearIncompleteLoginSession(dynamic ref) async {
  if (!OxplayerConfig.isEnabled) return;

  AccountModel? currentUser = ref.read(userProvider);
  currentUser ??= ref.read(sharedUtilityProvider).getActiveAccount();

  if (currentUser != null) {
    final zeroed = currentUser.copyWith(
      credentials: currentUser.credentials.copyWith(
        token: '',
        oxRefreshToken: '',
      ),
    );
    await ref.read(sharedUtilityProvider).addAccount(zeroed);
    await ref.read(sharedUtilityProvider).removeAccount(currentUser);
  }

  if (!kIsWeb) {
    try {
      final td = OxplayerTelegramTdSession(tdlib: OxplayerTelegramTdRuntime.facade);
      await td.initClient();
      await td.abandonStaleInteractiveAuthIfNeeded();
      await td.resetLocalSessionForQrLogin();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OX] oxplayerClearIncompleteLoginSession TDLib: $e');
      }
    }
  }

  ref.read(authProvider.notifier).clearAllProviders();
  oxplayerClearSessionEstablished();
  ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
      OxplayerBackgroundAuthStatus.idle;
  ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
}

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

    // Splash gate already rotated tokens; a second refresh invalidates in-flight API calls.
    if (oxplayerSessionEstablishedThisProcess) {
      ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.online;
      return;
    }

    ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.connecting;

    try {
      final result = await oxplayerWithExclusiveSessionRefresh(
        () => _oxplayerSplashSessionGateWithTimeout(ref),
      );
      _oxplayerApplyBackgroundAuthGateResult(ref, result);
    } catch (e) {
      _oxplayerApplyBackgroundAuthGateResult(
        ref,
        OxplayerSplashGateResult.needTelegramLogin,
        error: e,
      );
    }
  }
}

/// Saved Jellyfin access token is enough for cached UI; TDLib/WebApp re-auth is best-effort.
bool _oxplayerHasUsableJellyfinAccessToken(Ref ref) {
  final user = ref.read(userProvider);
  return user != null && user.credentials.token.trim().isNotEmpty;
}

void _oxplayerApplyBackgroundAuthGateResult(
  Ref ref,
  OxplayerSplashGateResult result, {
  Object? error,
}) {
  if (result == OxplayerSplashGateResult.proceedToDashboard) {
    ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.online;
    return;
  }

  // Do not keep the home stack "online" when Telegram re-auth failed but a stale token remains
  // (e.g. user closed the app during 2FA — API calls would 401 until recovery runs).
  if (_oxplayerHasUsableJellyfinAccessToken(ref) &&
      result != OxplayerSplashGateResult.needTelegramLogin) {
    if (kDebugMode) {
      debugPrint(
        '[OX] background session refresh: gate=$result with saved access token — status Online',
      );
    }
    ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.online;
    return;
  }

  if (error != null) {
    ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = error;
  }
  ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
      OxplayerBackgroundAuthStatus.error;
  if (OxplayerConfig.isEnabled) {
    unawaited(oxplayerClearIncompleteLoginSession(ref));
    final tg = ref.read(oxplayerTelegramSessionReadyProvider);
    oxplayerScheduleSessionRecoveryNavigation(
      ref,
      telegramTdlibAuthorized: tg,
    );
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

  final result = await oxplayerWithExclusiveSessionRefresh(
    () => _oxplayerSplashSessionGateWithTimeout(ref),
  );

  if (result == OxplayerSplashGateResult.proceedToDashboard) {
    oxplayerNoteSessionEstablished();
    ref.read(oxplayerBackgroundAuthErrorProvider.notifier).state = null;
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.online;
  }

  return result;
}

Future<OxplayerSplashGateResult> _oxplayerSplashSessionGateWithTimeout(dynamic ref) {
  return awaitFutureWithTimeout(
    _oxplayerRunSplashSessionGateImpl(ref),
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
      ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
          OxplayerBackgroundAuthStatus.online;
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
    if (await td.hasPartialInteractiveAuthorization()) {
      return OxplayerSplashGateResult.needTelegramLogin;
    }
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
        ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
            OxplayerBackgroundAuthStatus.online;
        return OxplayerSplashGateResult.proceedToDashboard;
      } catch (_) {}
    }

    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state = OxplayerBackgroundAuthStatus.refreshing;
    final exchanged = await td.authenticateWithOxApi(deviceName: deviceName);
    await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
    ref.read(lockScreenActiveProvider.notifier).update((s) => false);
    ref.read(oxplayerBackgroundAuthStatusProvider.notifier).state =
        OxplayerBackgroundAuthStatus.online;
    return OxplayerSplashGateResult.proceedToDashboard;
  } catch (_) {
    return OxplayerSplashGateResult.needTelegramLogin;
  }
}
