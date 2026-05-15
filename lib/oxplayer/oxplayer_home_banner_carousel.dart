import 'dart:developer' show log;

import 'package:collection/collection.dart';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart' show FladderItemType, ItemBaseModel;
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
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

/// OX Jellyfin `ProviderIds.OX=general_video` — never show in the home hero carousel (latest, resume, curated, etc.).
bool _isOxGeneralVideoCarouselItem(ItemBaseModel it) {
  if (it is! MovieModel) return false;
  final p = it.providerIds;
  return p != null && p['OX']?.toString() == 'general_video';
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
    // General videos live under `homevideos`; the hero carousel must not include them (only real movies).
    if (v.collectionType != CollectionType.movies) {
      continue;
    }
    for (final it in v.recentlyAdded) {
      // `Users/.../Items/Latest` is scoped to this account's libraries. Prefer [jellyType] and fall back
      // to [ItemBaseModel.type] when the API omits or maps `Type` differently.
      if (_isOxGeneralVideoCarouselItem(it)) continue;
      if (_carouselTreatsAsMovie(it)) {
        candidates.add(it);
      }
    }
  }
  candidates.sort((a, b) => _dateAddedOrEpoch(b).compareTo(_dateAddedOrEpoch(a)));
  final out = <ItemBaseModel>[];
  final seenKey = <String>{};
  for (final it in candidates) {
    if (out.length >= max) break;
    if (!seenKey.add(_oxHomeBannerDedupeKey(it))) continue;
    out.add(it);
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
    final k = _oxHomeBannerDedupeKey(it);
    if (!seenSeries.add(k)) continue;
    out.add(it);
  }
  return out;
}

ItemBaseModel? _mostRecentlyPlayedVideo(List<ItemBaseModel> resumeVideo) {
  final eligible =
      resumeVideo.where((e) => !_isOxGeneralVideoCarouselItem(e)).toList();
  if (eligible.isEmpty) return null;
  return eligible
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
  final movieKeys = <String>{};
  final tvKeys = <String>{};
  for (final item in [...curated, ...globalLatest]) {
    if (_isOxGeneralVideoCarouselItem(item)) continue;
    final t = item.jellyType;
    final isMovie = t == BaseItemKind.movie || item.type == FladderItemType.movie;
    final isSeries = t == BaseItemKind.series || item.type == FladderItemType.series;
    final isEpisode = t == BaseItemKind.episode || item.type == FladderItemType.episode;
    if (isMovie && outMovies.length < maxEach) {
      final k = _oxHomeBannerDedupeKey(item);
      if (movieKeys.add(k)) outMovies.add(item);
    } else if (isSeries && outTv.length < maxEach) {
      final k = _oxHomeBannerDedupeKey(item);
      if (tvKeys.add(k)) outTv.add(item);
    } else if (isEpisode && outTv.length < maxEach) {
      final k = _oxHomeBannerDedupeKey(item);
      if (tvKeys.add(k)) outTv.add(item);
    }
  }
}

/// Stable identity for carousel dedupe — prefers TMDB (`ProviderIds` / synthetic `tmdb-*` ids),
/// then TV series grouping, then Jellyfin id.
String _oxHomeBannerDedupeKey(ItemBaseModel item) {
  if (item is MovieModel) {
    final p = item.providerIds;
    final t = p?['Tmdb'] ?? p?['tmdb'];
    if (t != null && t.toString().trim().isNotEmpty) {
      return 'tm:${t.toString()}';
    }
  }
  if (item is SeriesModel) {
    final p = item.providerIds;
    final t = p?['Tmdb'] ?? p?['tmdb'];
    if (t != null && t.toString().trim().isNotEmpty) {
      return 'tt:${t.toString()}';
    }
  }
  final id = item.id;
  final movieM = RegExp(r'^tmdb-movie-(\d+)$').firstMatch(id);
  if (movieM != null) return 'tm:${movieM.group(1)}';
  final tvM = RegExp(r'^tmdb-tv-(\d+)$').firstMatch(id);
  if (tvM != null) return 'tt:${tvM.group(1)}';
  if (_carouselTreatsAsTv(item)) {
    return 'tvs:${_tvSeriesDedupeKey(item)}';
  }
  return 'id:$id';
}

void _appendCarouselDeduped(List<ItemBaseModel> out, Set<String> seenKeys, ItemBaseModel item) {
  if (_isOxGeneralVideoCarouselItem(item)) return;
  final k = _oxHomeBannerDedupeKey(item);
  if (seenKeys.add(k)) {
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

/// OX home hero: **combined** = last played → your library latest (2+2 or 1+1) → server-pinned custom slides →
/// curated/global → **TrendingTop10**. Dedupes by TMDB (and series key) so the same title is not shown twice.
/// **General video** (`ProviderIds.OX=general_video`) is never included (not even from resume / next up / curated lists).
List<ItemBaseModel> buildOxplayerHomeCarouselItems({
  required HomeCarouselSettings mode,
  required List<ItemBaseModel> allResume,
  required List<ItemBaseModel> resumeVideo,
  required List<ItemBaseModel> nextUp,
  required List<ViewModel> dashboardViews,
  required List<ItemBaseModel> bannerCurated,
  required List<ItemBaseModel> bannerGlobalLatest,
  required List<ItemBaseModel> bannerCustom,
  required List<ItemBaseModel> bannerTrendingTop10,
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
      if (bannerCustom.isEmpty && bannerTrendingTop10.isEmpty) {
        return List.of(nextUp);
      }
      final nextUpOut = <ItemBaseModel>[];
      final seenNu = <String>{};
      for (final n in nextUp) {
        _appendCarouselDeduped(nextUpOut, seenNu, n);
      }
      for (final c in bannerCustom) {
        _appendCarouselDeduped(nextUpOut, seenNu, c);
      }
      for (final x in bannerTrendingTop10) {
        _appendCarouselDeduped(nextUpOut, seenNu, x);
      }
      return nextUpOut;
    case HomeCarouselSettings.cont:
      if (bannerCustom.isEmpty && bannerTrendingTop10.isEmpty) {
        return List.of(allResume);
      }
      final contOut = <ItemBaseModel>[];
      final seenCt = <String>{};
      final lastPlayedCont = _mostRecentlyPlayedVideo(resumeVideo);
      if (lastPlayedCont != null) {
        _appendCarouselDeduped(contOut, seenCt, lastPlayedCont);
      }
      final hasSuppCont = bannerCurated.isNotEmpty ||
          bannerGlobalLatest.isNotEmpty ||
          bannerTrendingTop10.isNotEmpty;
      final userMovieNCont = hasSuppCont ? 1 : 2;
      final userTvNCont = hasSuppCont ? 1 : 2;
      for (final m in _userOwnedMoviesLatest(dashboardViews, userMovieNCont)) {
        _appendCarouselDeduped(contOut, seenCt, m);
      }
      for (final t in _userOwnedTvLatestBySeries(dashboardViews, userTvNCont)) {
        _appendCarouselDeduped(contOut, seenCt, t);
      }
      for (final c in bannerCustom) {
        _appendCarouselDeduped(contOut, seenCt, c);
      }
      for (final r in allResume) {
        _appendCarouselDeduped(contOut, seenCt, r);
      }
      for (final x in bannerTrendingTop10) {
        _appendCarouselDeduped(contOut, seenCt, x);
      }
      return contOut;
    case HomeCarouselSettings.combined:
      final out = <ItemBaseModel>[];
      final seen = <String>{};

      final lastPlayed = _mostRecentlyPlayedVideo(resumeVideo);
      if (lastPlayed != null) {
        _appendCarouselDeduped(out, seen, lastPlayed);
      }

      final hasSupplementalBanner = bannerCurated.isNotEmpty ||
          bannerGlobalLatest.isNotEmpty ||
          bannerTrendingTop10.isNotEmpty;
      final userMovieN = hasSupplementalBanner ? 1 : 2;
      final userTvN = hasSupplementalBanner ? 1 : 2;
      final moviePicks = _userOwnedMoviesLatest(dashboardViews, userMovieN);
      final tvPicks = _userOwnedTvLatestBySeries(dashboardViews, userTvN);
      for (final m in moviePicks) {
        _appendCarouselDeduped(out, seen, m);
      }
      for (final t in tvPicks) {
        _appendCarouselDeduped(out, seen, t);
      }

      for (final c in bannerCustom) {
        _appendCarouselDeduped(out, seen, c);
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
          _appendCarouselDeduped(out, seen, m);
        }
        for (final t in suggTv) {
          _appendCarouselDeduped(out, seen, t);
        }
      }

      for (final x in bannerTrendingTop10) {
        _appendCarouselDeduped(out, seen, x);
      }

      if (out.isEmpty) {
        for (final r in resumeVideo) {
          _appendCarouselDeduped(out, seen, r);
          if (out.length >= 8) break;
        }
        for (final n in nextUp) {
          _appendCarouselDeduped(out, seen, n);
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
            '$mode|supp=$hasSupplementalBanner|rv=${resumeVideo.length}|nu=${nextUp.length}|bc=${bannerCustom.length}|bt=${bannerTrendingTop10.length}|dv=${dashboardViews.length}|tr=$totalRecent|mp=${moviePicks.length}|tp=${tvPicks.length}|out=${out.length}',
        message:
            'OX home carousel combined: mode=$mode supplementalBanner=$hasSupplementalBanner '
            'resumeVideo=${resumeVideo.length} lastPlayed=${lastPlayed != null} bannerCustom=${bannerCustom.length} '
            'trending=${bannerTrendingTop10.length} nextUp=${nextUp.length} '
            'dashboardViews=${dashboardViews.length} recentTotal=$totalRecent '
            'perView=$viewSummary ${_oxDebugRecentKindStats(dashboardViews)} '
            'pickedMovies=${moviePicks.length}/$userMovieN pickedTv=${tvPicks.length}/$userTvN '
            'outCount=${out.length} ids=${out.take(6).map((e) => e.id).join(",")}',
      );

      return out;
  }
}
