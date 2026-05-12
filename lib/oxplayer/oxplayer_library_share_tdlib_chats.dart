import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/oxplayer/telegram/source_chats_tdlib.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';

/// Chats the signed-in Telegram user can post to (main dialog list via TDLib).
///
/// Unlike [OxplayerUserChatsClient.fetchUserChats], this does not require rows
/// in the OX API `Chat` table (indexing / "My Telegram" sync).
Future<List<OxUserChatRow>> oxplayerLoadSharePickerChatsFromTdlib(
  TdlibFacade facade, {
  int limit = 200,
}) async {
  final self = await tdlibGetSelfUserId(facade);
  await tdlibLoadChatsPage(facade, limit: limit);
  final ids = await tdlibGetMainChatIds(facade, limit);
  final rows = <OxUserChatRow>[];
  final seen = <int>{};
  for (final id in ids) {
    if (!seen.add(id)) continue;
    final chat = await tdlibGetChat(facade, id);
    if (chat == null) continue;
    final picker = await tdlibBuildPickerRow(
      facade: facade,
      chat: chat,
      selfUserId: self,
      savedMessagesTitle: 'Saved Messages',
    );
    if (picker == null) continue;
    // User messages as self: channels usually fail; skip for a cleaner list.
    if (picker.apiChatType == 'channel') continue;

    rows.add(
      OxUserChatRow(
        id: 'td_${picker.chatId}',
        tdlibChatId: picker.chatId.toString(),
        title: picker.title,
        photoUrl: null,
        chatType: picker.apiChatType,
        peerIsBot: picker.peerIsBot,
        isForum: picker.isForum,
        isIndexed: false,
        showInVideo: false,
        showInMusic: false,
      ),
    );
  }
  rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return rows;
}
