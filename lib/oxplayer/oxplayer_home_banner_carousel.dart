import 'package:collection/collection.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Admin or VIP (OX role), or Jellyfin administrator when OX is enabled.
bool oxplayerHomeBannerIsSpecialUser({
  required UserPolicy? policy,
  required String? oxUserRole,
}) {
  if (!OxplayerConfig.isEnabled) return false;
  final role = (oxUserRole ?? '').trim().toLowerCase();
  if (role == 'vip' || role == 'admin') return true;
  return policy?.isAdministrator == true;
}

List<ItemBaseModel> _mergedLatestMoviesAndEpisodes(Iterable<ViewModel> dashboardViews) {
  final items = <ItemBaseModel>[];
  for (final v in dashboardViews) {
    if (v.collectionType != CollectionType.movies && v.collectionType != CollectionType.tvshows) {
      continue;
    }
    for (final it in v.recentlyAdded) {
      final t = it.jellyType;
      if (t == BaseItemKind.movie || t == BaseItemKind.episode) {
        items.add(it);
      }
    }
  }
  return items.sortedByCompare(
    (e) => e.overview.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0),
    (a, b) => b.compareTo(a),
  );
}

void _appendIfNew(List<ItemBaseModel> out, Set<String> seen, ItemBaseModel item) {
  if (seen.add(item.id)) {
    out.add(item);
  }
}

/// OX home hero carousel: resume (1 vs 2) → latest added movie/episode (1 vs 2) → VIP/admin extras.
List<ItemBaseModel> buildOxplayerHomeCarouselItems({
  required HomeCarouselSettings mode,
  required UserPolicy? policy,
  required String? oxUserRole,
  required List<ItemBaseModel> allResume,
  required List<ItemBaseModel> nextUp,
  required List<ViewModel> dashboardViews,
  required List<ItemBaseModel> bannerCurated,
  required List<ItemBaseModel> bannerGlobalLatest,
}) {
  if (!OxplayerConfig.isEnabled) {
    return switch (mode) {
      HomeCarouselSettings.nextUp => List.of(nextUp),
      HomeCarouselSettings.combined => [...allResume, ...nextUp],
      HomeCarouselSettings.cont => List.of(allResume),
    };
  }

  final special = oxplayerHomeBannerIsSpecialUser(policy: policy, oxUserRole: oxUserRole);

  switch (mode) {
    case HomeCarouselSettings.nextUp:
      return List.of(nextUp);
    case HomeCarouselSettings.cont:
      return List.of(allResume);
    case HomeCarouselSettings.combined:
      final resumeN = special ? 1 : 2;
      final latestN = special ? 1 : 2;
      final resumeSeg = allResume.take(resumeN).toList();
      final latestPool = _mergedLatestMoviesAndEpisodes(dashboardViews);
      final latestSeg = latestPool.where((e) => !resumeSeg.any((r) => r.id == e.id)).take(latestN).toList();
      final out = <ItemBaseModel>[...resumeSeg, ...latestSeg];
      final seen = out.map((e) => e.id).toSet();
      if (special) {
        for (final c in bannerCurated.take(4)) {
          _appendIfNew(out, seen, c);
        }
        for (final g in bannerGlobalLatest) {
          _appendIfNew(out, seen, g);
        }
      }
      return out;
  }
}
