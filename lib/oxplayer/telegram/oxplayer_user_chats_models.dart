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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      if (tdlibChatId != null) 'tdlibChatId': tdlibChatId,
      'title': title,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'chatType': chatType,
      'peerIsBot': peerIsBot,
      'isForum': isForum,
      'isIndexed': isIndexed,
      'showInVideo': showInVideo,
      'showInMusic': showInMusic,
    };
  }

  factory OxUserChatRow.fromJson(Map<String, dynamic> json) {
    return OxUserChatRow(
      id: json['id']?.toString() ?? '',
      tdlibChatId: json['tdlibChatId']?.toString(),
      title: json['title']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString(),
      chatType: json['chatType']?.toString() ?? 'private',
      peerIsBot: json['peerIsBot'] == true,
      isForum: json['isForum'] == true,
      isIndexed: json['isIndexed'] == true,
      showInVideo: json['showInVideo'] == true,
      showInMusic: json['showInMusic'] == true,
    );
  }
}

class OxUserChatListPage {
  const OxUserChatListPage({required this.items, required this.total});

  final List<OxUserChatRow> items;
  final int total;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'items': items.map((e) => e.toJson()).toList(),
      'total': total,
    };
  }

  factory OxUserChatListPage.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    return OxUserChatListPage(
      items: itemsRaw is List
          ? itemsRaw
              .whereType<Map>()
              .map((e) => OxUserChatRow.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.id.isNotEmpty)
              .toList()
          : const [],
      total: json['total'] is int
          ? json['total'] as int
          : int.tryParse(json['total']?.toString() ?? '') ?? 0,
    );
  }
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fileId': fileId,
      'messageId': messageId,
      if (remoteFileId != null) 'remoteFileId': remoteFileId,
      if (caption != null) 'caption': caption,
      if (messageDate != null) 'messageDate': messageDate,
      if (fileName != null) 'fileName': fileName,
      if (chatId != null) 'chatId': chatId,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
      if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
    };
  }

  factory OxChatMediaRow.fromJson(Map<String, dynamic> json) {
    return OxChatMediaRow(
      fileId: json['fileId']?.toString() ?? '',
      messageId: json['messageId']?.toString() ?? '',
      remoteFileId: json['remoteFileId']?.toString(),
      caption: json['caption']?.toString(),
      messageDate: json['messageDate']?.toString(),
      fileName: json['fileName']?.toString(),
      chatId: json['chatId'] is int
          ? json['chatId'] as int
          : int.tryParse(json['chatId']?.toString() ?? ''),
      durationSeconds: json['durationSeconds'] is int
          ? json['durationSeconds'] as int
          : int.tryParse(json['durationSeconds']?.toString() ?? ''),
      fileSizeBytes: json['fileSizeBytes'] is int
          ? json['fileSizeBytes'] as int
          : int.tryParse(json['fileSizeBytes']?.toString() ?? ''),
    );
  }
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'items': items.map((e) => e.toJson()).toList(),
      'total': total,
      'hasMoreHistory': hasMoreHistory,
      if (nextHistoryFromMessageId != null) 'nextHistoryFromMessageId': nextHistoryFromMessageId,
      'liveSearchUsesDocumentFilter': liveSearchUsesDocumentFilter,
    };
  }

  factory OxChatMediaPage.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    return OxChatMediaPage(
      items: itemsRaw is List
          ? itemsRaw
              .whereType<Map>()
              .map((e) => OxChatMediaRow.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.fileId.isNotEmpty && e.messageId.isNotEmpty)
              .toList()
          : const [],
      total: json['total'] is int
          ? json['total'] as int
          : int.tryParse(json['total']?.toString() ?? '') ?? 0,
      hasMoreHistory: json['hasMoreHistory'] == true,
      nextHistoryFromMessageId: json['nextHistoryFromMessageId'] is int
          ? json['nextHistoryFromMessageId'] as int
          : int.tryParse(json['nextHistoryFromMessageId']?.toString() ?? ''),
      liveSearchUsesDocumentFilter: json['liveSearchUsesDocumentFilter'] == true,
    );
  }
}
