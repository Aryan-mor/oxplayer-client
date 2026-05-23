import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/providers/ox_my_telegram_swr_providers.dart';
import 'package:fladder/oxplayer/providers/oxplayer_swr_cache.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/oxplayer/my_telegram/my_telegram_ui_widgets.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';

void _mtHubLog(String m) {
  if (kDebugMode) debugPrint('[MyTelegram hub] $m');
}

@RoutePage()
class MyTelegramHubScreen extends ConsumerWidget {
  const MyTelegramHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OxplayerConfig.isEnabled || kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: Text(context.localized.myTelegramTitle)),
        body: Center(child: Text(context.localized.myTelegramAuthRequired)),
      );
    }
    return const _MyTelegramHubBody();
  }
}

class _MyTelegramHubBody extends ConsumerStatefulWidget {
  const _MyTelegramHubBody();

  @override
  ConsumerState<_MyTelegramHubBody> createState() => _MyTelegramHubBodyState();
}

class _MyTelegramHubBodyState extends ConsumerState<_MyTelegramHubBody> {
  final _refresh = GlobalKey<RefreshIndicatorState>();
  String? _error;
  final Map<String, List<OxUserChatRow>> _byBucket = {};
  var _loading = true;
  bool _loadInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loadInFlight) {
      _mtHubLog('(0) skip _load() because previous run is still in-flight');
      return;
    }
    _loadInFlight = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      ref.invalidate(myTelegramHubSwrProvider);
      final snapshot = await ref.read(myTelegramHubSwrProvider.future);
      _mtHubLog('(1) SWR load items=${snapshot.data.values.fold<int>(0, (p, e) => p + e.length)}');
      if (mounted) {
        setState(() {
          _byBucket
            ..clear()
            ..addAll(snapshot.data);
          _error = snapshot.error?.toString();
          _loading = false;
        });
      }
    } catch (e, st) {
      _mtHubLog('(2) ERROR: $e\n$st');
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    } finally {
      _loadInFlight = false;
    }
  }

  String _labelForBucket(BuildContext context, String b) {
    final l = context.localized;
    return switch (b) {
      'chats' => l.myTelegramBucketChats,
      'groups' => l.myTelegramBucketGroups,
      'supergroups' => l.myTelegramBucketSupergroups,
      'channels' => l.myTelegramBucketChannels,
      'bots' => l.myTelegramBucketBots,
      _ => b,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<OxplayerSwrSnapshot<MyTelegramHubBuckets>>>(
      myTelegramHubSwrProvider,
      (previous, next) {
        next.whenData((snapshot) {
          if (!mounted) return;
          setState(() {
            _byBucket
              ..clear()
              ..addAll(snapshot.data);
            _error = snapshot.error?.toString();
            _loading = false;
          });
        });
      },
    );
    final l = context.localized;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.myTelegramTitle),
        actions: [
          IconButton(
            icon: const Icon(IconsaxPlusLinear.setting_2),
            tooltip: l.myTelegramConfigureChats,
            onPressed: () async {
              final changed = await context.router.push<bool>(const MyTelegramConfigRoute());
              if (changed == true && context.mounted) {
                _refresh.currentState?.show();
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('${l.myTelegramError}\n$_error', textAlign: TextAlign.center))
              : PullToRefresh(
                  onRefresh: _load,
                  refreshKey: _refresh,
                  refreshOnStart: false,
                  child: (ctx) {
                    if (_byBucket.values.every((e) => e.isEmpty)) {
                      return ListView(
                        children: [
                          const SizedBox(height: 48),
                          Icon(IconsaxPlusLinear.message, size: 48, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(l.myTelegramNoChatsYet, textAlign: TextAlign.center),
                        ],
                      );
                    }
                    final padding = AdaptiveLayout.adaptivePadding(context);
                    return CustomScrollView(
                      slivers: [
                        for (final e in _byBucket.entries) ...[
                          if (e.value.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(padding.left, 20, padding.right, 8),
                                child: Text(
                                  _labelForBucket(context, e.key),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
                              sliver: SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: myTelegramPosterGridCrossAxisCount(context, ref)
                                      .clamp(2, 3),
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 0.92,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) {
                                    final row = e.value[i];
                                    final idStr = row.tdlibChatId;
                                    if (idStr == null || idStr.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return MyTelegramFolderTile(
                                      title: row.title,
                                      photoUrl: row.photoUrl,
                                      subtitle: [
                                        if (row.isIndexed) l.myTelegramIndexed,
                                        if (row.showInVideo) l.myTelegramShowInMyTelegram,
                                      ].where((s) => s.isNotEmpty).join(' · '),
                                      onTap: () {
                                        if (row.isForum) {
                                          context.router.push(
                                            MyTelegramForumTopicsRoute(
                                              chatTitle: row.title,
                                              tdlibChatId: idStr,
                                              chatIsIndexed: row.isIndexed,
                                            ),
                                          );
                                        } else {
                                          context.router.push(
                                            MyTelegramChatMediaRoute(
                                              chatTitle: row.title,
                                              tdlibChatId: idStr,
                                              libraryIndexed: row.isIndexed,
                                              messageThreadId: 0,
                                              isForum: row.isForum,
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                  childCount: e.value.length,
                                ),
                              ),
                            ),
                          ],
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    );
                  },
                ),
    );
  }
}
