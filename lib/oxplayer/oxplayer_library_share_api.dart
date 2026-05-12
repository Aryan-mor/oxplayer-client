import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';

CredentialsModel? _creds(WidgetRef ref) =>
    ref.read(userProvider)?.credentials ?? ref.read(authProvider).serverLoginModel?.tempCredentials;

String? _origin(WidgetRef ref) {
  final raw = ref.read(serverUrlProvider)?.trim() ?? '';
  if (raw.isEmpty) return null;
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

/// Response from `POST /me/library/share`.
class OxplayerLibrarySharePayload {
  const OxplayerLibrarySharePayload({
    required this.shareUrl,
    required this.telegramMessageHtml,
    required this.telegramMessageSegments,
  });

  final String shareUrl;
  final String telegramMessageHtml;
  final List<Map<String, dynamic>> telegramMessageSegments;
}

Future<OxplayerLibrarySharePayload?> oxplayerPostLibraryShare(WidgetRef ref, String itemId) async {
  if (!OxplayerConfig.isEnabled) return null;
  final origin = _origin(ref);
  final creds = _creds(ref);
  if (origin == null || creds == null || creds.token.isEmpty) return null;

  final uri = Uri.parse('$origin/me/library/share');
  final headers = {
    ...creds.header(ref),
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  final res = await http.post(
    uri,
    headers: headers,
    body: jsonEncode(<String, dynamic>{'itemId': itemId}),
  );
  if (res.statusCode != 200) return null;
  final decoded = jsonDecode(res.body);
  if (decoded is! Map<String, dynamic>) return null;
  final segsRaw = decoded['telegramMessageSegments'];
  final segs = <Map<String, dynamic>>[];
  if (segsRaw is List) {
    for (final e in segsRaw) {
      if (e is Map) {
        segs.add(Map<String, dynamic>.from(e));
      }
    }
  }
  final html = decoded['telegramMessageHtml']?.toString() ?? '';
  final url = decoded['shareUrl']?.toString() ?? '';
  if (url.isEmpty) return null;
  return OxplayerLibrarySharePayload(
    shareUrl: url,
    telegramMessageHtml: html,
    telegramMessageSegments: segs,
  );
}
