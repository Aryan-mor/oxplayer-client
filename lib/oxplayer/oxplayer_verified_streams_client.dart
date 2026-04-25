import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// In-memory: media file id → server already has a player-verified manifest.
final Map<String, bool> oxplayerVerifiedStreamsCache = {};

/// Path segment after `oxplayer://telegram/` — the library DB media row id (bigint string), not Telegram chat id.
String? parseOxplayerTelegramMediaId(String? mediaUrl) {
  if (mediaUrl == null || mediaUrl.isEmpty) return null;
  final u = Uri.tryParse(mediaUrl);
  if (u == null) return null;
  if (u.scheme != 'oxplayer' || u.host != 'telegram') return null;
  if (u.pathSegments.isEmpty) return null;
  final id = u.pathSegments.first.trim();
  if (id.isEmpty || !RegExp(r'^\d+$').hasMatch(id)) return null;
  return id;
}

CredentialsModel? _credentials(Ref ref) =>
    ref.read(userProvider)?.credentials ?? ref.read(authProvider).serverLoginModel?.tempCredentials;

String? _apiOrigin(Ref ref) {
  final raw = ref.read(serverUrlProvider)?.trim() ?? '';
  if (raw.isEmpty) return null;
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

Future<bool?> fetchStreamsPlayerVerified(Ref ref, String mediaId) async {
  if (!OxplayerConfig.isEnabled) return null;
  final cached = oxplayerVerifiedStreamsCache[mediaId];
  if (cached == true) return true;

  final origin = _apiOrigin(ref);
  final creds = _credentials(ref);
  if (origin == null || creds == null || creds.token.isEmpty) return null;

  final uri = Uri.parse('$origin/me/library/media/$mediaId/stream-manifest-status');
  try {
    final res = await http.get(uri, headers: creds.header(ref));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(res.body) as Map<String, dynamic>?;
    final v = j?['streamsPlayerVerified'];
    final verified = v == true;
    if (verified) {
      oxplayerVerifiedStreamsCache[mediaId] = true;
    }
    return verified;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _audioRow(AudioStreamModel a) {
  return {
    if (a.language.isNotEmpty && a.language != 'Unknown') 'language': a.language,
    if (a.codec.isNotEmpty) 'codec': a.codec,
    if (a.displayTitle.isNotEmpty) 'displayTitle': a.displayTitle,
    if (a.channelLayout.isNotEmpty) 'channelLayout': a.channelLayout,
    'isDefault': a.isDefault,
  };
}

Map<String, dynamic> _subRow(SubStreamModel s) {
  return {
    if (s.language.isNotEmpty && s.language != 'Unknown') 'language': s.language,
    if (s.codec.isNotEmpty) 'codec': s.codec,
    if (s.displayTitle.isNotEmpty) 'displayTitle': s.displayTitle,
    'isDefault': s.isDefault,
    'isTextSubtitleStream': true,
  };
}

/// POST player-discovered muxed streams once per media file (server ignores duplicates).
Future<void> postVerifiedStreamsManifestIfNeeded(
  Ref ref, {
  required String mediaId,
  required List<AudioStreamModel> audio,
  required List<SubStreamModel> subtitles,
}) async {
  if (!OxplayerConfig.isEnabled) {
    oxMuxedStreamsLog('verified HTTP: skip (Oxplayer off)');
    return;
  }
  if (oxplayerVerifiedStreamsCache[mediaId] == true) {
    oxMuxedStreamsLog('verified HTTP: skip in-memory cache hit mediaId=$mediaId');
    return;
  }

  final origin = _apiOrigin(ref);
  final creds = _credentials(ref);
  if (origin == null || creds == null || creds.token.isEmpty) {
    oxMuxedStreamsLog(
      'verified HTTP: skip no API origin or creds origin=${origin != null} creds=${creds != null} tokenEmpty=${creds?.token.isEmpty ?? true}',
    );
    return;
  }

  final already = await fetchStreamsPlayerVerified(ref, mediaId);
  if (already == true) {
    oxMuxedStreamsLog('verified HTTP: skip server already verified mediaId=$mediaId');
    return;
  }

  if (audio.isEmpty && subtitles.isEmpty) {
    oxMuxedStreamsLog('verified HTTP: skip empty body');
    return;
  }

  final body = <String, dynamic>{
    'v': 1,
    'audio': audio.map(_audioRow).toList(),
    'subtitles': subtitles.map(_subRow).toList(),
  };

  final uri = Uri.parse('$origin/me/library/media/$mediaId/verified-streams');
  oxMuxedStreamsLog(
    'verified HTTP: POST $uri audio=${audio.length} subtitles=${subtitles.length}',
  );
  try {
    final res = await http.post(
      uri,
      headers: {
        ...creds.header(ref),
        'content-type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      oxMuxedStreamsLog(
        'verified HTTP: POST failed status=${res.statusCode} bodyLen=${res.body.length}',
      );
      return;
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>?;
    final stored = j?['stored'] == true;
    final alreadyVerified = j?['alreadyVerified'] == true;
    oxMuxedStreamsLog(
      'verified HTTP: response stored=$stored alreadyVerified=$alreadyVerified',
    );
    if (stored || alreadyVerified) {
      oxplayerVerifiedStreamsCache[mediaId] = true;
    }
  } catch (e) {
    oxMuxedStreamsLog('verified HTTP: POST exception $e');
  }
}
