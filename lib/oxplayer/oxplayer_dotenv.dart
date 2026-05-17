import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:fladder/oxplayer/oxplayer_debug.dart';

/// Loads [assets/env/default.env] once (same keys as `oxplayer-android/assets/env/default.env`).
///
/// On **Flutter web**, [dotenv.load] often fails to resolve the asset and [isOptional] leaves an
/// **empty** map while still marking initialized — we try [rootBundle.loadString] on known asset
/// paths first, then [dotenv.testLoad].
abstract final class OxplayerDotenv {
  /// `true` only after a **successful** [dotenv.load] / [dotenv.testLoad] (same as [dotenv.isInitialized]).
  static bool get isLoaded => dotenv.isInitialized;

  /// Asset path that produced keys, or null when falling back to empty optional load.
  static String? get loadedAssetPath => _loadedAssetPath;

  static String? _loadedAssetPath;

  /// Number of keys in the loaded map (0 when optional empty fallback).
  static int get keyCount => dotenv.isInitialized ? dotenv.env.length : 0;

  static Future<void> ensureLoaded() async {
    if (dotenv.isInitialized) {
      oxEnvLog('dotenv.ensureLoaded: already initialized (skip)');
      return;
    }
    _loadedAssetPath = null;

    const candidates = <String>[
      'assets/env/default.env',
      'packages/fladder/assets/env/default.env',
    ];

    for (final name in candidates) {
      try {
        final raw = await rootBundle.loadString(name);
        if (raw.trim().isEmpty) {
          oxEnvLog('dotenv: skip empty asset "$name"');
          continue;
        }
        dotenv.testLoad(fileInput: raw);
        _loadedAssetPath = name;
        oxEnvLog(
          'dotenv loaded from "$name" keyCount=${dotenv.env.length}',
        );
        return;
      } catch (e) {
        oxEnvLog('dotenv: could not load "$name": $e');
      }
    }

    try {
      await dotenv.load(
        fileName: candidates.first,
        isOptional: true,
      );
      oxEnvLog(
        'dotenv optional fallback after asset miss: keyCount=${dotenv.env.length} '
        '(use dart-define-from-file or fix asset path)',
      );
    } catch (e) {
      oxEnvLog('dotenv.load FAILED: $e');
    }
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
