import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';

List<OxChatMediaRow> mergeOxChatMediaRowsByMessageIdPreferNewerList(
  List<OxChatMediaRow> fromNetworkNewestFirst,
  List<OxChatMediaRow> existing,
) {
  final by = <String, OxChatMediaRow>{};
  for (final e in existing) {
    if (e.messageId.isNotEmpty) {
      by[e.messageId] = e;
    }
  }
  for (final n in fromNetworkNewestFirst) {
    if (n.messageId.isNotEmpty) {
      by[n.messageId] = n;
    }
  }
  final out = by.values.toList();
  out.sort((a, b) {
    final da = DateTime.tryParse(a.messageDate ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final db = DateTime.tryParse(b.messageDate ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return db.compareTo(da);
  });
  return out;
}
