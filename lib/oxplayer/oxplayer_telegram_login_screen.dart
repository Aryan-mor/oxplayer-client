import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_session.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/fladder_config.dart';

@RoutePage()
class OxplayerTelegramLoginScreen extends ConsumerStatefulWidget {
  const OxplayerTelegramLoginScreen({super.key});

  @override
  ConsumerState<OxplayerTelegramLoginScreen> createState() =>
      _OxplayerTelegramLoginScreenState();
}

class _OxplayerTelegramLoginScreenState
    extends ConsumerState<OxplayerTelegramLoginScreen> {
  late final TextEditingController _jellyfinUrlController;
  late final TextEditingController _apiBaseController;
  final TextEditingController _initDataController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final defaultJelly = FladderConfig.baseUrl?.trim() ?? '';
    _jellyfinUrlController = TextEditingController(text: defaultJelly);
    _apiBaseController =
        TextEditingController(text: OxplayerEnv.apiBaseUrl ?? '');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).initModel();
    });
  }

  @override
  void dispose() {
    _jellyfinUrlController.dispose();
    _apiBaseController.dispose();
    _initDataController.dispose();
    super.dispose();
  }

  Future<void> _connectJellyfin() async {
    final raw = _jellyfinUrlController.text.trim();
    if (raw.isEmpty) {
      FladderSnack.show('Enter your Jellyfin server URL', context: context);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).setServer(raw);
      if (mounted) {
        final err = ref.read(authProvider).errorMessage;
        if (err != null) {
          FladderSnack.show(err, context: context);
        } else {
          FladderSnack.show('Connected to server', context: context);
        }
      }
    } catch (e) {
      if (mounted) FladderSnack.show('$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithTelegram() async {
    final apiBase = _apiBaseController.text.trim();
    if (apiBase.isEmpty) {
      FladderSnack.show(
          'Enter OXPlayer API base URL (or set OXPLAYER_API_BASE)',
          context: context);
      return;
    }
    final initData = _initDataController.text.trim();
    if (initData.isEmpty) {
      FladderSnack.show('Paste Telegram WebApp initData', context: context);
      return;
    }
    if (ref.read(authProvider).serverLoginModel == null) {
      FladderSnack.show('Connect to Jellyfin first', context: context);
      return;
    }

    setState(() => _busy = true);
    try {
      final app = ref.read(applicationInfoProvider);
      final deviceName = kIsWeb
          ? 'Fladder Web'
          : '${app.name} / ${defaultTargetPlatform.name}';

      final client = OxplayerTelegramAuthClient(
          apiBase: apiBase.replaceAll(RegExp(r'/$'), ''));
      final exchanged = await client.exchangeInitData(
        initData: initData,
        deviceName: deviceName,
      );

      await oxplayerApplyTelegramJellyfinSession(ref, exchanged.jellyfin);

      ref.read(lockScreenActiveProvider.notifier).update((s) => false);

      if (mounted) {
        await context.router.replaceAll([const DashboardRoute()]);
      }
    } on OxplayerTelegramAuthException catch (e) {
      if (mounted) FladderSnack.show(e.message, context: context);
    } catch (e) {
      if (mounted) FladderSnack.show('$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMiniAppInBrowser() async {
    final url = OxplayerEnv.telegramWebAppUrl;
    if (url == null) {
      FladderSnack.show(
        'Set OXPLAYER_TELEGRAM_WEB_APP_URL to open the Mini App in a browser',
        context: context,
      );
      return;
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      FladderSnack.show('Could not launch URL', context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authLoading = ref.watch(authProvider.select((s) => s.loading));
    final hasBaseUrl = ref.watch(authProvider.select((s) => s.hasBaseUrl));
    final serverReady =
        ref.watch(authProvider.select((s) => s.serverLoginModel != null));

    return NotificationManagerInitializer(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sign in with Telegram'),
          actions: [
            TextButton(
              onPressed:
                  _busy ? null : () => context.router.replace(LoginRoute()),
              child: const Text('Classic login'),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy || authLoading,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Connect to your Jellyfin-compatible server, then paste initData from your Telegram Mini App '
                '(Telegram.WebApp.initData).',
              ),
              const SizedBox(height: 20),
              if (!hasBaseUrl) ...[
                TextField(
                  controller: _jellyfinUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Jellyfin server URL',
                    hintText: 'https://jellyfin.example.com',
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _connectJellyfin,
                  child: const Text('Connect to server'),
                ),
              ] else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Jellyfin server'),
                  subtitle:
                      Text('Using fixed base URL from build configuration'),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(serverReady ? Icons.check_circle : Icons.hourglass_empty,
                      size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      serverReady
                          ? 'Server session ready'
                          : 'Server not connected yet',
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              TextField(
                controller: _apiBaseController,
                decoration: const InputDecoration(
                  labelText: 'OXPlayer API base URL',
                  hintText: 'https://api.your-oxplayer.example',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _initDataController,
                decoration: const InputDecoration(
                  labelText: 'Telegram initData',
                  alignLabelWithHint: true,
                ),
                minLines: 3,
                maxLines: 8,
                autocorrect: false,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _signInWithTelegram,
                child: const Text('Sign in with Telegram'),
              ),
              if (OxplayerEnv.telegramWebAppUrl != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openMiniAppInBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open Mini App in browser'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
