import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/oxplayer_session_recovery_navigation.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/application_info.dart';

Future<bool>? _oxJellyfinRefreshInFlight;

/// On **401**: Telegram must be authorized; then try **POST /auth/refresh** if a refresh token exists,
/// else exchange WebApp [initData] via TDLib (`POST /auth/telegram`).
Future<bool> oxplayerTryRefreshJellyfinSessionAfter401(Ref ref) {
  final existing = _oxJellyfinRefreshInFlight;
  if (existing != null) return existing;

  final run = _oxplayerDoJellyfinSessionRefresh(ref);
  _oxJellyfinRefreshInFlight = run;
  run.whenComplete(() {
    if (identical(_oxJellyfinRefreshInFlight, run)) {
      _oxJellyfinRefreshInFlight = null;
    }
  });
  return run;
}

Future<bool> _oxplayerDoJellyfinSessionRefresh(Ref ref) async {
  if (!OxplayerConfig.isEnabled || kIsWeb) return false;

  final authNotifier = ref.read(authProvider.notifier);
  if (authNotifier.oxplayerServerLoginModel == null) return false;

  final apiBase = OxplayerEnv.apiBaseUrl;
  if (apiBase == null) return false;

  var telegramTdlibSessionAuthorized = false;

  try {
    final td = OxplayerTelegramTdSession();
    await td.initClient();
    try {
      await td.td.ensureAuthorized();
    } on TdlibInteractiveLoginRequired catch (e, st) {
      log('OX 401 refresh: Telegram re-login required', error: e, stackTrace: st);
      oxplayerScheduleSessionRecoveryNavigation(
        ref,
        telegramTdlibAuthorized: false,
      );
      return false;
    }

    telegramTdlibSessionAuthorized = true;

    final app = ref.read(applicationInfoProvider);
    final deviceName = '${app.name} / ${defaultTargetPlatform.name}';
    final identity = await OxplayerTelegramTdSession.resolveDeviceIdentity(
      defaultDeviceName: deviceName,
    );

    final storedRefresh = ref.read(userProvider)?.credentials.oxRefreshToken.trim() ??
        ref.read(authProvider).serverLoginModel?.tempCredentials.oxRefreshToken.trim() ??
        '';

    if (storedRefresh.isNotEmpty) {
      try {
        final client = OxplayerTelegramAuthClient(apiBase: apiBase);
        final exchanged = await client.refreshAccessToken(
          refreshToken: storedRefresh,
          deviceId: identity.deviceId,
        );
        await authNotifier.applyOxplayerTelegramAuthResponse(exchanged);
        return true;
      } catch (e, st) {
        log(
          'OX 401 refresh: POST /auth/refresh failed, falling back to WebApp initData',
          error: e,
          stackTrace: st,
        );
      }
    }

    final exchanged = await td.authenticateWithOxApi(deviceName: deviceName);
    await authNotifier.applyOxplayerTelegramAuthResponse(exchanged);
    return true;
  } on TdlibInteractiveLoginRequired catch (e, st) {
    log('OX 401 refresh: Telegram re-login required', error: e, stackTrace: st);
    oxplayerScheduleSessionRecoveryNavigation(
      ref,
      telegramTdlibAuthorized: false,
    );
    return false;
  } on OxplayerTelegramAuthException catch (e, st) {
    log('OX 401 refresh: auth exchange failed', error: e, stackTrace: st);
    oxplayerScheduleSessionRecoveryNavigation(
      ref,
      telegramTdlibAuthorized: telegramTdlibSessionAuthorized,
    );
    return false;
  } catch (e, st) {
    log('OX 401 refresh failed', error: e, stackTrace: st);
    oxplayerScheduleSessionRecoveryNavigation(
      ref,
      telegramTdlibAuthorized: telegramTdlibSessionAuthorized,
    );
    return false;
  }
}
