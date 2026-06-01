import 'package:chopper/chopper.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_session_refresh_coordinator.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:fladder/oxplayer/oxplayer_riverpod_ref.dart';
/// Jellyfin [AuthenticateUserByName] username for 6-char Telegram login (password = code).
const kOxJellyfinLoginUsername = 'ox';

/// Jellyfin username for silent refresh (password = oxRefreshToken).
const kOxJellyfinRefreshUsername = '__ox_refresh__';

String? oxplayerAuthResponseHeader(Response response, String name) {
  for (final entry in response.base.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value;
    }
  }
  return null;
}

/// Persists [X-Ox-Refresh-Token] from AuthenticateByName (OX extension, not in Jellyfin JSON).
Future<void> oxplayerPersistRefreshTokenFromAuthResponse(
  dynamic ref,
  Response<AccountModel> response,
) async {
  final r = oxplayerCoerceRef(ref);
  final refresh =
      oxplayerAuthResponseHeader(response, 'x-ox-refresh-token')?.trim() ?? '';
  if (refresh.isEmpty) return;

  final user = r.read(userProvider);
  if (user == null) return;

  final updated = user.copyWith(
    credentials: user.credentials.copyWith(oxRefreshToken: refresh),
  );
  r.read(userProvider.notifier).userState = updated;
  await r.read(sharedUtilityProvider).addAccount(updated);

  r.read(authProvider.notifier).oxplayerAttachSessionToken(
        updated.credentials.token,
        serverId: updated.credentials.serverId,
        refreshToken: refresh,
      );
}

/// Login with main-bot code via Fladder's Jellyfin authenticateByName (no OX /auth/claim-code).
Future<Response<AccountModel>?> oxplayerAuthenticateWithClaimCode(
  dynamic ref,
  String code,
) async {
  final r = oxplayerCoerceRef(ref);
  final normalized = code.trim().toUpperCase();
  final response = await r.read(authProvider.notifier).authenticateByName(
        kOxJellyfinLoginUsername,
        normalized,
      );
  if (response?.isSuccessful == true && response?.body != null) {
    await oxplayerPersistRefreshTokenFromAuthResponse(r, response!);
    if (OxplayerConfig.isEnabled && !kIsWeb) {
      oxplayerNoteSessionEstablished();
    }
  }
  return response;
}

/// Refresh access token via Jellyfin AuthenticateByName (OX refresh username convention).
Future<bool> oxplayerRefreshSessionViaJellyfin(dynamic ref) async {
  final r = oxplayerCoerceRef(ref);
  final storedRefresh = r.read(userProvider)?.credentials.oxRefreshToken.trim() ??
      r.read(authProvider).serverLoginModel?.tempCredentials.oxRefreshToken.trim() ??
      '';
  if (storedRefresh.isEmpty) return false;

  final response = await r.read(authProvider.notifier).authenticateByName(
        kOxJellyfinRefreshUsername,
        storedRefresh,
      );
  if (response?.isSuccessful != true || response?.body == null) {
    return false;
  }
  await oxplayerPersistRefreshTokenFromAuthResponse(r, response!);
  if (OxplayerConfig.isEnabled && !kIsWeb) {
    oxplayerNoteSessionEstablished();
  }
  return true;
}
