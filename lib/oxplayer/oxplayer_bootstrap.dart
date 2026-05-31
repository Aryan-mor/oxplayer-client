import 'package:flutter/foundation.dart';

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/oxplayer/bootstrap/oxplayer_bootstrap_stub.dart'
    if (dart.library.js_interop) 'package:fladder/oxplayer/bootstrap/oxplayer_bootstrap_web.dart'
    if (dart.library.io) 'package:fladder/oxplayer/bootstrap/oxplayer_bootstrap_native.dart'
    as platform_boot;
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_401_interceptor_delegate.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_session_refresh_stub.dart'
    if (dart.library.io) 'package:fladder/oxplayer/oxplayer_jellyfin_session_refresh.dart'
    as ox_jellyfin_refresh;
import 'package:fladder/oxplayer/oxplayer_persisted_url_sync.dart';
import 'package:fladder/util/fladder_config.dart';

/// OX-specific startup — avoids scattering `OXPLAYER` checks across upstream files.
///
/// Native-only bootstrap hooks live in
/// `lib/oxplayer/bootstrap/oxplayer_bootstrap_native.dart` and is selected via the
/// conditional import above.  The web compiler never sees that file, eliminating
/// the `MissingPluginException` that arose when DDC built the metadata graph for
/// the native import even though the `if (!kIsWeb)` guard prevented runtime calls.
abstract final class OxplayerBootstrap {
  /// Runs before [bootstrapApplication] (env, logging, experiments).
  static Future<void> beforeAppBootstrap(List<String> args) async {
    if (!OxplayerConfig.isEnabled) return;
  }

  /// Runs after [bootstrapApplication] when prefs / dirs are available.
  ///
  /// Platform-specific work (e.g. TDLib warm-up on native) is delegated to
  /// [platform_boot.executePlatformSpecificBoot] so the web compiler is never
  /// exposed to native-only import graphs.
  static Future<void> afterAppBootstrap(AppBootstrapResult bootstrap) async {
    if (!OxplayerConfig.isEnabled) return;
    oxplayerJellyfin401RefreshHandler =
        ox_jellyfin_refresh.oxplayerTryRefreshJellyfinSessionAfter401;
    final media = OxplayerEnv.effectiveMediaServerUrl;
    if (media != null && media.isNotEmpty) {
      FladderConfig.baseUrl = media;
    }
    // SharedPreferences + normalize_url only — no api_provider / Riverpod graph,
    // so web boot never pulls path_provider through this call.
    await OxplayerPersistedUrlSync.syncAccountsIfNeeded(bootstrap.sharedPreferences);
    await platform_boot.executePlatformSpecificBoot(bootstrap);
  }
}
