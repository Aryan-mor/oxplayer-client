import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Compile-time configuration for OXPlayer-only flows (Telegram auth, API base).
///
/// Use with `--dart-define=OXPLAYER=true` and e.g.:
/// `--dart-define=OXPLAYER_API_BASE=https://api.example.com`
/// `--dart-define=OXPLAYER_TELEGRAM_WEB_APP_URL=https://example.com/miniapp`
abstract final class OxplayerEnv {
  static const String _apiBaseRaw = String.fromEnvironment(
    'OXPLAYER_API_BASE',
    defaultValue: '',
  );

  static const String _telegramWebAppUrlRaw = String.fromEnvironment(
    'OXPLAYER_TELEGRAM_WEB_APP_URL',
    defaultValue: '',
  );

  /// Normalized API origin (no trailing slash), or null when unset / blank.
  static String? get apiBaseUrl {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _apiBaseRaw.trim();
    if (t.isEmpty) return null;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  /// Optional Mini App / Web App URL for in-app WebView (non-web targets only).
  static String? get telegramWebAppUrl {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _telegramWebAppUrlRaw.trim();
    return t.isEmpty ? null : t;
  }
}
