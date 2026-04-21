import 'dart:convert';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:http/http.dart' as http;

/// Successful `POST /auth/telegram` response (subset used by the client).
class OxplayerTelegramAuthResponse {
  OxplayerTelegramAuthResponse({
    required this.accessToken,
    required this.jellyfin,
    this.refreshToken,
  });

  final String accessToken;
  final AuthenticationResult jellyfin;
  final String? refreshToken;
}

/// Calls the OXPlayer HTTP API to exchange Telegram Mini App [initData] for a session.
final class OxplayerTelegramAuthClient {
  OxplayerTelegramAuthClient({required this.apiBase});

  /// Origin only, e.g. `https://api.example.com` (no trailing slash).
  final String apiBase;

  Uri get _telegramAuthUri => Uri.parse('$apiBase/auth/telegram');
  Uri get _refreshAuthUri => Uri.parse('$apiBase/auth/refresh');

  Future<OxplayerTelegramAuthResponse> refreshAccessToken({
    required String refreshToken,
    String? deviceId,
  }) async {
    final payload = <String, dynamic>{
      'refreshToken': refreshToken,
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'deviceId': deviceId.trim(),
    };

    final response = await http.post(
      _refreshAuthUri,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(payload),
    );

    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
      final err = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final msg = err is String ? err : 'HTTP ${response.statusCode}';
      throw OxplayerTelegramAuthException(msg);
    }

    return _parseAuthOk(decoded);
  }

  Future<OxplayerTelegramAuthResponse> exchangeInitData({
    required String initData,
    String? deviceId,
    String? deviceName,
  }) async {
    final payload = <String, dynamic>{
      'initData': initData,
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'deviceId': deviceId.trim(),
      if (deviceName != null && deviceName.trim().isNotEmpty)
        'deviceName': deviceName.trim(),
    };

    final response = await http.post(
      _telegramAuthUri,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(payload),
    );

    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
      final err = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final msg = err is String ? err : 'HTTP ${response.statusCode}';
      throw OxplayerTelegramAuthException(msg);
    }

    return _parseAuthOk(decoded);
  }

  OxplayerTelegramAuthResponse _parseAuthOk(Map<String, dynamic> decoded) {
    final jellyfinRaw = decoded['jellyfin'];
    if (jellyfinRaw is! Map) {
      throw const OxplayerTelegramAuthException(
          'Invalid response: missing jellyfin');
    }

    final jellyfinMap = Map<String, dynamic>.from(jellyfinRaw);
    final jellyfin = AuthenticationResult.fromJson(jellyfinMap);

    final topToken = decoded['accessToken'] as String?;
    final token = topToken ?? jellyfin.accessToken ?? '';
    if (token.isEmpty) {
      throw const OxplayerTelegramAuthException(
          'Invalid response: missing access token');
    }

    final refresh = decoded['refreshToken'] as String?;

    return OxplayerTelegramAuthResponse(
      accessToken: token,
      jellyfin: jellyfin,
      refreshToken: (refresh != null && refresh.isNotEmpty) ? refresh : null,
    );
  }
}

final class OxplayerTelegramAuthException implements Exception {
  const OxplayerTelegramAuthException(this.message);
  final String message;

  @override
  String toString() => 'OxplayerTelegramAuthException: $message';
}
