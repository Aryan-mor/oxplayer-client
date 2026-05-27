import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/util/app_http_client.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';

/// Result of `POST /me/test-mode/activate`.
final class OxplayerTestModeActivateResult {
  const OxplayerTestModeActivateResult({
    required this.addedCount,
    required this.skippedCount,
    this.unresolvedMovieTmdb = const [],
    this.unresolvedTvTmdb = const [],
  });

  final int addedCount;
  final int skippedCount;
  final List<String> unresolvedMovieTmdb;
  final List<String> unresolvedTvTmdb;
}

/// Thrown when test-mode activation fails.
final class OxplayerTestModeApiException implements Exception {
  const OxplayerTestModeApiException(this.message);
  final String message;

  @override
  String toString() => 'OxplayerTestModeApiException: $message';
}

/// `POST /me/test-mode/activate` — attach env catalog and mark user as tester (server-side only).
Future<OxplayerTestModeActivateResult> oxplayerPostTestModeActivate({
  required Map<String, String> authorizationHeaders,
}) async {
  final rawBase = OxplayerEnv.apiBaseUrl?.trim() ?? '';
  if (rawBase.isEmpty) {
    throw const OxplayerTestModeApiException('Missing API configuration');
  }
  final base = rawBase.endsWith('/') ? rawBase.substring(0, rawBase.length - 1) : rawBase;
  final uri = Uri.parse('$base/me/test-mode/activate');

  final headers = <String, String>{
    'Content-Type': 'application/json; charset=utf-8',
    ...authorizationHeaders,
  };

  final response = await appHttpClient.post(
    uri,
    headers: headers,
    body: jsonEncode(<String, dynamic>{}),
  );

  final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
  if (response.statusCode == 503) {
    final err = decoded is Map<String, dynamic> ? decoded['error'] : null;
    throw OxplayerTestModeApiException(
      err is String ? err : 'Test mode is not configured on the server',
    );
  }
  if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
    final err = decoded is Map<String, dynamic> ? decoded['error'] : null;
    final msg = err is String ? err : 'HTTP ${response.statusCode}';
    throw OxplayerTestModeApiException(msg);
  }
  if (decoded['ok'] != true) {
    throw const OxplayerTestModeApiException('Invalid response');
  }

  List<String> stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  return OxplayerTestModeActivateResult(
    addedCount: (decoded['addedCount'] as num?)?.toInt() ?? 0,
    skippedCount: (decoded['skippedCount'] as num?)?.toInt() ?? 0,
    unresolvedMovieTmdb: stringList(decoded['unresolvedMovieTmdb']),
    unresolvedTvTmdb: stringList(decoded['unresolvedTvTmdb']),
  );
}
