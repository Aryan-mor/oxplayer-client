import 'dart:async';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_riverpod_ref.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/routes/auto_router.dart' as fladder_stack;
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final oxplayerRegisteredAppRouterProvider =
    StateProvider<fladder_stack.AutoRouter?>((ref) => null);

bool _oxSessionRecoveryNavigationScheduled = false;

/// After an irrecoverable auth failure, clear the session and open claim-code login.
void oxplayerScheduleSessionRecoveryNavigation(dynamic ref) {
  if (kIsWeb || !OxplayerConfig.isEnabled) return;
  if (_oxSessionRecoveryNavigationScheduled) return;
  _oxSessionRecoveryNavigationScheduled = true;

  final r = oxplayerCoerceRef(ref);

  scheduleMicrotask(() async {
    try {
      r.read(authProvider.notifier).clearAllProviders();

      final router = r.read(oxplayerRegisteredAppRouterProvider);
      if (router == null) {
        if (kDebugMode) {
          debugPrint('[OX] session recovery: no app router registered yet');
        }
        return;
      }

      await router.replaceAll([const OxplayerLoginRoute()]);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OX] session recovery navigation failed: $e\n$st');
      }
    } finally {
      _oxSessionRecoveryNavigationScheduled = false;
    }
  });
}
