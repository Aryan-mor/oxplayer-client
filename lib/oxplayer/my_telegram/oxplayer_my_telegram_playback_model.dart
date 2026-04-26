import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart' as tda;

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/oxplayer/oxplayer_playback_resolver.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/util/bitrate_helper.dart';

/// [ItemBaseModel.id] for videos opened from the My Telegram hub (no Jellyfin row yet).
String oxTelegramHubItemId(int chatId, int messageId) => 'ox_tg_${chatId}_$messageId';

/// Minimal [ItemBaseModel] so My Telegram uses the same [Item.play] / [createPlaybackModel] / [_playVideo] path as library items.
ItemBaseModel buildOxTelegramHubPlayItem({
  required int chatId,
  required int messageId,
  required String name,
}) {
  return ItemBaseModel(
    id: oxTelegramHubItemId(chatId, messageId),
    name: name,
    overview: const OverviewModel(summary: ''),
    parentId: '',
    playlistId: '',
    images: null,
    childCount: 0,
    primaryRatio: 0,
    userData: const UserData(),
    canDownload: false,
    canDelete: false,
    jellyType: BaseItemKind.movie,
  );
}

final RegExp _oxTgIdRe = RegExp(r'^ox_tg_(-?\d+)_(\d+)$');

bool isOxTelegramHubSyntheticId(String id) => _oxTgIdRe.hasMatch(id);

/// Resolves a synthetic My Telegram [ItemBaseModel] to a [DirectPlaybackModel] with the same
/// [resolveTelegramMessageToPlayableUrl] pipeline used after [GetMessage] in the
/// OX `oxplayer://` locator flow ([resolveOxplayerTelegramLocatorToPlayableUrl] on the server model).
///
/// Returns `null` if the id is not a hub id, on web, or if resolution fails.
Future<PlaybackModel?> tryCreateOxTelegramHubPlaybackModel({
  required Ref ref,
  required ItemBaseModel firstItemToPlay,
  required List<ItemBaseModel> libraryQueue,
}) async {
  if (kIsWeb) return null;
  final match = _oxTgIdRe.firstMatch(firstItemToPlay.id);
  if (match == null) return null;

  final chatId = int.parse(match.group(1)!);
  final messageId = int.parse(match.group(2)!);

  if (!await OxplayerTelegramTdSession.ensureReadyForPlayback()) {
    return null;
  }

  final td = OxplayerTelegramTdSession().td;
  final msg = await td.send(tda.GetMessage(chatId: chatId, messageId: messageId));
  if (msg is! tda.Message) {
    return null;
  }

  final fileUrl = await resolveTelegramMessageToPlayableUrl(message: msg);
  if (fileUrl == null || fileUrl.isEmpty) {
    return null;
  }

  final queue = libraryQueue.isNotEmpty ? libraryQueue : <ItemBaseModel>[firstItemToPlay];
  return DirectPlaybackModel(
    item: firstItemToPlay,
    queue: queue,
    media: Media(url: fileUrl),
    bitRateOptions: {for (final b in Bitrate.values) b: true},
    reportJellyfinSessions: false,
  );
}
