import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Loads [assets/env/default.env] once (same keys as `oxplayer-android/assets/env/default.env`).
///
/// If loading fails (missing asset, parse error), [dotenv] stays **uninitialized** and
/// [get] returns empty strings — never throws [NotInitializedError].
abstract final class OxplayerDotenv {
  /// `true` only after a **successful** [dotenv.load] (same as [dotenv.isInitialized]).
  static bool get isLoaded => dotenv.isInitialized;

  static Future<void> ensureLoaded() async {
    if (dotenv.isInitialized) {
      oxEnvLog('dotenv.ensureLoaded: already initialized (skip)');
      return;
    }
    try {
      await dotenv.load(
        fileName: 'assets/env/default.env',
        isOptional: true,
      );
    } catch (e) {
      oxEnvLog('dotenv.load FAILED: $e');
    }
    final n = dotenv.isInitialized ? dotenv.env.length : 0;
    final hasApi = dotenv.isInitialized &&
        (dotenv.env['OXPLAYER_API_BASE_URL']?.isNotEmpty ?? false);
    oxEnvLog(
      'dotenv after load: isInitialized=${dotenv.isInitialized} keyCount=$n '
      'has OXPLAYER_API_BASE_URL=$hasApi',
    );
  }

  static String _stripOuterQuotes(String s) {
    var t = s.trim();
    if (t.length >= 2 &&
        ((t.startsWith('"') && t.endsWith('"')) ||
            (t.startsWith("'") && t.endsWith("'")))) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  /// Raw value for [key], or empty when missing / dotenv not initialized.
  static String get(String key) {
    if (!dotenv.isInitialized) return '';
    final raw = dotenv.env[key];
    if (raw == null) return '';
    return _stripOuterQuotes(raw);
  }
}
