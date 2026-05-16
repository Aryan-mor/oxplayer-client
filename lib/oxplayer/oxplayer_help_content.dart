import 'package:flutter/material.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';

/// Shared “get started” panel: QR → bot link, short copy, open-in-Telegram button.
class OxplayerHelpContent extends StatelessWidget {
  const OxplayerHelpContent({
    super.key,
    this.embedded = false,
  });

  /// When true, used inside the home [CustomScrollView] (no nested scroll view).
  final bool embedded;

  Future<void> _openBot(BuildContext context) async {
    final link = OxplayerEnv.telegramBotOpenLink;
    if (link == null) return;
    await launchUrl(context, link);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = OxplayerEnv.telegramBotOpenLink;
    final bot = OxplayerEnv.botUsername;
    final ap = AdaptiveLayout.adaptivePadding(context);
    final pad = ap.copyWith(
      top: embedded ? 8 : 16,
      bottom: embedded ? 24 : 16,
    );

    final qrSize = (MediaQuery.sizeOf(context).shortestSide * 0.42).clamp(160.0, 220.0);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (embedded) ...[
          Text(
            context.localized.oxplayerHelpTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
        ],
        if (link != null) ...[
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrImageView(
                data: link,
                size: qrSize,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.localized.oxplayerHelpQrCaption,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          context.localized.oxplayerHelpBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (link == null) ...[
          const SizedBox(height: 16),
          Text(
            context.localized.oxplayerHelpBotNotConfigured,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (link != null && bot != null)
          FilledButton.icon(
            onPressed: () => _openBot(context),
            icon: const Icon(Icons.telegram),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(context.localized.oxplayerHelpOpenBot(bot)),
            ),
          ),
      ],
    );

    if (embedded) {
      return Padding(padding: pad, child: body);
    }
    return SingleChildScrollView(
      padding: pad,
      child: body,
    );
  }
}
