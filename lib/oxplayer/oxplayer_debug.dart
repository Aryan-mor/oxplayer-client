import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

/// OX tagged diagnostics ([OX_SYNC], playback traces, TDLib flow). Off in release/profile.
bool get oxDiagnosticLogsEnabled => kDebugMode;

/// Shared debug-only log (DevTools + console). [name] is the `developer.log` logger name.
void oxDevLog(
  String message, {
  required String name,
  String? linePrefix,
}) {
  if (!oxDiagnosticLogsEnabled) return;
  developer.log(message, name: name);
  debugPrint('${linePrefix ?? '[$name]'} $message');
}

/// Log line visible in Android Studio Logcat ΓÇö filter by **`OX_ENV`**.
///
/// On **Flutter web**, [developer.log] is easy to miss in the browser console; in [kDebugMode]
/// we also [debugPrint] a prefixed line so startup env checks are visible next to `[OX main]`.
void oxEnvLog(String message) {
  if (!oxDiagnosticLogsEnabled) return;
  developer.log(message, name: 'OX_ENV');
  debugPrint('[OX_ENV] $message');
}

/// High-signal web/local diagnostics. Filter browser console by **`[OX_DEBUG]`**.
void oxDebugLog(String message) {
  if (!oxDiagnosticLogsEnabled) return;
  developer.log(message, name: 'OX_DEBUG');
  if (kIsWeb) {
    debugPrint('[OX_DEBUG] $message');
  }
}
