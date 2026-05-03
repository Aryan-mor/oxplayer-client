import 'dart:developer' show log;

import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart' show FladderItemType, ItemBaseModel;
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

DateTime _dateAddedOrEpoch(ItemBaseModel e) => e.overview.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);

bool _carouselTreatsAsMovie(ItemBaseModel it) {
  if (it.jellyType == BaseItemKind.movie) return true;
  return it.type == FladderItemType.movie;
}

bool _carouselTreatsAsTv(ItemBaseModel it) {
  final t = it.jellyType;
  if (t == BaseItemKind.series || t == BaseItemKind.episode) return true;
  return it.type == FladderItemType.series || it.type == FladderItemType.episode;
}

String _tvSeriesDedupeKey(ItemBaseModel it) {
  if (it.type == FladderItemType.series) return 's:${it.id}';
  if (it.type == FladderItemType.episode) {
    final pid = it.parentId;
    if (pid != null && pid.isNotEmpty) return 's:$pid';
  }
  final t = it.jellyType;
  if (t == BaseItemKind.series) return 's:${it.id}';
  if (t == BaseItemKind.episode) {
    final pid = it.parentId;
    if (pid != null && pid.isNotEmpty) return 's:$pid';
  }
  return 'id:${it.id}';
}

List<ItemBaseModel> _userOwnedMoviesLatest(Iterable<ViewModel> dashboardViews, int max) {
  final candidates = <ItemBaseModel>[];
  for (final v in dashboardViews) {
    if (v.collectionType != CollectionType.movies && v.collectionType != CollectionType.homevideos) {
      continue;
    }
    for (final it in v.recentlyAdded) {
      // `Users/.../Items/Latest` is scoped to this account's libraries. Prefer [jellyType] and fall back
      // to [ItemBaseModel.type] when the API omits or maps `Type` differently.
      if (_carouselTreatsAsMovie(it)) {
        candidates.add(it);
      }
    }
  }
  candidates.sort((a, b) => _dateAddedOrEpoch(b).compareTo(_dateAddedOrEpoch(a)));
  final out = <ItemBaseModel>[];
  final seenId = <String>{};
  for (final it in candidates) {
    if (out.length >= max) break;
    if (seenId.add(it.id)) out.add(it);
  }
  return out;
}

List<ItemBaseModel> _userOwnedTvLatestBySeries(Iterable<ViewModel> dashboardViews, int max) {
  final candidates = <ItemBaseModel>[];
  for (final v in dashboardViews) {
    if (v.collectionType != CollectionType.tvshows) continue;
    for (final it in v.recentlyAdded) {
      if (_carouselTreatsAsTv(it)) {
        candidates.add(it);
      }
    }
  }
  candidates.sort((a, b) => _dateAddedOrEpoch(b).compareTo(_dateAddedOrEpoch(a)));
  final out = <ItemBaseModel>[];
  final seenSeries = <String>{};
  for (final it in candidates) {
    if (out.length >= max) break;
    final key = _tvSeriesDedupeKey(it);
    if (!seenSeries.add(key)) continue;
    out.add(it);
  }
  return out;
}

ItemBaseModel? _mostRecentlyPlayedVideo(List<ItemBaseModel> resumeVideo) {
  if (resumeVideo.isEmpty) return null;
  return resumeVideo
      .sortedByCompare(
        (e) => e.userData.lastPlayed ?? DateTime.fromMillisecondsSinceEpoch(0),
        (a, b) => b.compareTo(a),
      )
      .first;
}

/// Splits [curated] then [globalLatest] into up to [maxEach] movies and TV rows (server-driven lists).
void _suggestedMoviesAndTv(
  List<ItemBaseModel> curated,
  List<ItemBaseModel> globalLatest, {
  required int maxEach,
  required List<ItemBaseModel> outMovies,
  required List<ItemBaseModel> outTv,
}) {
  final movieIds = <String>{};
  final tvKeys = <String>{};
  for (final item in [...curated, ...globalLatest]) {
    final t = item.jellyType;
    final isMovie = t == BaseItemKind.movie || item.type == FladderItemType.movie;
    final isSeries = t == BaseItemKind.series || item.type == FladderItemType.series;
    final isEpisode = t == BaseItemKind.episode || item.type == FladderItemType.episode;
    if (isMovie && outMovies.length < maxEach) {
      if (movieIds.add(item.id)) outMovies.add(item);
    } else if (isSeries && outTv.length < maxEach) {
      if (tvKeys.add('s:${item.id}')) outTv.add(item);
    } else if (isEpisode && outTv.length < maxEach) {
      final pid = item.parentId;
      if (pid != null && pid.isNotEmpty && tvKeys.add('s:$pid')) {
        outTv.add(item);
      }
    }
  }
}

void _appendIfNew(List<ItemBaseModel> out, Set<String> seen, ItemBaseModel item) {
  if (seen.add(item.id)) {
    out.add(item);
  }
}

/// Debug-only: log when inputs change (avoids spam on every [Widget.build]).
String? _oxCarouselDebugLastFp;

void _oxHomeCarouselDebugLog({
  required String fingerprint,
  required String message,
}) {
  if (!kDebugMode) return;
  if (fingerprint == _oxCarouselDebugLastFp) return;
  _oxCarouselDebugLastFp = fingerprint;
  log(message, name: 'ox_home_carousel');
}

/// Counts [jellyType] on latest rows under movie + tv dashboard views (helps debug empty carousels).
String _oxDebugRecentKindStats(Iterable<ViewModel> dashboardViews) {
  var nullType = 0;
  var movie = 0;
  var episode = 0;
  var series = 0;
  var other = 0;
  for (final v in dashboardViews) {
    if (v.collectionType != CollectionType.movies &&
        v.collectionType != CollectionType.tvshows &&
        v.collectionType != CollectionType.homevideos) {
      continue;
    }
    for (final it in v.recentlyAdded) {
      final t = it.jellyType;
      if (t == BaseItemKind.movie) {
        movie++;
      } else if (t == BaseItemKind.episode) {
        episode++;
      } else if (t == BaseItemKind.series) {
        series++;
      } else if (t == null) {
        nullType++;
        if (it.type == FladderItemType.movie) {
          movie++;
        } else if (it.type == FladderItemType.series) {
          series++;
        } else if (it.type == FladderItemType.episode) {
          episode++;
        } else {
          other++;
        }
      } else {
        other++;
      }
    }
  }
  return 'recentJellyTypes null=$nullType movie=$movie episode=$episode series=$series other=$other';
}

/// OX home hero carousel when [HomeCarouselSettings.combined]: last played video (if any), latest
/// movies/TV from libraries, then optional rows from [bannerCurated]/[bannerGlobalLatest] when the API
/// returns them. If nothing matched, fills from [resumeVideo] then [nextUp] so the banner is not empty.
List<ItemBaseModel> buildOxplayerHomeCarouselItems({
  required HomeCarouselSettings mode,
  required List<ItemBaseModel> allResume,
  required List<ItemBaseModel> resumeVideo,
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

  switch (mode) {
    case HomeCarouselSettings.nextUp:
      return List.of(nextUp);
    case HomeCarouselSettings.cont:
      return List.of(allResume);
    case HomeCarouselSettings.combined:
      final out = <ItemBaseModel>[];
      final seen = <String>{};

      final lastPlayed = _mostRecentlyPlayedVideo(resumeVideo);
      if (lastPlayed != null) {
        _appendIfNew(out, seen, lastPlayed);
      }

      final hasSupplementalBanner =
          bannerCurated.isNotEmpty || bannerGlobalLatest.isNotEmpty;
      final userMovieN = hasSupplementalBanner ? 1 : 2;
      final userTvN = hasSupplementalBanner ? 1 : 2;
      final moviePicks = _userOwnedMoviesLatest(dashboardViews, userMovieN);
      final tvPicks = _userOwnedTvLatestBySeries(dashboardViews, userTvN);
      for (final m in moviePicks) {
        _appendIfNew(out, seen, m);
      }
      for (final t in tvPicks) {
        _appendIfNew(out, seen, t);
      }

      if (hasSupplementalBanner) {
        final suggMovies = <ItemBaseModel>[];
        final suggTv = <ItemBaseModel>[];
        _suggestedMoviesAndTv(
          bannerCurated,
          bannerGlobalLatest,
          maxEach: 5,
          outMovies: suggMovies,
          outTv: suggTv,
        );
        for (final m in suggMovies) {
          _appendIfNew(out, seen, m);
        }
        for (final t in suggTv) {
          _appendIfNew(out, seen, t);
        }
      }

      if (out.isEmpty) {
        for (final r in resumeVideo) {
          _appendIfNew(out, seen, r);
          if (out.length >= 8) break;
        }
        for (final n in nextUp) {
          _appendIfNew(out, seen, n);
          if (out.length >= 12) break;
        }
      }

      final totalRecent = dashboardViews.fold<int>(
        0,
        (a, v) => a + v.recentlyAdded.length,
      );
      final viewSummary = dashboardViews
          .map((v) => '${v.collectionType.name}:${v.recentlyAdded.length}')
          .join(';');
      _oxHomeCarouselDebugLog(
        fingerprint:
            '$mode|supp=$hasSupplementalBanner|rv=${resumeVideo.length}|nu=${nextUp.length}|dv=${dashboardViews.length}|tr=$totalRecent|mp=${moviePicks.length}|tp=${tvPicks.length}|out=${out.length}',
        message:
            'OX home carousel combined: mode=$mode supplementalBanner=$hasSupplementalBanner '
            'resumeVideo=${resumeVideo.length} lastPlayed=${lastPlayed != null} nextUp=${nextUp.length} '
            'dashboardViews=${dashboardViews.length} recentTotal=$totalRecent '
            'perView=$viewSummary ${_oxDebugRecentKindStats(dashboardViews)} '
            'pickedMovies=${moviePicks.length}/$userMovieN pickedTv=${tvPicks.length}/$userTvN '
            'outCount=${out.length} ids=${out.take(6).map((e) => e.id).join(",")}',
      );

      return out;
  }
}
