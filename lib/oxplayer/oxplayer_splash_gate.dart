import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/fladder_config.dart';

/// Result of [oxplayerRunSplashSessionGate] (native OX builds only).
enum OxplayerSplashGateResult {
  /// Fresh API session applied; safe to open the home stack.
  proceedToDashboard,

  /// Telegram or token exchange failed; send the user to `/ox-login`.
  needTelegramLogin,
}

/// Validates **Telegram (TDLib)** then obtains a **new API token** (`POST /auth/refresh` when possible,
/// otherwise WebApp initData + `POST /auth/telegram`) before the first Dashboard load.
///
/// Call only when `OxplayerConfig.isEnabled && !kIsWeb` and the user chose auto-login.
Future<OxplayerSplashGateResult> oxplayerRunSplashSessionGate(WidgetRef ref) async {
  if (!OxplayerConfig.isEnabled || kIsWeb) {
    return OxplayerSplashGateResult.proceedToDashboard;
  }

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

  try {
    final td = OxplayerTelegramTdSession();
    await OxplayerTelegramTdSession.initPlugin();
    await td.initClient();
    if (!await td.trySilentRestore()) {
      return OxplayerSplashGateResult.needTelegramLogin;
    }

    final app = ref.read(applicationInfoProvider);
    final deviceName = '${app.name} / ${defaultTargetPlatform.name}';
    final identity = await OxplayerTelegramTdSession.resolveDeviceIdentity(
      defaultDeviceName: deviceName,
    );

    final saved = ref.read(sharedUtilityProvider).getActiveAccount();
    final refresh = saved?.credentials.oxRefreshToken.trim() ?? '';

    if (refresh.isNotEmpty) {
      try {
        final exchanged = await OxplayerTelegramAuthClient(apiBase: api).refreshAccessToken(
          refreshToken: refresh,
          deviceId: identity.deviceId,
        );
        await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
        ref.read(lockScreenActiveProvider.notifier).update((s) => false);
        return OxplayerSplashGateResult.proceedToDashboard;
      } catch (_) {}
    }

    final exchanged = await td.authenticateWithOxApi(deviceName: deviceName);
    await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
    ref.read(lockScreenActiveProvider.notifier).update((s) => false);
    return OxplayerSplashGateResult.proceedToDashboard;
  } catch (_) {
    return OxplayerSplashGateResult.needTelegramLogin;
  }
}
