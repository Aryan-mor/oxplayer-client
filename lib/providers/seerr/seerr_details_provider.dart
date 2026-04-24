import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/ox_tmdb_seerr_session.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/seerr_user_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:fladder/util/seerr_helpers.dart';

part 'seerr_details_provider.freezed.dart';
part 'seerr_details_provider.g.dart';

@riverpod
class SeerrDetails extends _$SeerrDetails {
  late final api = ref.read(seerrApiProvider);

  @override
  SeerrDetailsModel build({
    required int tmdbId,
    required SeerrMediaType mediaType,
    SeerrDashboardPosterModel? poster,
  }) {
    state = SeerrDetailsModel(
      tmdbId: tmdbId,
      mediaType: mediaType,
      poster: poster,
      recommended: const [],
      similar: const [],
    );

    fetch();

    return state;
  }

  Future<void> fetch() async {
    final currentTmdbId = state.tmdbId;
    final currentMediaType = state.mediaType;
    if (currentTmdbId == null || currentMediaType == null) return;

    final ox = ref.read(oxTmdbSeerrOpenProvider);
    final seerrUrl =
        (FladderConfig.seerrBaseUrl ?? ref.read(userProvider)?.seerrCredentials?.serverUrl ?? '')
            .trim();
    if (OxplayerConfig.isEnabled &&
        seerrUrl.isEmpty &&
        ox != null &&
        ox.tmdbId == currentTmdbId &&
        ox.mediaType == currentMediaType) {
      try {
        await _fetchOxTmdbBundle();
        return;
      } finally {
        ref.read(oxTmdbSeerrOpenProvider.notifier).state = null;
      }
    }

    SeerrDashboardPosterModel? poster = state.poster;

    final refreshedPoster = await api.fetchDashboardPosterFromIds(
      tmdbId: currentTmdbId,
      mediaType: currentMediaType,
    );

    poster = refreshedPoster ?? poster;
    if (poster == null) return;

    state = state.copyWith(poster: poster);

    final currentUserBody = await ref.read(seerrUserProvider.notifier).refreshUser();
    final isTv = currentMediaType == SeerrMediaType.tvshow;
    if (isTv) {
      final tvDetailsResponse = await api.tvDetails(tvId: poster.tmdbId);
      if (tvDetailsResponse.isSuccessful && tvDetailsResponse.body != null) {
        final details = tvDetailsResponse.body!;

        final seasonStatusMap = SeerrHelpers.buildSeasonStatusMap(details);

        final userRegion = currentUserBody?.settings?.discoverRegion ?? 'US';
        final contentRating = SeerrHelpers.extractContentRating(details.contentRatings, userRegion);

        final ratings = await api.tvRatings(poster.tmdbId);

        final updatedPoster = poster.copyWith(
          seasons: details.seasons,
          seasonStatuses: seasonStatusMap.isEmpty ? poster.seasonStatuses : seasonStatusMap,
          mediaInfo: details.mediaInfo,
        );

        state = state.copyWith(
          poster: updatedPoster,
          genres: details.genres ?? [],
          relatedVideos: details.relatedVideos ?? const [],
          voteAverage: details.voteAverage,
          contentRating: contentRating,
          releaseDate: details.firstAirDate,
          people: _mapCredits(details.credits),
          seasonStatuses: updatedPoster.seasonStatuses ?? const {},
          externalIds: details.externalIds ?? state.externalIds,
          ratings: SeerrRatingsResponse(
            rt: ratings,
          ),
        );
      }
    } else {
      final movieDetailsResponse = await api.movieDetails(tmdbId: poster.tmdbId);
      if (movieDetailsResponse.isSuccessful && movieDetailsResponse.body != null) {
        final details = movieDetailsResponse.body!;
        final userRegion = currentUserBody?.settings?.discoverRegion ?? 'US';
        final contentRating = SeerrHelpers.extractContentRating(details.contentRatings, userRegion);

        final updatedPoster = poster.copyWith(
          mediaInfo: details.mediaInfo,
        );

        final ratings = await api.movieRatings(poster.tmdbId);

        state = state.copyWith(
          poster: updatedPoster,
          genres: details.genres ?? [],
          relatedVideos: details.relatedVideos ?? const [],
          voteAverage: details.voteAverage,
          contentRating: contentRating,
          releaseDate: details.releaseDate,
          people: _mapCredits(details.credits),
          externalIds: details.externalIds ?? state.externalIds,
          ratings: ratings,
        );
      }
    }

    if (currentMediaType == SeerrMediaType.movie) {
      final recommended = await api.discoverRecommendedMovies(tmdbId: poster.tmdbId);
      final related = await api.discoverRelatedMovies(tmdbId: poster.tmdbId);
      state = state.copyWith(recommended: recommended, similar: related);
    } else {
      final recommended = await api.discoverRecommendedSeries(tmdbId: poster.tmdbId);
      final related = await api.discoverRelatedSeries(tmdbId: poster.tmdbId);
      state = state.copyWith(recommended: recommended, similar: related);
    }

    state = state.copyWith(
      currentUser: currentUserBody,
      poster: poster.copyWith(
        mediaInfo: refreshedPoster?.mediaInfo == null ? null : poster.mediaInfo,
      ),
    );
  }

  /// Loads the same [SeerrDetailsModel] as Seerr, but from OXPlayer TMDB cache (no Seerr server).
  Future<void> _fetchOxTmdbBundle() async {
    final tmdbId = state.tmdbId!;
    final mediaType = state.mediaType!;

    final credentials = ref.read(userProvider)?.credentials;
    if (credentials == null) return;

    final credUrl = credentials.url.trim();
    final rawOrigin = credUrl.isNotEmpty ? credUrl : (OxplayerEnv.apiBaseUrl ?? '');
    if (rawOrigin.isEmpty) return;
    final base = rawOrigin.endsWith('/') ? rawOrigin.substring(0, rawOrigin.length - 1) : rawOrigin;

    final mParam = mediaType == SeerrMediaType.tvshow ? 'tv' : 'movie';
    final uri = Uri.parse('$base/tmdb/seerr-bundle')
        .replace(queryParameters: {'mediaType': mParam, 'tmdbId': '$tmdbId'});

    final res = await http.get(uri, headers: credentials.header(ref));
    if (res.statusCode != 200) return;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['isOxTmdbSource'] != true) return;

    final p = map['poster'] as Map<String, dynamic>?;
    if (p == null) return;

    final primary = p['primaryImageUrl'] as String?;
    final backs = (p['backdropImageUrls'] as List?)?.whereType<String>().toList() ?? <String>[];

    var bi = 0;
    final images = ImagesData(
      primary: primary != null ? ImageData(path: primary, key: 'ox-${p['tmdbId']}-p') : null,
      backDrop: backs
          .map(
            (u) {
              final k = bi++;
              return ImageData(path: u, key: 'ox-${p['tmdbId']}-bd-$k');
            },
          )
          .toList(),
    );

    final isTv = mediaType == SeerrMediaType.tvshow;
    final seasonMaps = (p['seasons'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final seasons = <SeerrSeason>[];
    for (final s in seasonMaps) {
      seasons.add(SeerrSeason(
        id: s['id'] as int?,
        name: s['name'] as String?,
        overview: s['overview'] as String?,
        seasonNumber: s['seasonNumber'] as int?,
        internalPosterPath: s['posterPath'] as String?,
        episodeCount: s['episodeCount'] as int?,
      ));
    }

    final tvdb = map['tvdbId'] as int?;
    final exMap = map['externalIds'] as Map<String, dynamic>?;
    var imdb = exMap?['imdbId'] as String?;
    if (imdb != null && imdb.isNotEmpty && !imdb.startsWith('tt')) {
      imdb = 'tt$imdb';
    }

    final mediaInfo =
        isTv ? SeerrMediaInfo(tmdbId: tmdbId, tvdbId: tvdb, requests: const []) : null;

    final poster = SeerrDashboardPosterModel(
      id: p['id'] as String? ?? 'ox-$tmdbId',
      type: isTv ? SeerrMediaType.tvshow : SeerrMediaType.movie,
      tmdbId: tmdbId,
      title: p['title'] as String? ?? '',
      overview: p['overview'] as String? ?? '',
      images: images,
      mediaStatus: SeerrMediaStatus.unknown,
      requestStatus: null,
      jellyfinItemId: null,
      releaseYear: p['year'] as String?,
      seasons: seasons,
      mediaInfo: mediaInfo,
    );

    final genreList = (map['genres'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final genres = genreList
        .map(
          (g) => SeerrGenre(id: g['id'] as int?, name: g['name'] as String?),
        )
        .toList();

    final people = <Person>[];
    final peopleRaw = (map['people'] as List?) ?? const [];
    for (final row in peopleRaw.whereType<Map<String, dynamic>>()) {
      final kind = row['kind'] as String? ?? '';
      final url = row['profilePath'] as String?;
      people.add(
        Person(
          id: row['id'] as String? ?? '',
          name: row['name'] as String? ?? '',
          role: row['role'] as String? ?? '',
          image: url != null && url.isNotEmpty
              ? ImageData(path: url, key: 'oxp-${row['id']}')
              : null,
          type: kind == 'actor' ? PersonKind.actor : _mapCrewKind(row['role'] as String?),
        ),
      );
    }

    final vids = (map['relatedVideos'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final relatedVideos = vids
        .map(
          (v) => SeerrRelatedVideo(
            url: v['url'] as String?,
            key: v['key'] as String?,
            name: v['name'] as String?,
            type: v['type'] as String?,
            site: v['site'] as String?,
          ),
        )
        .toList();

    state = SeerrDetailsModel(
      tmdbId: tmdbId,
      mediaType: mediaType,
      poster: poster,
      genres: genres,
      voteAverage: (map['voteAverage'] as num?)?.toDouble(),
      contentRating: map['contentRating'] as String?,
      releaseDate: map['releaseDate'] as String?,
      recommended: _mapOxPosterList(map['recommended']),
      similar: _mapOxPosterList(map['similar']),
      people: people,
      seasonStatuses: const {},
      currentUser: null,
      relatedVideos: relatedVideos,
      externalIds: imdb != null && imdb.isNotEmpty
          ? SeerrExternalIds(imdbId: imdb)
          : null,
      ratings: null,
      isOxTmdbSource: true,
    );
  }

  List<SeerrDashboardPosterModel> _mapOxPosterList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <SeerrDashboardPosterModel>[];
    for (final e in raw.whereType<Map<String, dynamic>>()) {
      final id = e['tmdbId'];
      if (id is! int) continue;
      final isTv = e['mediaType'] == 'tv';
      out.add(SeerrDashboardPosterModel(
        id: 'oxr-$id',
        type: isTv ? SeerrMediaType.tvshow : SeerrMediaType.movie,
        tmdbId: id,
        title: e['title'] as String? ?? '',
        overview: e['overview'] as String? ?? '',
        images: ImagesData(
          primary: e['posterPath'] != null
              ? ImageData(path: e['posterPath']! as String, key: 'oxr-$id')
              : null,
        ),
        mediaStatus: SeerrMediaStatus.unknown,
        requestStatus: null,
        jellyfinItemId: null,
        releaseYear: e['year'] as String?,
      ));
    }
    return out;
  }

  List<Person> _mapCredits(SeerrCredits? credits) {
    if (credits == null) return const [];

    final people = <Person>[];
    final seen = <String>{};

    void addPerson({
      int? id,
      required String name,
      String? role,
      String? profileUrl,
      PersonKind? type,
    }) {
      final safeName = name.trim();
      if (safeName.isEmpty) return;

      final dedupeKey = '${id ?? safeName}::${role ?? ''}';
      if (!seen.add(dedupeKey)) return;

      ImageData? image;
      if (profileUrl != null && profileUrl.isNotEmpty) {
        image = ImageData(path: profileUrl, key: 'seerr_person_${id ?? safeName.hashCode}');
      }

      people.add(
        Person(
          id: (id ?? safeName.hashCode).toString(),
          name: safeName,
          role: role ?? '',
          image: image,
          type: type,
        ),
      );
    }

    for (final cast in credits.cast ?? const <SeerrCast>[]) {
      addPerson(
        id: cast.id,
        name: cast.name ?? '',
        role: (cast.character?.trim().isEmpty ?? true) ? null : cast.character,
        profileUrl: cast.profileUrl,
        type: PersonKind.actor,
      );
    }

    for (final crew in credits.crew ?? const <SeerrCrew>[]) {
      addPerson(
        id: crew.id,
        name: crew.name ?? '',
        role: (crew.job?.trim().isEmpty ?? true) ? crew.department : crew.job,
        profileUrl: crew.profileUrl,
        type: _mapCrewKind(crew.job),
      );
    }

    return people;
  }

  PersonKind _mapCrewKind(String? job) {
    final normalized = job?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) return PersonKind.unknown;
    if (normalized.contains('director')) return PersonKind.director;
    if (normalized.contains('producer')) return PersonKind.producer;
    if (normalized.contains('writer') || normalized.contains('screenplay') || normalized.contains('story')) {
      return PersonKind.writer;
    }
    if (normalized.contains('composer') || normalized.contains('music')) return PersonKind.composer;
    return PersonKind.unknown;
  }

  Future<void> toggleSeasonExpanded(int seasonNumber) async {
    final currentExpanded = state.expandedSeasons[seasonNumber] ?? false;
    final newExpanded = !currentExpanded;

    final updatedExpanded = Map<int, bool>.from(state.expandedSeasons);
    updatedExpanded[seasonNumber] = newExpanded;
    state = state.copyWith(expandedSeasons: updatedExpanded);

    if (newExpanded && !state.episodesCache.containsKey(seasonNumber)) {
      await _fetchSeasonEpisodes(seasonNumber);
    }
  }

  Future<void> _fetchSeasonEpisodes(int seasonNumber) async {
    final poster = state.poster;
    if (poster == null) return;

    if (state.isOxTmdbSource) {
      final credentials = ref.read(userProvider)?.credentials;
      if (credentials == null) return;
      final credUrl = credentials.url.trim();
      final rawOrigin = credUrl.isNotEmpty ? credUrl : (OxplayerEnv.apiBaseUrl ?? '');
      if (rawOrigin.isEmpty) return;
      final base = rawOrigin.endsWith('/') ? rawOrigin.substring(0, rawOrigin.length - 1) : rawOrigin;
      final uri = Uri.parse('$base/tmdb/tv/season-episodes').replace(
        queryParameters: {'tvId': '${poster.tmdbId}', 'seasonNumber': '$seasonNumber'},
      );
      final res = await http.get(uri, headers: credentials.header(ref));
      if (res.statusCode != 200) return;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = map['episodes'] as List? ?? const [];
      final episodes = <SeerrEpisode>[];
      for (final e in raw.whereType<Map<String, dynamic>>()) {
        episodes.add(SeerrEpisode(
          id: e['id'] as int?,
          name: e['name'] as String?,
          overview: e['overview'] as String?,
          episodeNumber: e['episodeNumber'] as int?,
          seasonNumber: e['seasonNumber'] as int?,
          airDate: e['airDate'] as String?,
          internalStillPath: e['stillPath'] as String?,
          voteAverage: (e['voteAverage'] as num?)?.toDouble(),
          voteCount: e['voteCount'] as int?,
        ));
      }
      final updatedCache = Map<int, List<SeerrEpisode>>.from(state.episodesCache);
      updatedCache[seasonNumber] = episodes;
      state = state.copyWith(episodesCache: updatedCache);
      return;
    }

    final response = await api.seasonDetails(
      tvId: poster.tmdbId,
      seasonNumber: seasonNumber,
    );

    if (response.isSuccessful && response.body != null) {
      final episodes = response.body!.episodes ?? [];
      final updatedCache = Map<int, List<SeerrEpisode>>.from(state.episodesCache);
      updatedCache[seasonNumber] = episodes;
      state = state.copyWith(episodesCache: updatedCache);
    }
  }

  Future<void> approveRequest(int requestId) async {
    final response = await api.approveRequest(requestId: requestId);
    if (response.isSuccessful) {
      await fetch();
    }
  }

  Future<void> declineRequest(int requestId) async {
    final response = await api.deleteRequest(requestId: requestId);
    if (response.isSuccessful) {
      await fetch();
    }
  }
}

@Freezed(copyWith: true)
abstract class SeerrDetailsModel with _$SeerrDetailsModel {
  const SeerrDetailsModel._();

  const factory SeerrDetailsModel({
    int? tmdbId,
    SeerrMediaType? mediaType,
    SeerrDashboardPosterModel? poster,
    @Default([]) List<SeerrGenre> genres,
    double? voteAverage,
    String? contentRating,
    String? releaseDate,
    @Default([]) List<SeerrDashboardPosterModel> recommended,
    @Default([]) List<SeerrDashboardPosterModel> similar,
    @Default([]) List<Person> people,
    @Default({}) Map<int, SeerrMediaStatus> seasonStatuses,
    SeerrUserModel? currentUser,
    @Default({}) Map<int, bool> expandedSeasons,
    @Default({}) Map<int, List<SeerrEpisode>> episodesCache,
    @Default([]) List<SeerrRelatedVideo> relatedVideos,
    SeerrExternalIds? externalIds,
    SeerrRatingsResponse? ratings,
    /// Filled when details were loaded via [Route /tmdb/seerr-bundle] (OX TMDB) instead of Seerr.
    @Default(false) bool isOxTmdbSource,
  }) = _SeerrDetailsModel;

  bool get isTv => mediaType == SeerrMediaType.tvshow;

  bool? get hasRequestPermission {
    final user = currentUser;
    if (user == null) return null;

    final baseRequest = user.hasPermission(SeerrPermission.request);
    if (isTv) {
      return baseRequest || user.hasPermission(SeerrPermission.requestTv);
    }
    return baseRequest || user.hasPermission(SeerrPermission.requestMovie);
  }

  List<ExternalUrls> buildExternalUrls() {
    final poster = this.poster;
    final state = this;
    if (poster == null) return [];

    final urls = <ExternalUrls>[];
    final tmdbId = poster.tmdbId;
    final imdbId = state.externalIds?.imdbId;
    final tvdbId = poster.mediaInfo?.tvdbId;
    final rtUrl = state.ratings?.rt?.url;

    void addUrl(String name, String? url) {
      if (url == null || url.isEmpty) return;
      urls.add(ExternalUrls(name: name, url: url));
    }

    addUrl('TMDB', 'https://www.themoviedb.org/${isTv ? 'tv' : 'movie'}/$tmdbId');
    addUrl('IMDb', imdbId != null ? 'https://www.imdb.com/title/$imdbId' : null);
    addUrl('Trakt',
        imdbId != null ? 'https://trakt.tv/search/imdb/$imdbId?source=imdb' : 'https://trakt.tv/search/tmdb/$tmdbId');
    addUrl('TVDB', tvdbId != null ? 'http://www.thetvdb.com/?tab=series&id=$tvdbId' : null);
    addUrl('Rotten Tomatoes', rtUrl);
    return urls;
  }

  SeerrRelatedVideo? get officialTrailer {
    if (relatedVideos.isEmpty) return null;

    final trailers = relatedVideos
        .where(
          (video) => (video.type ?? '').toLowerCase() == 'trailer',
        )
        .toList(growable: false);

    for (final trailer in trailers) {
      if ((trailer.name ?? '').toLowerCase().contains('official')) {
        return trailer;
      }
    }

    if (trailers.isNotEmpty) {
      return trailers.first;
    }

    return relatedVideos.first;
  }

  String? get officialTrailerUrl {
    final trailer = officialTrailer;
    final url = trailer?.url;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  bool get hasTrailerAction => (officialTrailerUrl ?? '').isNotEmpty;

  List<ExternalUrls> buildRelatedVideoUrls() {
    final urls = <ExternalUrls>[];

    for (var i = 0; i < relatedVideos.length; i++) {
      final video = relatedVideos[i];
      final url = video.url;
      if (url == null || url.isEmpty) continue;

      final videoName = video.name?.trim() ?? '';
      final videoType = video.type?.trim() ?? '';
      final label = videoName.isNotEmpty ? videoName : (videoType.isNotEmpty ? videoType : 'Video ${i + 1}');

      urls.add(ExternalUrls(name: label, url: url));
    }

    return urls;
  }

  bool isRequestedAlready(int seasonNumber) {
    final status = seasonStatuses[seasonNumber];
    return status != null && status.isKnown && status != SeerrMediaStatus.deleted;
  }
}
