import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_sentry.dart';

/// Shared [http.Client] with Sentry HTTP spans when crash reporting is active.
///
/// Use for Chopper clients, cache managers, and ad-hoc `get`/`post` instead of
/// top-level `http.get` so endpoint latency appears in Performance traces.
http.Client createAppHttpClient({http.Client? inner}) {
  final base = inner ?? http.Client();
  if (!OxplayerSentry.isActive) return base;
  return SentryHttpClient(
    client: base,
    captureFailedRequests: false,
  );
}

http.Client? _sharedAppHttpClient;

/// Lazy singleton for direct HTTP calls (OX API, TMDB, connectivity probes).
http.Client get appHttpClient => _sharedAppHttpClient ??= createAppHttpClient();
