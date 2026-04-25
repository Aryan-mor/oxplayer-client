import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Muxed audio/subtitle discovery → merge → verified-streams POST.
///
/// Visible in:
/// - `flutter run` console
/// - Android: `adb logcat | findstr OX_MUX_STR`
///
/// `print` is included because `debugPrint` / `developer.log` are easy to miss in release or filtered views.
void oxMuxedStreamsLog(String detail) {
  const tag = 'OX_MUX_STR';
  final line = '[$tag] $detail';
  developer.log(detail, name: tag);
  debugPrint(line);
  print(line);
}
