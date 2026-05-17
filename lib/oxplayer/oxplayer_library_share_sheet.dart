import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fladder/td_api_generated/td_api.dart' as td;

import 'package:fladder/oxplayer/oxplayer_library_share_api.dart';
import 'package:fladder/oxplayer/oxplayer_library_share_tdlib_chats.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_formatted_from_segments.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';

/// Picks a Telegram chat and sends the server-built share message via TDLib.
Future<void> showOxplayerLibraryShareSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
}) async {
  if (kIsWeb) {
    FladderSnack.show('Sharing is available in the mobile app with Telegram.', context: context);
    return;
  }

  final payload = await oxplayerPostLibraryShare(ref, itemId);
  if (!context.mounted) return;
  if (payload == null) {
    FladderSnack.show('Could not create a share link.', context: context);
    return;
  }

  if (!await OxplayerTelegramTdSession.ensureReadyForPlayback()) {
    if (!context.mounted) return;
    FladderSnack.show('Telegram is not ready. Open My Telegram and sign in.', context: context);
    return;
  }

  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => _ShareChatPickerPage(payload: payload),
    ),
  );
}

class _ShareChatPickerPage extends StatefulWidget {
  const _ShareChatPickerPage({required this.payload});

  final OxplayerLibrarySharePayload payload;

  @override
  State<_ShareChatPickerPage> createState() => _ShareChatPickerPageState();
}

class _ShareChatPickerPageState extends State<_ShareChatPickerPage> {
  late Future<List<OxUserChatRow>> _future;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _loadChats();
    _search.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  Future<List<OxUserChatRow>> _loadChats() async {
    final facade = OxplayerTelegramTdSession().td;
    return oxplayerLoadSharePickerChatsFromTdlib(facade, limit: 200);
  }

  List<OxUserChatRow> _filterRows(List<OxUserChatRow> rows) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where(
          (r) =>
              r.title.toLowerCase().contains(q) ||
              r.chatType.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _sendToChat(int chatId) async {
    final facade = OxplayerTelegramTdSession().td;
    final html = widget.payload.telegramMessageHtml;
    td.FormattedText formatted;
    try {
      final parsed = await facade.send(
        td.ParseTextEntities(
          text: html,
          parseMode: const td.TextParseModeHTML(),
        ),
      );
      if (parsed is td.FormattedText) {
        formatted = oxplayerSanitizeFormattedTextForTdSend(parsed);
      } else {
        formatted = oxplayerFormattedTextFromShareSegments(widget.payload.telegramMessageSegments);
      }
    } catch (_) {
      formatted = oxplayerFormattedTextFromShareSegments(widget.payload.telegramMessageSegments);
    }
    await facade.send(
      td.SendMessage(
        chatId: chatId,
        topicId: null,
        inputMessageContent: td.InputMessageText(
          text: formatted,
          linkPreviewOptions: const td.LinkPreviewOptions(
            isDisabled: true,
            url: '',
            forceSmallMedia: false,
            forceLargeMedia: false,
            showAboveText: false,
          ),
          clearDraft: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share via Telegram'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search chats',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<OxUserChatRow>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load chats: ${snapshot.error}', maxLines: 8),
                    );
                  }
                  final rows = snapshot.data!;
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No chats found. Open Telegram on this device and wait for your chat list to load, then try again.',
                      ),
                    );
                  }
                  final filtered = _filterRows(rows);
                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No chats match your search.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final r = filtered[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              r.photoUrl != null && r.photoUrl!.isNotEmpty ? NetworkImage(r.photoUrl!) : null,
                          child: r.photoUrl == null || r.photoUrl!.isEmpty
                              ? Text(r.title.isNotEmpty ? r.title[0].toUpperCase() : '?')
                              : null,
                        ),
                        title: Text(r.title),
                        subtitle: Text(r.chatType),
                        onTap: () async {
                          final raw = r.tdlibChatId?.trim();
                          if (raw == null || raw.isEmpty) {
                            if (context.mounted) {
                              FladderSnack.show('Missing chat id for this row.', context: context);
                            }
                            return;
                          }
                          final chatId = int.tryParse(raw);
                          if (chatId == null) {
                            if (context.mounted) {
                              FladderSnack.show('Invalid chat id.', context: context);
                            }
                            return;
                          }
                          Navigator.of(context).pop();
                          try {
                            await _sendToChat(chatId);
                            if (context.mounted) {
                              FladderSnack.show('Message sent.', context: context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              FladderSnack.show('Could not send: $e', context: context);
                            }
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
