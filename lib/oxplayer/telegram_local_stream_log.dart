import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Telegram TDLib → loopback HTTP (filter: `OX_TG_STREAM`).
/// - Locator chain: `--dart-define=OX_TELEGRAM_LOCATOR_VERBOSE=true`.
/// - Provider `t.me` backup resolve: `--dart-define=OX_PROVIDER_BACKUP_VERBOSE=true` (extra parse/chat/file lines).
void oxTelegramLocalStreamLog(String step, [String? detail]) {
  final msg = (detail == null || detail.isEmpty) ? step : '$step | $detail';
  developer.log(msg, name: 'OX_TG_STREAM');
  debugPrint('[OX_TG_STREAM] $msg');
}
