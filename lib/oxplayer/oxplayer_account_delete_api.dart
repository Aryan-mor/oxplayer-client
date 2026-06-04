import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';

class OxplayerAccountDeleteException implements Exception {
  OxplayerAccountDeleteException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Self-service tombstone via POST /me/account/delete.
class OxplayerAccountDeleteApi {
  OxplayerAccountDeleteApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> deleteAccount({required String accessToken}) async {
    final base = OxplayerEnv.apiBaseUrl;
    if (base == null) {
      throw OxplayerAccountDeleteException('OXPLAYER_API_BASE_URL is not configured');
    }
    final uri = Uri.parse('$base/me/account/delete');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'MediaBrowser Token="$accessToken"',
      },
      body: '{}',
    );
    if (response.statusCode == 200) {
      return;
    }
    throw OxplayerAccountDeleteException(_errorMessage(response));
  }

  String _errorMessage(http.Response response) {
    try {
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final err = map['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {}
    return 'Could not delete account (${response.statusCode})';
  }
}
