import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/my_telegram/my_telegram_formatters.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/oxplayer/telegram/telegram_message_thumbnail.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// Grid column count aligned with [PosterGrid] / library poster density.
int myTelegramPosterGridCrossAxisCount(BuildContext context, WidgetRef ref) {
  final w = MediaQuery.sizeOf(context).width;
  final poster = AdaptiveLayout.poster(context);
  final sizeMul = ref.watch(clientSettingsProvider.select((s) => s.posterSize));
  final size = w / (poster.gridRatio * sizeMul);
  return size.toInt().clamp(2, 12);
}

/// Grid `childAspectRatio` (width / height) for [MyTelegramVideoPosterTile]: 16:9 video area
/// plus a fixed title block (2 lines + optional date). Matches
/// [SliverGridDelegateWithFixedCrossAxisCount] + [SliverPadding] 8 in My Telegram media.
double myTelegramVideoGridChildAspectRatio(BuildContext context, WidgetRef ref) {
  final w = MediaQuery.sizeOf(context).width;
  const sliverHPad = 8.0 * 2;
  const spacing = 8.0;
  final cross = myTelegramPosterGridCrossAxisCount(context, ref);
  final innerW = w - sliverHPad;
  final cellW = (innerW - (cross - 1) * spacing) / cross;
  final thumbH = cellW * 9.0 / 16.0;
  // SizedBox(4) + 2 title lines (strut ~40) + gap + [labelSmall] sub — must match
  // [MyTelegramVideoPosterTile] to avoid SliverGrid overflow under the last line.
  const textBlockH = 4.0 + 40.0 + 2.0 + 16.0;
  return cellW / (thumbH + textBlockH);
}

class MyTelegramFolderTile extends StatelessWidget {
  const MyTelegramFolderTile({
    super.key,
    required this.title,
    this.photoUrl,
    this.subtitle,
    required this.onTap,
  });

  final String title;
  final String? photoUrl;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: FladderTheme.smallShape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: FladderTheme.smallShape.borderRadius,
                    color: scheme.surfaceContainerHigh,
                  ),
                  child: _FolderThumb(photoUrl: photoUrl),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderThumb extends StatelessWidget {
  const _FolderThumb({this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final u = photoUrl?.trim();
    if (u != null && u.isNotEmpty && (u.startsWith('http://') || u.startsWith('https://'))) {
      return ClipRRect(
        borderRadius: FladderTheme.smallShape.borderRadius,
        child: Image.network(
          u,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _FolderIconPlaceholder(),
        ),
      );
    }
    return const _FolderIconPlaceholder();
  }
}

class _FolderIconPlaceholder extends StatelessWidget {
  const _FolderIconPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        IconsaxPlusLinear.folder_2,
        size: 44,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// One video cell: poster aspect (like library), title below — tap opens detail.
class MyTelegramVideoPosterTile extends StatelessWidget {
  const MyTelegramVideoPosterTile({
    super.key,
    required this.row,
    required this.chatId,
    required this.messageId,
    required this.onTap,
  });

  final OxChatMediaRow row;
  final int chatId;
  final int messageId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (row.caption?.trim().isNotEmpty == true)
        ? row.caption!.trim()
        : (row.fileName?.trim().isNotEmpty == true)
            ? row.fileName!
            : 'Video';
    final sub = _formatSub(row);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: scheme.surfaceContainer,
            shape: FladderTheme.smallShape,
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TdlibMessageVideoThumbnail(
                    chatId: chatId,
                    messageId: messageId,
                    fit: BoxFit.cover,
                  ),
                  if (row.durationSeconds != null && row.durationSeconds! > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.scrim.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            myTelegramFormatDurationHms(row.durationSeconds!),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            strutStyle: const StrutStyle(
              fontSize: 14,
              height: 1.25,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: const StrutStyle(
                fontSize: 12,
                height: 1.2,
                leadingDistribution: TextLeadingDistribution.even,
              ),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.outline,
                    height: 1.2,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  String? _formatSub(OxChatMediaRow r) {
    if (r.messageDate == null || r.messageDate!.isEmpty) return null;
    return r.messageDate;
  }

}
