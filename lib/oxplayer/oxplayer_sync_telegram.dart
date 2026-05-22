import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/syncing/sync_item.dart';
import 'package:fladder/oxplayer/ox_sync_log.dart';
import 'package:fladder/oxplayer/ox_sync_telegram_progress.dart';
import 'package:fladder/oxplayer/oxplayer_playback_resolver.dart';

/// TDLib full download for offline sync. Returns a `file://` path, or null.
Future<String?> oxDownloadTelegramMediaToLocalPath({
  required Ref ref,
  required String mediaId,
  OxTelegramSyncProgressCallback? onProgress,
}) async {
  if (kIsWeb) {
    oxSyncLog('telegram', 'skip TDLib download on web');
    return null;
  }

  oxSyncLog('telegram', 'TDLib full download mediaId=$mediaId');
  final playableUrl = await downloadOxplayerTelegramMediaForSync(
    ref: ref,
    mediaId: mediaId,
    onProgress: onProgress,
  );

  if (playableUrl == null || playableUrl.isEmpty) {
    oxSyncLog('telegram', 'FAIL resolve/download returned null');
    return null;
  }

  final srcUri = Uri.tryParse(playableUrl);
  if (srcUri == null || srcUri.scheme != 'file') {
    oxSyncLog('telegram', 'FAIL expected file:// URL, got $playableUrl');
    return null;
  }

  final srcPath = srcUri.toFilePath(windows: Platform.isWindows);
  if (!await File(srcPath).exists()) {
    oxSyncLog('telegram', 'FAIL source missing path=$srcPath');
    return null;
  }

  oxSyncLog('telegram', 'OK local path=$srcPath');
  return srcPath;
}

/// Copies [localPath] into the Fladder sync folder with byte progress (phase weight 0–1).
Future<bool> oxCopyTelegramDownloadIntoSyncFolder({
  required SyncedItem syncItem,
  required String localPath,
  void Function(double copyFraction)? onCopyProgress,
}) async {
  final srcFile = File(localPath);
  final destFile = syncItem.videoFile;
  final total = await srcFile.length();
  if (total <= 0) {
    await destFile.parent.create(recursive: true);
    await srcFile.copy(destFile.path);
    onCopyProgress?.call(1.0);
    return true;
  }

  await destFile.parent.create(recursive: true);
  if (await destFile.exists()) {
    await destFile.delete();
  }

  const chunkSize = 512 * 1024;
  final buffer = List<int>.filled(chunkSize, 0);
  final input = await srcFile.open();
  final output = await destFile.open(mode: FileMode.writeOnly);

  try {
    var copied = 0;
    while (copied < total) {
      final read = await input.readInto(buffer);
      if (read <= 0) break;
      await output.writeFrom(buffer, 0, read);
      copied += read;
      onCopyProgress?.call((copied / total).clamp(0.0, 1.0));
    }
  } finally {
    await input.close();
    await output.close();
  }

  oxSyncLog('telegram', 'copy $total bytes → ${destFile.path}');
  return true;
}

/// Stable filename for Telegram-backed library rows (not `oxplayer://…` basenames).
String oxSyncTelegramVideoFileName(String mediaId, {String extension = '.mp4'}) {
  final ext = extension.startsWith('.') ? extension : '.$extension';
  return 'ox_telegram_${mediaId.trim()}$ext';
}
