import 'dart:convert';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cached raw JSON for [GET /UserItems/HomeBannerDiscovery] (1 day per user).
abstract final class OxHomeBannerDiscoveryCache {
  static const ttl = Duration(days: 1);
  static const _keyPrefix = 'ox_home_banner_discovery_v1';

  static String _key(String userId) => '$_keyPrefix:$userId';

  static Future<({
    List<BaseItemDto> curated,
    List<BaseItemDto> globalLatest,
    List<BaseItemDto> customSlider,
    List<BaseItemDto> trendingTop10,
  })?> read(Ref ref) async {
    if (!OxplayerConfig.isEnabled) return null;
    final userId = ref.read(userProvider.select((u) => u?.id));
    if (userId == null || userId.isEmpty) return null;

    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(map['cachedAt'] as String? ?? '');
      if (cachedAt == null || DateTime.now().difference(cachedAt) > ttl) {
        return null;
      }
      return (
        curated: _parseDtoList(map['Curated']),
        globalLatest: _parseDtoList(map['GlobalLatest']),
        customSlider: _parseDtoList(map['CustomSlider']),
        trendingTop10: _parseDtoList(map['TrendingTop10']),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    Ref ref, {
    required List<BaseItemDto> curated,
    required List<BaseItemDto> globalLatest,
    required List<BaseItemDto> customSlider,
    required List<BaseItemDto> trendingTop10,
  }) async {
    if (!OxplayerConfig.isEnabled) return;
    final userId = ref.read(userProvider.select((u) => u?.id));
    if (userId == null || userId.isEmpty) return;

    final payload = <String, dynamic>{
      'cachedAt': DateTime.now().toUtc().toIso8601String(),
      'Curated': curated.map((e) => e.toJson()).toList(),
      'GlobalLatest': globalLatest.map((e) => e.toJson()).toList(),
      'CustomSlider': customSlider.map((e) => e.toJson()).toList(),
      'TrendingTop10': trendingTop10.map((e) => e.toJson()).toList(),
    };

    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_key(userId), jsonEncode(payload));
  }

  static Future<void> clearForUser(Ref ref, String userId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_key(userId));
  }

  static List<BaseItemDto> _parseDtoList(Object? raw) {
    if (raw is! List) return [];
    final out = <BaseItemDto>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(BaseItemDto.fromJson(e));
        } catch (_) {}
      }
    }
    return out;
  }
}
