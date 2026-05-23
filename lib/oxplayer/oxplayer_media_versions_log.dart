import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Multi-file / Jellyfin `MediaSources` diagnostics. Filter logcat:
/// `adb logcat | findstr OX_MS_VER` (cmd) or `Select-String "OX_MS_VER"` (PowerShell).
void oxMediaVersionsLog(String detail) {
  if (!oxDiagnosticLogsEnabled) return;
  oxDevLog(detail, name: 'OX_MS_VER', linePrefix: '[OX_MS_VER]');
}
