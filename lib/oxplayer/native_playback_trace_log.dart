import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Trace path: UI → [loadPlaybackItem] → [MediaControlsWrapper.loadVideo] →
/// [NativePlayer.sendPlaybackDataToNative] / [NativePlayer.loadVideo] → Android Exo.
///
/// Flutter console: `flutter run`
/// Android: `adb logcat | findstr OX_NATIVE_PLY`
void oxNativePlaybackTrace(String detail) {
  const tag = 'OX_NATIVE_PLY';
  final line = '[$tag] $detail';
  developer.log(detail, name: tag);
  debugPrint(line);
  print(line);
}

/// Short URL line for logs (full query strings are often huge / sensitive).
String oxNativePlaybackUrlHint(String? url) {
  if (url == null || url.isEmpty) return 'url=<empty>';
  final uri = Uri.tryParse(url);
  if (uri == null) return 'url=<unparseable len=${url.length}>';
  return 'scheme=${uri.scheme} host=${uri.host} pathLen=${uri.path.length} '
      'hasQuery=${uri.hasQuery} len=${url.length}';
}
