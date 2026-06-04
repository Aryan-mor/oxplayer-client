import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_test_account_api.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/screens/login/login_screen_credentials.dart';

/// Hold duration for the hidden tester sign-in on the login QR code.
const kOxTestAccountQrHoldDuration = Duration(seconds: 5);

Future<void> oxplayerSignInAsTestAccount({
  required WidgetRef ref,
  required BuildContext context,
  Future<void> Function()? onSuccess,
}) async {
  final deviceId = ref.read(authProvider).serverLoginModel?.tempCredentials.deviceId;
  if (deviceId == null || deviceId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device not ready. Wait a moment and try again.')),
      );
    }
    return;
  }

  try {
    final api = OxplayerTestAccountApi();
    final result = await api.signIn(ref: ref, deviceId: deviceId);
    if (!context.mounted) return;
    if (result?.body != null) {
      if (onSuccess != null) {
        await onSuccess();
      } else {
        await loggedInGoToHome(context, ref);
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test sign-in failed. Check API is running and reachable.')),
    );
  } on OxplayerTestAccountException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Test sign-in failed: $e')),
    );
  }
}
