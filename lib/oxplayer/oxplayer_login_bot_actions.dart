import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_bot_qr_dialog.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/localization_helper.dart';

/// Below claim-code Continue: card with open-bot + QR actions.
class OxplayerLoginBotActions extends StatelessWidget {
  const OxplayerLoginBotActions({super.key});

  void _openQr(BuildContext context, String link, String bot) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      showOxplayerBotQrSheet(
        context,
        telegramLink: link,
        botUsername: bot,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final link = OxplayerEnv.telegramBotLoginLink;
    final bot = OxplayerEnv.botUsername;
    if (link == null || bot == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.localized;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => launchUrl(context, link),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF229ED9).withValues(alpha: 0.15),
                        child: const Icon(
                          Icons.telegram,
                          color: Color(0xFF229ED9),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.oxplayerLoginOpenOnAndroid,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@$bot',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.6),
            ),
            Material(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              child: InkWell(
                onTap: () => _openQr(context, link, bot),
                child: SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.qr_code_2_rounded,
                        size: 28,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.oxplayerLoginBotQrShort,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
