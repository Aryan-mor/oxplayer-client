import 'package:flutter/material.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/localization_helper.dart';

/// Bottom sheet with bot QR (avoids [AlertDialog] layout issues inside login [ListView]).
void showOxplayerBotQrSheet(
  BuildContext context, {
  required String telegramLink,
  String? botUsername,
}) {
  final rootContext = Navigator.of(context, rootNavigator: true).context;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!rootContext.mounted) return;
    showModalBottomSheet<void>(
      context: rootContext,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(rootContext).colorScheme.surface,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final l10n = sheetContext.localized;
        final bottom = MediaQuery.paddingOf(sheetContext).bottom;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  botUsername != null ? '@$botUsername' : l10n.oxplayerHelpTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.oxplayerHelpQrCaption,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        data: telegramLink,
                        size: 220,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                        gapless: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (botUsername != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await launchUrl(sheetContext, telegramLink);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      icon: const Icon(Icons.telegram),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(l10n.oxplayerHelpOpenBot(botUsername)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  });
}
