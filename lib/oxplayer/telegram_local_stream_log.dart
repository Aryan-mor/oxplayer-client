import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Telegram TDLib → loopback HTTP (filter: `OX_TG_STREAM`).
/// - Locator chain: `--dart-define=OX_TELEGRAM_LOCATOR_VERBOSE=true`.
/// - Provider `t.me` backup resolve: `--dart-define=OX_PROVIDER_BACKUP_VERBOSE=true` (extra parse/chat/file lines).
void oxTelegramLocalStreamLog(String step, [String? detail]) {
  if (!oxDiagnosticLogsEnabled) return;
  final msg = (detail == null || detail.isEmpty) ? step : '$step | $detail';
  oxDevLog(msg, name: 'OX_TG_STREAM', linePrefix: '[OX_TG_STREAM]');
}
