import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;


import 'package:fladder/oxplayer/ox_tmdb_seerr_session.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/widgets/oxplayer_tmdb_empty_image_placeholder.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/fladder_config.dart';

/// One TMDB search suggestion as returned by `GET /search/suggestions`.
class _TmdbSuggestion {
  const _TmdbSuggestion({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    this.year,
  });

  final int tmdbId;
  final String mediaType;
  final String title;
  final String? posterPath;
  final String? year;

  static _TmdbSuggestion? fromJson(Map<String, dynamic> j) {
    final id = j['tmdbId'];
    final type = j['mediaType'];
    final title = j['title'];
    if (id is! int || type is! String || title is! String || title.isEmpty) {
      return null;
    }
    return _TmdbSuggestion(
      tmdbId: id,
      mediaType: type,
      title: title,
      posterPath: j['posterPath'] as String?,
      year: j['year'] as String?,
    );
  }
}

/// Fetches TMDB suggestions from the OXPlayer API server.
/// Uses the credentials URL (always current, updated by OxplayerPersistedUrlSync)
/// rather than the static env var which may be null when not compile-time defined.
/// Returns an empty list for general users (server returns 403) or on any error.
final _oxplayerTmdbSuggestionsProvider =
    FutureProvider.autoDispose.family<List<_TmdbSuggestion>, String>(
  (ref, query) async {
    debugPrint('[OX_TMDB] provider triggered, query="$query"');

    if (query.trim().isEmpty) return const [];

    final credentials = ref.read(userProvider)?.credentials;
    if (credentials == null) {
      debugPrint('[OX_TMDB] no credentials — user not logged in, skipping');
      return const [];
    }

    // Prefer the live credentials URL (kept in sync by OxplayerPersistedUrlSync).
    // Fall back to the compile/dotenv API base URL when the stored URL is blank.
    final credUrl = credentials.url.trim();
    final rawOrigin = credUrl.isNotEmpty ? credUrl : (OxplayerEnv.apiBaseUrl ?? '');
    debugPrint('[OX_TMDB] credentials.url="$credUrl", effective="$rawOrigin"');

    if (rawOrigin.isEmpty) {
      debugPrint('[OX_TMDB] URL is empty — skipping request');
      return const [];
    }

    final base =
        rawOrigin.endsWith('/') ? rawOrigin.substring(0, rawOrigin.length - 1) : rawOrigin;
    final uri = Uri.parse('$base/search/suggestions').replace(
      queryParameters: {'q': query.trim()},
    );
    debugPrint('[OX_TMDB] --> GET $uri');

    try {
      final headers = credentials.header(ref);
      final res = await http.get(uri, headers: headers);
      debugPrint('[OX_TMDB] <-- ${res.statusCode} (${res.body.length} bytes)');

      if (res.statusCode != 200) {
        debugPrint('[OX_TMDB] non-200: ${res.body}');
        return const [];
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final rawResults = decoded['results'];
      if (rawResults is! List) return const [];

      final results = rawResults
          .whereType<Map<String, dynamic>>()
          .map(_TmdbSuggestion.fromJson)
          .whereType<_TmdbSuggestion>()
          .toList(growable: false);
      debugPrint('[OX_TMDB] parsed ${results.length} suggestions');
      return results;
    } catch (e, st) {
      debugPrint('[OX_TMDB] error: $e\n$st');
      return const [];
    }
  },
);

/// Horizontal scrollable row of TMDB poster suggestions from the OXPlayer server.
/// Silently renders nothing for general users (server 403) or when no results.
class OxplayerSearchTmdbSuggestions extends ConsumerWidget {
  const OxplayerSearchTmdbSuggestions({
    required this.query,
    super.key,
  });

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();

    final suggestionsAsync = ref.watch(_oxplayerTmdbSuggestionsProvider(query));

    return suggestionsAsync.when(
      loading: () => const _TmdbSuggestionsShimmer(),
      error: (err, st) {
        debugPrint('[OX_TMDB] widget error state: $err');
        return const SizedBox.shrink();
      },
      data: (posters) {
        if (posters.isEmpty) return const SizedBox.shrink();
        return _TmdbSuggestionsSection(posters: posters);
      },
    );
  }
}

class _TmdbSuggestionsSection extends ConsumerWidget {
  const _TmdbSuggestionsSection({required this.posters});

  final List<_TmdbSuggestion> posters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.movie_filter_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Suggestions from TMDB',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: posters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return _TmdbPosterTile(poster: posters[index]);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TmdbPosterTile extends ConsumerWidget {
  const _TmdbPosterTile({required this.poster});

  final _TmdbSuggestion poster;



  Future<void> _openSeerrDetails(BuildContext context, WidgetRef ref) async {
    final credentials = ref.read(userProvider)?.credentials;
    if (credentials == null) return;
    final credUrl = credentials.url.trim();
    final rawOrigin = credUrl.isNotEmpty ? credUrl : (OxplayerEnv.apiBaseUrl ?? '');
    if (rawOrigin.isEmpty) return;
    final base =
        rawOrigin.endsWith('/') ? rawOrigin.substring(0, rawOrigin.length - 1) : rawOrigin;

    try {
      final openUri = Uri.parse('$base/tmdb/open');
      await http.post(
        openUri,
        headers: {
          ...credentials.header(ref as Ref),
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'tmdbId': poster.tmdbId,
          'mediaType': poster.mediaType,
        }),
      );
    } catch (_) {}

    final seerrUrl =
        (FladderConfig.seerrBaseUrl ?? ref.read(userProvider)?.seerrCredentials?.serverUrl ?? '')
            .trim();
    if (seerrUrl.isEmpty) {
      ref.read(oxTmdbSeerrOpenProvider.notifier).state = OxTmdbSeerrOpen(
        tmdbId: poster.tmdbId,
        mediaType: poster.mediaType == 'tv' ? SeerrMediaType.tvshow : SeerrMediaType.movie,
      );
    }

    if (!context.mounted) return;
    final id = 'tmdb-${poster.mediaType == 'tv' ? 'tv' : 'movie'}-${poster.tmdbId}';
    await context.router.push(
      DetailsRoute(id: id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 110,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openSeerrDetails(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: poster.posterPath != null
                      ? Image.network(
                          poster.posterPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const OxplayerTmdbEmptyImagePlaceholder(),
                        )
                      : const OxplayerTmdbEmptyImagePlaceholder(),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              poster.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (poster.year != null)
              Text(
                poster.year!,
                maxLines: 1,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TmdbSuggestionsShimmer extends StatelessWidget {
  const _TmdbSuggestionsShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.movie_filter_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Suggestions from TMDB',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, _) {
              return SizedBox(
                width: 110,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
