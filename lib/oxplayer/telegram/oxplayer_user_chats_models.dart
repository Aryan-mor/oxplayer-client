/// OX API `GET /me/chats` `bucket` query (aligned with [OxUserChatBucket]).
enum OxUserChatBucket {
  chats,
  groups,
  supergroups,
  channels,
  bots;

  String get apiValue => name;
}

const oxUserChatBucketApiValues = <String>[
  'chats',
  'groups',
  'supergroups',
  'channels',
  'bots',
];

/// One row from `GET /me/chats`.
class OxUserChatRow {
  const OxUserChatRow({
    required this.id,
    this.tdlibChatId,
    required this.title,
    this.photoUrl,
    required this.chatType,
    required this.peerIsBot,
    this.isForum = false,
    required this.isIndexed,
    required this.showInVideo,
    required this.showInMusic,
  });

  final String id;
  final String? tdlibChatId;
  final String title;
  final String? photoUrl;
  final String chatType;
  final bool peerIsBot;
  final bool isForum;
  final bool isIndexed;
  final bool showInVideo;
  final bool showInMusic;
}

class OxUserChatListPage {
  const OxUserChatListPage({required this.items, required this.total});

  final List<OxUserChatRow> items;
  final int total;
}

/// One row from `GET /me/chats/by-tdlib-id/:id/media`.
class OxChatMediaRow {
  const OxChatMediaRow({
    required this.fileId,
    required this.messageId,
    this.remoteFileId,
    this.caption,
    this.messageDate,
    this.fileName,
    this.chatId,
    this.durationSeconds,
    this.fileSizeBytes,
  });

  final String fileId;
  final String messageId;
  final String? remoteFileId;
  final String? caption;
  final String? messageDate;
  final String? fileName;
  final int? chatId;
  final int? durationSeconds;
  final int? fileSizeBytes;
}

class OxChatMediaPage {
  const OxChatMediaPage({
    required this.items,
    required this.total,
    this.hasMoreHistory = false,
    this.nextHistoryFromMessageId,
    this.liveSearchUsesDocumentFilter = false,
  });

  final List<OxChatMediaRow> items;
  final int total;
  final bool hasMoreHistory;
  final int? nextHistoryFromMessageId;
  final bool liveSearchUsesDocumentFilter;
}
