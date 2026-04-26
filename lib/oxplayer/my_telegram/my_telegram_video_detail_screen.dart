import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:tdlib/td_api.dart' as tda;

import 'package:fladder/oxplayer/my_telegram/my_telegram_index_refresh.dart';
import 'package:fladder/oxplayer/my_telegram/my_telegram_formatters.dart';
import 'package:fladder/oxplayer/my_telegram/oxplayer_my_telegram_playback_model.dart';
import 'package:fladder/oxplayer/my_telegram/oxplayer_telegram_index_forward_to_bot.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_client.dart';
import 'package:fladder/oxplayer/telegram/telegram_message_thumbnail.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class MyTelegramVideoDetailScreen extends ConsumerStatefulWidget {
  const MyTelegramVideoDetailScreen({
    super.key,
    required this.chatTitle,
    required this.tdlibChatId,
    this.messageThreadId = 0,
    this.isForum = false,
    required this.chatIsIndexed,
    required this.messageId,
    required this.fileId,
    this.caption,
    this.fileName,
    this.messageDate,
    this.remoteFileId,
    this.durationSeconds,
  });

  final String chatTitle;
  final String tdlibChatId;
  final int messageThreadId;
  final bool isForum;
  /// Whether this dialog is marked for library indexing in OX (`isIndexed` on the chat row).
  final bool chatIsIndexed;
  final String messageId;
  final String fileId;
  final String? caption;
  final String? fileName;
  final String? messageDate;
  final String? remoteFileId;
  final int? durationSeconds;

  @override
  ConsumerState<MyTelegramVideoDetailScreen> createState() => _MyTelegramVideoDetailScreenState();
}

class _MyTelegramVideoDetailScreenState extends ConsumerState<MyTelegramVideoDetailScreen> {
  String? _senderLabel;
  var _loadingSender = true;
  var _indexing = false;
  /// Set while [Item.play] is running (including the fullscreen session); avoids double start.
  var _playInFlight = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSender());
    } else {
      _loadingSender = false;
    }
  }

  Future<void> _loadSender() async {
    final chatId = int.tryParse(widget.tdlibChatId);
    final msgId = int.tryParse(widget.messageId);
    if (chatId == null || msgId == null) {
      if (mounted) setState(() => _loadingSender = false);
      return;
    }
    try {
      if (!await OxplayerTelegramTdSession.ensureReadyForPlayback()) {
        if (mounted) setState(() => _loadingSender = false);
        return;
      }
      final td = OxplayerTelegramTdSession().td;
      final o = await td.send(tda.GetMessage(chatId: chatId, messageId: msgId));
      if (o is! tda.Message) {
        if (mounted) setState(() => _loadingSender = false);
        return;
      }
      String? label;
      final s = o.senderId;
      if (s is tda.MessageSenderUser) {
        final u = await td.send(tda.GetUser(userId: s.userId));
        if (u is tda.User) {
          final p = <String>[u.firstName, u.lastName].where((e) => e.trim().isNotEmpty).join(' ');
          label = p.isNotEmpty ? p : 'User ${u.id}';
        }
      } else if (s is tda.MessageSenderChat) {
        final c = await td.send(tda.GetChat(chatId: s.chatId));
        if (c is tda.Chat) {
          label = c.title;
        }
      }
      if (mounted) {
        setState(() {
          _senderLabel = label;
          _loadingSender = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSender = false);
    }
  }

  Future<void> _onPlay() async {
    if (_playInFlight) {
      return;
    }
    final chatId = int.tryParse(widget.tdlibChatId);
    final messageId = int.tryParse(widget.messageId);
    if (chatId == null || messageId == null) {
      _messengerSnack(context.localized.unableToPlayMedia);
      return;
    }
    setState(() => _playInFlight = true);
    try {
      final l = context.localized;
      final name = (widget.caption?.trim().isNotEmpty == true)
          ? widget.caption!.trim()
          : (widget.fileName?.trim().isNotEmpty == true)
              ? widget.fileName!.trim()
              : l.myTelegramVideo;
      final item = buildOxTelegramHubPlayItem(
        chatId: chatId,
        messageId: messageId,
        name: name,
      );
      // Same as library: loading dialog, then loadPlaybackItem, await [openPlayer] until user exits.
      await item.play(context, ref);
    } finally {
      if (mounted) {
        setState(() => _playInFlight = false);
      }
    }
  }

  void _messengerSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// OX [ingest] requires a `Chat` row. Mirroring Configure, we upsert from TDLib first.
  Future<void> _ensureChatRowInOx(OxplayerUserChatsClient api) async {
    final id = int.tryParse(widget.tdlibChatId);
    if (id == null) {
      throw StateError('Invalid tdlib chat id');
    }
    if (!await OxplayerTelegramTdSession.ensureReadyForPlayback()) {
      throw StateError('Telegram is not ready');
    }
    final td = OxplayerTelegramTdSession().td;
    final co = await td.send(tda.GetChat(chatId: id));
    if (co is! tda.Chat) {
      throw StateError('Could not load chat');
    }
    final title = co.title;
    final type = co.type;
    var chatType = 'private';
    var peerIsBot = false;
    var isForum = false;
    if (type is tda.ChatTypePrivate) {
      chatType = 'private';
      final uo = await td.send(tda.GetUser(userId: type.userId));
      if (uo is tda.User) {
        peerIsBot = uo.type is tda.UserTypeBot;
      }
    } else if (type is tda.ChatTypeBasicGroup) {
      chatType = 'group';
    } else if (type is tda.ChatTypeSupergroup) {
      if (type.isChannel) {
        chatType = 'channel';
      } else {
        final sg = await td.send(tda.GetSupergroup(supergroupId: type.supergroupId));
        if (sg is tda.Supergroup) {
          isForum = sg.isForum;
        }
        chatType = 'supergroup';
      }
    } else if (type is tda.ChatTypeSecret) {
      chatType = 'private';
    }
    await api.upsertUserChatMapping(
      tdlibChatId: id,
      title: title,
      chatType: chatType,
      peerIsBot: peerIsBot,
      isForum: isForum,
    );
  }

  Future<void> _onAddToIndex() async {
    if (kIsWeb) {
      _messengerSnack(context.localized.myTelegramIndexNeedSignIn);
      return;
    }
    final api = ref.read(oxplayerUserChatsClientProvider);
    if (api == null) {
      _messengerSnack(context.localized.myTelegramIndexNeedSignIn);
      return;
    }
    setState(() => _indexing = true);
    try {
      await _ensureChatRowInOx(api);
      await api.patchUserChatsIndexed(
        items: <Map<String, dynamic>>[
          <String, dynamic>{'tdlibChatId': widget.tdlibChatId, 'isIndexed': true},
        ],
      );
      final item = <String, dynamic>{
        'messageId': widget.messageId,
        if (widget.remoteFileId != null && widget.remoteFileId!.isNotEmpty) 'remoteFileId': widget.remoteFileId,
        if (widget.caption != null && widget.caption!.trim().isNotEmpty) 'caption': widget.caption,
        if (widget.messageDate != null && widget.messageDate!.isNotEmpty) 'messageDate': widget.messageDate,
        if (widget.messageThreadId != 0) 'messageThreadId': widget.messageThreadId,
      };
      final r = await api.ingestChatMedia(
        tdlibChatId: widget.tdlibChatId,
        items: <Map<String, dynamic>>[item],
        lastIndexedMessageId: widget.messageId,
      );
      if (!mounted) {
        return;
      }
      if (r.upserted > 0) {
        ref.read(myTelegramIndexedIngestBumpedProvider.notifier).state =
            ref.read(myTelegramIndexedIngestBumpedProvider) + 1;
        unawaited(
          tryForwardIndexedMessageToEnvBot(
            fromChatId: int.parse(widget.tdlibChatId),
            messageId: int.parse(widget.messageId),
          ),
        );
      }
      final msg = context.localized.myTelegramIndexQueued(r.upserted);
      _messengerSnack(msg);
      FladderSnack.show(msg, context: context);
    } catch (e) {
      if (mounted) {
        final m = '${context.localized.myTelegramError}: $e';
        _messengerSnack(m);
        FladderSnack.show(m, context: context);
      }
    } finally {
      if (mounted) {
        setState(() => _indexing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.localized;
    final scheme = Theme.of(context).colorScheme;
    final detailChatId = int.tryParse(widget.tdlibChatId) ?? 0;
    final detailMessageId = int.tryParse(widget.messageId) ?? 0;
    return Scaffold(
          appBar: AppBar(title: Text(l.myTelegramVideoDetails)),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
          ClipRRect(
            borderRadius: FladderTheme.defaultShape.borderRadius,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: kIsWeb
                  ? ColoredBox(
                      color: scheme.surfaceContainerHigh,
                      child: const Center(child: Icon(IconsaxPlusLinear.video, size: 64)),
                    )
                  : TdlibMessageVideoThumbnail(
                      chatId: detailChatId,
                      messageId: detailMessageId,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (kIsWeb || _playInFlight || _indexing) ? null : _onPlay,
            icon: const Icon(IconsaxPlusLinear.play),
            label: Text(l.myTelegramPlay),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_playInFlight || _indexing) ? null : _onAddToIndex,
            icon: _indexing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(IconsaxPlusLinear.save_2),
            label: Text(l.myTelegramAddToLibraryIndex),
          ),
          const SizedBox(height: 20),
          Text(
            (widget.caption?.trim().isNotEmpty == true)
                ? widget.caption!
                : (widget.fileName?.trim().isNotEmpty == true)
                    ? widget.fileName!
                    : l.myTelegramVideo,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _MetaRow(icon: IconsaxPlusLinear.user, label: l.myTelegramDetailSender, value: _loadingSender ? '…' : (_senderLabel ?? '—')),
          const SizedBox(height: 6),
          _MetaRow(
            icon: IconsaxPlusLinear.message,
            label: l.myTelegramDetailFolder,
            value: widget.chatTitle,
          ),
          if (widget.messageDate != null && widget.messageDate!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _MetaRow(icon: IconsaxPlusLinear.calendar, label: l.myTelegramDetailDate, value: widget.messageDate!),
          ],
          if (widget.durationSeconds != null && widget.durationSeconds! > 0) ...[
            const SizedBox(height: 6),
            _MetaRow(
              icon: IconsaxPlusLinear.timer_1,
              label: l.myTelegramDetailDuration,
              value: myTelegramFormatDurationHms(widget.durationSeconds!),
            ),
          ],
          const SizedBox(height: 6),
          _MetaRow(
            icon: IconsaxPlusLinear.information,
            label: l.myTelegramDetailMessageId,
            value: widget.messageId,
          ),
          if (widget.isForum && widget.messageThreadId != 0) ...[
            const SizedBox(height: 6),
            _MetaRow(
              icon: IconsaxPlusLinear.hashtag,
              label: l.myTelegramDetailTopic,
              value: '${widget.messageThreadId}',
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
