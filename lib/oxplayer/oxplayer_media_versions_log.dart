import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Multi-file / Jellyfin `MediaSources` diagnostics. Filter logcat:
/// `adb logcat | findstr OX_MS_VER` (cmd) or `Select-String "OX_MS_VER"` (PowerShell).
void oxMediaVersionsLog(String detail) {
  const tag = 'OX_MS_VER';
  developer.log(detail, name: tag);
  debugPrint('[$tag] $detail');
}
