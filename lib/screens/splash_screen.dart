import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_splash_gate.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';

@RoutePage()
class SplashScreen extends ConsumerStatefulWidget {
  final Function(bool loggedIn)? loggedIn;
  const SplashScreen({this.loggedIn, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _oxSessionGateLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((value) async {
      await Future.delayed(const Duration(milliseconds: 500));
      final AccountModel? lastUsedAccount =
          ref.read(sharedUtilityProvider).getActiveAccount();
      final newWindow = ref.read(argumentsStateProvider).newWindow == true;

      if (!context.mounted) return;

      // OX (native): never open Dashboard on a stale saved token — require TDLib + fresh `/auth/telegram`.
      if (OxplayerConfig.isEnabled &&
          !kIsWeb &&
          lastUsedAccount != null &&
          lastUsedAccount.authMethod == Authentication.autoLogin &&
          !newWindow) {
        setState(() => _oxSessionGateLoading = true);
        final gate = await oxplayerRunSplashSessionGate(ref);
        if (!context.mounted) return;
        setState(() => _oxSessionGateLoading = false);

        if (widget.loggedIn == null) {
          if (gate == OxplayerSplashGateResult.proceedToDashboard) {
            context.router.replace(const DashboardRoute());
          } else {
            ref.read(userProvider.notifier).clear();
            ref.read(lockScreenActiveProvider.notifier).update((s) => false);
            context.router.replace(OxplayerTelegramLoginRoute());
          }
        } else {
          final ok = gate == OxplayerSplashGateResult.proceedToDashboard;
          widget.loggedIn?.call(ok);
          context.router.maybePop(ok);
        }
        return;
      }

      ref.read(userProvider.notifier).updateUser(lastUsedAccount);

      if (lastUsedAccount == null || newWindow) {
        callBackOrNavigate(false);
      } else {
        switch (lastUsedAccount.authMethod) {
          case Authentication.autoLogin:
            callBackOrNavigate(true);
            break;
          case Authentication.biometrics:
          case Authentication.none:
          case Authentication.passcode:
            callBackOrNavigate(false);
            break;
        }
      }
    });
  }

  void callBackOrNavigate(bool loggedIn) {
    if (widget.loggedIn == null) {
      if (loggedIn) {
        context.router.replace(const DashboardRoute());
      } else {
        if (OxplayerConfig.isEnabled) {
          context.router.replace(OxplayerTelegramLoginRoute());
        } else {
          context.router.replace(LoginRoute());
        }
      }
    } else {
      widget.loggedIn?.call(loggedIn);
      context.router.maybePop(loggedIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationManagerInitializer(
      child: Scaffold(
        body: Stack(
          children: [
            const Center(
              child: FractionallySizedBox(
                heightFactor: 0.4,
                child: FladderLogo(),
              ),
            ),
            if (_oxSessionGateLoading)
              Positioned(
                left: 0,
                right: 0,
                bottom: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connecting…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
