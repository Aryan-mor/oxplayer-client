import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_splash_gate.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart' as ox_connectivity;
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((value) async {
      if (!OxplayerConfig.isEnabled) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      final AccountModel? lastUsedAccount =
          ref.read(sharedUtilityProvider).getActiveAccount();
      final newWindow = ref.read(argumentsStateProvider).newWindow == true;

      if (!context.mounted) return;

      // OX: refresh API session on splash before opening the home stack.
      if (OxplayerConfig.isEnabled &&
          lastUsedAccount != null &&
          lastUsedAccount.authMethod == Authentication.autoLogin &&
          !newWindow) {
        final connectivity = await Connectivity().checkConnectivity();
        ref.read(ox_connectivity.connectivityStatusProvider.notifier).onStateChange(connectivity);
        final isOffline = connectivity.contains(ConnectivityResult.none);

        if (!isOffline) {
          final gateResult = await oxplayerRunSplashSessionGate(ref);
          if (gateResult != OxplayerSplashGateResult.proceedToDashboard) {
            await oxplayerClearIncompleteLoginSession(ref);
            if (!context.mounted) return;
            callBackOrNavigate(false);
            return;
          }
        }

        final activeAccount =
            ref.read(sharedUtilityProvider).getActiveAccount() ?? lastUsedAccount;
        ref.read(userProvider.notifier).updateUser(activeAccount);
        if (widget.loggedIn == null) {
          // No network: Fladder OX offline mode (Synced tab only).
          // Server down but Wi‑Fi up: open the normal home stack so bottom nav works.
          if (isOffline) {
            context.router.replaceAll([
              const HomeRoute(children: [SyncedRoute()]),
            ]);
          } else {
            context.router.replace(const DashboardRoute());
          }
        } else {
          widget.loggedIn?.call(true);
          context.router.maybePop(true);
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
          context.router.replace(const OxplayerLoginRoute());
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
    return const NotificationManagerInitializer(
      child: Scaffold(
        body: Stack(
          children: [
            Center(
              child: FractionallySizedBox(
                heightFactor: 0.4,
                child: FladderLogo(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
