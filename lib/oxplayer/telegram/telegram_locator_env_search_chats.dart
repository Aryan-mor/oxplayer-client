import 'package:tdlib/td_api.dart' as td;

import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';

const Duration _kSearchPublicChatTimeout = Duration(seconds: 12);

/// Resolves [OxplayerEnv.botUsername] / [OxplayerEnv.providerBotUsername] to TDLib chat ids
/// for locator-tag [SearchChatMessages] fallbacks (oxplayer-android: [_locatorTagTelegramSearchChatIdsForEnv]).
final Map<String, int?> _usernameToChatIdCache = {};

Future<List<int>> oxplayerLocatorTagTelegramSearchChatIds(
  TdlibFacade tdlib,
  void Function(String message)? onDiagnostic,
) async {
  final out = <int>[];
  final seen = <int>{};

  Future<int?> cachedChatIdForUsername(String usernameKey) async {
    if (_usernameToChatIdCache.containsKey(usernameKey)) {
      return _usernameToChatIdCache[usernameKey];
    }
    try {
      final resolved = await tdlib
          .send(td.SearchPublicChat(username: usernameKey))
          .timeout(_kSearchPublicChatTimeout);
      if (resolved is td.Chat) {
        _usernameToChatIdCache[usernameKey] = resolved.id;
        onDiagnostic?.call('SearchPublicChat @$usernameKey → chatId=${resolved.id}');
        return resolved.id;
      }
    } on td.TdError catch (e) {
      onDiagnostic?.call('SearchPublicChat @$usernameKey failed: code=${e.code} ${e.message}');
    } catch (e) {
      onDiagnostic?.call('SearchPublicChat @$usernameKey crashed: $e');
    }
    _usernameToChatIdCache[usernameKey] = null;
    return null;
  }

  for (final raw in <String?>[
    OxplayerEnv.botUsername,
    OxplayerEnv.providerBotUsername,
  ]) {
    var u = raw?.trim() ?? '';
    if (u.isEmpty) continue;
    if (u.startsWith('@')) u = u.substring(1);
    final id = await cachedChatIdForUsername(u);
    if (id != null && seen.add(id)) out.add(id);
  }

  return out;
}
