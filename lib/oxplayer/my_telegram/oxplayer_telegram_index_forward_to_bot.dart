import 'package:flutter/foundation.dart';
import 'package:fladder/td_api_generated/td_api.dart' as tda;

import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';

/// After a video is [ingest]ed on the OX API, also sends a copy to the main bot user from
/// [OxplayerEnv.botUsername] (env `BOT_USERNAME` / `OXPLAYER_BOT_USERNAME`) so the same pipeline
/// the bot would see from a normal forward is available. Best-effort: no throw; logs on failure.
Future<void> tryForwardIndexedMessageToEnvBot({
  required int fromChatId,
  required int messageId,
}) async {
  if (kIsWeb) return;
  if (!await OxplayerTelegramTdSession.ensureReadyForPlayback()) {
    return;
  }
  final s = OxplayerTelegramTdSession();
  final botChatId = await s.resolveMainBotPrivateChatId();
  if (botChatId == null) {
    if (kDebugMode) {
      debugPrint(
        '[MyTelegram index] forward to bot: skip (BOT_USERNAME unset or not resolvable)',
      );
    }
    return;
  }
  try {
    await s.td.send(
      tda.ForwardMessages(
        chatId: botChatId,
        topicId: null,
        fromChatId: fromChatId,
        messageIds: [messageId],
        options: null,
        // Copy avoids "cannot forward" on many channel posts while still delivering media to the bot.
        sendCopy: true,
        removeCaption: false,
      ),
    );
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[MyTelegram index] forward to BOT_USERNAME chat failed: $e\n$st');
    }
  }
}
