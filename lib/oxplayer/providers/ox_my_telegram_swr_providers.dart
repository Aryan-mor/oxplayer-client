import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/oxplayer/providers/oxplayer_swr_cache.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_client.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_user_chats_models.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';

typedef MyTelegramHubBuckets = Map<String, List<OxUserChatRow>>;

const _swrRefreshAfter = Duration(seconds: 30);

final myTelegramHubSwrProvider =
    FutureProvider.autoDispose<OxplayerSwrSnapshot<MyTelegramHubBuckets>>((ref) async {
  final visibleBuckets = ref.watch(clientSettingsProvider).myTelegramVisibleBuckets.toSet();
  final buckets = oxUserChatBucketApiValues.where(visibleBuckets.contains).toList();
  final cache = ref.read(oxplayerSwrCacheProvider);
  final cacheKey = 'my_telegram_hub_v1:${buckets.join(',')}';
  final cached = await _readEnvelope<MyTelegramHubBuckets>(
    cache,
    cacheKey,
    decode: _decodeHubBuckets,
  );
  final offline = ref.watch(effectiveOfflineModeProvider);
  final api = ref.watch(oxplayerUserChatsClientProvider);

  if (offline || api == null || buckets.isEmpty) {
    return OxplayerSwrSnapshot(
      data: cached?.data ?? <String, List<OxUserChatRow>>{
        for (final b in buckets) b: const [],
      },
      isFromCache: cached != null,
      isRefreshing: false,
      error: api == null ? 'Not signed in' : null,
    );
  }

  if (cached != null) {
    final stale = DateTime.now().difference(cached.storedAt) > _swrRefreshAfter;
    if (stale) {
      unawaited(_refreshHub(ref, api, cache, cacheKey, buckets));
    }
    return OxplayerSwrSnapshot(
      data: cached.data,
      isFromCache: true,
      isRefreshing: stale,
    );
  }

  return OxplayerSwrSnapshot(
    data: await _fetchHub(ref, api, buckets).then((data) async {
      await _writeEnvelope(cache, cacheKey, _encodeHubBuckets(data));
      return data;
    }),
    isFromCache: false,
    isRefreshing: false,
  );
});

class MyTelegramIndexedMediaQuery {
  const MyTelegramIndexedMediaQuery({
    required this.tdlibChatId,
    this.messageThreadId,
    this.limit = 40,
    this.offset = 0,
  });

  final String tdlibChatId;
  final int? messageThreadId;
  final int limit;
  final int offset;

  String get cacheKey =>
      'my_telegram_indexed_media_v1:$tdlibChatId:${messageThreadId ?? 0}:$limit:$offset';

  @override
  bool operator ==(Object other) {
    return other is MyTelegramIndexedMediaQuery &&
        other.tdlibChatId == tdlibChatId &&
        other.messageThreadId == messageThreadId &&
        other.limit == limit &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(tdlibChatId, messageThreadId, limit, offset);
}

final myTelegramIndexedMediaSwrProvider = FutureProvider.autoDispose
    .family<OxplayerSwrSnapshot<OxChatMediaPage>, MyTelegramIndexedMediaQuery>((ref, query) async {
  final cache = ref.read(oxplayerSwrCacheProvider);
  final cached = await _readEnvelope<OxChatMediaPage>(
    cache,
    query.cacheKey,
    decode: (json) => OxChatMediaPage.fromJson(Map<String, dynamic>.from(json as Map)),
  );
  final offline = ref.watch(effectiveOfflineModeProvider);
  final api = ref.watch(oxplayerUserChatsClientProvider);

  if (offline || api == null) {
    return OxplayerSwrSnapshot(
      data: cached?.data ?? const OxChatMediaPage(items: [], total: 0),
      isFromCache: cached != null,
      isRefreshing: false,
      error: api == null ? 'Not signed in' : null,
    );
  }

  if (cached != null) {
    final stale = DateTime.now().difference(cached.storedAt) > _swrRefreshAfter;
    if (stale) {
      unawaited(_refreshIndexed(ref, api, cache, query));
    }
    return OxplayerSwrSnapshot(
      data: cached.data,
      isFromCache: true,
      isRefreshing: stale,
    );
  }

  final page = await _fetchIndexed(ref, api, query);
  await _writeEnvelope(cache, query.cacheKey, page.toJson());
  return OxplayerSwrSnapshot(data: page, isFromCache: false, isRefreshing: false);
});

Future<MyTelegramHubBuckets> _fetchHub(
  Ref ref,
  OxplayerUserChatsClient api,
  List<String> buckets,
) {
  return oxplayerTrackSwrRequest(ref, () async {
    final out = <String, List<OxUserChatRow>>{};
    for (final bucket in buckets) {
      final page = await api.fetchUserChats(
        bucket: bucket,
        showInVideoOnly: true,
        limit: 200,
        offset: 0,
      );
      out[bucket] = page.items;
    }
    return out;
  });
}

Future<void> _refreshHub(
  Ref ref,
  OxplayerUserChatsClient api,
  OxplayerSwrCache cache,
  String cacheKey,
  List<String> buckets,
) async {
  try {
    final data = await _fetchHub(ref, api, buckets);
    await _writeEnvelope(cache, cacheKey, _encodeHubBuckets(data));
    ref.invalidateSelf();
  } catch (_) {}
}

Future<OxChatMediaPage> _fetchIndexed(
  Ref ref,
  OxplayerUserChatsClient api,
  MyTelegramIndexedMediaQuery query,
) {
  return oxplayerTrackSwrRequest(ref, () {
    return api.fetchIndexedChatMedia(
      tdlibChatId: query.tdlibChatId,
      messageThreadId: query.messageThreadId,
      limit: query.limit,
      offset: query.offset,
    );
  });
}

Future<void> _refreshIndexed(
  Ref ref,
  OxplayerUserChatsClient api,
  OxplayerSwrCache cache,
  MyTelegramIndexedMediaQuery query,
) async {
  try {
    final data = await _fetchIndexed(ref, api, query);
    await _writeEnvelope(cache, query.cacheKey, data.toJson());
    ref.invalidateSelf();
  } catch (_) {}
}

({T data, DateTime storedAt})? _decodeEnvelope<T>(
  Object? json, {
  required T Function(Object? json) decode,
}) {
  if (json is! Map) return null;
  final map = Map<String, dynamic>.from(json);
  final storedAt = DateTime.tryParse(map['storedAt']?.toString() ?? '');
  if (storedAt == null) return null;
  return (data: decode(map['data']), storedAt: storedAt);
}

Future<({T data, DateTime storedAt})?> _readEnvelope<T>(
  OxplayerSwrCache cache,
  String key, {
  required T Function(Object? json) decode,
}) {
  return cache.read<({T data, DateTime storedAt})?>(key, decode: (json) {
    return _decodeEnvelope(json, decode: decode);
  });
}

Future<void> _writeEnvelope(
  OxplayerSwrCache cache,
  String key,
  Object? data,
) {
  return cache.write(
    key,
    json: <String, dynamic>{
      'storedAt': DateTime.now().toIso8601String(),
      'data': data,
    },
  );
}

MyTelegramHubBuckets _decodeHubBuckets(Object? json) {
  if (json is! Map) return const {};
  final out = <String, List<OxUserChatRow>>{};
  for (final entry in Map<String, dynamic>.from(json).entries) {
    final items = entry.value;
    out[entry.key] = items is List
        ? items
            .whereType<Map>()
            .map((e) => OxUserChatRow.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.id.isNotEmpty)
            .toList()
        : const [];
  }
  return out;
}

Map<String, dynamic> _encodeHubBuckets(MyTelegramHubBuckets buckets) {
  return <String, dynamic>{
    for (final entry in buckets.entries) entry.key: entry.value.map((e) => e.toJson()).toList(),
  };
}
