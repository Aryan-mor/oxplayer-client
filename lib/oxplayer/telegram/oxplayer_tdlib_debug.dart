import 'package:flutter/foundation.dart';

/// Minimal logging for TDLib (replaces oxplayer-android [AuthDebugService] hooks).
enum AuthDebugLevel { info, success, error }

void authDebugSuccess(String message) => debugPrint('[OX TDLib] $message');

void authDebugError(String message) => debugPrint('[OX TDLib ERROR] $message');

void authDebugDedup(
  String key,
  AuthDebugLevel level,
  String message, {
  Object? completeStatus,
}) {
  debugPrint('[OX TDLib] $message');
}
