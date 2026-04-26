import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_client.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/oxplayer/telegram/source_chats_tdlib.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';

const bool _kMyTelegramConfigVerboseLog = true;
void _mtConfLog(String m) {
  if (_kMyTelegramConfigVerboseLog) {
    debugPrint('[MyTelegram config] $m');
  }
}

@RoutePage()
class MyTelegramConfigScreen extends ConsumerStatefulWidget {
  const MyTelegramConfigScreen({super.key});

  @override
  ConsumerState<MyTelegramConfigScreen> createState() => _MyTelegramConfigScreenState();
}

class _MyTelegramConfigScreenState extends ConsumerState<MyTelegramConfigScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _search = TextEditingController();
  final Map<int, TdlibPickerChatRow> _rowsByChatId = {};
  final List<int> _mainChatOrder = [];
  var _listLimit = 50;
  var _loading = true;
  var _loadingMore = false;
  var _saving = false;
  bool _loadChatsInFlight = false;
  String? _error;
  int? _selfUserId;

  final _serverShowInVideoIds = <String>{};
  final _draftShowInVideoIds = <String>{};

  TdlibFacade get _facade => OxplayerTelegramTdSession().td;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _mtConfLog('(1) _bootstrap start');
    if (kIsWeb) {
      _mtConfLog('(2) web — skip');
      setState(() {
        _loading = false;
        _error = 'Not available on web';
      });
      return;
    }
    try {
      _mtConfLog('(2) initClient…');
      await OxplayerTelegramTdSession().initClient();
      _mtConfLog('(3) ensureAuthorized…');
      await _facade.ensureAuthorized();
      _mtConfLog('(3) ensureAuthorized done');
    } on TdlibInteractiveLoginRequired {
      _mtConfLog('(3) interactive login required');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Telegram is not connected';
        });
      }
      return;
    } catch (e, st) {
      _mtConfLog('(2–3) init/auth ERROR: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
      return;
    }
    _mtConfLog('(4) tdlibGetSelfUserId…');
    _selfUserId = await tdlibGetSelfUserId(_facade);
    _mtConfLog('(4) selfUserId=$_selfUserId');
    _mtConfLog('(5) _loadShowInVideoIds (OX HTTP; can block on TLS)…');
    await _loadShowInVideoIds();
    _mtConfLog('(5) _loadShowInVideoIds done');
    if (mounted) {
      _mtConfLog('(6) _loadChats(reset: true)…');
      await _loadChats(reset: true);
      _mtConfLog('(6) _loadChats done');
    }
  }

  Future<void> _loadShowInVideoIds() async {
    final api = ref.read(oxplayerUserChatsClientProvider);
    if (api == null) {
      _mtConfLog('(5a) OX user chats client null — skip show-in-video prefetch');
      return;
    }
    final buckets = oxUserChatBucketApiValues;
    final next = <String>{};
    for (final b in buckets) {
      try {
        var offset = 0;
        var pageIdx = 0;
        while (true) {
          pageIdx += 1;
          _mtConfLog('(5a) bucket=$b page#$pageIdx offset=$offset');
          final page = await api.fetchUserChats(
            bucket: b,
            showInVideoOnly: true,
            limit: 200,
            offset: offset,
          );
          for (final r in page.items) {
            final id = r.tdlibChatId;
            if (id != null && id.isNotEmpty) next.add(id);
          }
          offset += page.items.length;
          if (page.items.isEmpty || offset >= page.total) break;
        }
        _mtConfLog('(5a) bucket=$b complete');
      } catch (e, st) {
        _mtConfLog('(5a) bucket=$b ERROR: $e\n$st');
      }
    }
    if (mounted) {
      setState(() {
        _serverShowInVideoIds
          ..clear()
          ..addAll(next);
        _draftShowInVideoIds
          ..clear()
          ..addAll(next);
      });
    }
  }

  Future<void> _loadChats({required bool reset}) async {
    if (_loadChatsInFlight) {
      _mtConfLog('(6) skip _loadChats(reset: $reset) because another load is in-flight');
      return;
    }
    _loadChatsInFlight = true;
    if (reset) {
      setState(() {
        _loading = true;
        _listLimit = 50;
        _rowsByChatId.clear();
        _mainChatOrder.clear();
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final t0 = DateTime.now();
    try {
      if (_selfUserId == null) {
        _mtConfLog('(6a) resolve self user id');
        _selfUserId = await tdlibGetSelfUserId(_facade);
      }
      final self = _selfUserId ?? 0;
      _mtConfLog('(6b) tdlibLoadChatsPage limit=80');
      await tdlibLoadChatsPage(_facade, limit: 80);
      _mtConfLog('(6c) tdlibGetMainChatIds limit=$_listLimit');
      final limit = _listLimit;
      final ids = await tdlibGetMainChatIds(_facade, limit);
      _mtConfLog('(6d) got ${ids.length} main chat id(s) in ${DateTime.now().difference(t0).inMilliseconds}ms');
      var n = 0;
      for (final id in ids) {
        if (_rowsByChatId.containsKey(id)) continue;
        n += 1;
        if (n <= 3 || n % 20 == 0) {
          _mtConfLog('(6e) getChat $n/${ids.length} chatId=$id');
        }
        final chat = await tdlibGetChat(_facade, id);
        if (chat == null) continue;
        final row = await tdlibBuildPickerRow(
          facade: _facade,
          chat: chat,
          selfUserId: self,
          savedMessagesTitle: 'Saved Messages',
        );
        if (row != null) {
          _rowsByChatId[id] = row;
          _mainChatOrder.add(id);
        }
      }
      _mtConfLog('(6f) rows built=${_rowsByChatId.length} total ${DateTime.now().difference(t0).inMilliseconds}ms');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = null;
        });
      }
    } catch (e, st) {
      _mtConfLog('(6) _loadChats ERROR: $e\n$st');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _error = describeTdlibError(e);
        });
      }
    } finally {
      _loadChatsInFlight = false;
    }
  }

  SourceChatPickerBucket get _currentBucket => SourceChatPickerBucket.values[_tabController.index];

  bool get _isDirty {
    if (_serverShowInVideoIds.length != _draftShowInVideoIds.length) return true;
    for (final id in _serverShowInVideoIds) {
      if (!_draftShowInVideoIds.contains(id)) return true;
    }
    for (final id in _draftShowInVideoIds) {
      if (!_serverShowInVideoIds.contains(id)) return true;
    }
    return false;
  }

  List<TdlibPickerChatRow> get _visibleRows {
    final bucket = _currentBucket;
    final list = _rowsByChatId.values.where((r) => r.matchesBucket(bucket)).toList();
    int orderOf(TdlibPickerChatRow r) {
      final i = _mainChatOrder.indexOf(r.chatId);
      return i >= 0 ? i : 1 << 30;
    }

    if (bucket == SourceChatPickerBucket.chats) {
      list.sort((a, b) {
        if (a.isSavedMessages != b.isSavedMessages) {
          return a.isSavedMessages ? -1 : 1;
        }
        return orderOf(a).compareTo(orderOf(b));
      });
    } else {
      list.sort((a, b) => orderOf(a).compareTo(orderOf(b)));
    }
    return list;
  }

  List<TdlibPickerChatRow> get _filteredRows {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _visibleRows;
    return _visibleRows.where((r) => r.title.toLowerCase().contains(q)).toList();
  }

  void _toggleRow(TdlibPickerChatRow row) {
    if (_saving) return;
    final idStr = row.chatId.toString();
    setState(() {
      if (_draftShowInVideoIds.contains(idStr)) {
        _draftShowInVideoIds.remove(idStr);
      } else {
        _draftShowInVideoIds.add(idStr);
      }
    });
  }

  Future<void> _onSave() async {
    if (!_isDirty || _saving || _loading) return;
    final api = ref.read(oxplayerUserChatsClientProvider);
    if (api == null) return;
    setState(() => _saving = true);
    try {
      for (final idStr in _draftShowInVideoIds) {
        final id = int.tryParse(idStr);
        if (id == null) continue;
        final row = _rowsByChatId[id];
        if (row == null) continue;
        await api.upsertUserChatMapping(
          tdlibChatId: id,
          title: row.title,
          chatType: row.apiChatType,
          peerIsBot: row.peerIsBot,
          isForum: row.apiChatType == 'supergroup' && row.isForum,
        );
      }

      final toOn = _draftShowInVideoIds.difference(_serverShowInVideoIds);
      final toOff = _serverShowInVideoIds.difference(_draftShowInVideoIds);
      final patchItems = <Map<String, dynamic>>[
        for (final id in toOn) <String, dynamic>{'tdlibChatId': id, 'showInVideo': true},
        for (final id in toOff) <String, dynamic>{'tdlibChatId': id, 'showInVideo': false},
      ];
      const chunkSize = 200;
      var patched = 0;
      for (var i = 0; i < patchItems.length; i += chunkSize) {
        final end = i + chunkSize > patchItems.length ? patchItems.length : i + chunkSize;
        patched += await api.patchUserChatsShowInVideo(items: patchItems.sublist(i, end));
      }
      if (patchItems.isNotEmpty && patched == 0) {
        throw StateError('showInVideo patch updated 0 rows');
      }
      if (!mounted) return;
      setState(() {
        _serverShowInVideoIds
          ..clear()
          ..addAll(_draftShowInVideoIds);
        _saving = false;
      });
      FladderSnack.show(context.localized.myTelegramSavedSelection, context: context);
      if (context.mounted) {
        context.router.maybePop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        FladderSnack.show('${context.localized.myTelegramError}: $e', context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!OxplayerConfig.isEnabled) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('OXPlayer is disabled')),
      );
    }
    final l = context.localized;
    final bucketLabels = <SourceChatPickerBucket, String>{
      SourceChatPickerBucket.chats: l.myTelegramBucketChats,
      SourceChatPickerBucket.groups: l.myTelegramBucketGroups,
      SourceChatPickerBucket.supergroups: l.myTelegramBucketSupergroups,
      SourceChatPickerBucket.channels: l.myTelegramBucketChannels,
      SourceChatPickerBucket.bots: l.myTelegramBucketBots,
    };
    final settings = ref.watch(clientSettingsProvider);
    final visibleBuckets = settings.myTelegramVisibleBuckets.toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.myTelegramConfigureChats),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          onTap: (_) => setState(() {}),
          tabs: [for (final b in SourceChatPickerBucket.values) Tab(text: bucketLabels[b] ?? b.name)],
        ),
        actions: [
          TextButton(
            onPressed: _saving || !_isDirty ? null : _onSave,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.myTelegramSave),
          ),
        ],
      ),
      body: _error != null && !_loading
          ? Center(child: Text(_error!))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l.myTelegramSearchChatsHint,
                      prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.myTelegramShowSectionInHub, style: Theme.of(context).textTheme.labelLarge),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final b in oxUserChatBucketApiValues)
                            FilterChip(
                              label: Text(_apiBucketToLabel(l, b)),
                              selected: visibleBuckets.contains(b),
                              onSelected: (v) {
                                final next = Set<String>.from(visibleBuckets);
                                if (v) {
                                  next.add(b);
                                } else {
                                  next.remove(b);
                                }
                                ref.read(clientSettingsProvider.notifier).setMyTelegramVisibleBuckets(next);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else
                  Expanded(
                    child: PullToRefresh(
                      onRefresh: () => _loadChats(reset: true),
                      refreshOnStart: false,
                      child: (ctx) {
                        final rows = _filteredRows;
                        if (rows.isEmpty) {
                          return ListView(
                            children: const [
                              SizedBox(height: 48),
                            ],
                          );
                        }
                        return ListView.builder(
                          itemCount: rows.length + 1,
                          itemBuilder: (context, i) {
                            if (i == rows.length) {
                              if (_loadingMore) {
                                return const Center(child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ));
                              }
                              return TextButton(
                                onPressed: _loadingMore
                                    ? null
                                    : () async {
                                        setState(() {
                                          _listLimit += 50;
                                        });
                                        await _loadChats(reset: false);
                                      },
                                child: Text(l.myTelegramLoadMore),
                              );
                            }
                            final row = rows[i];
                            final idStr = row.chatId.toString();
                            final on = _draftShowInVideoIds.contains(idStr);
                            return SwitchListTile(
                              value: on,
                              onChanged: (_) => _toggleRow(row),
                              title: Text(row.title),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  String _apiBucketToLabel(AppLocalizations l, String b) {
    return switch (b) {
      'chats' => l.myTelegramBucketChats,
      'groups' => l.myTelegramBucketGroups,
      'supergroups' => l.myTelegramBucketSupergroups,
      'channels' => l.myTelegramBucketChannels,
      'bots' => l.myTelegramBucketBots,
      _ => b,
    };
  }
}
