import 'dart:async';
import 'dart:convert';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/util/app_http_client.dart';

/// Interactive login (claim code, etc.) — user can wait a bit longer.
const Duration kOxAuthHttpTimeoutDefault = Duration(seconds: 30);

/// Splash silent refresh — fail fast when API is unreachable.
const Duration kOxAuthHttpTimeoutSplash = Duration(seconds: 8);

/// Successful `POST /auth/telegram` response (subset used by the client).
class OxplayerTelegramAuthResponse {
  OxplayerTelegramAuthResponse({
    required this.accessToken,
    required this.jellyfin,
    this.refreshToken,
    this.photoUrl,
    this.accountDeleteDisabled = false,
  });

  final String accessToken;
  final AuthenticationResult jellyfin;
  final String? refreshToken;
  final String? photoUrl;
  final bool accountDeleteDisabled;
}

/// Calls the OXPlayer HTTP API to exchange Telegram Mini App [initData] for a session.
final class OxplayerTelegramAuthClient {
  OxplayerTelegramAuthClient({required this.apiBase});

  /// Origin only, e.g. `https://api.example.com` (no trailing slash).
  final String apiBase;

  Uri get _telegramAuthUri => Uri.parse('$apiBase/auth/telegram');
  Uri get _claimCodeAuthUri => Uri.parse('$apiBase/auth/claim-code');
  Uri get _refreshAuthUri => Uri.parse('$apiBase/auth/refresh');

  /// Exchange 6-character code from main-bot `/login` for a session (api-v2).
  Future<OxplayerTelegramAuthResponse> claimLoginCode({
    required String code,
    String? deviceId,
    Duration httpTimeout = kOxAuthHttpTimeoutDefault,
  }) async {
    final payload = <String, dynamic>{
      'code': code.trim().toUpperCase(),
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'deviceId': deviceId.trim(),
    };

    return _parseAuthOk(
      await _postJson(_claimCodeAuthUri, payload, httpTimeout: httpTimeout),
    );
  }

  Future<OxplayerTelegramAuthResponse> refreshAccessToken({
    required String refreshToken,
    String? deviceId,
    Duration httpTimeout = kOxAuthHttpTimeoutDefault,
  }) async {
    final payload = <String, dynamic>{
      'refreshToken': refreshToken,
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'deviceId': deviceId.trim(),
    };

    return _parseAuthOk(
      await _postJson(_refreshAuthUri, payload, httpTimeout: httpTimeout),
    );
  }

  Future<OxplayerTelegramAuthResponse> googlePlayReviewLogin({
    required String phoneNumber,
    required String code,
    String? deviceId,
    String? deviceName,
  }) async {
    final payload = <String, dynamic>{
      'phoneNumber': phoneNumber,
      'code': code,
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'deviceId': deviceId.trim(),
      if (deviceName != null && deviceName.trim().isNotEmpty)
        'deviceName': deviceName.trim(),
    };

    final response = await appHttpClient.post(
      Uri.parse('$apiBase/auth/google-play-review'),
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

    final response = await appHttpClient.post(
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

  /// Fladder [UserPolicy] requires non-null provider id strings; api-v2 must send them.
  static Map<String, dynamic> _normalizeJellyfinAuthPayload(
    Map<String, dynamic> jellyfin,
  ) {
    const defaultAuthProvider =
        'Jellyfin.Server.Implementations.Users.DefaultAuthenticationProvider';
    const defaultPasswordReset =
        'Jellyfin.Server.Implementations.Users.DefaultPasswordResetProvider';

    final user = jellyfin['User'];
    if (user is Map) {
      final userMap = Map<String, dynamic>.from(user);
      final policy = userMap['Policy'];
      final policyMap = policy is Map
          ? Map<String, dynamic>.from(policy)
          : <String, dynamic>{};
      policyMap.putIfAbsent('AuthenticationProviderId', () => defaultAuthProvider);
      policyMap.putIfAbsent('PasswordResetProviderId', () => defaultPasswordReset);
      userMap['Policy'] = policyMap;
      jellyfin['User'] = userMap;
    }
    return jellyfin;
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> payload, {
    Duration httpTimeout = kOxAuthHttpTimeoutDefault,
  }) async {
    try {
      final response = await appHttpClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(httpTimeout);
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
        final err = decoded is Map<String, dynamic> ? decoded['error'] : null;
        final msg = err is String ? err : 'HTTP ${response.statusCode}';
        throw OxplayerTelegramAuthException(msg);
      }
      return decoded;
    } on TimeoutException {
      throw OxplayerTelegramAuthException(
        'Could not reach $apiBase (timed out). '
        'Use the same Wi‑Fi as your PC and check OXPLAYER_API_BASE_URL.',
      );
    }
  }

  OxplayerTelegramAuthResponse _parseAuthOk(Map<String, dynamic> decoded) {
    final jellyfinRaw = decoded['jellyfin'];
    if (jellyfinRaw is! Map) {
      throw const OxplayerTelegramAuthException(
          'Invalid response: missing jellyfin');
    }

    final jellyfinMap = _normalizeJellyfinAuthPayload(
      Map<String, dynamic>.from(jellyfinRaw),
    );
    final jellyfin = AuthenticationResult.fromJson(jellyfinMap);

    final topToken = decoded['accessToken'] as String?;
    final token = topToken ?? jellyfin.accessToken ?? '';
    if (token.isEmpty) {
      throw const OxplayerTelegramAuthException(
          'Invalid response: missing access token');
    }

    final refresh = decoded['refreshToken'] as String?;
    
    final userRaw = decoded['user'];
    final photoUrl = userRaw is Map ? userRaw['photoUrl'] as String? : null;
    final accountDeleteDisabled = userRaw is Map
        ? userRaw['accountDeleteDisabled'] == true
        : false;

    return OxplayerTelegramAuthResponse(
      accessToken: token,
      jellyfin: jellyfin,
      refreshToken: (refresh != null && refresh.isNotEmpty) ? refresh : null,
      photoUrl: photoUrl,
      accountDeleteDisabled: accountDeleteDisabled,
    );
  }
}

final class OxplayerTelegramAuthException implements Exception {
  const OxplayerTelegramAuthException(this.message);
  final String message;

  bool get isNetworkUnreachable {
    final m = message.toLowerCase();
    return m.contains('timed out') || m.contains('could not reach');
  }

  @override
  String toString() => 'OxplayerTelegramAuthException: $message';
}
