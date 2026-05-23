import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Trace path: UI → [loadPlaybackItem] → [MediaControlsWrapper.loadVideo] →
/// [NativePlayer.sendPlaybackDataToNative] / [NativePlayer.loadVideo] → Android Exo.
///
/// Flutter console: `flutter run`
/// Android: `adb logcat | findstr OX_NATIVE_PLY`
void oxNativePlaybackTrace(String detail) {
  if (!oxDiagnosticLogsEnabled) return;
  oxDevLog(detail, name: 'OX_NATIVE_PLY', linePrefix: '[OX_NATIVE_PLY]');
}

/// Short URL line for logs (full query strings are often huge / sensitive).
String oxNativePlaybackUrlHint(String? url) {
  if (url == null || url.isEmpty) return 'url=<empty>';
  final uri = Uri.tryParse(url);
  if (uri == null) return 'url=<unparseable len=${url.length}>';
  return 'scheme=${uri.scheme} host=${uri.host} pathLen=${uri.path.length} '
      'hasQuery=${uri.hasQuery} len=${url.length}';
}
