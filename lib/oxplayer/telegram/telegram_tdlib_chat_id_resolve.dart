import 'package:tdlib/td_api.dart' as td;

import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';

const Duration _kTdlibOpTimeout = Duration(seconds: 8);

/// Matches [DataRepository._resolveTdlibChatIdForMedia] in oxplayer-android: maps stored
/// peer ids to a [td.Chat] TDLib can use before [GetMessage] / history search.
Future<int> resolveTdlibChatIdForMedia({
  required TdlibFacade tdlib,
  required int candidate,
  void Function(String message)? onDiagnostic,
}) async {
  Future<T?> tdTimeout<T>(Future<T> f) => f.timeout(_kTdlibOpTimeout);

  Future<int?> tryGetChat() async {
    try {
      final o = await tdTimeout(tdlib.send(td.GetChat(chatId: candidate)));
      if (o is td.Chat) return o.id;
    } on td.TdError catch (e) {
      onDiagnostic?.call('GetChat($candidate) TdError code=${e.code} message=${e.message}');
    } catch (_) {}
    return null;
  }

  final first = await tryGetChat();
  if (first != null) return first;

  if (candidate > 0) {
    try {
      final o = await tdTimeout(tdlib.send(td.CreatePrivateChat(userId: candidate, force: false)));
      if (o is td.Chat) {
        onDiagnostic?.call(
          'resolveTdlibChatIdForMedia: user id $candidate → chatId=${o.id} via CreatePrivateChat',
        );
        return o.id;
      }
    } on td.TdError catch (e) {
      onDiagnostic?.call(
        'resolveTdlibChatIdForMedia: CreatePrivateChat($candidate) code=${e.code} message=${e.message}',
      );
    } catch (_) {}
    return candidate;
  }

  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await tdTimeout(tdlib.send(const td.LoadChats(chatList: td.ChatListMain(), limit: 200)));
    } catch (_) {}
    await Future<void>.delayed(Duration(milliseconds: 120 + attempt * 180));
    final again = await tryGetChat();
    if (again != null) {
      onDiagnostic?.call(
        'resolveTdlibChatIdForMedia: GetChat($candidate) ok after LoadChats attempt=${attempt + 1}',
      );
      return again;
    }
  }

  return candidate;
}
