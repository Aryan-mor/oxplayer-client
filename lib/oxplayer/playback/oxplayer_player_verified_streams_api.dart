// OXPLAYER — playback / server manifest (not Fladder upstream).
// Posts muxed track lists to oxplayer-be `MediaVariants/.../PlayerVerifiedStreams`.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/app_http_client.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';

/// Result of POST /MediaVariants/{id}/PlayerVerifiedStreams.
final class OxplayerVerifiedStreamsPostResult {
  const OxplayerVerifiedStreamsPostResult({
    required this.stored,
    required this.alreadyVerified,
  });

  final bool stored;
  final bool alreadyVerified;
}

/// Parses `ms_42` or `42` → variant id digits for the API path.
String? oxplayerVariantIdFromMediaSourceId(String? mediaSourceId) {
  if (mediaSourceId == null || mediaSourceId.isEmpty) return null;
  var raw = mediaSourceId.trim();
  if (raw.startsWith('ms_')) raw = raw.substring(3);
  if (raw.isEmpty || int.tryParse(raw) == null) return null;
  return raw;
}

Future<bool> oxplayerFetchVariantStreamsAlreadyVerified({
  required Ref ref,
  required String variantId,
}) async {
  final base = _apiBase();
  if (base == null) return false;
  final creds = ref.read(userProvider)?.credentials;
  if (creds == null || creds.token.isEmpty) return false;

  final uri = Uri.parse('$base/MediaVariants/$variantId/PlayerVerifiedStreams');
  try {
    final response = await appHttpClient.get(uri, headers: creds.header(ref));
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return false;
    return decoded['streamsPlayerVerified'] == true;
  } catch (e) {
    oxMuxedStreamsLog('verified-streams GET failed variant=$variantId err=$e');
    return false;
  }
}

Future<OxplayerVerifiedStreamsPostResult?> oxplayerPostPlayerVerifiedStreams({
  required Ref ref,
  required String variantId,
  required List<AudioStreamModel> embeddedAudio,
  required List<SubStreamModel> embeddedSubtitles,
}) async {
  final base = _apiBase();
  if (base == null) return null;
  final creds = ref.read(userProvider)?.credentials;
  if (creds == null || creds.token.isEmpty) return null;

  final audio = embeddedAudio.where((s) => !s.isExternal && s.index >= 0).toList();
  final subs = embeddedSubtitles.where((s) => !s.isExternal && s.index >= 0).toList();
  if (audio.isEmpty && subs.isEmpty) return null;

  final body = <String, dynamic>{
    'v': 1,
    'audio': audio.map(_audioRow).toList(),
    'subtitles': subs.map(_subtitleRow).toList(),
  };

  final uri = Uri.parse('$base/MediaVariants/$variantId/PlayerVerifiedStreams');
  try {
    final response = await appHttpClient.post(
      uri,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        ...creds.header(ref),
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      oxMuxedStreamsLog(
        'verified-streams POST variant=$variantId status=${response.statusCode} body=${response.body}',
      );
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    return OxplayerVerifiedStreamsPostResult(
      stored: decoded['stored'] == true,
      alreadyVerified: decoded['alreadyVerified'] == true,
    );
  } catch (e) {
    oxMuxedStreamsLog('verified-streams POST failed variant=$variantId err=$e');
    return null;
  }
}

String? _apiBase() {
  final raw = OxplayerEnv.apiBaseUrl?.trim() ?? '';
  if (raw.isEmpty) return null;
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

Map<String, dynamic> _audioRow(AudioStreamModel s) {
  return {
    if (s.language.isNotEmpty) 'language': s.language,
    if (s.codec.isNotEmpty) 'codec': s.codec,
    if (s.displayTitle.isNotEmpty) 'displayTitle': s.displayTitle,
    if (s.channelLayout.isNotEmpty) 'channelLayout': s.channelLayout,
    if (s.isDefault) 'isDefault': true,
  };
}

Map<String, dynamic> _subtitleRow(SubStreamModel s) {
  return {
    if (s.language.isNotEmpty) 'language': s.language,
    if (s.codec.isNotEmpty) 'codec': s.codec,
    if (s.displayTitle.isNotEmpty) 'displayTitle': s.displayTitle,
    'isTextSubtitleStream': true,
    if (s.isDefault) 'isDefault': true,
  };
}
