import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/telegram/telegram_range_playback.dart';

Future<void> releaseOxplayerTelegramPlaybackIfNeeded() async {
  if (kIsWeb || !OxplayerConfig.isEnabled) return;
  await TelegramRangePlayback.instance.releaseActiveCacheIfAny(reason: 'player_stop');
}
