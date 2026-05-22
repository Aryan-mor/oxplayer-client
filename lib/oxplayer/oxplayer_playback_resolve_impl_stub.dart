import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fladder/oxplayer/ox_sync_telegram_progress.dart';
import 'package:fladder/td_api_generated/td_api.dart' as td;

Future<String?> resolveTelegramMessageToPlayableUrl({required td.Message message}) async => null;

Future<String?> downloadOxplayerTelegramMediaForSync({
  required Ref ref,
  required String mediaId,
  OxTelegramSyncProgressCallback? onProgress,
}) async =>
    null;

Future<String?> resolveOxplayerTelegramLocatorToPlayableUrl({
  required String oxplayerLocatorUri,
  required Ref ref,
  bool forOfflineSync = false,
}) async =>
    null;
