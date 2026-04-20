import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// OXPlayer-aware cache manager.
///
/// Differs from [CustomCacheManager] in two ways:
///  1. Adds `ngrok-skip-browser-warning` header for any ngrok URL so the server
///     returns the actual image instead of the browser-interstitial HTML page.
///  2. Keeps a separate cache key so the two managers don't share stale entries.
class OxplayerCacheManager {
  static const key = 'oxCacheKey';

  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 3),
      maxNrOfCacheObjects: 256,
      fileService: HttpFileService(httpClient: _OxHttpClient()),
    ),
  );
}

/// HTTP client that injects the ngrok tunnel bypass header on ngrok hosts.
class _OxHttpClient extends http.BaseClient {
  final _inner = http.Client();

  static const _ngrokHosts = ['ngrok-free.app', 'ngrok.io', 'ngrok.app'];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final host = request.url.host;
    if (_ngrokHosts.any((suffix) => host.endsWith(suffix))) {
      request.headers['ngrok-skip-browser-warning'] = 'true';
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
