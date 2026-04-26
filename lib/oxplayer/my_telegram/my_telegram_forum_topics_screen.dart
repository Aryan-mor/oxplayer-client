import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tdlib/td_api.dart' as td;

import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/source_chats_tdlib.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class MyTelegramForumTopicsScreen extends ConsumerStatefulWidget {
  const MyTelegramForumTopicsScreen({
    super.key,
    required this.chatTitle,
    required this.tdlibChatId,
  });

  final String chatTitle;
  final String tdlibChatId;

  @override
  ConsumerState<MyTelegramForumTopicsScreen> createState() => _MyTelegramForumTopicsScreenState();
}

class _MyTelegramForumTopicsScreenState extends ConsumerState<MyTelegramForumTopicsScreen> {
  List<td.ForumTopic>? _topics;
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (kIsWeb) {
      setState(() {
        _loading = false;
        _error = 'Not on web';
      });
      return;
    }
    final id = int.tryParse(widget.tdlibChatId);
    if (id == null) {
      setState(() {
        _loading = false;
        _error = 'bad id';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      await OxplayerTelegramTdSession().initClient();
      await OxplayerTelegramTdSession().td.ensureAuthorized();
      final topics = await tdlibLoadAllForumTopics(OxplayerTelegramTdSession().td, id);
      if (mounted) {
        setState(() {
          _topics = topics;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeTdlibError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.localized;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.chatTitle} · ${l.myTelegramForumTopics}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      ListTile(
                        title: Text(l.all),
                        onTap: () {
                          context.router.push(
                            MyTelegramChatMediaRoute(
                              chatTitle: widget.chatTitle,
                              tdlibChatId: widget.tdlibChatId,
                              libraryIndexed: false,
                              messageThreadId: 0,
                              isForum: true,
                            ),
                          );
                        },
                      ),
                      if (_topics != null)
                        for (final top in _topics!)
                          ListTile(
                            title: Text(top.info.name.trim().isEmpty ? '…' : top.info.name.trim()),
                            onTap: () {
                              context.router.push(
                                MyTelegramChatMediaRoute(
                                  chatTitle: top.info.name.trim().isEmpty ? '…' : top.info.name.trim(),
                                  tdlibChatId: widget.tdlibChatId,
                                  libraryIndexed: false,
                                  messageThreadId: top.info.messageThreadId,
                                  isForum: true,
                                ),
                              );
                            },
                          ),
                    ],
                  ),
                ),
    );
  }
}
