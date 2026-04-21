import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tdlib/td_api.dart' as td;

import 'package:fladder/oxplayer/telegram_local_stream_log.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/telegram/telegram_locator_env_search_chats.dart';
import 'package:fladder/oxplayer/telegram/telegram_media_file_locator_resolver.dart';
import 'package:fladder/oxplayer/telegram/telegram_range_playback.dart';

/// Full TDLib locator fallback chain (`GetMessage`, `SearchChatMessages`, …). Off by default.
const bool _kOxTelegramLocatorVerbose = bool.fromEnvironment(
  'OX_TELEGRAM_LOCATOR_VERBOSE',
  defaultValue: false,
);

class _OxLibraryFileDto {
  _OxLibraryFileDto({
    required this.id,
    required this.mediaId,
    required this.fileUniqueId,
    this.locatorType,
    this.locatorChatId,
    this.locatorMessageId,
    this.locatorRemoteFileId,
  });

  final String id;
  final String mediaId;
  final String fileUniqueId;
  final String? locatorType;
  final int? locatorChatId;
  final int? locatorMessageId;
  final String? locatorRemoteFileId;

  static _OxLibraryFileDto? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = m['id']?.toString();
    final mediaId = m['mediaId']?.toString();
    final fu = m['fileUniqueId']?.toString();
    if (id == null || mediaId == null || fu == null) return null;
    return _OxLibraryFileDto(
      id: id,
      mediaId: mediaId,
      fileUniqueId: fu,
      locatorType: m['locatorType']?.toString(),
      locatorChatId: _parseInt(m['locatorChatId']),
      locatorMessageId: _parseInt(m['locatorMessageId']),
      locatorRemoteFileId: m['locatorRemoteFileId']?.toString(),
    );
  }
}

int? _parseInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

class _OxLibraryDetailDto {
  _OxLibraryDetailDto({required this.files});

  final List<_OxLibraryFileDto> files;

  static _OxLibraryDetailDto? tryParseBody(String body) {
    final dec = jsonDecode(body);
    if (dec is! Map) return null;
    final filesRaw = dec['files'];
    if (filesRaw is! List) return null;
    final files = <_OxLibraryFileDto>[];
    for (final f in filesRaw) {
      final p = _OxLibraryFileDto.tryParse(f);
      if (p != null) files.add(p);
    }
    return _OxLibraryDetailDto(files: files);
  }
}

Future<_OxLibraryDetailDto?> _fetchLibraryMediaDetail(Ref ref, String globalId) async {
  final serverUrl = ref.read(serverUrlProvider);
  final login = ref.read(userProvider)?.credentials ?? ref.read(authProvider).serverLoginModel?.tempCredentials;
  if (serverUrl == null || serverUrl.isEmpty || login == null) return null;

  final uri = Uri.parse(serverUrl).resolve('me/library/media/$globalId');
  final response = await http.get(uri, headers: login.header(ref));
  if (response.statusCode != 200) {
    oxTelegramLocalStreamLog('prep FAIL', 'library HTTP ${response.statusCode}');
    return null;
  }
  return _OxLibraryDetailDto.tryParseBody(response.body);
}

String? _parseOxplayerTelegramMediaId(String uri) {
  final u = Uri.tryParse(uri.trim());
  if (u == null || u.scheme != 'oxplayer' || u.host != 'telegram') return null;
  final id = u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
  if (id == null || !RegExp(r'^\d+$').hasMatch(id)) return null;
  return id;
}

_OxLibraryFileDto? _pickFile(_OxLibraryDetailDto detail, String targetMediaId) {
  for (final f in detail.files) {
    if (f.mediaId == targetMediaId) return f;
  }
  for (final f in detail.files) {
    if (f.locatorChatId != null && f.locatorMessageId != null) return f;
  }
  return detail.files.isEmpty ? null : detail.files.first;
}

String? _mimeFromMessage(td.Message message) {
  final content = message.content;
  if (content is td.MessageVideo) return content.video.mimeType;
  if (content is td.MessageDocument) return content.document.mimeType;
  return null;
}

Future<String?> _downloadTelegramFileFully(
  TdlibFacade tdlib,
  int fileId,
) async {
  try {
    await tdlib.send(td.DownloadFile(fileId: fileId, priority: 5, offset: 0, limit: 0, synchronous: false));
  } catch (_) {}

  const pollInterval = Duration(milliseconds: 320);

  while (true) {
    final fileResult = await tdlib.send(td.GetFile(fileId: fileId));
    if (fileResult is! td.File) return null;

    final srcPath = fileResult.local.path.trim();
    if (srcPath.isNotEmpty && fileResult.local.isDownloadingCompleted) {
      return srcPath;
    }

    await Future<void>.delayed(pollInterval);
  }
}

Future<String?> _waitForReadableVideoPrefix(TdlibFacade tdlib, int fileId) async {
  const minVideoPrefixBytes = 768 * 1024;
  const maxTdlibDownloadLimit = 4 * 1024 * 1024;
  const prefixWait = Duration(seconds: 26);
  const pollInterval = Duration(milliseconds: 380);

  final deadline = DateTime.now().add(prefixWait);
  while (DateTime.now().isBefore(deadline)) {
    td.File? file;
    try {
      final obj = await tdlib.send(td.GetFile(fileId: fileId));
      if (obj is td.File) file = obj;
    } catch (_) {}

    if (file != null) {
      final path = file.local.path.trim();
      final downloaded = file.local.downloadedSize;
      final total = file.size;
      if (path.isNotEmpty && file.local.isDownloadingCompleted) {
        return path;
      }
      if (total > 0 && path.isNotEmpty && downloaded >= total) {
        return path;
      }
      if (path.isNotEmpty && downloaded >= minVideoPrefixBytes) {
        return path;
      }
    }

    try {
      await tdlib.send(
        td.DownloadFile(fileId: fileId, priority: 8, offset: 0, limit: maxTdlibDownloadLimit, synchronous: false),
      );
    } catch (_) {}

    await Future<void>.delayed(pollInterval);
  }

  return null;
}

Future<String?> _resolveToStreamOrFileUrl({
  required TdlibFacade tdlib,
  required td.File resolvedFile,
  required td.Message? messageForMime,
}) async {
  final mime = messageForMime != null ? _mimeFromMessage(messageForMime) : null;
  final streamUrl = await TelegramRangePlayback.instance.openResolvedFile(
    tdlib: tdlib,
    file: resolvedFile,
    mimeType: mime,
  );
  if (streamUrl != null) {
    oxTelegramLocalStreamLog('stream', 'OK fileId=${resolvedFile.id} → $streamUrl');
    return streamUrl.toString();
  }

  oxTelegramLocalStreamLog('stream', 'loopback failed → prefix on disk');
  final quickStartPath = await _waitForReadableVideoPrefix(tdlib, resolvedFile.id);
  if (quickStartPath != null && quickStartPath.isNotEmpty) {
    oxTelegramLocalStreamLog('stream', 'file prefix $quickStartPath');
    return Uri.file(quickStartPath).toString();
  }

  oxTelegramLocalStreamLog('stream', 'prefix timeout → full download');
  final downloadedPath = await _downloadTelegramFileFully(tdlib, resolvedFile.id);
  if (downloadedPath != null && downloadedPath.isNotEmpty) {
    oxTelegramLocalStreamLog('stream', 'file full $downloadedPath');
    return Uri.file(downloadedPath).toString();
  }

  oxTelegramLocalStreamLog('stream', 'FAIL no playable url');
  return null;
}

Future<String?> resolveOxplayerTelegramLocatorToPlayableUrl({
  required String oxplayerLocatorUri,
  required Ref ref,
}) async {
  if (kIsWeb) {
    oxTelegramLocalStreamLog('prep ABORT', 'web');
    return null;
  }

  final mediaId = _parseOxplayerTelegramMediaId(oxplayerLocatorUri);
  if (mediaId == null) {
    oxTelegramLocalStreamLog('prep ABORT', 'bad oxplayer locator');
    return null;
  }

  final detail = await _fetchLibraryMediaDetail(ref, mediaId);
  if (detail == null || detail.files.isEmpty) {
    oxTelegramLocalStreamLog('prep FAIL', 'no library file row (need locator metadata)');
    return null;
  }

  final file = _pickFile(detail, mediaId);
  if (file == null) {
    oxTelegramLocalStreamLog('prep FAIL', 'pickFile empty');
    return null;
  }

  oxTelegramLocalStreamLog(
    'tdlib.session',
    'ensureReadyForPlayback mediaId=$mediaId locator=${file.locatorType} chat=${file.locatorChatId} msg=${file.locatorMessageId}',
  );
  final ready = await OxplayerTelegramTdSession.ensureReadyForPlayback();
  if (!ready) {
    oxTelegramLocalStreamLog('tdlib.session', 'FAIL not authorized / not ready');
    return null;
  }
  oxTelegramLocalStreamLog('tdlib.session', 'OK');

  final tdlib = OxplayerTelegramTdRuntime.facade;

  void onDiag(String m) {
    if (!_kOxTelegramLocatorVerbose) return;
    oxTelegramLocalStreamLog('tdlib.resolve', m);
  }

  final envSearchChats = await oxplayerLocatorTagTelegramSearchChatIds(tdlib, onDiag);

  final resolvedMedia = await resolveTelegramMediaFile(
    tdlib: tdlib,
    mediaFileId: file.mediaId,
    fileUniqueId: file.fileUniqueId,
    locatorType: file.locatorType,
    locatorChatId: file.locatorChatId,
    locatorMessageId: file.locatorMessageId,
    locatorRemoteFileId: file.locatorRemoteFileId,
    locatorTagTelegramSearchChatIds: envSearchChats,
    onDiagnostic: onDiag,
  );

  if (resolvedMedia == null) {
    oxTelegramLocalStreamLog('tdlib.file', 'FAIL (no message/file)');
    return null;
  }
  oxTelegramLocalStreamLog(
    'tdlib.file',
    'OK fileId=${resolvedMedia.file.id} reason=${resolvedMedia.resolutionReason ?? "?"} '
    'expectedSize=${resolvedMedia.file.expectedSize}',
  );

  final url = await _resolveToStreamOrFileUrl(
    tdlib: tdlib,
    resolvedFile: resolvedMedia.file,
    messageForMime: null,
  );
  if (url == null) {
    oxTelegramLocalStreamLog('resolve.done', 'FAIL');
  } else {
    oxTelegramLocalStreamLog('resolve.done', 'OK $url');
  }
  return url;
}
