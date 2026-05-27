import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/util/app_http_client.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/person_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/user_provider.dart';

/// Must match [ImagesData] / server `TMDB_IMAGE_PRIMARY_EXTERNAL_NAME`.
const String _oxTmdbImagePrimaryName = 'TmdbImagePrimary';

/// Loads TMDB person + filmography via OX API (`/tmdb/v3/...`) with server-side cache.
abstract final class OxplayerPersonTmdbLoader {
  static String? _mediaOrigin() {
    final raw = OxplayerEnv.effectiveMediaServerUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static Future<Map<String, dynamic>?> _getJson(
    Ref ref,
    String path,
    Map<String, String> query,
  ) async {
    final origin = _mediaOrigin();
    if (origin == null) return null;
    final uri = Uri.parse('$origin/$path').replace(queryParameters: query);
    final headers = ref.read(userProvider)?.credentials.header(ref) ?? const <String, String>{};
    final res = await appHttpClient.get(uri, headers: headers);
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  }

  /// TMDB numeric person id from cast [Person.id], or null.
  static int? parseTmdbPersonId(String raw) {
    final str = raw.trim();
    if (str.startsWith('tmdb-person-')) {
      return int.tryParse(str.substring('tmdb-person-'.length));
    }
    return int.tryParse(str);
  }

  static Map<String, dynamic> _emptyUserData(String id) => {
        'Played': false,
        'IsFavorite': false,
        'PlayCount': 0,
        'PlaybackPositionTicks': 0,
        'ItemId': id,
        'Key': id,
      };

  static Map<String, dynamic> _personBaseItemJson(Map<String, dynamic> p, String personId) {
    final profilePath = p['profile_path'];
    final external = <Map<String, dynamic>>[];
    if (profilePath is String && profilePath.isNotEmpty) {
      final path = profilePath.startsWith('http')
          ? profilePath
          : 'https://image.tmdb.org/t/p/w780$profilePath';
      external.add({'Name': _oxTmdbImagePrimaryName, 'Url': path});
    }
    final birthday = p['birthday'];
    DateTime? premiere;
    if (birthday is String && birthday.isNotEmpty) {
      premiere = DateTime.tryParse(birthday);
    }
    final place = p['place_of_birth'];
    final locations = place is String && place.trim().isNotEmpty ? <String>[place.trim()] : <String>[];

    final pid = parseTmdbPersonId(personId);
    return {
      'Type': 'Person',
      'Name': p['name']?.toString() ?? '',
      'Id': personId,
      'Overview': p['biography']?.toString() ?? '',
      'PremiereDate': premiere?.toIso8601String(),
      'ProductionLocations': locations,
      if (pid != null) 'ProviderIds': {'Tmdb': '$pid'},
      if (external.isNotEmpty) 'ExternalUrls': external,
      'UserData': _emptyUserData(personId),
      'PrimaryImageAspectRatio': 0.67,
    };
  }

  static Future<PersonModel?> loadPerson(Ref ref, String personId) async {
    if (!OxplayerConfig.isEnabled) return null;
    final tmdbId = parseTmdbPersonId(personId);
    if (tmdbId == null) return null;

    final lang = 'en-US';
    final json = await _getJson(ref, 'tmdb/v3/person/$tmdbId', {'language': lang});
    if (json == null) return null;

    final resolvedId = 'tmdb-person-$tmdbId';
    final baseItemJson = _personBaseItemJson(json, resolvedId);

    try {
      final user = ref.read(userProvider);
      if (user != null) {
        final origin = _mediaOrigin();
        if (origin != null) {
          final udUri = Uri.parse('$origin/Users/${user.id}/Items/$resolvedId');
          final udRes = await appHttpClient.get(udUri, headers: user.credentials.header(ref));
          if (udRes.statusCode == 200) {
            final udJson = jsonDecode(udRes.body);
            if (udJson is Map<String, dynamic> && udJson['UserData'] != null) {
              baseItemJson['UserData'] = udJson['UserData'];
            }
          }
        }
      }
    } catch (_) {}

    final dtoItem = dto.BaseItemDto.fromJson(baseItemJson);
    return PersonModel.fromBaseDto(dtoItem, ref);
  }

  static int _creditDateMs(Map<String, dynamic> c) {
    final d = c['release_date'] ?? c['first_air_date'];
    if (d is! String || d.isEmpty) return 0;
    final dt = DateTime.tryParse(d);
    return dt?.millisecondsSinceEpoch ?? 0;
  }

  static Future<({List<MovieModel> movies, List<SeriesModel> series})> loadFilmography(
    Ref ref,
    int tmdbPersonId,
  ) async {
    if (!OxplayerConfig.isEnabled) {
      return (movies: <MovieModel>[], series: <SeriesModel>[]);
    }
    final lang = 'en-US';
    final json = await _getJson(ref, 'tmdb/v3/person/$tmdbPersonId/combined_credits', {'language': lang});
    if (json == null) {
      return (movies: <MovieModel>[], series: <SeriesModel>[]);
    }
    final cast = json['cast'];
    if (cast is! List) {
      return (movies: <MovieModel>[], series: <SeriesModel>[]);
    }

    final movies = <MovieModel>[];
    final series = <SeriesModel>[];
    final seenMovie = <String>{};
    final seenTv = <String>{};

    final rows = cast.whereType<Map<String, dynamic>>().toList()
      ..sort((a, b) => _creditDateMs(b).compareTo(_creditDateMs(a)));

    for (final c in rows) {
      final mediaType = c['media_type']?.toString();
      final idRaw = c['id'];
      if (idRaw is! int || mediaType == null) continue;

      if (mediaType == 'movie') {
        if (movies.length >= 25) continue;
        final sid = 'tmdb-movie-$idRaw';
        if (!seenMovie.add(sid)) continue;
        final title = c['title']?.toString() ?? '';
        final poster = c['poster_path']?.toString();
        final rd = c['release_date']?.toString();
        final year = rd != null && rd.length >= 4 ? int.tryParse(rd.substring(0, 4)) : null;
        final ext = <Map<String, dynamic>>[];
        if (poster != null && poster.isNotEmpty) {
          ext.add({
            'Name': _oxTmdbImagePrimaryName,
            'Url': poster.startsWith('http') ? poster : 'https://image.tmdb.org/t/p/w500$poster',
          });
        }
        final map = {
          'Type': 'Movie',
          'Name': title,
          'Id': sid,
          'Overview': c['overview']?.toString() ?? '',
          'ProductionYear': year,
          if (rd != null && rd.isNotEmpty) 'PremiereDate': DateTime.tryParse(rd)?.toIso8601String(),
          'ProviderIds': {'Tmdb': '$idRaw'},
          if (ext.isNotEmpty) 'ExternalUrls': ext,
          'UserData': _emptyUserData(sid),
          'PrimaryImageAspectRatio': 1.5,
        };
        movies.add(MovieModel.fromBaseDto(dto.BaseItemDto.fromJson(map), ref));
      } else if (mediaType == 'tv') {
        if (series.length >= 25) continue;
        final sid = 'tmdb-tv-$idRaw';
        if (!seenTv.add(sid)) continue;
        final name = c['name']?.toString() ?? '';
        final poster = c['poster_path']?.toString();
        final rd = c['first_air_date']?.toString();
        final year = rd != null && rd.length >= 4 ? int.tryParse(rd.substring(0, 4)) : null;
        final ext = <Map<String, dynamic>>[];
        if (poster != null && poster.isNotEmpty) {
          ext.add({
            'Name': _oxTmdbImagePrimaryName,
            'Url': poster.startsWith('http') ? poster : 'https://image.tmdb.org/t/p/w500$poster',
          });
        }
        final map = {
          'Type': 'Series',
          'Name': name,
          'Id': sid,
          'Overview': c['overview']?.toString() ?? '',
          'ProductionYear': year,
          'ProviderIds': {'Tmdb': '$idRaw'},
          if (ext.isNotEmpty) 'ExternalUrls': ext,
          'UserData': _emptyUserData(sid),
          'OriginalTitle': name,
          'SortName': name,
          'Status': 'Continuing',
          'PrimaryImageAspectRatio': 1.5,
        };
        series.add(SeriesModel.fromBaseDto(dto.BaseItemDto.fromJson(map), ref));
      }
      if (movies.length >= 25 && series.length >= 25) break;
    }

    return (movies: movies, series: series);
  }
}
