import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Offline sync / download (filter logcat by `OX_SYNC`).
void oxSyncLog(String step, [String? detail]) {
  final msg = (detail == null || detail.isEmpty) ? step : '$step | $detail';
  developer.log(msg, name: 'OX_SYNC');
  debugPrint('[OX_SYNC] $msg');
}
