import 'package:auto_route/auto_route.dart';
import 'package:fladder/oxplayer/oxplayer_claim_code_login_panel.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/screens/login/login_screen_credentials.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// OX v2 login: main-bot `/login` code only (Fladder shell + branding).
@RoutePage()
class OxplayerLoginScreen extends ConsumerStatefulWidget {
  const OxplayerLoginScreen({super.key});

  @override
  ConsumerState<OxplayerLoginScreen> createState() => _OxplayerLoginScreenState();
}

class _OxplayerLoginScreenState extends ConsumerState<OxplayerLoginScreen> {
  bool _bootstrapping = true;
  String? _bootstrapError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
    });

    OxplayerEnv.debugLogApiResolution();
    final api = OxplayerEnv.apiBaseUrl;
    final media = OxplayerEnv.effectiveMediaServerUrl;
    if (api == null || media == null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError =
            'Set OXPLAYER_API_BASE_URL in assets/env/default.env (e.g. http://192.168.1.10:3004).';
      });
      return;
    }

    FladderConfig.baseUrl = media;

    try {
      await ref.read(authProvider.notifier).initModel(clearUserState: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _bootstrapError = '$e';
        });
      }
      return;
    }

    if (!mounted) return;
    final err = ref.read(authProvider).errorMessage;
    if (err != null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError = err;
      });
      return;
    }

    setState(() => _bootstrapping = false);
  }

  Future<void> _onAuthSuccess() async {
    if (!mounted) return;
    await loggedInGoToHome(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationManagerInitializer(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _bootstrapping
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 120,
                            width: double.infinity,
                            child: FladderLogo(),
                          ),
                          SizedBox(height: 24),
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Connecting…', style: TextStyle(color: Colors.grey)),
                        ],
                      )
                    : _bootstrapError != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                height: 120,
                                width: double.infinity,
                                child: FladderLogo(),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _bootstrapError!,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _bootstrap,
                                child: const Text('Retry'),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(
                                height: 120,
                                width: double.infinity,
                                child: FladderLogo(),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sign in',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              OxplayerClaimCodeLoginPanel(
                                onSuccess: _onAuthSuccess,
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
