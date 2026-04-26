import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/my_telegram/my_telegram_index_refresh.dart';
import 'package:fladder/oxplayer/my_telegram/my_telegram_live_cache.dart';
import 'package:fladder/oxplayer/my_telegram/my_telegram_merge_media_rows.dart';
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
    with TickerProviderStateMixin {
  TabController? _tabController;
  var _bootstrapDone = false;
  /// `true` only if we have at least one indexed OX [File] for this key (or thread), so we show a tab.
  var _hasIndexedFileRows = false;
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

  int get _mtThreadKey => widget.messageThreadId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!widget.libraryIndexed) {
      _tabController = TabController(length: 1, vsync: this);
      _hasIndexedFileRows = false;
      if (mounted) {
        setState(() => _bootstrapDone = true);
      }
      await _restoreLiveCache();
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingLive = _liveItems.isEmpty;
        _loadingIndexed = false;
      });
      if (_liveItems.isNotEmpty) {
        unawaited(_refreshHeadMerge());
      } else {
        unawaited(_fetchLiveFromNetwork(isAppend: false));
      }
      return;
    }
    // Chat marked indexed: probe for actual File rows (may be 0 in this thread or global)
    setState(() {
      _loadingIndexed = true;
      _loadingLive = true;
    });
    final api = ref.read(oxplayerUserChatsClientProvider);
    if (api == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Not signed in';
        _loadingIndexed = false;
        _loadingLive = false;
        _hasIndexedFileRows = false;
        _tabController = TabController(length: 1, vsync: this);
        _bootstrapDone = true;
      });
      return;
    }
    try {
      final probe = await api
          .fetchIndexedChatMedia(
            tdlibChatId: widget.tdlibChatId,
            messageThreadId: _mtThreadKey == 0 ? null : _mtThreadKey,
            limit: 1,
            offset: 0,
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => const OxChatMediaPage(items: [], total: 0, hasMoreHistory: false),
          );
      if (!mounted) {
        return;
      }
      final has = probe.items.isNotEmpty || probe.total > 0;
      _hasIndexedFileRows = has;
      if (has) {
        _tabController = TabController(length: 2, initialIndex: 1, vsync: this);
      } else {
        _tabController = TabController(length: 1, vsync: this);
      }
      setState(() {
        _bootstrapDone = true;
        _loadingIndexed = has;
      });
      if (has) {
        unawaited(_loadIndexed());
      } else {
        setState(() => _loadingIndexed = false);
      }
      await _restoreLiveCache();
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingLive = _liveItems.isEmpty;
      });
      if (_liveItems.isNotEmpty) {
        unawaited(_refreshHeadMerge());
      } else {
        unawaited(_fetchLiveFromNetwork(isAppend: false));
      }
    } catch (e) {
      _mtMediaLog('bootstrap error: $e');
      if (!mounted) {
        return;
      }
      _tabController = TabController(length: 1, vsync: this);
      setState(() {
        _error = '$_error\n$e';
        _bootstrapDone = true;
        _hasIndexedFileRows = false;
        _loadingIndexed = false;
        _loadingLive = false;
      });
    }
  }

  /// Restore Live tab from disk (instant); head merge runs separately.
  Future<void> _restoreLiveCache() async {
    if (kIsWeb) {
      return;
    }
    final c = await MyTelegramLiveCache.load(widget.tdlibChatId, _mtThreadKey);
    if (!mounted || c.items.isEmpty) {
      return;
    }
    setState(() {
      _liveItems
        ..clear()
        ..addAll(c.items);
      _nextLive = c.nextId;
    });
  }

  Future<void> _persistLiveCache() async {
    if (kIsWeb || _liveItems.isEmpty) {
      return;
    }
    await MyTelegramLiveCache.save(
      widget.tdlibChatId,
      _mtThreadKey,
      items: _liveItems,
      nextLive: _nextLive,
    );
  }

  /// Fresh first page, merged on top of existing cache / list (keeps [load more] cursor when set).
  Future<void> _refreshHeadMerge() async {
    if (_liveInFlight || kIsWeb || !OxplayerConfig.isEnabled) {
      return;
    }
    final beforeNext = _nextLive;
    _mtMediaLog('(3h) _refreshHeadMerge start next=$beforeNext items=${_liveItems.length}');
    _liveInFlight = true;
    try {
      await OxplayerTelegramTdSession().initClient();
      await OxplayerTelegramTdSession().td.ensureAuthorized();
      final fetcher = MyTelegramLiveMediaFetcher(OxplayerTelegramTdSession().td);
      final page = await fetcher.fetchPage(
        tdlibChatId: widget.tdlibChatId,
        messageThreadId: widget.messageThreadId,
        continueFromMessageId: null,
      );
      if (!mounted) {
        return;
      }
      if (page.items.isEmpty) {
        setState(() {
          _loadingLive = false;
        });
        return;
      }
      final was = List<OxChatMediaRow>.from(_liveItems);
      setState(() {
        _liveItems
          ..clear()
          ..addAll(mergeOxChatMediaRowsByMessageIdPreferNewerList(page.items, was));
        if (beforeNext != null) {
          _nextLive = beforeNext;
        } else {
          _nextLive = page.nextHistoryFromMessageId;
        }
        _hasMoreLive = _hasMoreLive || page.hasMoreHistory;
        _loadingLive = false;
      });
      await _persistLiveCache();
      _mtMediaLog('(3h) _refreshHeadMerge done merged=${_liveItems.length} next=$_nextLive');
    } catch (e) {
      _mtMediaLog('(3h) _refreshHeadMerge ERROR: $e');
      if (mounted) {
        setState(() {
          _loadingLive = false;
        });
      }
    } finally {
      _liveInFlight = false;
    }
  }

  /// [isAppend] true: append using [_nextLive] as cursor. [isAppend] false: replace with first page.
  Future<void> _fetchLiveFromNetwork({
    required bool isAppend,
  }) async {
    if (_liveInFlight) {
      _mtMediaLog('(3) skip _fetch (in flight)');
      return;
    }
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _loadingLive = false;
          _hasMoreLive = false;
        });
      }
      return;
    }
    if (!OxplayerConfig.isEnabled) {
      if (mounted) {
        setState(() {
          _loadingLive = false;
        });
      }
      return;
    }
    _liveInFlight = true;
    _mtMediaLog('(3) _fetch fromMessageId=${isAppend ? _nextLive : 'null( head )'}');
    if (mounted) {
      setState(() => _loadingLive = true);
    }
    try {
      await OxplayerTelegramTdSession().initClient();
      await OxplayerTelegramTdSession().td.ensureAuthorized();
      final fetcher = MyTelegramLiveMediaFetcher(OxplayerTelegramTdSession().td);
      final page = await fetcher.fetchPage(
        tdlibChatId: widget.tdlibChatId,
        messageThreadId: widget.messageThreadId,
        continueFromMessageId: isAppend ? _nextLive : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (isAppend) {
          _liveItems.addAll(page.items);
        } else {
          _liveItems
            ..clear()
            ..addAll(page.items);
        }
        _nextLive = page.nextHistoryFromMessageId;
        _hasMoreLive = page.hasMoreHistory;
        _loadingLive = false;
      });
      unawaited(_persistLiveCache());
      _mtMediaLog('(3) _fetch done +items=${page.items.length} next=$_nextLive hasMore=$_hasMoreLive');
    } catch (e) {
      _mtMediaLog('(3) _fetch ERROR: $e');
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

  Future<void> _loadMoreLive() async {
    if (_nextLive == null) {
      return;
    }
    await _fetchLiveFromNetwork(isAppend: true);
  }

  /// Full reload (pull): reset live tail + re-fetch head, indexed reset.
  Future<void> _pullFullRefresh() async {
    setState(() {
      _offIndexed = 0;
      _nextLive = null;
    });
    if (_hasIndexedFileRows) {
      setState(() {
        _indexedItems.clear();
        _offIndexed = 0;
      });
      await _loadIndexed();
    } else {
      setState(() => _loadingIndexed = false);
    }
    setState(() {
      _liveItems.clear();
      _nextLive = null;
    });
    await _fetchLiveFromNetwork(isAppend: false);
  }

  Future<void> _loadIndexed() async {
    if (_indexedInFlight) {
      return;
    }
    _indexedInFlight = true;
    final api = ref.read(oxplayerUserChatsClientProvider);
    if (api == null) {
      if (mounted) {
        setState(() {
          _loadingIndexed = false;
          _error = 'Not signed in';
        });
      }
      _indexedInFlight = false;
      return;
    }
    if (mounted) {
      setState(() => _loadingIndexed = true);
    }
    try {
      final page = await api.fetchIndexedChatMedia(
        tdlibChatId: widget.tdlibChatId,
        messageThreadId: _mtThreadKey == 0 ? null : _mtThreadKey,
        limit: 40,
        offset: _offIndexed,
      );
      if (!mounted) {
        return;
      }
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
    } catch (e) {
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

  Future<void> _onIngestBumped() async {
    if (!widget.libraryIndexed) {
      return;
    }
    final api = ref.read(oxplayerUserChatsClientProvider);
    if (api == null) {
      return;
    }
    if (_hasIndexedFileRows) {
      if (mounted) {
        setState(() {
          _offIndexed = 0;
          _indexedItems.clear();
        });
        await _loadIndexed();
      }
      return;
    }
    // Was single-tab: first ingest; upgrade to two tabs if the server has rows
    try {
      final p = await api.fetchIndexedChatMedia(
        tdlibChatId: widget.tdlibChatId,
        messageThreadId: _mtThreadKey == 0 ? null : _mtThreadKey,
        limit: 1,
        offset: 0,
      );
      if (!mounted) {
        return;
      }
      if (p.items.isEmpty && p.total == 0) {
        return;
      }
      // [SingleTickerProvider] only allows one [TabController] per State. We use
      // [TickerProviderStateMixin] and replace the controller after the current frame
      // so [TabBar]/[TabBarView] are not mid-build when the old controller is disposed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final old = _tabController;
        setState(() {
          _hasIndexedFileRows = true;
          _tabController = TabController(length: 2, initialIndex: 1, vsync: this);
          _offIndexed = 0;
          _indexedItems.clear();
          _loadingIndexed = true;
        });
        old?.dispose();
        unawaited(_loadIndexed());
      });
    } catch (e, st) {
      _mtMediaLog('onIngestBumped: $e\n$st');
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
      unawaited(_onIngestBumped());
    });
    final l = context.localized;
    if (!_bootstrapDone) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.chatTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final hasDual = _hasIndexedFileRows;
    final tab = _tabController;
    if (hasDual && tab == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.chatTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatTitle),
        bottom: hasDual
            ? TabBar(
                key: const ValueKey<String>('mt_media_dual_tabs'),
                controller: tab,
                tabs: [
                  Tab(text: l.myTelegramIndexed),
                  Tab(text: l.myTelegramLive),
                ],
              )
            : null,
      ),
      body: _error != null && _liveItems.isEmpty && _indexedItems.isEmpty
          ? Center(child: Text(_error!))
          : hasDual
              ? TabBarView(
                  key: const ValueKey<String>('mt_media_dual_view'),
                  controller: tab,
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
                      onLoadMore: _loadMoreLive,
                    ),
                  ],
                )
              : _buildMediaGrid(
                  items: _liveItems,
                  loading: _loadingLive,
                  hasMore: _hasMoreLive,
                  onLoadMore: _loadMoreLive,
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
      onRefresh: _pullFullRefresh,
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
