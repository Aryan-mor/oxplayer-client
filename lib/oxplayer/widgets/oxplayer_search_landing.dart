import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_help_content.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/oxplayer/providers/ox_home_banner_discovery_cache.dart';
import 'package:fladder/providers/dashboard_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool _isMovieOrTvSeries(ItemBaseModel it) {
  final j = it.jellyType;
  if (j == BaseItemKind.movie || j == BaseItemKind.series) return true;
  return it.type == FladderItemType.movie || it.type == FladderItemType.series;
}

List<ItemBaseModel> _moviesAndSeriesOnly(Iterable<ItemBaseModel> items) {
  return items.where(_isMovieOrTvSeries).toList(growable: false);
}

/// Recent + discovery titles, de-duplicated, movies and series only (no episodes / seasons).
List<ItemBaseModel> _mixedMovieAndSeries({
  required List<ItemBaseModel> recentSlice,
  required List<ItemBaseModel> custom,
  required List<ItemBaseModel> top10,
}) {
  final seen = <String>{};
  final out = <ItemBaseModel>[];
  for (final x in [...recentSlice, ...custom, ...top10]) {
    if (!_isMovieOrTvSeries(x)) continue;
    if (!seen.add(x.id)) continue;
    out.add(x);
  }
  return out;
}

/// Mixed movie/TV suggestions for the search screen when the query is empty (Oxplayer only).
class OxplayerSearchLandingData {
  const OxplayerSearchLandingData({this.mixedPosters = const []});

  final List<ItemBaseModel> mixedPosters;

  bool get hasAny => mixedPosters.isNotEmpty;
}

final oxplayerSearchLandingProvider = FutureProvider.autoDispose<OxplayerSearchLandingData>((ref) async {
  if (!OxplayerConfig.isEnabled) {
    return const OxplayerSearchLandingData();
  }

  final userId = ref.watch(userProvider.select((a) => a?.id));
  if (userId == null || userId.isEmpty) {
    return const OxplayerSearchLandingData();
  }

  final api = ref.read(jellyApiProvider);
  final dash = ref.read(dashboardProvider);

  late final List<ItemBaseModel> custom;
  late final List<ItemBaseModel> top10;
  late final bool homeDiscoveryLayout;

  if (dash.bannerCustom.isNotEmpty && dash.bannerTrendingTop10.isNotEmpty) {
    custom = _moviesAndSeriesOnly(dash.bannerCustom);
    top10 = _moviesAndSeriesOnly(dash.bannerTrendingTop10);
    homeDiscoveryLayout = true;
  } else {
    final cached = await OxHomeBannerDiscoveryCache.read(ref);
    if (cached != null) {
      homeDiscoveryLayout = true;
      custom = _moviesAndSeriesOnly(
        cached.customSlider.map((e) => ItemBaseModel.fromBaseDto(e, ref)),
      );
      top10 = _moviesAndSeriesOnly(
        cached.trendingTop10.map((e) => ItemBaseModel.fromBaseDto(e, ref)),
      );
    } else {
      final disc = await api.userItemsHomeBannerDiscoveryGet();
      homeDiscoveryLayout = disc != null;
      if (disc != null) {
        await OxHomeBannerDiscoveryCache.write(
          ref,
          curated: disc.curated,
          globalLatest: disc.globalLatest,
          customSlider: disc.customSlider,
          trendingTop10: disc.trendingTop10,
        );
        custom = _moviesAndSeriesOnly(
          disc.customSlider.map((e) => ItemBaseModel.fromBaseDto(e, ref)),
        );
        top10 = _moviesAndSeriesOnly(
          disc.trendingTop10.map((e) => ItemBaseModel.fromBaseDto(e, ref)),
        );
      } else {
        custom = const [];
        top10 = const [];
      }
    }
  }

  const imagesToFetch = [
    ImageType.logo,
    ImageType.primary,
    ImageType.backdrop,
    ImageType.banner,
  ];

  final fieldsToFetch = {
    ItemFields.parentid,
    ItemFields.mediastreams,
    ItemFields.mediasources,
    ItemFields.candelete,
    ItemFields.candownload,
    ItemFields.primaryimageaspectratio,
    ItemFields.overview,
    ItemFields.airtime,
  };

  final recentResponse = await api.itemsGet(
    recursive: true,
    sortBy: [ItemSortBy.datecreated],
    sortOrder: [SortOrder.descending],
    limit: 24,
    includeItemTypes: [BaseItemKind.movie, BaseItemKind.series],
    enableImageTypes: imagesToFetch,
    fields: fieldsToFetch.toList(),
    enableTotalRecordCount: false,
  );
  final recentAll = recentResponse.isSuccessful
      ? _moviesAndSeriesOnly(recentResponse.body?.items ?? const <ItemBaseModel>[])
      : const <ItemBaseModel>[];

  final recentSlice = homeDiscoveryLayout
      ? recentAll.take(4).toList(growable: false)
      : recentAll.take(10).toList(growable: false);

  final mixed = _mixedMovieAndSeries(
    recentSlice: recentSlice,
    custom: custom,
    top10: top10,
  );

  return OxplayerSearchLandingData(mixedPosters: mixed);
});

/// Shown on the search screen when Oxplayer is enabled and the library search field is empty.
class OxplayerSearchLanding extends ConsumerWidget {
  const OxplayerSearchLanding({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(oxplayerSearchLandingProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        if (!data.hasAny) {
          return const OxplayerHelpContent(embedded: true);
        }
        return PosterRow(
          posters: data.mixedPosters,
          label: 'Movies & TV',
        );
      },
    );
  }
}
