import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set from OX bootstrap to [oxplayerTryRefreshJellyfinSessionAfter401] so [JellyRequest] does not
/// import `oxplayer_jellyfin_session_refresh.dart` (avoids a provider import cycle with [authProvider]).
Future<bool> Function(Ref ref)? oxplayerJellyfin401RefreshHandler;

Future<bool> oxplayerInvokeJellyfin401RefreshHandler(Ref ref) async {
  final handler = oxplayerJellyfin401RefreshHandler;
  if (handler == null) return false;
  return handler(ref);
}
