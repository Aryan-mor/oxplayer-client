import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/providers/auth_provider.dart';

/// Wires a Jellyfin-shaped [AuthenticationResult] into Fladder providers (same idea as password login).
///
/// Prefer [OxplayerTelegramAuthResponse] + [AuthNotifier.applyOxplayerTelegramAuthResponse] when you have
/// a full API response (includes optional refresh token).
Future<void> oxplayerApplyTelegramJellyfinSession(
  WidgetRef ref,
  AuthenticationResult authenticationResult, {
  String? oxRefreshToken,
}) {
  final token = authenticationResult.accessToken ?? '';
  return ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(
        OxplayerTelegramAuthResponse(
          accessToken: token,
          jellyfin: authenticationResult,
          refreshToken: oxRefreshToken,
        ),
      );
}
