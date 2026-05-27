import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/util/app_http_client.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';

/// Thrown when `POST /me/account/delete` fails or the API base URL is missing.
final class OxplayerAccountApiException implements Exception {
  const OxplayerAccountApiException(this.message);
  final String message;

  @override
  String toString() => 'OxplayerAccountApiException: $message';
}

/// Calls `POST /me/account/delete` with the same Jellyfin-style `Authorization` header as other OX API calls.
Future<void> oxplayerPostDeleteAccount({
  required Map<String, String> authorizationHeaders,
}) async {
  final rawBase = OxplayerEnv.apiBaseUrl?.trim() ?? '';
  if (rawBase.isEmpty) {
    throw const OxplayerAccountApiException('Missing API configuration');
  }
  final base = rawBase.endsWith('/') ? rawBase.substring(0, rawBase.length - 1) : rawBase;
  final uri = Uri.parse('$base/me/account/delete');

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
  if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
    final err = decoded is Map<String, dynamic> ? decoded['error'] : null;
    final msg = err is String ? err : 'HTTP ${response.statusCode}';
    throw OxplayerAccountApiException(msg);
  }
  final ok = decoded['ok'] == true;
  if (!ok) {
    throw const OxplayerAccountApiException('Invalid response');
  }
}
