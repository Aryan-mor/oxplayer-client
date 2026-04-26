import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/my_telegram/my_telegram_index_refresh.dart';
import 'package:fladder/oxplayer/my_telegram/my_telegram_ui_widgets.dart';
import 'package:fladder/oxplayer/telegram/my_telegram_live_fetcher.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_client.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';

const bool _kMyTelegramChatMediaVerboseLog = true;
void _mtMediaLog(String m) {
  if (_kMyTelegramChatMediaVerboseLog) {
    debugPrint('[MyTelegram media] $m');
  }
}

@RoutePage()
class MyTelegramChatMediaScreen extends ConsumerStatefulWidget {
  const MyTelegramChatMediaScreen({
    super.key,
    required this.chatTitle,
    required this.tdlibChatId,
    this.libraryIndexed = false,
    this.messageThreadId = 0,
    this.isForum = false,
  });

  final String chatTitle;
  final String tdlibChatId;
  final bool libraryIndexed;
  final int messageThreadId;
  final bool isForum;

  @override
  ConsumerState<MyTelegramChatMediaScreen> createState() => _MyTelegramChatMediaScreenState();
}

class _MyTelegramChatMediaScreenState extends ConsumerState<MyTelegramChatMediaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _indexedItems = <OxChatMediaRow>[];
  final _liveItems = <OxChatMediaRow>[];
  int? _nextLive;
  int _offIndexed = 0;
  var _loadingIndexed = true;
  var _loadingLive = true;
  var _hasMoreIndexed = true;
  var _hasMoreLive = true;
  bool _indexedInFlight = false;
  bool _liveInFlight = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final showIndexed = widget.libraryIndexed;
    _tabController = TabController(
      length: showIndexed ? 2 : 1,
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mtMediaLog('(1) init chatId=${widget.tdlibChatId} indexed=${widget.libraryIndexed} thread=${widget.messageThreadId}');
      if (showIndexed) {
        _loadIndexed();
      } else {
        setState(() => _loadingIndexed = false);
      }
      _loadLive();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadIndexed() async {
    if (_indexedInFlight) {
      _mtMediaLog('(2) skip _loadIndexed (already in-flight)');
      return;
    }
    _indexedInFlight = true;
    final api = ref.read(oxplayerUserChatsClientProvider);
    if (api == null) {
      _mtMediaLog('(2) _loadIndexed: api client is null');
      setState(() {
        _loadingIndexed = false;
        _error = 'Not signed in';
      });
      _indexedInFlight = false;
      return;
    }
    _mtMediaLog('(2) _loadIndexed start offset=$_offIndexed');
    setState(() => _loadingIndexed = true);
    try {
      final page = await api.fetchIndexedChatMedia(
        tdlibChatId: widget.tdlibChatId,
        messageThreadId: widget.messageThreadId == 0 ? null : widget.messageThreadId,
        limit: 40,
        offset: _offIndexed,
      );
      if (!mounted) return;
      setState(() {
        if (_offIndexed == 0) {
          _indexedItems
            ..clear()
            ..addAll(page.items);
        } else {
          _indexedItems.addAll(page.items);
        }
        _hasMoreIndexed = page.hasMoreHistory;
        _offIndexed += page.items.length;
        _loadingIndexed = false;
      });
      _mtMediaLog('(2) _loadIndexed done items=${page.items.length} nextOffset=$_offIndexed hasMore=$_hasMoreIndexed');
    } catch (e) {
      _mtMediaLog('(2) _loadIndexed ERROR: $e');
      if (mounted) {
        setState(() {
          _loadingIndexed = false;
          _error = '$e';
        });
      }
    } finally {
      _indexedInFlight = false;
    }
  }

  Future<void> _loadLive() async {
    if (_liveInFlight) {
      _mtMediaLog('(3) skip _loadLive (already in-flight)');
      return;
    }
    _liveInFlight = true;
    if (kIsWeb) {
      _mtMediaLog('(3) _loadLive web — disabled');
      setState(() {
        _loadingLive = false;
        _hasMoreLive = false;
      });
      _liveInFlight = false;
      return;
    }
    if (!OxplayerConfig.isEnabled) {
      _mtMediaLog('(3) _loadLive ox disabled');
      setState(() => _loadingLive = false);
      _liveInFlight = false;
      return;
    }
    _mtMediaLog('(3) _loadLive start fromMessageId=$_nextLive');
    setState(() => _loadingLive = true);
    try {
      await OxplayerTelegramTdSession().initClient();
      await OxplayerTelegramTdSession().td.ensureAuthorized();
      final fetcher = MyTelegramLiveMediaFetcher(OxplayerTelegramTdSession().td);
      final page = await fetcher.fetchPage(
        tdlibChatId: widget.tdlibChatId,
        messageThreadId: widget.messageThreadId,
        continueFromMessageId: _nextLive,
      );
      if (!mounted) return;
      setState(() {
        if (_nextLive == null) {
          _liveItems
            ..clear()
            ..addAll(page.items);
        } else {
          _liveItems.addAll(page.items);
        }
        _nextLive = page.nextHistoryFromMessageId;
        _hasMoreLive = page.hasMoreHistory;
        _loadingLive = false;
      });
      _mtMediaLog('(3) _loadLive done items=${page.items.length} next=$_nextLive hasMore=$_hasMoreLive');
    } catch (e) {
      _mtMediaLog('(3) _loadLive ERROR: $e');
      if (mounted) {
        setState(() {
          _loadingLive = false;
          _error = '$_error\n$e';
        });
      }
    } finally {
      _liveInFlight = false;
    }
  }

  void _openVideoDetail(OxChatMediaRow row) {
    context.router.push(
      MyTelegramVideoDetailRoute(
        chatTitle: widget.chatTitle,
        tdlibChatId: widget.tdlibChatId,
        messageThreadId: widget.messageThreadId,
        isForum: widget.isForum,
        chatIsIndexed: widget.libraryIndexed,
        messageId: row.messageId,
        fileId: row.fileId,
        caption: row.caption,
        fileName: row.fileName,
        messageDate: row.messageDate,
        remoteFileId: row.remoteFileId,
        durationSeconds: row.durationSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(myTelegramIndexedIngestBumpedProvider, (prev, next) {
      if (widget.libraryIndexed) {
        setState(() {
          _offIndexed = 0;
          _indexedItems.clear();
        });
        unawaited(_loadIndexed());
      }
    });
    final l = context.localized;
    final showIndexed = widget.libraryIndexed;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatTitle),
        bottom: showIndexed
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: l.myTelegramIndexed),
                  Tab(text: l.myTelegramLive),
                ],
              )
            : null,
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : showIndexed
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMediaGrid(
                      items: _indexedItems,
                      loading: _loadingIndexed,
                      hasMore: _hasMoreIndexed,
                      onLoadMore: _loadIndexed,
                    ),
                    _buildMediaGrid(
                      items: _liveItems,
                      loading: _loadingLive,
                      hasMore: _hasMoreLive,
                      onLoadMore: _loadLive,
                    ),
                  ],
                )
              : _buildMediaGrid(
                  items: _liveItems,
                  loading: _loadingLive,
                  hasMore: _hasMoreLive,
                  onLoadMore: _loadLive,
                ),
    );
  }

  Widget _buildMediaGrid({
    required List<OxChatMediaRow> items,
    required bool loading,
    required bool hasMore,
    required Future<void> Function() onLoadMore,
  }) {
    final l = context.localized;
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          Icon(IconsaxPlusLinear.video, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(l.myTelegramNothingToShow, textAlign: TextAlign.center),
        ],
      );
    }
    final cross = myTelegramPosterGridCrossAxisCount(context, ref);
    final ar = myTelegramVideoGridChildAspectRatio(context, ref);
    return PullToRefresh(
      onRefresh: () async {
        _mtMediaLog('(4) pull-to-refresh start');
        setState(() {
          _offIndexed = 0;
          _nextLive = null;
        });
        if (widget.libraryIndexed) {
          setState(() {
            _indexedItems.clear();
            _offIndexed = 0;
          });
          await _loadIndexed();
        }
        setState(() {
          _liveItems.clear();
          _nextLive = null;
        });
        await _loadLive();
        _mtMediaLog('(4) pull-to-refresh done');
      },
      refreshOnStart: false,
      child: (ctx) {
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: ar,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final row = items[i];
                    final chatId = row.chatId ?? int.tryParse(widget.tdlibChatId) ?? 0;
                    final messageId = int.tryParse(row.messageId) ?? 0;
                    return MyTelegramVideoPosterTile(
                      row: row,
                      chatId: chatId,
                      messageId: messageId,
                      onTap: () => _openVideoDetail(row),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
            if (hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Center(
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          )
                        : TextButton(
                            onPressed: onLoadMore,
                            child: Text(l.myTelegramLoadMore),
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
