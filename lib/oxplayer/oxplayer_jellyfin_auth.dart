import 'package:chopper/chopper.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kOxJellyfinLoginUsername = 'ox';

Future<Response<AccountModel>?> oxplayerAuthenticateWithClaimCode(
  WidgetRef ref,
  String code,
) async {
  final response = await ref.read(authProvider.notifier).authenticateByName(
        kOxJellyfinLoginUsername,
        code.trim().toUpperCase(),
      );
  final account = response?.body;
  if (response != null && account != null) {
    await oxplayerPersistRefreshFromResponse(ref, account, response);
  }
  return response;
}
