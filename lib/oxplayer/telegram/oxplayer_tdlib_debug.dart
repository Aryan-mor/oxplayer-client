import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Minimal logging for TDLib (replaces oxplayer-android [AuthDebugService] hooks).
enum AuthDebugLevel { info, success, error }

void authDebugSuccess(String message) {
  if (!oxDiagnosticLogsEnabled) return;
  debugPrint('[OX TDLib] $message');
}

void authDebugError(String message) {
  if (!oxDiagnosticLogsEnabled) return;
  debugPrint('[OX TDLib ERROR] $message');
}

void authDebugDedup(
  String key,
  AuthDebugLevel level,
  String message, {
  Object? completeStatus,
}) {
  if (!oxDiagnosticLogsEnabled) return;
  debugPrint('[OX TDLib] $message');
}
