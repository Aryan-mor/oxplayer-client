import 'dart:convert';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// TDLib chat + message to load Telegram’s local video preview (from `GET /me/library/media/:id` → `files[0]`).
class OxMediaTelegramRef {
  const OxMediaTelegramRef({required this.chatId, required this.messageId});

  final int chatId;
  final int messageId;
}

/// Resolves [OxMediaTelegramRef] for OX `ProviderIds.OXMedia` (raw `media.id` string from the API).
final oxMediaTelegramRefProvider = FutureProvider.family<OxMediaTelegramRef?, String>(
  (ref, mediaId) async {
    if (!OxplayerConfig.isEnabled) return null;
    final t = mediaId.trim();
    if (t.isEmpty) return null;
    final serverUrl = ref.read(serverUrlProvider);
    final creds = ref.read(userProvider)?.credentials;
    if (serverUrl == null || serverUrl.isEmpty || creds == null) {
      return null;
    }
    final uri = Uri.parse(serverUrl).resolve('me/library/media/${Uri.encodeComponent(t)}');
    final r = await http.get(uri, headers: creds.header(ref));
    if (r.statusCode != 200) return null;
    final d = jsonDecode(r.body);
    if (d is! Map) return null;
    final files = d['files'] as List<dynamic>?;
    if (files == null || files.isEmpty) return null;
    final f0 = files.first;
    if (f0 is! Map) return null;
    final c = f0['locatorChatId'] ?? f0['locator_chat_id'];
    final m = f0['locatorMessageId'] ?? f0['locator_message_id'];
    if (c is! num || m is! num) return null;
    return OxMediaTelegramRef(
      chatId: c.toInt(),
      messageId: m.toInt(),
    );
  },
);
