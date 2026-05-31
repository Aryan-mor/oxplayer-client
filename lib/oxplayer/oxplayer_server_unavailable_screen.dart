import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_api_reachability.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_splash_gate.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class OxplayerServerUnavailableScreen extends ConsumerStatefulWidget {
  const OxplayerServerUnavailableScreen({super.key});

  @override
  ConsumerState<OxplayerServerUnavailableScreen> createState() =>
      _OxplayerServerUnavailableScreenState();
}

class _OxplayerServerUnavailableScreenState
    extends ConsumerState<OxplayerServerUnavailableScreen> {
  bool _retrying = false;

  Future<void> _retryConnection() async {
    if (_retrying || !OxplayerConfig.isEnabled) return;
    final api = OxplayerEnv.apiBaseUrl;
    if (api == null) return;

    setState(() => _retrying = true);
    try {
      final reachable = await oxplayerProbeApiReachable(api);
      if (!mounted) return;
      if (!reachable) return;

      oxplayerSetApiServerReachable(ref, true);
      final refreshed = await oxplayerSilentRefreshSession(ref);
      if (!mounted) return;
      if (refreshed) {
        context.router.replace(const DashboardRoute());
      }
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.localized;
    final newsLink = OxplayerEnv.telegramNewsChannelLink;
    final newsLabel = OxplayerEnv.telegramNewsChannelLabel;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const FractionallySizedBox(
                widthFactor: 0.45,
                child: FladderLogo(),
              ),
              const SizedBox(height: 32),
              Icon(
                IconsaxPlusLinear.cloud_cross,
                size: 48,
                color: cs.error,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.oxplayerServerUnavailableTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.oxplayerServerUnavailableBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (newsLink != null) ...[
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => launchUrl(context, newsLink),
                  icon: const Icon(Icons.telegram),
                  label: Text(
                    newsLabel != null
                        ? '${l10n.oxplayerServerUnavailableOpenChannelGeneric} ($newsLabel)'
                        : l10n.oxplayerServerUnavailableOpenChannelGeneric,
                  ),
                ),
              ],
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _retrying ? null : _retryConnection,
                  child: _retrying
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : Text(l10n.oxplayerServerUnavailableRetry),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  context.router.replaceAll([
                    const HomeRoute(children: [SyncedRoute()]),
                  ]);
                },
                child: Text(l10n.oxplayerServerUnavailableOfflineDownloads),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
