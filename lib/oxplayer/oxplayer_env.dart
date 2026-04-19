import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

/// Runtime + compile-time configuration for OXPlayer (Telegram, API, optional keys).
///
/// Values are read in this order:
/// 1. **`--dart-define=…` / `--dart-define-from-file=…`** (compile-time; refreshed on each `flutter run`)
/// 2. **Android / Gradle:** `android/build.gradle` also injects defines from `assets/env/default.env`
///    and `dart_defines.ngrok.json` (written by `pnpm dev:ngrok`) so Android Studio does not need
///    `--dart-define-from-file`.
/// 3. **`assets/env/default.env`** via [OxplayerDotenv] (bundled in the APK — needs rebuild to change)
///
/// Telegram **sign-in** on Android uses TDLib + `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` (see
/// `lib/oxplayer/telegram/`). Mini App URLs here are still used **after** TDLib login to fetch
/// signed `initData` for `POST /auth/telegram` (same as oxplayer-android).
///
/// For Web / iOS, optional: `--dart-define-from-file=dart_defines.ngrok.json` after `pnpm dev:ngrok`.
abstract final class OxplayerEnv {
  static const String _cApiBase = String.fromEnvironment(
    'OXPLAYER_API_BASE',
    defaultValue: '',
  );
  static const String _cApiBaseUrl = String.fromEnvironment(
    'OXPLAYER_API_BASE_URL',
    defaultValue: '',
  );
  static const String _cTelegramWebAppUrl = String.fromEnvironment(
    'OXPLAYER_TELEGRAM_WEB_APP_URL',
    defaultValue: '',
  );
  static const String _cTelegramWebAppUrlAlt = String.fromEnvironment(
    'OXPLAYER_TELEGRAM_WEBAPP_URL',
    defaultValue: '',
  );
  static const String _cJellyfinUrl = String.fromEnvironment(
    'OXPLAYER_JELLYFIN_URL',
    defaultValue: '',
  );
  static const String _cBotUsername = String.fromEnvironment(
    'OXPLAYER_BOT_USERNAME',
    defaultValue: '',
  );
  static const String _cBotUsernameLegacy = String.fromEnvironment(
    'BOT_USERNAME',
    defaultValue: '',
  );
  static const String _cWebAppShortName = String.fromEnvironment(
    'OXPLAYER_TELEGRAM_WEBAPP_SHORT_NAME',
    defaultValue: '',
  );
  static const String _cTelegramApiId = String.fromEnvironment(
    'TELEGRAM_API_ID',
    defaultValue: '',
  );
  static const String _cTelegramApiHash = String.fromEnvironment(
    'TELEGRAM_API_HASH',
    defaultValue: '',
  );
  static const String _cProviderBotUsername = String.fromEnvironment(
    'PROVIDER_BOT_USERNAME',
    defaultValue: '',
  );
  static const String _cSubdlApiKey = String.fromEnvironment(
    'SUBDL_API_KEY',
    defaultValue: '',
  );

  static String _pick(
    List<String> dotKeys,
    String definePrimary, [
    String defineSecondary = '',
  ]) {
    final a = definePrimary.trim();
    if (a.isNotEmpty) return a;
    final b = defineSecondary.trim();
    if (b.isNotEmpty) return b;
    for (final k in dotKeys) {
      final d = OxplayerDotenv.get(k);
      if (d.isNotEmpty) return d;
    }
    return '';
  }

  static String _normOrigin(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  /// Normalized API origin (no trailing slash), or null when unset / blank.
  static String? get apiBaseUrl {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _normOrigin(_pick(
      ['OXPLAYER_API_BASE', 'OXPLAYER_API_BASE_URL'],
      _cApiBase,
      _cApiBaseUrl,
    ));
    return t.isEmpty ? null : t;
  }

  /// Logcat filter: **`OX_ENV`**. Call after [OxplayerDotenv.ensureLoaded] to trace API URL resolution.
  static void debugLogApiResolution() {
    final dotBase = OxplayerDotenv.get('OXPLAYER_API_BASE');
    final dotUrl = OxplayerDotenv.get('OXPLAYER_API_BASE_URL');
    oxEnvLog(
      'OxplayerEnv.resolve: isEnabled=${OxplayerConfig.isEnabled} '
      'dotenvInit=${OxplayerDotenv.isLoaded} '
      'defineLen apiBase=${_cApiBase.length} apiBaseUrl=${_cApiBaseUrl.length} '
      'dotenvLen apiBase=${dotBase.length} apiBaseUrl=${dotUrl.length} '
      'apiBaseUrl=${apiBaseUrl ?? 'null'} '
      'effectiveMediaServerUrl=${effectiveMediaServerUrl ?? 'null'}',
    );
  }

  /// Jellyfin-compatible base URL for this build: explicit Jellyfin URL, else API origin.
  static String? get effectiveMediaServerUrl {
    final j = jellyfinServerUrl;
    if (j != null && j.isNotEmpty) return j;
    return apiBaseUrl;
  }

  /// Optional Mini App / Web App URL (HTTPS or `t.me/...`).
  static String? get telegramWebAppUrl {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _pick(
      ['OXPLAYER_TELEGRAM_WEB_APP_URL', 'OXPLAYER_TELEGRAM_WEBAPP_URL'],
      _cTelegramWebAppUrl,
      _cTelegramWebAppUrlAlt,
    );
    return t.isEmpty ? null : t;
  }

  /// Jellyfin-compatible server URL (trimmed), or null when unset.
  static String? get jellyfinServerUrl {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _pick(['OXPLAYER_JELLYFIN_URL'], _cJellyfinUrl);
    return t.isEmpty ? null : t;
  }

  /// Telegram bot username without `@`.
  static String? get botUsername {
    if (!OxplayerConfig.isEnabled) return null;
    var t = _pick(
      ['OXPLAYER_BOT_USERNAME', 'BOT_USERNAME'],
      _cBotUsername,
      _cBotUsernameLegacy,
    ).replaceFirst(RegExp(r'^@'), '');
    return t.isEmpty ? null : t;
  }

  /// Mini App short name for `https://t.me/<bot>/<shortName>`, optional.
  static String? get telegramWebAppShortName {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _pick(['OXPLAYER_TELEGRAM_WEBAPP_SHORT_NAME'], _cWebAppShortName);
    return t.isEmpty ? null : t;
  }

  /// Prefer direct Mini App URL from env; else `https://t.me/<bot>/<shortName>` when both are set.
  static String? get telegramMiniAppOpenLink {
    final direct = telegramWebAppUrl;
    if (direct != null) return direct;
    final bot = botUsername;
    final short = telegramWebAppShortName;
    if (bot != null && short != null) {
      return 'https://t.me/$bot/$short';
    }
    return null;
  }

  static String? get telegramApiId {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _pick(['TELEGRAM_API_ID'], _cTelegramApiId);
    return t.isEmpty ? null : t;
  }

  static String? get telegramApiHash {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _pick(['TELEGRAM_API_HASH'], _cTelegramApiHash);
    return t.isEmpty ? null : t;
  }

  static String? get providerBotUsername {
    if (!OxplayerConfig.isEnabled) return null;
    var t = _pick(['PROVIDER_BOT_USERNAME'], _cProviderBotUsername)
        .replaceFirst(RegExp(r'^@'), '');
    return t.isEmpty ? null : t;
  }

  static String? get subdlApiKey {
    if (!OxplayerConfig.isEnabled) return null;
    final t = _pick(['SUBDL_API_KEY'], _cSubdlApiKey);
    return t.isEmpty ? null : t;
  }
}
