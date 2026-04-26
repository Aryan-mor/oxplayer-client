import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/user_provider.dart';

/// Thrown when the OX access token is missing (same shape as [OxUserChatsClientException] for auth).
class OxUserChatsUnauthorized implements Exception {
  const OxUserChatsUnauthorized();
  @override
  String toString() => 'Not signed in to OX API';
}

/// Authorized REST calls for `/me/chats*`.
final oxplayerUserChatsClientProvider = Provider<OxplayerUserChatsClient?>((ref) {
  if (OxplayerEnv.apiBaseUrl == null) return null;
  final u = ref.watch(userProvider);
  final creds = u?.credentials;
  if (creds == null || creds.token.isEmpty) return null;
  return OxplayerUserChatsClient(
    apiBase: OxplayerEnv.apiBaseUrl!,
    getAuthorizationValue: () {
      final h = creds.header(ref)['authorization'];
      return h ?? '';
    },
  );
});

String? _readTrimmed(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _readInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class OxplayerUserChatsClient {
  OxplayerUserChatsClient({
    required this.apiBase,
    required this.getAuthorizationValue,
  });

  final String apiBase;
  final String Function() getAuthorizationValue;

  Map<String, String> get _jsonHeaders {
    final auth = getAuthorizationValue().trim();
    if (auth.isEmpty) {
      throw const OxUserChatsUnauthorized();
    }
    return {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': auth,
    };
  }

  Future<OxUserChatListPage> fetchUserChats({
    required String bucket,
    bool indexedOnly = false,
    bool showInVideoOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final uri = Uri.parse('$apiBase/me/chats').replace(
      queryParameters: <String, String>{
        'bucket': bucket,
        'indexedOnly': indexedOnly.toString(),
        'showInVideoOnly': showInVideoOnly.toString(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    final sw = Stopwatch()..start();
    debugPrint(
      '[MyTelegram API] (1) GET /me/chats start bucket=$bucket offset=$offset limit=$limit host=${uri.host}',
    );
    late http.Response r;
    try {
      r = await http.get(uri, headers: _jsonHeaders);
    } catch (e, st) {
      debugPrint(
        '[MyTelegram API] (2) GET /me/chats FAILED after ${sw.elapsedMilliseconds}ms: $e\n$st',
      );
      rethrow;
    }
    debugPrint(
      '[MyTelegram API] (2) GET /me/chats done status=${r.statusCode} bodyLen=${r.body.length} in ${sw.elapsedMilliseconds}ms',
    );
    if (r.statusCode == 401) throw const OxUserChatsUnauthorized();
    if (r.statusCode != 200) {
      throw StateError('GET /me/chats failed: ${r.statusCode} ${r.body}');
    }
    final data = r.body.isEmpty ? null : jsonDecode(r.body);
    if (data is! Map<String, dynamic>) {
      return const OxUserChatListPage(items: [], total: 0);
    }
    final itemsRaw = data['items'];
    final total = (data['total'] as num?)?.toInt() ?? 0;
    if (itemsRaw is! List) {
      return OxUserChatListPage(items: const [], total: total);
    }
    final items = <OxUserChatRow>[];
    for (final e in itemsRaw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = _readTrimmed(m['id']) ?? '';
      if (id.isEmpty) continue;
      items.add(
        OxUserChatRow(
          id: id,
          tdlibChatId: _readTrimmed(m['tdlibChatId'] ?? m['telegramChatId']),
          title: _readTrimmed(m['title']) ?? '',
          photoUrl: _readTrimmed(m['photoUrl']),
          chatType: _readTrimmed(m['chatType']) ?? 'private',
          peerIsBot: m['peerIsBot'] == true,
          isForum: m['isForum'] == true,
          isIndexed: m['isIndexed'] == true,
          showInVideo: m['showInVideo'] == true,
          showInMusic: m['showInMusic'] == true,
        ),
      );
    }
    return OxUserChatListPage(items: items, total: total);
  }

  Future<void> upsertUserChatMapping({
    required int tdlibChatId,
    required String title,
    required String chatType,
    bool peerIsBot = false,
    bool isForum = false,
  }) async {
    final body = <String, dynamic>{
      'tdlibChatId': tdlibChatId.toString(),
      'title': title,
      'chatType': chatType,
      'peerIsBot': peerIsBot,
      if (chatType == 'supergroup') 'isForum': isForum,
    };
    final uri = Uri.parse('$apiBase/me/chats/upsert');
    final r = await http.post(uri, headers: _jsonHeaders, body: jsonEncode(body));
    if (r.statusCode == 401) throw const OxUserChatsUnauthorized();
    if (r.statusCode != 200) {
      throw StateError('POST /me/chats/upsert failed: ${r.statusCode} ${r.body}');
    }
  }

  Future<int> patchUserChatsIndexed({required List<Map<String, dynamic>> items}) async {
    final uri = Uri.parse('$apiBase/me/chats/indexed');
    final r = await http.patch(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(<String, dynamic>{'items': items}),
    );
    if (r.statusCode == 401) throw const OxUserChatsUnauthorized();
    if (r.statusCode != 200) {
      throw StateError('PATCH /me/chats/indexed failed: ${r.statusCode} ${r.body}');
    }
    final data = r.body.isEmpty ? null : jsonDecode(r.body);
    if (data is Map<String, dynamic>) {
      final u = data['updated'];
      if (u is int) return u;
      return int.tryParse(u?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  /// Registers Telegram file rows with the OX indexer (main-bot pipeline expects indexed chats).
  Future<({int upserted, String? lastIndexedMessageId})> ingestChatMedia({
    required String tdlibChatId,
    required List<Map<String, dynamic>> items,
    String? lastIndexedMessageId,
  }) async {
    final body = <String, dynamic>{'items': items};
    if (lastIndexedMessageId != null) {
      body['lastIndexedMessageId'] = lastIndexedMessageId;
    }
    final uri = Uri.parse('$apiBase/me/chats/by-tdlib-id/$tdlibChatId/ingest');
    final r = await http.post(uri, headers: _jsonHeaders, body: jsonEncode(body));
    if (r.statusCode == 401) throw const OxUserChatsUnauthorized();
    if (r.statusCode != 200) {
      throw StateError('POST /me/chats/.../ingest failed: ${r.statusCode} ${r.body}');
    }
    final data = r.body.isEmpty ? null : jsonDecode(r.body);
    if (data is! Map<String, dynamic>) {
      return (upserted: 0, lastIndexedMessageId: null);
    }
    final u = data['upserted'];
    final last = data['lastIndexedMessageId']?.toString();
    return (
      upserted: u is int ? u : int.tryParse(u?.toString() ?? '') ?? 0,
      lastIndexedMessageId: last,
    );
  }

  Future<int> patchUserChatsShowInVideo({required List<Map<String, dynamic>> items}) async {
    final uri = Uri.parse('$apiBase/me/chats/show-in-video');
    final r = await http.patch(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(<String, dynamic>{'items': items}),
    );
    if (r.statusCode == 401) throw const OxUserChatsUnauthorized();
    if (r.statusCode != 200) {
      throw StateError('PATCH /me/chats/show-in-video failed: ${r.statusCode} ${r.body}');
    }
    final data = r.body.isEmpty ? null : jsonDecode(r.body);
    if (data is Map<String, dynamic>) {
      final u = data['updated'];
      if (u is int) return u;
      return int.tryParse(u?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  /// Indexed `File` rows; optional [messageThreadId] for forum topic.
  Future<OxChatMediaPage> fetchIndexedChatMedia({
    required String tdlibChatId,
    int? messageThreadId,
    int limit = 40,
    int offset = 0,
  }) async {
    final qp = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (messageThreadId != null) {
      qp['messageThreadId'] = messageThreadId.toString();
    }
    final uri = Uri.parse('$apiBase/me/chats/by-tdlib-id/$tdlibChatId/media')
        .replace(queryParameters: qp);
    final r = await http.get(uri, headers: _jsonHeaders);
    if (r.statusCode == 401) throw const OxUserChatsUnauthorized();
    if (r.statusCode != 200) {
      throw StateError('GET /me/chats/.../media failed: ${r.statusCode} ${r.body}');
    }
    final data = r.body.isEmpty ? null : jsonDecode(r.body);
    if (data is! Map<String, dynamic>) {
      return const OxChatMediaPage(items: [], total: 0);
    }
    final itemsRaw = data['items'];
    final total = (data['total'] as num?)?.toInt() ?? 0;
    if (itemsRaw is! List) {
      return OxChatMediaPage(items: const [], total: total);
    }
    final chatIdInt = int.tryParse(tdlibChatId);
    final items = <OxChatMediaRow>[];
    for (final e in itemsRaw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final fileId = _readTrimmed(m['fileId']) ?? '';
      if (fileId.isEmpty) continue;
      items.add(
        OxChatMediaRow(
          fileId: fileId,
          messageId: _readTrimmed(m['messageId']) ?? '',
          remoteFileId: _readTrimmed(m['remoteFileId']),
          caption: _readTrimmed(m['caption']),
          messageDate: _readTrimmed(m['messageDate']),
          fileName: _readTrimmed(m['fileName']),
          chatId: chatIdInt,
          durationSeconds: _readInt(m['durationSeconds'] ?? m['duration']),
          fileSizeBytes: _readInt(m['fileSizeBytes'] ?? m['fileSize'] ?? m['size']),
        ),
      );
    }
    final loaded = offset + items.length;
    return OxChatMediaPage(
      items: items,
      total: total,
      hasMoreHistory: loaded < total,
    );
  }
}
