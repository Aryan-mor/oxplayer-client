import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/image_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// Wires a Jellyfin-shaped [AuthenticationResult] into Fladder providers (same idea as password login).
Future<void> oxplayerApplyTelegramJellyfinSession(
  WidgetRef ref,
  AuthenticationResult authenticationResult,
) async {
  await ref.read(authProvider.notifier).switchUser();

  final token = authenticationResult.accessToken ?? '';
  if (token.isEmpty) {
    throw StateError('Missing access token');
  }

  final authNotifier = ref.read(authProvider.notifier);
  if (authNotifier.oxplayerServerLoginModel == null) {
    throw StateError('Server is not configured; connect to Jellyfin first');
  }

  authNotifier.oxplayerAttachSessionToken(
    token,
    serverId: authenticationResult.serverId,
  );

  final serverResponse = await ref.read(jellyApiProvider).systemInfoPublicGet();
  final login = authNotifier.oxplayerServerLoginModel!;
  final mergedCreds = login.tempCredentials;
  final creds = mergedCreds.copyWith(
    serverName: serverResponse.body?.serverName ?? mergedCreds.serverName,
    serverId: authenticationResult.serverId ?? mergedCreds.serverId,
  );

  final imageUrl = ref
      .read(imageUtilityProvider)
      .getUserImageUrl(authenticationResult.user?.id ?? '');
  final newUser = AccountModel(
    name: authenticationResult.user?.name ?? '',
    id: authenticationResult.user?.id ?? '',
    avatar: imageUrl,
    credentials: creds,
    lastUsed: DateTime.now(),
  );

  ref.read(sharedUtilityProvider).addAccount(newUser);
  ref.read(userProvider.notifier).userState = newUser;
  authNotifier.getSavedAccounts();
}
