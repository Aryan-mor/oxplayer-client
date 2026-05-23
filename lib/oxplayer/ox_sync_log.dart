import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Offline sync / download (filter logcat by `OX_SYNC`).
void oxSyncLog(String step, [String? detail]) {
  if (!oxDiagnosticLogsEnabled) return;
  final msg = (detail == null || detail.isEmpty) ? step : '$step | $detail';
  oxDevLog(msg, name: 'OX_SYNC', linePrefix: '[OX_SYNC]');
}
