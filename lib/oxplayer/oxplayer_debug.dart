import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

/// Log line visible in Android Studio Logcat — filter by **`OX_ENV`**.
///
/// On **Flutter web**, [developer.log] is easy to miss in the browser console; in [kDebugMode]
/// we also [debugPrint] a prefixed line so startup env checks are visible next to `[OX main]`.
void oxEnvLog(String message) {
  developer.log(message, name: 'OX_ENV');
  if (kDebugMode && kIsWeb) {
    debugPrint('[OX_ENV] $message');
  }
}

/// High-signal web/local diagnostics. Filter browser console by **`[OX_DEBUG]`**.
void oxDebugLog(String message) {
  developer.log(message, name: 'OX_DEBUG');
  if (kDebugMode && kIsWeb) {
    debugPrint('[OX_DEBUG] $message');
  }
}
