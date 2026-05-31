import 'dart:async';
import 'dart:developer';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_device_identity.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_session_refresh_coordinator.dart';
import 'package:fladder/oxplayer/oxplayer_session_recovery_navigation.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/application_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> oxplayerTryRefreshJellyfinSessionAfter401(Ref ref) {
  return oxplayerWithExclusiveSessionRefresh(() async {
    if (oxplayerSessionRefreshCompletedRecently()) {
      final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
      if (token.isNotEmpty) return true;
    }
    return _oxplayerDoJellyfinSessionRefresh(ref);
  });
}

Future<bool> _oxplayerDoJellyfinSessionRefresh(Ref ref) async {
  if (!OxplayerConfig.isEnabled || kIsWeb) return false;

  final authNotifier = ref.read(authProvider.notifier);
  if (authNotifier.oxplayerServerLoginModel == null) return false;

  final apiBase = OxplayerEnv.apiBaseUrl;
  if (apiBase == null) return false;

  final storedRefresh = ref.read(userProvider)?.credentials.oxRefreshToken.trim() ??
      ref.read(authProvider).serverLoginModel?.tempCredentials.oxRefreshToken.trim() ??
      '';
  if (storedRefresh.isEmpty) {
    oxplayerScheduleSessionRecoveryNavigation(ref);
    return false;
  }

  try {
    final app = ref.read(applicationInfoProvider);
    final deviceName = '${app.name} / ${defaultTargetPlatform.name}';
    final identity = await oxplayerResolveDeviceIdentity(defaultDeviceName: deviceName);
    final exchanged = await OxplayerTelegramAuthClient(apiBase: apiBase).refreshAccessToken(
      refreshToken: storedRefresh,
      deviceId: identity.deviceId,
    );
    await authNotifier.applyOxplayerTelegramAuthResponse(exchanged);
    return true;
  } catch (e, st) {
    log('OX 401 refresh failed', error: e, stackTrace: st);
    oxplayerScheduleSessionRecoveryNavigation(ref);
    return false;
  }
}
