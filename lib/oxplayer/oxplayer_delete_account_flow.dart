import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_account_api.dart';
import 'package:fladder/oxplayer/oxplayer_navigation.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';

/// Shows a confirmation dialog; on success calls the API, logs out, and clears local session.
Future<void> showOxplayerDeleteAccountDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final loc = context.localized;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.oxplayerDeleteAccountDialogTitle),
      scrollable: true,
      content: Text(loc.oxplayerDeleteAccountDialogBody),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(loc.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom().copyWith(
            iconColor: WidgetStatePropertyAll(Theme.of(ctx).colorScheme.onErrorContainer),
            foregroundColor: WidgetStatePropertyAll(Theme.of(ctx).colorScheme.onErrorContainer),
            backgroundColor: WidgetStatePropertyAll(Theme.of(ctx).colorScheme.errorContainer),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(loc.oxplayerDeleteAccountConfirm),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final user = ref.read(userProvider);
  if (user == null) return;

  try {
    await oxplayerPostDeleteAccount(
      authorizationHeaders: user.credentials.header(ref),
    );
  } catch (e) {
    if (context.mounted) {
      FladderSnack.show(
        '${context.localized.oxplayerDeleteAccountFailed} ($e)',
        context: context,
      );
    }
    return;
  }

  await ref.read(authProvider.notifier).logOutUser();

  if (!context.mounted) return;
  await context.router.replaceAll(oxplayerSignOutRouteList());
}
