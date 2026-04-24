import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/seerr/seerr_models.dart';

/// When non-null, the next [SeerrDetails] /fetch/ loads TMDB data from the OXPlayer API
/// (same [SeerrDetailsScreen] as Related → no Seerr server required). Cleared after fetch.
class OxTmdbSeerrOpen {
  const OxTmdbSeerrOpen({required this.tmdbId, required this.mediaType});

  final int tmdbId;
  final SeerrMediaType mediaType;
}

final oxTmdbSeerrOpenProvider =
    StateProvider<OxTmdbSeerrOpen?>((ref) => null);
