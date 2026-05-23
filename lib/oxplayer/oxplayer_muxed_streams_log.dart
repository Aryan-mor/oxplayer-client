import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Muxed audio/subtitle discovery → merge → verified-streams POST.
///
/// Visible in:
/// - `flutter run` console
/// - Android: `adb logcat | findstr OX_MUX_STR`
void oxMuxedStreamsLog(String detail) {
  if (!oxDiagnosticLogsEnabled) return;
  oxDevLog(detail, name: 'OX_MUX_STR', linePrefix: '[OX_MUX_STR]');
}
