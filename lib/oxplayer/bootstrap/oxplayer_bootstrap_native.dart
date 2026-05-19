import 'package:flutter/foundation.dart';

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';

/// Native (Android / iOS / desktop) implementation: starts the TDLib client
/// early so playback works without the user explicitly opening `/ox-login`.
Future<void> executePlatformSpecificBoot(AppBootstrapResult bootstrap) async {
  await _warmUpTdlibIfNeeded();
}

/// Initialize TDLib so the saved-session restore path in Splash works without
/// opening `/ox-login` first.  We deliberately do NOT await [trySilentRestore]:
/// it can block on transient TDLib handshakes and races the HTTP refresh gate.
Future<void> _warmUpTdlibIfNeeded() async {
  try {
    await OxplayerTelegramTdSession.initPlugin();
    final session = OxplayerTelegramTdSession();
    await session.initClient();
    if (kDebugMode) {
      debugPrint('[OX TDLib] bootstrap warm-up: init only (no silentRestore)');
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[OX TDLib] bootstrap warm-up: $e\n$st');
    }
  }
}
