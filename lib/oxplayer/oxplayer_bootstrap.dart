import 'package:flutter/foundation.dart';

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_persisted_url_sync.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/util/fladder_config.dart';

/// OX-specific startup — avoid scattering `OXPLAYER` checks across upstream files.
abstract final class OxplayerBootstrap {
  /// Runs before [bootstrapApplication] (env, logging, experiments).
  static Future<void> beforeAppBootstrap(List<String> args) async {
    if (!OxplayerConfig.isEnabled) return;
    // Telegram login UI: `OxplayerTelegramLoginScreen` (route `/ox-login`) when `OXPLAYER=true`.
  }

  /// Runs after [bootstrapApplication] when prefs/dirs are available.
  static Future<void> afterAppBootstrap(AppBootstrapResult bootstrap) async {
    if (!OxplayerConfig.isEnabled) return;
    final media = OxplayerEnv.effectiveMediaServerUrl;
    if (media != null && media.isNotEmpty) {
      FladderConfig.baseUrl = media;
    }
    await OxplayerPersistedUrlSync.syncAccountsIfNeeded(bootstrap.sharedPreferences);

    if (!kIsWeb) {
      await _warmUpTdlibIfNeeded();
    }
  }

  /// Initialize TDLib early so playback works without opening `/ox-login` first
  /// (e.g. Splash → Dashboard with saved account). Safe if user is not logged in.
  static Future<void> _warmUpTdlibIfNeeded() async {
    try {
      await OxplayerTelegramTdSession.initPlugin();
      final session = OxplayerTelegramTdSession();
      await session.initClient();
      final restored = await session.trySilentRestore();
      if (kDebugMode) {
        debugPrint('[OX TDLib] bootstrap warm-up silentRestore=$restored');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OX TDLib] bootstrap warm-up: $e\n$st');
      }
    }
  }
}
