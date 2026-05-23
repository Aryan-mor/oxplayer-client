import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart';

import 'package:fladder/td_api_generated/td_api.dart' as td;
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/telegram/telegram_locator_env_search_chats.dart';
import 'package:fladder/oxplayer/telegram/telegram_media_file_locator_resolver.dart';
import 'package:fladder/oxplayer/telegram_local_stream_log.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/api_provider.dart';

void _webPlayLog(String context, String message) {
  oxTelegramLocalStreamLog('web.$context', message);
}

JSObject get _windowObj => window as JSObject;

JSObject? _tdwebBridgeObj() {
  final raw = _windowObj.getProperty<JSAny?>('oxplayerTdweb'.toJS);
  if (raw == null) return null;
  try {
    return raw as JSObject;
  } catch (_) {
    return null;
  }
}

String _jsAnyToDartString(JSAny? value) {
  if (value == null) return '';
  try {
    return (value as JSString).toDart;
  } catch (_) {}
  try {
    final d = value.dartify();
    if (d is String) return d;
    return d?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

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
    final fileUniqueId = m['fileUniqueId']?.toString();
    if (id == null || mediaId == null || fileUniqueId == null) return null;
    return _OxLibraryFileDto(
      id: id,
      mediaId: mediaId,
      fileUniqueId: fileUniqueId,
      locatorType: (m['locatorType'] ?? m['locator_type'])?.toString(),
      locatorChatId: _parseInt(m['locatorChatId'] ?? m['locator_chat_id']),
      locatorMessageId: _parseInt(m['locatorMessageId'] ?? m['locator_message_id']),
      locatorRemoteFileId: (m['locatorRemoteFileId'] ?? m['locator_remote_file_id'])?.toString(),
    );
  }
}

class _OxLibraryDetailDto {
  _OxLibraryDetailDto({
    required this.files,
    this.providerBackupPostUrl,
    this.isGeneralVideo = false,
  });

  final List<_OxLibraryFileDto> files;
  final String? providerBackupPostUrl;
  final bool isGeneralVideo;

  static _OxLibraryDetailDto? tryParseBody(String body) {
    final dec = jsonDecode(body);
    if (dec is! Map) return null;
    final filesRaw = dec['files'];
    if (filesRaw is! List) return null;
    final mediaRaw = dec['media'];
    String? backup = mediaRaw is Map
        ? (mediaRaw['providerBackupPostUrl'] ?? mediaRaw['provider_backup_post_url'])
            ?.toString()
            .trim()
        : null;
    if (backup != null && backup.isEmpty) backup = null;
    final files = <_OxLibraryFileDto>[];
    for (final f in filesRaw) {
      final parsed = _OxLibraryFileDto.tryParse(f);
      if (parsed != null) files.add(parsed);
    }
    return _OxLibraryDetailDto(
      files: files,
      providerBackupPostUrl: backup,
      isGeneralVideo: mediaRaw is Map && mediaRaw['type']?.toString() == 'GENERAL_VIDEO',
    );
  }
}

int? _parseInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

String? _parseOxplayerTelegramMediaId(String uri) {
  final u = Uri.tryParse(uri.trim());
  if (u == null || u.scheme != 'oxplayer' || u.host != 'telegram') return null;
  final id = u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
  if (id == null || !RegExp(r'^\d+$').hasMatch(id)) return null;
  return id;
}

Future<_OxLibraryDetailDto?> _fetchLibraryMediaDetail(Ref ref, String globalId) async {
  final serverUrl = ref.read(serverUrlProvider);
  final login = ref.read(userProvider)?.credentials ??
      ref.read(authProvider).serverLoginModel?.tempCredentials;
  if (serverUrl == null || serverUrl.isEmpty || login == null) {
    _webPlayLog('detail', 'missing serverUrl/login');
    return null;
  }

  final uri = Uri.parse(serverUrl).resolve('me/library/media/$globalId');
  final response = await http.get(uri, headers: login.header(ref));
  if (response.statusCode != 200) {
    _webPlayLog('detail', 'HTTP ${response.statusCode}');
    return null;
  }
  return _OxLibraryDetailDto.tryParseBody(response.body);
}

List<_OxLibraryFileDto> _candidateFiles(_OxLibraryDetailDto detail, String targetMediaId) {
  final out = <_OxLibraryFileDto>[];
  void add(_OxLibraryFileDto file) {
    final key = [
      file.id,
      file.mediaId,
      file.fileUniqueId,
      file.locatorType ?? '',
      file.locatorChatId?.toString() ?? '',
      file.locatorMessageId?.toString() ?? '',
      file.locatorRemoteFileId ?? '',
    ].join('|');
    if (out.any((x) =>
        [
          x.id,
          x.mediaId,
          x.fileUniqueId,
          x.locatorType ?? '',
          x.locatorChatId?.toString() ?? '',
          x.locatorMessageId?.toString() ?? '',
          x.locatorRemoteFileId ?? '',
        ].join('|') ==
        key)) {
      return;
    }
    out.add(file);
  }

  for (final f in detail.files) {
    if (f.mediaId == targetMediaId) add(f);
  }
  for (final f in detail.files) {
    if (f.locatorChatId != null && f.locatorMessageId != null) add(f);
  }
  for (final f in detail.files) {
    add(f);
  }
  return out;
}

td.File? _extractPlayableFileFromMessage(td.Message message) {
  final content = message.content;
  if (content is td.MessageVideo) return content.video.video;
  if (content is td.MessageDocument) return content.document.document;
  if (content is td.MessageAnimation) return content.animation.animation;
  if (content is td.MessageVideoNote) return content.videoNote.video;
  return null;
}

String? _mimeFromMessage(td.Message? message) {
  final content = message?.content;
  if (content is td.MessageVideo) return content.video.mimeType;
  if (content is td.MessageDocument) return content.document.mimeType;
  return null;
}

String _messagePlaybackMeta(td.Message message) {
  final content = message.content;
  if (content is td.MessageVideo) {
    final v = content.video;
    return 'MessageVideo mime=${v.mimeType} file="${v.fileName}" '
        'streaming=${v.supportsStreaming} ${v.width}x${v.height} '
        'duration=${v.duration}s size=${v.video.size} expected=${v.video.expectedSize}';
  }
  if (content is td.MessageDocument) {
    final d = content.document;
    return 'MessageDocument mime=${d.mimeType} file="${d.fileName}" '
        'size=${d.document.size} expected=${d.document.expectedSize}';
  }
  if (content is td.MessageAnimation) {
    final a = content.animation;
    return 'MessageAnimation mime=${a.mimeType} file="${a.fileName}" '
        'size=${a.animation.size} expected=${a.animation.expectedSize}';
  }
  if (content is td.MessageVideoNote) {
    final v = content.videoNote;
    return 'MessageVideoNote size=${v.video.size} expected=${v.video.expectedSize}';
  }
  return content.runtimeType.toString();
}

String? _normalizePublicTmeUrl(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final withScheme = t.startsWith('http') ? t : 'https://$t';
  final u = Uri.tryParse(withScheme);
  if (u == null || u.host.toLowerCase() != 't.me') return null;
  return Uri(
    scheme: 'https',
    host: 't.me',
    pathSegments: u.pathSegments.where((s) => s.isNotEmpty).toList(),
  ).toString();
}

Future<td.Message?> _messageFromProviderBackupUrl(
  TdlibFacade tdlib,
  String providerBackupPostUrl,
) async {
  _webPlayLog('provider', 'ENTER backupLen=${providerBackupPostUrl.length}');
  final normalized = _normalizePublicTmeUrl(providerBackupPostUrl);
  if (normalized == null) {
    _webPlayLog('provider', 'backup URL is not t.me');
    return null;
  }
  try {
    _webPlayLog('provider', 'GetMessageLinkInfo start');
    final info = await tdlib
        .send(td.GetMessageLinkInfo(url: normalized))
        .timeout(const Duration(seconds: 18));
    if (info is td.MessageLinkInfo && info.message != null) {
      _webPlayLog('provider', 'GetMessageLinkInfo embedded message chat=${info.chatId}');
      return info.message;
    }
    _webPlayLog('provider', 'GetMessageLinkInfo -> ${info.runtimeType}');
  } on td.TdError catch (e) {
    _webPlayLog('provider', 'GetMessageLinkInfo ${e.code} ${e.message}');
  } on TimeoutException {
    _webPlayLog('provider', 'GetMessageLinkInfo TIMEOUT');
  } catch (e) {
    _webPlayLog('provider', 'GetMessageLinkInfo ERROR $e');
  }
  return null;
}

Future<String?> _playableStreamUrlFromTdFile(
  TdlibFacade tdlib,
  td.File file, {
  String? mimeType,
}) async {
  _webPlayLog(
    'stream',
    'fromTdFile fileId=${file.id} size=${file.size} expected=${file.expectedSize}',
  );
  final prepared = await _prepareFileForTdwebStreaming(tdlib, file);
  if (prepared == null) {
    _webPlayLog('stream', 'prepare failed fileId=${file.id}');
    return null;
  }
  return _streamUrlFromTdwebFile(prepared, mimeType: mimeType);
}

Future<td.File?> _prepareFileForTdwebStreaming(TdlibFacade tdlib, td.File source) async {
  _webPlayLog('download', 'prepare stream fileId=${source.id} size=${source.size} expected=${source.expectedSize}');
  try {
    await tdlib.send(td.DownloadFile(
      fileId: source.id,
      priority: 32,
      offset: 0,
      limit: 4 * 1024 * 1024,
      synchronous: false,
    ));
  } catch (_) {}

  final deadline = DateTime.now().add(const Duration(seconds: 24));
  while (DateTime.now().isBefore(deadline)) {
    final obj = await tdlib.send(td.GetFile(fileId: source.id));
    if (obj is! td.File) return null;
    final path = obj.local.path.trim();
    final total = obj.size > 0 ? obj.size : obj.expectedSize;
    _webPlayLog(
      'download',
      'poll path=${path.isNotEmpty} completed=${obj.local.isDownloadingCompleted} '
          'offset=${obj.local.downloadOffset} prefix=${obj.local.downloadedPrefixSize} '
          'downloaded=${obj.local.downloadedSize} total=$total',
    );
    if (path.isNotEmpty && obj.local.downloadOffset == 0 && obj.local.downloadedPrefixSize >= 512 * 1024) {
      return obj;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
  _webPlayLog('download', 'prepare timeout');
  return null;
}

Future<String?> _streamUrlFromTdwebFile(td.File file, {String? mimeType}) async {
  final path = file.local.path.trim();
  final size = file.size > 0 ? file.size : file.expectedSize;
  _webPlayLog(
    'stream',
    'create fileId=${file.id} mime=${mimeType ?? "null"} size=$size pathLen=${path.length}',
  );
  if (path.isEmpty || size <= 0) {
    _webPlayLog('stream', 'missing path/size path=${path.isNotEmpty} size=$size');
    return null;
  }
  final bridge = _tdwebBridgeObj();
  if (bridge == null) {
    _webPlayLog('stream', 'oxplayerTdweb bridge missing');
    return null;
  }
  final promise = bridge.callMethodVarArgs<JSPromise<JSAny?>>(
    'createStreamUrlForTdFile'.toJS,
    <JSAny?>[
      file.id.toJS,
      path.toJS,
      size.toJS,
      (mimeType == null || mimeType.isEmpty ? 'video/mp4' : mimeType).toJS,
    ],
  );
  final JSAny? result;
  try {
    result = await promise.toDart.timeout(const Duration(seconds: 8));
  } on TimeoutException {
    _webPlayLog('stream', 'create URL timed out; falling back to server playback');
    return null;
  } catch (e) {
    _webPlayLog('stream', 'create URL failed $e');
    return null;
  }
  final raw = _jsAnyToDartString(result).trim();
  String? url;
  String? sniffedMime;
  String? webPlaybackRisk;
  var parsedJson = false;
  if (raw.startsWith('{')) {
    try {
      final dec = jsonDecode(raw);
      if (dec is Map) {
        parsedJson = true;
        final u = dec['url'];
        url = u == null ? null : u.toString();
        if (url == 'null') url = null;
        sniffedMime = dec['sniffedMime']?.toString();
        final risk = dec['webPlaybackRisk'];
        if (risk != null && risk.toString().isNotEmpty && risk.toString() != 'null') {
          webPlaybackRisk = risk.toString();
        }
      }
    } catch (_) {}
  }
  if (!parsedJson) {
    url = raw.isEmpty ? null : raw;
  }
  if (url == null || url.isEmpty) {
    _webPlayLog('stream', 'no stream URL sniffedMime=$sniffedMime');
    return null;
  }
  if (url.contains('/__ox_tdweb_stream/')) {
    _webPlayLog(
      'stream',
      'OK len=${url.length} sniffedMime=${sniffedMime ?? "null"} '
      'webPlaybackRisk=${webPlaybackRisk ?? "none"}',
    );
    if (webPlaybackRisk != null) {
      _webPlayLog(
        'stream',
        'web may not play in Chrome <video>: $webPlaybackRisk '
        '(Android TDLib+MPV or server transcode)',
      );
    }
    return url;
  }
  _webPlayLog('stream', 'unexpected result len=${url.length}');
  return null;
}

Future<String?> _messageToBlobUrl(TdlibFacade tdlib, td.Message message) async {
  _webPlayLog('message', 'toStream ${_messagePlaybackMeta(message)}');
  final file = _extractPlayableFileFromMessage(message);
  if (file == null) {
    _webPlayLog('message', 'no playable file content=${message.content.runtimeType}');
    return null;
  }
  final prepared = await _prepareFileForTdwebStreaming(tdlib, file);
  if (prepared == null) return null;
  return _streamUrlFromTdwebFile(prepared, mimeType: _mimeFromMessage(message));
}

Future<String?> resolveTelegramMessageToPlayableUrl({
  required td.Message message,
}) async {
  _webPlayLog('message', 'ENTER content=${message.content.runtimeType}');
  await OxplayerDotenv.ensureLoaded();
  final ready = await OxplayerTelegramTdSession.ensureReadyForPlayback();
  if (!ready) {
    _webPlayLog('message', 'TDLib not ready');
    return null;
  }
  return _messageToBlobUrl(OxplayerTelegramTdRuntime.facade, message);
}

Future<String?> downloadOxplayerTelegramMediaForSync({
  required Ref ref,
  required String mediaId,
}) async {
  _webPlayLog('sync', 'full offline download not implemented on web');
  return null;
}

Future<String?> resolveOxplayerTelegramLocatorToPlayableUrl({
  required String oxplayerLocatorUri,
  required Ref ref,
  bool forOfflineSync = false,
}) async {
  if (forOfflineSync) {
    return downloadOxplayerTelegramMediaForSync(
      ref: ref,
      mediaId: _parseOxplayerTelegramMediaId(oxplayerLocatorUri) ?? '',
    );
  }
  _webPlayLog('resolve', 'ENTER locator=$oxplayerLocatorUri');
  await OxplayerDotenv.ensureLoaded();
  final mediaId = _parseOxplayerTelegramMediaId(oxplayerLocatorUri);
  if (mediaId == null) {
    _webPlayLog('resolve', 'bad locator $oxplayerLocatorUri');
    return null;
  }

  final detail = await _fetchLibraryMediaDetail(ref, mediaId);
  if (detail == null) {
    _webPlayLog('resolve', 'detail null mediaId=$mediaId');
    return null;
  }
  _webPlayLog(
    'resolve',
    'detail files=${detail.files.length} backup=${detail.providerBackupPostUrl?.isNotEmpty == true} general=${detail.isGeneralVideo}',
  );

  final ready = await OxplayerTelegramTdSession.ensureReadyForPlayback();
  if (!ready) {
    _webPlayLog('resolve', 'TDLib not ready');
    return null;
  }
  final tdlib = OxplayerTelegramTdRuntime.facade;

  final candidates = _candidateFiles(detail, mediaId);
  if (candidates.isNotEmpty) {
    _webPlayLog(
      'resolve',
      'candidate files=${candidates.length} targetMediaId=$mediaId',
    );
    void onLocatorDiag(String m) => _webPlayLog('locator', m);
    List<int> envSearchChats = const [];
    try {
      envSearchChats = await oxplayerLocatorTagTelegramSearchChatIds(tdlib, onLocatorDiag);
    } catch (e, st) {
      _webPlayLog('resolve', 'oxplayerLocatorTagTelegramSearchChatIds ERROR $e\n$st');
    }
    for (var i = 0; i < candidates.length; i++) {
      final picked = candidates[i];
      _webPlayLog(
        'resolve',
        'try file[$i] id=${picked.id} mediaId=${picked.mediaId} locator=${picked.locatorType ?? "null"} chat=${picked.locatorChatId} msg=${picked.locatorMessageId} remote=${picked.locatorRemoteFileId?.isNotEmpty == true}',
      );
      try {
        final resolved = await resolveTelegramMediaFile(
          tdlib: tdlib,
          mediaFileId: picked.mediaId,
          fileUniqueId: picked.fileUniqueId,
          locatorType: picked.locatorType,
          locatorChatId: picked.locatorChatId,
          locatorMessageId: picked.locatorMessageId,
          locatorRemoteFileId: picked.locatorRemoteFileId,
          locatorTagTelegramSearchChatIds: envSearchChats,
          onDiagnostic: onLocatorDiag,
        );
        if (resolved != null) {
          _webPlayLog(
            'resolve',
            'resolveTelegramMediaFile OK fileId=${resolved.file.id} '
            'reason=${resolved.resolutionReason ?? "?"}',
          );
          try {
            final url = await _playableStreamUrlFromTdFile(tdlib, resolved.file, mimeType: resolved.mimeHint);
            if (url != null) return url;
            _webPlayLog('resolve', 'file[$i] stream URL null after prepare; trying next locator if available');
          } catch (e, st) {
            _webPlayLog('resolve', 'file[$i] _playableStreamUrlFromTdFile ERROR $e\n$st');
          }
        }
      } catch (e, st) {
        _webPlayLog('resolve', 'file[$i] resolveTelegramMediaFile ERROR $e\n$st');
      }
    }
    _webPlayLog('resolve', 'all locator paths failed; trying provider backup if available');
  } else {
    _webPlayLog('resolve', 'no candidate files');
  }

  final backup = detail.providerBackupPostUrl?.trim() ?? '';
  if (!detail.isGeneralVideo && backup.isNotEmpty) {
    final msg = await _messageFromProviderBackupUrl(tdlib, backup);
    if (msg != null) return _messageToBlobUrl(tdlib, msg);
  }

  final override = OxplayerEnv.playbackProviderPostUrlOverride.trim();
  if (override.isNotEmpty) {
    final msg = await _messageFromProviderBackupUrl(tdlib, override);
    if (msg != null) return _messageToBlobUrl(tdlib, msg);
  }

  _webPlayLog('resolve', 'FAIL mediaId=$mediaId');
  return null;
}
