import 'package:flutter/foundation.dart';

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_401_interceptor_delegate.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_session_refresh.dart';
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
    oxplayerJellyfin401RefreshHandler = oxplayerTryRefreshJellyfinSessionAfter401;
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
      // Intentionally do not await [trySilentRestore] here: it can block on TDLib
      // (e.g. transient 2FA / GetMe) and races the splash auto-login gate after
      // back-press. Splash tries HTTP refresh first, then restore + [authenticateWithOxApi].
      if (kDebugMode) {
        debugPrint('[OX TDLib] bootstrap warm-up: init only (no silentRestore)');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[OX TDLib] bootstrap warm-up: $e\n$st');
      }
    }
  }
}
