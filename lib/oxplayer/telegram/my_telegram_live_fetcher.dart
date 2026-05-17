import 'dart:async';

import 'package:fladder/td_api_generated/td_api.dart' as td;
import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';

const String _kLiveSearchChatMessagesQuery = '';
const bool _kMyTelegramLiveFetcherVerboseLog = true;
void _mtLiveLog(String m) {
  if (_kMyTelegramLiveFetcherVerboseLog) {
    debugPrint('[MyTelegram live-fetch] $m');
  }
}

const Duration _kSearchChatMessagesTimeout = Duration(seconds: 55);

Future<T> _tdSendWithTimeout<T>(
  Future<T> future, {
  required String label,
}) {
  return future.timeout(
    _kSearchChatMessagesTimeout,
    onTimeout: () {
      _mtLiveLog('TIMEOUT ($label) after ${_kSearchChatMessagesTimeout.inSeconds}s — using fallback/empty for this step');
      throw TimeoutException('TDLib $label');
    },
  );
}

/// [searchChatMessages] with an arbitrary [SearchMessagesFilter] (JSON shape for [offset]).
class _SearchChatMessagesFilteredRequest extends td.TdFunction {
  const _SearchChatMessagesFilteredRequest({
    required this.chatId,
    required this.fromMessageId,
    required this.limit,
    required this.filter,
    this.offsetInt = 0,
    this.messageThreadId = 0,
    this.omitMessageThreadId = false,
    this.isForum = false,
  });

  final int chatId;
  final int fromMessageId;
  final int limit;
  final int offsetInt;
  final td.SearchMessagesFilter filter;
  final int messageThreadId;
  final bool omitMessageThreadId;
  final bool isForum;

  @override
  String getConstructor() => 'searchChatMessages';

  @override
  Map<String, dynamic> toJson([dynamic extra]) {
    final m = <String, dynamic>{
      '@type': 'searchChatMessages',
      'chat_id': chatId,
      'query': _kLiveSearchChatMessagesQuery,
      'from_message_id': fromMessageId,
      'limit': limit,
      'filter': filter.toJson(),
      'offset': offsetInt,
      'only_local': false,
    };
    if (!omitMessageThreadId && messageThreadId != 0) {
      final topic = isForum
          ? td.MessageTopicForum(forumTopicId: messageThreadId)
          : td.MessageTopicThread(messageThreadId: messageThreadId);
      m['topic_id'] = topic.toJson();
    }
    if (extra != null) m['@extra'] = extra;
    return m;
  }
}

List<td.Message> _tdMessagesFromSearchResult(td.TdObject raw) {
  if (raw is td.FoundMessages) return raw.messages;
  if (raw is td.Messages) return raw.messages;
  return const <td.Message>[];
}

bool _tdlibDocumentMimeLooksLikeVideo(String mimeType) {
  final m = mimeType.trim().toLowerCase();
  if (m.isEmpty) return false;
  if (m.startsWith('video/')) return true;
  if (m == 'application/mp4' || m == 'application/x-matroska') return true;
  return false;
}

bool _tdlibDocumentFileNameLooksLikeVideo(String fileName) {
  final n = fileName.trim().toLowerCase();
  if (n.isEmpty) return false;
  return n.endsWith('.mp4') ||
      n.endsWith('.mkv') ||
      n.endsWith('.webm') ||
      n.endsWith('.mov') ||
      n.endsWith('.m4v') ||
      n.endsWith('.avi') ||
      n.endsWith('.mpeg') ||
      n.endsWith('.mpg') ||
      n.endsWith('.3gp');
}

bool _tdlibDocumentIsPlayableVideo(td.Document doc) {
  if (_tdlibDocumentMimeLooksLikeVideo(doc.mimeType)) return true;
  final m = doc.mimeType.trim().toLowerCase();
  if (m == 'application/octet-stream' || m == 'binary/octet-stream') {
    return _tdlibDocumentFileNameLooksLikeVideo(doc.fileName);
  }
  return _tdlibDocumentFileNameLooksLikeVideo(doc.fileName);
}

bool _tdlibDocumentLooksLikeAnimationOrGif(td.Document doc) {
  final m = doc.mimeType.trim().toLowerCase();
  if (m == 'image/gif') return true;
  final n = doc.fileName.trim().toLowerCase();
  if (n.endsWith('.gif')) return true;
  return false;
}

bool _documentPassesMergedGalleryDocumentPolicy(td.Document doc) {
  if (_tdlibDocumentLooksLikeAnimationOrGif(doc)) return false;
  final m = doc.mimeType.trim().toLowerCase();
  if (m.startsWith('video/')) return true;
  if (m == 'application/x-matroska' || m == 'application/mp4') return true;
  final n = doc.fileName.trim().toLowerCase();
  return n.endsWith('.mkv') || n.endsWith('.mp4') || n.endsWith('.avi') || n.endsWith('.mov');
}

int? _tdlibMessageVideoFileSizeBytes(td.Message message) {
  final content = message.content;
  if (content is td.MessageVideo) {
    final n = content.video.video.size;
    return n > 0 ? n : null;
  }
  if (content is td.MessageDocument) {
    final n = content.document.document.size;
    return n > 0 ? n : null;
  }
  return null;
}

OxChatMediaRow? _oxChatMediaRowFromDocumentMessageForMergedGallery(td.Message message, int chatId) {
  final content = message.content;
  if (content is! td.MessageDocument) return null;
  final doc = content.document;
  if (!_documentPassesMergedGalleryDocumentPolicy(doc)) return null;
  final date = DateTime.fromMillisecondsSinceEpoch(message.date * 1000);
  final fileId = doc.document.id.toString();
  if (fileId.isEmpty) return null;
  return OxChatMediaRow(
    fileId: fileId,
    messageId: message.id.toString(),
    remoteFileId: doc.document.remote.uniqueId,
    caption: content.caption.text,
    messageDate: date.toIso8601String(),
    fileName: doc.fileName,
    chatId: chatId,
    durationSeconds: null,
    fileSizeBytes: _tdlibMessageVideoFileSizeBytes(message),
  );
}

List<OxChatMediaRow> _rowsFromDocumentSearchForMergedGallery(List<td.Message> messages, int chatId) {
  final out = <OxChatMediaRow>[];
  final seen = <String>{};
  for (final m in messages) {
    final row = _oxChatMediaRowFromDocumentMessageForMergedGallery(m, chatId);
    if (row == null) continue;
    if (seen.add(row.messageId)) out.add(row);
  }
  return out;
}

List<OxChatMediaRow> _dedupeOxChatMediaRowsByMessageId(List<OxChatMediaRow> rows) {
  final seen = <String>{};
  return rows.where((r) => seen.add(r.messageId)).toList();
}

List<OxChatMediaRow> _sortOxChatMediaRowsByMessageDateDesc(List<OxChatMediaRow> rows) {
  final copy = List<OxChatMediaRow>.from(rows);
  copy.sort((a, b) {
    final da = DateTime.tryParse(a.messageDate ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final db = DateTime.tryParse(b.messageDate ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return db.compareTo(da);
  });
  return copy;
}

OxChatMediaRow? _oxChatMediaRowFromTdVideoMessage(td.Message message, int chatId) {
  final content = message.content;
  final date = DateTime.fromMillisecondsSinceEpoch(message.date * 1000);

  if (content is td.MessageVideo) {
    final v = content.video;
    final fileId = v.video.id.toString();
    if (fileId.isEmpty) return null;
    return OxChatMediaRow(
      fileId: fileId,
      messageId: message.id.toString(),
      remoteFileId: v.video.remote.uniqueId,
      caption: content.caption.text,
      messageDate: date.toIso8601String(),
      fileName: v.fileName,
      chatId: chatId,
      durationSeconds: v.duration,
      fileSizeBytes: _tdlibMessageVideoFileSizeBytes(message),
    );
  }
  if (content is td.MessageDocument) {
    final doc = content.document;
    if (!_tdlibDocumentIsPlayableVideo(doc)) return null;
    final fileId = doc.document.id.toString();
    if (fileId.isEmpty) return null;
    return OxChatMediaRow(
      fileId: fileId,
      messageId: message.id.toString(),
      remoteFileId: doc.document.remote.uniqueId,
      caption: content.caption.text,
      messageDate: date.toIso8601String(),
      fileName: doc.fileName,
      chatId: chatId,
      durationSeconds: null,
      fileSizeBytes: _tdlibMessageVideoFileSizeBytes(message),
    );
  }
  return null;
}

OxChatMediaRow? _oxChatMediaRowFromLiveTdVideoMessage(td.Message message, int chatId) {
  final content = message.content;
  if (content is td.MessageVideoNote) return null;
  if (content is td.MessageAnimation) return null;
  if (content is td.MessageDocument) {
    if (_tdlibDocumentLooksLikeAnimationOrGif(content.document)) return null;
  }
  return _oxChatMediaRowFromTdVideoMessage(message, chatId);
}

List<OxChatMediaRow> _rowsFromLiveVideoMessages(List<td.Message> messages, int chatId) {
  final out = <OxChatMediaRow>[];
  final seen = <String>{};
  for (final m in messages) {
    final row = _oxChatMediaRowFromLiveTdVideoMessage(m, chatId);
    if (row == null) continue;
    if (seen.add(row.messageId)) out.add(row);
  }
  return out;
}

int? _nextSearchAnchorFromVideoDocBatches(List<td.Message> videoMsgs, List<td.Message> docMsgs) {
  final ids = <int>[];
  if (videoMsgs.isNotEmpty) ids.add(videoMsgs.last.id);
  if (docMsgs.isNotEmpty) ids.add(docMsgs.last.id);
  if (ids.isEmpty) return null;
  return ids.reduce((a, b) => a < b ? a : b);
}

int? _forumTopicIdFromMessage(td.Message m) {
  final t = m.topicId;
  if (t is td.MessageTopicForum) return t.forumTopicId;
  return null;
}

List<td.Message> _filterTdMessagesForForumTopic(
  List<td.Message> messages, {
  required int topicId,
  required bool isForum,
}) {
  if (!isForum || topicId == 0) return messages;
  return messages
      .where((m) => _forumTopicIdFromMessage(m) == topicId)
      .toList(growable: false);
}

Future<void> _viewMessagesForSearchActivation(
  TdlibFacade tdlib, {
  required int chatId,
  td.Chat? chat,
}) async {
  var messageId = chat?.lastMessage?.id ?? 0;
  if (messageId <= 0) {
    try {
      final hist = await tdlib.send(
        td.GetChatHistory(
          chatId: chatId,
          fromMessageId: 0,
          offset: 0,
          limit: 1,
          onlyLocal: false,
        ),
      );
      final msgs = hist is td.Messages ? hist.messages : const <td.Message>[];
      if (msgs.isEmpty) return;
      messageId = msgs.first.id;
    } catch (_) {
      return;
    }
  }
  if (messageId <= 0) return;
  try {
    await tdlib.send(
      td.ViewMessages(
        chatId: chatId,
        messageIds: <int>[messageId],
        forceRead: false,
      ),
    );
  } catch (_) {}
}

/// TDLib live video/doc search for My Telegram (aligned with oxplayer-android [DataRepository.fetchLiveChatVideos]).
final class MyTelegramLiveMediaFetcher {
  MyTelegramLiveMediaFetcher(this._td);

  final TdlibFacade _td;
  static const int _tdLimit = 30;
  static const int _historyFallbackLimit = 60;
  static const int _historyFallbackMaxPages = 6;

  final Map<String, int> _chatIdCache = <String, int>{};

  Future<int> _resolveTdlibChatIdForMedia(int candidate) async {
    Future<int?> tryGetChat() async {
      try {
        final o = await _td.send(td.GetChat(chatId: candidate));
        if (o is td.Chat) return o.id;
      } on td.TdError {
        // ignore
      }
      return null;
    }

    final first = await tryGetChat();
    if (first != null) return first;

    if (candidate > 0) {
      try {
        final o = await _td.send(td.CreatePrivateChat(userId: candidate, force: false));
        if (o is td.Chat) return o.id;
      } on td.TdError {
        // ignore
      }
      return candidate;
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _td.send(const td.LoadChats(chatList: td.ChatListMain(), limit: 200));
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: 120 + attempt * 180));
      final again = await tryGetChat();
      if (again != null) return again;
    }
    return candidate;
  }

  Future<({int effectiveThreadId, bool omitMessageThreadId, bool isForum, td.Chat? chat})>
      _resolveThreadParams(int chatId, int requestedMessageThreadId) async {
    try {
      final resolved = await _td.send(td.GetChat(chatId: chatId));
      if (resolved is! td.Chat) {
        return (effectiveThreadId: requestedMessageThreadId, omitMessageThreadId: false, isForum: false, chat: null);
      }
      final type = resolved.type;
      if (type is td.ChatTypeSupergroup) {
        var isForum = false;
        try {
          final sg = await _td.send(td.GetSupergroup(supergroupId: type.supergroupId));
          if (sg is td.Supergroup) isForum = sg.isForum;
        } catch (_) {}
        if (isForum) {
          return (effectiveThreadId: requestedMessageThreadId, omitMessageThreadId: false, isForum: true, chat: resolved);
        }
        return (effectiveThreadId: 0, omitMessageThreadId: false, isForum: false, chat: resolved);
      }
      if (type is td.ChatTypePrivate || type is td.ChatTypeBasicGroup) {
        return (effectiveThreadId: 0, omitMessageThreadId: true, isForum: false, chat: resolved);
      }
      return (effectiveThreadId: 0, omitMessageThreadId: false, isForum: false, chat: resolved);
    } catch (_) {
      return (effectiveThreadId: requestedMessageThreadId, omitMessageThreadId: false, isForum: false, chat: null);
    }
  }

  Future<td.TdObject> _sendSearchFiltered({
    required int chatId,
    required td.SearchMessagesFilter filter,
    required int effectiveThreadId,
    required bool omitMessageThreadId,
    required bool isForum,
    int? continueFromMessageId,
  }) async {
    final fromId =
        (continueFromMessageId != null && continueFromMessageId > 0) ? continueFromMessageId : 0;
    return _td.send(
      _SearchChatMessagesFilteredRequest(
        chatId: chatId,
        fromMessageId: fromId,
        limit: _tdLimit,
        filter: filter,
        offsetInt: 0,
        messageThreadId: effectiveThreadId,
        omitMessageThreadId: omitMessageThreadId,
        isForum: isForum,
      ),
    );
  }

  Future<OxChatMediaPage> _fallbackFromHistory({
    required int chatId,
    required int effectiveThreadId,
    required bool isForum,
    required int searchAnchor,
  }) async {
    var fromMessageId = searchAnchor > 0 ? searchAnchor : 0;
    final collected = <OxChatMediaRow>[];
    var oldestSeen = 0;
    var reachedStart = false;

    for (var i = 0; i < _historyFallbackMaxPages; i++) {
      final td.TdObject hist;
      try {
        hist = await _tdSendWithTimeout(
          _td.send(
            td.GetChatHistory(
              chatId: chatId,
              fromMessageId: fromMessageId,
              offset: 0,
              limit: _historyFallbackLimit,
              onlyLocal: false,
            ),
          ),
          label: 'GetChatHistory(fallback p=${i + 1})',
        );
      } on TimeoutException {
        _mtLiveLog('history-fallback page=${i + 1} TIMEOUT; returning partial');
        break;
      }
      final msgs = hist is td.Messages ? hist.messages : const <td.Message>[];
      _mtLiveLog(
        'history-fallback page=${i + 1} from=$fromMessageId got=${msgs.length} forum=$isForum thread=$effectiveThreadId',
      );
      if (msgs.isEmpty) {
        reachedStart = true;
        break;
      }

      var filtered = msgs;
      if (isForum && effectiveThreadId > 0) {
        filtered = _filterTdMessagesForForumTopic(
          msgs,
          topicId: effectiveThreadId,
          isForum: isForum,
        );
      }
      if (searchAnchor > 0) {
        filtered = filtered.where((m) => m.id < searchAnchor).toList(growable: false);
      }

      final vRows = _rowsFromLiveVideoMessages(filtered, chatId);
      final dRows = _rowsFromDocumentSearchForMergedGallery(filtered, chatId);
      final pageRows = _dedupeOxChatMediaRowsByMessageId(<OxChatMediaRow>[...vRows, ...dRows]);
      collected.addAll(pageRows);

      oldestSeen = msgs.last.id;
      if (oldestSeen <= 0) {
        reachedStart = true;
        break;
      }
      fromMessageId = oldestSeen;
      if (pageRows.isNotEmpty) {
        break;
      }
    }

    final merged = _sortOxChatMediaRowsByMessageDateDesc(
      _dedupeOxChatMediaRowsByMessageId(collected),
    );
    final hasMore = !reachedStart && oldestSeen > 0;
    _mtLiveLog(
      'history-fallback done items=${merged.length} next=$oldestSeen hasMore=$hasMore',
    );
    return OxChatMediaPage(
      items: merged,
      total: merged.length + (hasMore ? 1 : 0),
      hasMoreHistory: hasMore,
      nextHistoryFromMessageId: hasMore ? oldestSeen : null,
      liveSearchUsesDocumentFilter: true,
    );
  }

  /// Loads the next page of video-like messages. [continueFromMessageId] is the oldest id from the previous batch.
  Future<OxChatMediaPage> fetchPage({
    required String tdlibChatId,
    int messageThreadId = 0,
    int? continueFromMessageId,
  }) async {
    _mtLiveLog(
      'fetchPage start chat=$tdlibChatId thread=$messageThreadId continueFrom=$continueFromMessageId',
    );
    final parsed = int.tryParse(tdlibChatId.trim());
    if (parsed == null) {
      return const OxChatMediaPage(items: [], total: 0);
    }

    var chatId = _chatIdCache[tdlibChatId.trim()] ?? await _resolveTdlibChatIdForMedia(parsed);
    _chatIdCache[tdlibChatId.trim()] = chatId;

    final tParams = await _resolveThreadParams(chatId, messageThreadId);
    var effectiveThreadId = tParams.effectiveThreadId;
    if (!tParams.isForum) {
      effectiveThreadId = 0;
    }
    final omit = tParams.omitMessageThreadId;
    final isForum = tParams.isForum;
    var chatSnap = tParams.chat;

    if (continueFromMessageId == null || continueFromMessageId <= 0) {
      if (chatSnap == null) {
        final o = await _td.send(td.GetChat(chatId: chatId));
        if (o is td.Chat) chatSnap = o;
      }
      try {
        await _td.send(td.OpenChat(chatId: chatId));
      } catch (_) {}
      if (chatSnap != null) {
        await _viewMessagesForSearchActivation(_td, chatId: chatId, chat: chatSnap);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } else {
        await _viewMessagesForSearchActivation(_td, chatId: chatId, chat: null);
      }
    }

    final searchAnchor =
        (continueFromMessageId ?? 0) > 0 ? (continueFromMessageId ?? 0) : 0;

    final fromForSearch = searchAnchor > 0 ? searchAnchor : null;
    _mtLiveLog('search video+doc steps anchor=$searchAnchor (fromId=${fromForSearch ?? 0})');
    final td.TdObject rawVideo;
    try {
      rawVideo = await _tdSendWithTimeout(
        _sendSearchFiltered(
          chatId: chatId,
          filter: const td.SearchMessagesFilterVideo(),
          effectiveThreadId: effectiveThreadId,
          omitMessageThreadId: omit,
          isForum: isForum,
          continueFromMessageId: fromForSearch,
        ),
        label: 'searchChatMessages(Video)',
      );
    } on TimeoutException {
      _mtLiveLog('search Video failed — history fallback for anchor=$searchAnchor');
      return _fallbackFromHistory(
        chatId: chatId,
        effectiveThreadId: effectiveThreadId,
        isForum: isForum,
        searchAnchor: searchAnchor,
      );
    }
    var videoMsgs = _tdMessagesFromSearchResult(rawVideo);
    if (isForum && effectiveThreadId > 0) {
      videoMsgs = _filterTdMessagesForForumTopic(videoMsgs, topicId: effectiveThreadId, isForum: isForum);
    }

    var docMsgs = const <td.Message>[];
    if (videoMsgs.length < _tdLimit) {
      try {
        final rawDoc = await _tdSendWithTimeout(
          _sendSearchFiltered(
            chatId: chatId,
            filter: const td.SearchMessagesFilterDocument(),
            effectiveThreadId: effectiveThreadId,
            omitMessageThreadId: omit,
            isForum: isForum,
            continueFromMessageId: fromForSearch,
          ),
          label: 'searchChatMessages(Document)',
        );
        var dm = _tdMessagesFromSearchResult(rawDoc);
        if (isForum && effectiveThreadId > 0) {
          dm = _filterTdMessagesForForumTopic(dm, topicId: effectiveThreadId, isForum: isForum);
        }
        docMsgs = dm;
      } on TimeoutException {
        _mtLiveLog('search Document timed out; using video search results only');
        docMsgs = const [];
      }
    }

    final videoRows = _rowsFromLiveVideoMessages(videoMsgs, chatId);
    final docRows = _rowsFromDocumentSearchForMergedGallery(docMsgs, chatId);
    var merged = _sortOxChatMediaRowsByMessageDateDesc(
      _dedupeOxChatMediaRowsByMessageId(<OxChatMediaRow>[...videoRows, ...docRows]),
    );
    _mtLiveLog(
      'search result videoMsgs=${videoMsgs.length} docMsgs=${docMsgs.length} merged=${merged.length} anchor=$searchAnchor',
    );

    if (merged.isEmpty && searchAnchor == 0) {
      try {
        final hist = await _td.send(
          td.GetChatHistory(
            chatId: chatId,
            fromMessageId: 0,
            offset: 0,
            limit: 50,
            onlyLocal: false,
          ),
        );
        final msgs = hist is td.Messages ? hist.messages : const <td.Message>[];
        var filtered = isForum && effectiveThreadId > 0
            ? _filterTdMessagesForForumTopic(msgs, topicId: effectiveThreadId, isForum: isForum)
            : msgs;
        final vRows = _rowsFromLiveVideoMessages(filtered, chatId);
        final dRows = _rowsFromDocumentSearchForMergedGallery(filtered, chatId);
        merged = _sortOxChatMediaRowsByMessageDateDesc(
          _dedupeOxChatMediaRowsByMessageId(<OxChatMediaRow>[...vRows, ...dRows]),
        );
        if (merged.isNotEmpty) {
          final nextAnchor = filtered.last.id;
          return OxChatMediaPage(
            items: merged,
            total: merged.length + 1,
            hasMoreHistory: nextAnchor > 0,
            nextHistoryFromMessageId: nextAnchor,
            liveSearchUsesDocumentFilter: false,
          );
        }
      } catch (_) {}
    }

    if (merged.isEmpty) {
      // TDLib search can occasionally return empty at a cursor even when older media exists.
      return _fallbackFromHistory(
        chatId: chatId,
        effectiveThreadId: effectiveThreadId,
        isForum: isForum,
        searchAnchor: searchAnchor,
      );
    }

    final next = _nextSearchAnchorFromVideoDocBatches(
      isForum && effectiveThreadId > 0
          ? _filterTdMessagesForForumTopic(videoMsgs, topicId: effectiveThreadId, isForum: isForum)
          : videoMsgs,
      isForum && effectiveThreadId > 0
          ? _filterTdMessagesForForumTopic(docMsgs, topicId: effectiveThreadId, isForum: isForum)
          : docMsgs,
    );
    final hasMore = next != null && next > 0;
    _mtLiveLog('fetchPage done items=${merged.length} next=$next hasMore=$hasMore');
    return OxChatMediaPage(
      items: merged,
      total: merged.length + (hasMore ? 1 : 0),
      hasMoreHistory: hasMore,
      nextHistoryFromMessageId: next,
      liveSearchUsesDocumentFilter: docMsgs.isNotEmpty,
    );
  }
}
