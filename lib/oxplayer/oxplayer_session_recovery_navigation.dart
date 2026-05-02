import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/routes/auto_router.dart' as fladder_stack;
import 'package:fladder/routes/auto_router.gr.dart';

/// Root stack router from [BaseAppWrapperState] ([fladder_stack.AutoRouter]), for navigation without a [BuildContext].
final oxplayerRegisteredAppRouterProvider =
    StateProvider<fladder_stack.AutoRouter?>((ref) => null);

bool _oxSessionRecoveryNavigationScheduled = false;

/// After an irrecoverable OX auth failure (e.g. `POST /auth/refresh` **401**), clear the Jellyfin
/// session and send the user to re-login.
///
/// [telegramTdlibAuthorized] is **true** when TDLib already has an interactive session (user is
/// "logged in" in Telegram); they are sent to [OxplayerTelegramLoginRoute] to re-establish the
/// OX/Jellyfin session. When **false**, they are sent to [LoginRoute] (on OX builds [AuthGuard]
/// redirects that to [OxplayerTelegramLoginRoute]).
void oxplayerScheduleSessionRecoveryNavigation(
  Ref ref, {
  required bool telegramTdlibAuthorized,
}) {
  if (kIsWeb || !OxplayerConfig.isEnabled) return;
  if (_oxSessionRecoveryNavigationScheduled) return;
  _oxSessionRecoveryNavigationScheduled = true;

  scheduleMicrotask(() async {
    try {
      ref.read(authProvider.notifier).clearAllProviders();

      final router = ref.read(oxplayerRegisteredAppRouterProvider);
      if (router == null) {
        if (kDebugMode) {
          debugPrint('[OX] session recovery: no app router registered yet');
        }
        return;
      }

      if (telegramTdlibAuthorized) {
        await router.replaceAll([OxplayerTelegramLoginRoute()]);
      } else {
        await router.replaceAll([LoginRoute()]);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OX] session recovery navigation failed: $e\n$st');
      }
    } finally {
      Future.delayed(const Duration(seconds: 2), () {
        _oxSessionRecoveryNavigationScheduled = false;
      });
    }
  });
}
