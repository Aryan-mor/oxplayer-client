import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';

const _kPrefix = 'ox_mt_live_v1_';

String myTelegramLiveCacheKey(String tdlibChatId, int messageThreadId) =>
    '$_kPrefix${tdlibChatId}_t$messageThreadId';

Map<String, dynamic> _rowToMap(OxChatMediaRow r) {
  return <String, dynamic>{
    'fileId': r.fileId,
    'messageId': r.messageId,
    if (r.remoteFileId != null) 'remoteFileId': r.remoteFileId,
    if (r.caption != null) 'caption': r.caption,
    if (r.messageDate != null) 'messageDate': r.messageDate,
    if (r.fileName != null) 'fileName': r.fileName,
    if (r.chatId != null) 'chatId': r.chatId,
    if (r.durationSeconds != null) 'durationSeconds': r.durationSeconds,
    if (r.fileSizeBytes != null) 'fileSizeBytes': r.fileSizeBytes,
  };
}

OxChatMediaRow _rowFromMap(Map<String, dynamic> m) {
  return OxChatMediaRow(
    fileId: m['fileId']?.toString() ?? '',
    messageId: m['messageId']?.toString() ?? '',
    remoteFileId: m['remoteFileId']?.toString(),
    caption: m['caption']?.toString(),
    messageDate: m['messageDate']?.toString(),
    fileName: m['fileName']?.toString(),
    chatId: m['chatId'] is int ? m['chatId'] as int : int.tryParse(m['chatId']?.toString() ?? ''),
    durationSeconds: m['durationSeconds'] is int
        ? m['durationSeconds'] as int
        : int.tryParse(m['durationSeconds']?.toString() ?? ''),
    fileSizeBytes: m['fileSizeBytes'] is int
        ? m['fileSizeBytes'] as int
        : int.tryParse(m['fileSizeBytes']?.toString() ?? ''),
  );
}

class MyTelegramLiveCache {
  const MyTelegramLiveCache._();

  static Future<({List<OxChatMediaRow> items, int? nextId})> load(
    String tdlibChatId,
    int messageThreadId,
  ) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(myTelegramLiveCacheKey(tdlibChatId, messageThreadId));
    if (s == null || s.isEmpty) {
      return (items: <OxChatMediaRow>[], nextId: null);
    }
    try {
      final o = jsonDecode(s);
      if (o is! Map) {
        return (items: <OxChatMediaRow>[], nextId: null);
      }
      final m = Map<String, dynamic>.from(o);
      final list = m['items'];
      if (list is! List) {
        return (items: <OxChatMediaRow>[], nextId: null);
      }
      final items = <OxChatMediaRow>[];
      for (final e in list) {
        if (e is! Map) continue;
        final row = _rowFromMap(Map<String, dynamic>.from(e));
        if (row.messageId.isNotEmpty) {
          items.add(row);
        }
      }
      final n = m['next'];
      int? nextId;
      if (n is int) {
        nextId = n;
      } else {
        nextId = int.tryParse(n?.toString() ?? '');
      }
      return (items: items, nextId: nextId);
    } catch (_) {
      return (items: <OxChatMediaRow>[], nextId: null);
    }
  }

  static Future<void> save(
    String tdlibChatId,
    int messageThreadId, {
    required List<OxChatMediaRow> items,
    required int? nextLive,
  }) async {
    if (items.isEmpty && nextLive == null) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    final m = <String, dynamic>{
      'items': items.map(_rowToMap).toList(),
      'next': nextLive,
    };
    await p.setString(myTelegramLiveCacheKey(tdlibChatId, messageThreadId), jsonEncode(m));
  }
}
