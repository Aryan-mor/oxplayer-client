import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/ox_general_video_thumb_ref.dart';
import 'package:fladder/oxplayer/telegram/telegram_message_thumbnail.dart';
import 'package:fladder/oxplayer/widgets/oxplayer_tmdb_empty_image_placeholder.dart';

/// Shown when Jellyfin has no [primaryImagePath] for OX general video: try Telegram (TDLib), then
/// the same local placeholder as the rest of OxPlayer.
class OxGeneralVideoArtwork extends ConsumerWidget {
  const OxGeneralVideoArtwork({
    super.key,
    required this.mediaId,
    this.fit = BoxFit.cover,
  });

  final String mediaId;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(oxMediaTelegramRefProvider(mediaId));
    return a.when(
      data: (r) {
        if (r == null) {
          return const OxplayerTmdbEmptyImagePlaceholder();
        }
        if (r.chatId == 0 || r.messageId == 0) {
          return const OxplayerTmdbEmptyImagePlaceholder();
        }
        return TdlibMessageVideoThumbnail(
          chatId: r.chatId,
          messageId: r.messageId,
          fit: fit,
        );
      },
      loading: () => const OxplayerTmdbEmptyImagePlaceholder(),
      error: (_, __) => const OxplayerTmdbEmptyImagePlaceholder(),
    );
  }
}
