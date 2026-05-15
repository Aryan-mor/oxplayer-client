import 'dart:convert';
import 'dart:developer' show log;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;
import 'package:http/http.dart' as http;

import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';

CredentialsModel? _credentials(WidgetRef ref) =>
    ref.read(userProvider)?.credentials ?? ref.read(authProvider).serverLoginModel?.tempCredentials;

String? _apiOrigin(WidgetRef ref) {
  final raw = ref.read(serverUrlProvider)?.trim() ?? '';
  if (raw.isEmpty) return null;
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

void _reportDebug(String message) {
  if (kDebugMode) {
    log(message, name: 'oxplayer_library_report');
  }
}

/// Outcome of `POST /me/library/media/:id/report`.
class OxplayerLibraryReportResult {
  const OxplayerLibraryReportResult._({
    required this.ok,
    required this.adminNotified,
    this.httpStatus,
    required this.debugLine,
  });

  /// Server accepted the report (`200` + `{ ok: true }`).
  factory OxplayerLibraryReportResult.success({required bool adminNotified}) {
    return OxplayerLibraryReportResult._(ok: true, adminNotified: adminNotified, httpStatus: 200, debugLine: '');
  }

  /// Client-side precheck failed or HTTP/parse error.
  factory OxplayerLibraryReportResult.failure({
    required String debugLine,
    int? httpStatus,
  }) {
    return OxplayerLibraryReportResult._(
      ok: false,
      adminNotified: false,
      httpStatus: httpStatus,
      debugLine: debugLine,
    );
  }

  final bool ok;
  final bool adminNotified;
  final int? httpStatus;
  /// Always set when `ok` is false; useful for `kDebugMode` / console.
  final String debugLine;
}

/// POST `/me/library/media/:id/report` — notifies admins via Telegram when configured.
Future<OxplayerLibraryReportResult> oxplayerPostLibraryMediaReport(WidgetRef ref, String mediaId) async {
  if (!OxplayerConfig.isEnabled) {
    const m = 'OxplayerConfig.isEnabled is false';
    _reportDebug(m);
    return OxplayerLibraryReportResult.failure(debugLine: m);
  }
  final origin = _apiOrigin(ref);
  final creds = _credentials(ref);
  if (origin == null || creds == null || creds.token.isEmpty) {
    final m =
        'missing origin or credentials (originEmpty=${origin == null}, credsNull=${creds == null}, tokenEmpty=${creds?.token.isEmpty ?? true})';
    _reportDebug(m);
    return OxplayerLibraryReportResult.failure(debugLine: m);
  }

  final uri = Uri.parse('$origin/me/library/media/$mediaId/report');
  final headers = {
    ...creds.header(ref),
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  try {
    final res = await http.post(uri, headers: headers, body: '{}');
    final status = res.statusCode;
    if (status != 200) {
      final snippet = res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body;
      final m = 'POST $uri → HTTP $status body=$snippet';
      _reportDebug(m);
      return OxplayerLibraryReportResult.failure(httpStatus: status, debugLine: m);
    }
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(res.body);
      map = decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      final m = 'jsonDecode failed: $e body=${res.body.length > 120 ? "${res.body.substring(0, 120)}…" : res.body}';
      _reportDebug(m);
      return OxplayerLibraryReportResult.failure(httpStatus: status, debugLine: m);
    }
    if (map == null) {
      const m = 'response JSON is not an object';
      _reportDebug(m);
      return OxplayerLibraryReportResult.failure(httpStatus: status, debugLine: m);
    }
    if (map['ok'] != true) {
      final m = 'response ok!=true: $map';
      _reportDebug(m);
      return OxplayerLibraryReportResult.failure(httpStatus: status, debugLine: m);
    }
    final raw = map['adminNotified'];
    final adminNotified = raw is bool ? raw : true;
    return OxplayerLibraryReportResult.success(adminNotified: adminNotified);
  } catch (e, st) {
    final m = 'network/exception: $e';
    _reportDebug('$m\n$st');
    return OxplayerLibraryReportResult.failure(debugLine: m);
  }
}

/// POST `/me/library/media/locator-heal` — after the user sends the media in **provider-bot DM** (or TDLib finds a better chat/message), persist the playable locator for later playback.
Future<bool> oxplayerPostLibraryMediaLocatorHeal(
  WidgetRef ref, {
  required String mediaId,
  required int locatorChatId,
  required int locatorMessageId,
  String? resolutionReason,
}) async {
  if (!OxplayerConfig.isEnabled) return false;
  final origin = _apiOrigin(ref);
  final creds = _credentials(ref);
  if (origin == null || creds == null || creds.token.isEmpty) return false;

  final uri = Uri.parse('$origin/me/library/media/locator-heal');
  final headers = {
    ...creds.header(ref),
    'Accept': 'application/json',
    'Content-Type': 'application/json; charset=utf-8',
  };
  final body = jsonEncode(<String, dynamic>{
    'mediaFileId': mediaId,
    'locatorChatId': locatorChatId,
    'locatorMessageId': locatorMessageId,
    if (resolutionReason != null && resolutionReason.trim().isNotEmpty)
      'resolutionReason': resolutionReason.trim(),
  });
  try {
    final res = await http.post(uri, headers: headers, body: body);
    if (res.statusCode != 200) {
      if (kDebugMode) {
        _reportDebug('locator-heal HTTP ${res.statusCode} ${res.body}');
      }
      return false;
    }
    final j = jsonDecode(res.body);
    return j is Map && j['ok'] == true;
  } catch (e, st) {
    if (kDebugMode) {
      _reportDebug('locator-heal exception: $e\n$st');
    }
    return false;
  }
}

/// DELETE `/me/library/media/:id` — removes this user's attachment to that media on the server.
Future<bool> oxplayerDeleteLibraryMedia(WidgetRef ref, String mediaId) async {
  if (!OxplayerConfig.isEnabled) return false;
  final origin = _apiOrigin(ref);
  final creds = _credentials(ref);
  if (origin == null || creds == null || creds.token.isEmpty) return false;

  final uri = Uri.parse('$origin/me/library/media/$mediaId');
  try {
    final res = await http.delete(uri, headers: creds.header(ref));
    if (res.statusCode != 200) return false;
    final j = jsonDecode(res.body);
    return j is Map && j['ok'] == true;
  } catch (_) {
    return false;
  }
}
