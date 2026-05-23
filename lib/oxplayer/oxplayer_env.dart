import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

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
/// Telegram **sign-in** uses TDLib: native builds use `libtdjson`; **Flutter web** uses the
/// official `tdweb` WASM bundle (see `web/tdweb/README.md`). `TELEGRAM_API_ID` / `TELEGRAM_API_HASH`
/// are required in all cases. Mini App URLs are still used **after** TDLib login to fetch signed
/// `initData` for `POST /auth/telegram` (same as oxplayer-android).
///
/// For Web / iOS, optional: `--dart-define-from-file=dart_defines.dev.json` (after `pnpm docker:dev`)
/// or `dart_defines.ngrok.json` (after `pnpm dev:ngrok`).
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
    'OXPLAYER_TELEGRAM_WEBAPP_URL',
    defaultValue: '',
  );
  static const String _cTelegramWebAppUrlAlt = String.fromEnvironment(
    'OXPLAYER_TELEGRAM_WEB_APP_URL',
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
  static const String _cDebugTelegramInitData = String.fromEnvironment(
    'OXPLAYER_DEBUG_TELEGRAM_INIT_DATA',
    defaultValue: '',
  );
  static const String _cGooglePlayReviewPhone = String.fromEnvironment(
    'OXPLAYER_GOOGLE_PLAY_REVIEW_PHONE',
    defaultValue: '',
  );
  static const String _cGooglePlayReviewCode = String.fromEnvironment(
    'OXPLAYER_GOOGLE_PLAY_REVIEW_CODE',
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
  static const String _cOxmPrefix = String.fromEnvironment(
    'OXM_PREFIX',
    defaultValue: '',
  );
  static const String _cSentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );
  static const String _cSentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: '',
  );
  static const String _cSentryTracesSampleRate = String.fromEnvironment(
    'SENTRY_TRACES_SAMPLE_RATE',
    defaultValue: '',
  );
  static const String _cSentryDebug = String.fromEnvironment(
    'SENTRY_DEBUG',
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

  /// Removes whitespace and Unicode line/paragraph separators from pasted `.env` / dart-define values.
  static String compactTelegramWireUrl(String raw) {
    if (raw.isEmpty) return raw;
    var t = raw;
    for (final sep in ['\u0000', '\u000b', '\u0085', '\u2028', '\u2029']) {
      t = t.replaceAll(sep, '');
    }
    return t.replaceAll(RegExp(r'\s+'), '');
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
      'dotenvAsset=${OxplayerDotenv.loadedAssetPath ?? "none"} '
      'dotenvKeys=${OxplayerDotenv.keyCount} '
      'defineLen apiBase=${_cApiBase.length} apiBaseUrl=${_cApiBaseUrl.length} '
      'dotenvLen apiBase=${dotBase.length} apiBaseUrl=${dotUrl.length} '
      'apiBaseUrl=${apiBaseUrl ?? 'null'} '
      'effectiveMediaServerUrl=${effectiveMediaServerUrl ?? 'null'}',
    );
  }

  /// Logcat / DevTools: **`OX_ENV`**. Call after [OxplayerDotenv.ensureLoaded]. Does not log secrets
  /// (only whether API id/hash exist and string lengths). Use from [main] in debug to verify env
  /// before Telegram login / WebApp init.
  static void debugLogTelegramReadiness() {
    if (!OxplayerConfig.isEnabled) {
      return;
    }
    final id = telegramApiId;
    final hash = telegramApiHash;
    final bot = botUsername;
    final short = telegramWebAppShortName;
    final direct = telegramWebAppUrl;
    final mini = telegramMiniAppOpenLink;
    final idDef = _cTelegramApiId.trim().isNotEmpty;
    final idDot = OxplayerDotenv.get('TELEGRAM_API_ID').trim().isNotEmpty;
    final hashDef = _cTelegramApiHash.trim().isNotEmpty;
    final hashDot = OxplayerDotenv.get('TELEGRAM_API_HASH').trim().isNotEmpty;
    final shortDef = _cWebAppShortName.trim().isNotEmpty;
    final shortDot =
        OxplayerDotenv.get('OXPLAYER_TELEGRAM_WEBAPP_SHORT_NAME').trim().isNotEmpty;
    final botDef =
        _cBotUsername.trim().isNotEmpty || _cBotUsernameLegacy.trim().isNotEmpty;
    final botDot = OxplayerDotenv.get('BOT_USERNAME').trim().isNotEmpty ||
        OxplayerDotenv.get('OXPLAYER_BOT_USERNAME').trim().isNotEmpty;
    final urlDef =
        _cTelegramWebAppUrl.trim().isNotEmpty || _cTelegramWebAppUrlAlt.trim().isNotEmpty;
    final urlDot = OxplayerDotenv.get('OXPLAYER_TELEGRAM_WEBAPP_URL').trim().isNotEmpty ||
        OxplayerDotenv.get('OXPLAYER_TELEGRAM_WEB_APP_URL').trim().isNotEmpty;

    String pickSrc(bool def, bool dot) {
      if (def) return 'dart-define';
      if (dot) return 'dotenv';
      return 'none';
    }

    oxEnvLog(
      'OxplayerEnv.telegram: web=$kIsWeb '
      'dotenvAsset=${OxplayerDotenv.loadedAssetPath ?? "none"} '
      'dotenvKeys=${OxplayerDotenv.keyCount} '
      'apiId=${id == null ? "missing" : "ok(len=${id.length})"} '
      'src=${pickSrc(idDef, idDot)} '
      'apiHash=${hash == null ? "missing" : "ok(len=${hash.length})"} '
      'src=${pickSrc(hashDef, hashDot)} '
      'bot=${bot ?? "missing"} src=${pickSrc(botDef, botDot)} '
      'webappShort=${short ?? "missing"} src=${pickSrc(shortDef, shortDot)} '
      'webappDirect=${direct == null ? "missing" : "ok(len=${direct.length})"} '
      'src=${pickSrc(urlDef, urlDot)} '
      'miniOpenLink=${mini ?? "missing"}',
    );
  }

  /// Media API base URL for this build: optional `OXPLAYER_JELLYFIN_URL` override, else API origin.
  static String? get effectiveMediaServerUrl {
    final j = jellyfinServerUrl;
    if (j != null && j.isNotEmpty) return j;
    return apiBaseUrl;
  }

  /// Optional Mini App / Web App URL (HTTPS or `t.me/...`).
  static String? get telegramWebAppUrl {
    if (!OxplayerConfig.isEnabled) return null;
    var t = _pick(
      ['OXPLAYER_TELEGRAM_WEBAPP_URL', 'OXPLAYER_TELEGRAM_WEB_APP_URL'],
      _cTelegramWebAppUrl,
      _cTelegramWebAppUrlAlt,
    );
    if (t.isEmpty) return null;
    final c = compactTelegramWireUrl(t);
    return c.isEmpty ? null : c;
  }

  /// Hosted **HTTPS** Mini App URL suitable for TDLib [getWebAppUrl] (not a `t.me/…` redirect).
  ///
  /// TDLib rejects `t.me` short links for the `url` argument; use your deployed app origin
  /// in `OXPLAYER_TELEGRAM_WEBAPP_URL` (legacy alias: `OXPLAYER_TELEGRAM_WEB_APP_URL`).
  /// Fragments (`#/ox-login`) are stripped because Telegram validates a raw HTTPS endpoint.
  static String? get telegramHostedWebAppHttpsUrl {
    final u = telegramWebAppUrl;
    if (u == null || u.isEmpty) return null;
    final lower = u.toLowerCase();
    if (!lower.startsWith('https://')) return null;
    if (lower.startsWith('https://t.me/')) return null;
    final uri = Uri.tryParse(u);
    if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      return null;
    }
    return uri.replace(fragment: '').toString();
  }

  /// Optional alternate media server URL (`OXPLAYER_JELLYFIN_URL`), or null when unset.
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
    t = compactTelegramWireUrl(t);
    return t.isEmpty ? null : t;
  }

  /// `https://t.me/<bot>` when [botUsername] is set.
  static String? get telegramBotOpenLink {
    final b = botUsername;
    if (b == null || b.isEmpty) return null;
    return compactTelegramWireUrl('https://t.me/$b');
  }

  /// Mini App short name for `https://t.me/<bot>/<shortName>`, optional.
  static String? get telegramWebAppShortName {
    if (!OxplayerConfig.isEnabled) return null;
    var t = _pick(['OXPLAYER_TELEGRAM_WEBAPP_SHORT_NAME'], _cWebAppShortName).trim();
    if (t.isEmpty) return null;
    t = compactTelegramWireUrl(t);
    return t.isEmpty ? null : t;
  }

  /// Prefer direct Mini App URL from env; else `https://t.me/<bot>/<shortName>` when both are set.
  static String? get telegramMiniAppOpenLink {
    final direct = telegramWebAppUrl;
    if (direct != null) return direct;
    final bot = botUsername;
    final short = telegramWebAppShortName;
    if (bot != null && short != null) {
      return compactTelegramWireUrl('https://t.me/$bot/$short');
    }
    return null;
  }

  /// **Debug only:** raw `tgWebAppData` query value for `/auth/telegram` when TDLib cannot
  /// produce signed Mini App data (e.g. BotFather Main Web App not set, or tdweb pin mismatch).
  ///
  /// Ignored unless [kDebugMode]. Set `OXPLAYER_DEBUG_TELEGRAM_INIT_DATA` via `--dart-define`,
  /// `--dart-define-from-file`, or [OxplayerDotenv].
  static String? get telegramWebAppInitDataDebugOverride {
    if (!OxplayerConfig.isEnabled || !kDebugMode) return null;
    final t = _pick(['OXPLAYER_DEBUG_TELEGRAM_INIT_DATA'], _cDebugTelegramInitData).trim();
    return t.isEmpty ? null : t;
  }

  static const String _defaultGooglePlayReviewPhone = '+123456789';
  static const String _defaultGooglePlayReviewCode = '1234';

  /// Google Play review login (defaults match server when env unset).
  static String get googlePlayReviewPhone {
    if (!OxplayerConfig.isEnabled) return _defaultGooglePlayReviewPhone;
    final t = _pick(
      ['OXPLAYER_GOOGLE_PLAY_REVIEW_PHONE', 'GOOGLE_PLAY_REVIEW_PHONE'],
      _cGooglePlayReviewPhone,
    ).trim();
    return t.isEmpty ? _defaultGooglePlayReviewPhone : t;
  }

  static String get googlePlayReviewCode {
    if (!OxplayerConfig.isEnabled) return _defaultGooglePlayReviewCode;
    final t = _pick(
      ['OXPLAYER_GOOGLE_PLAY_REVIEW_CODE', 'GOOGLE_PLAY_REVIEW_CODE'],
      _cGooglePlayReviewCode,
    ).trim();
    return t.isEmpty ? _defaultGooglePlayReviewCode : t;
  }

  static String normalizeReviewPhoneNumber(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (t.startsWith('00')) return '+${t.substring(2)}';
    if (t.startsWith('+')) return t;
    return '+$t';
  }

  static bool isGooglePlayReviewPhone(String phone) {
    return normalizeReviewPhoneNumber(phone) ==
        normalizeReviewPhoneNumber(googlePlayReviewPhone);
  }

  static bool isGooglePlayReviewCredentials(String phone, String code) {
    if (!isGooglePlayReviewPhone(phone)) return false;
    return code.trim() == googlePlayReviewCode.trim();
  }

  static bool get isGooglePlayReviewLoginConfigured => OxplayerConfig.isEnabled;

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

  /// Media locator hashtag for TDLib search fallbacks (`SearchMessages` / history / `#oxm_*`).
  /// Set **`OXM_PREFIX`** (e.g. `#oxm_dev_` in dev). If unset or blank, defaults to **`#oxm_`**.
  /// A leading `#` is added when missing so `oxm_dev_` becomes `#oxm_dev_`.
  static String get oxmLocatorTagPrefix {
    if (!OxplayerConfig.isEnabled) return '#oxm_';
    var t = _pick(['OXM_PREFIX'], _cOxmPrefix).trim();
    if (t.isEmpty) return '#oxm_';
    if (!t.startsWith('#')) t = '#$t';
    return t;
  }

  /// [oxmLocatorTagPrefix] without the leading `#` (for alternate search queries like `oxm_dev_14`).
  static String get oxmLocatorTagPrefixBare {
    final h = oxmLocatorTagPrefix;
    return h.startsWith('#') ? h.substring(1) : h;
  }

  /// When true, OX Telegram playback uses only [providerBackupPostUrl] (or [playbackProviderPostUrlOverride]);
  /// stored locator + TDLib search fallbacks are skipped. See `OX_FALLBACK_PROVIDER_ONLY` in `default.env`.
  static bool get playbackProviderOnly {
    const fromDefine = bool.fromEnvironment(
      'OX_FALLBACK_PROVIDER_ONLY',
      defaultValue: false,
    );
    if (fromDefine) return true;
    if (!OxplayerConfig.isEnabled) return false;
    final v = OxplayerDotenv.get('OX_FALLBACK_PROVIDER_ONLY').trim().toLowerCase();
    return v == 'true' || v == '1' || v == 'yes' || v == 'on';
  }

  /// Sentry DSN, or null when unset (crash reporting off). Same keys as `oxplayer` API: `SENTRY_DSN`, etc.
  static String? get sentryDsn {
    final dsn = _pick(['SENTRY_DSN'], _cSentryDsn).trim();
    return dsn.isEmpty ? null : dsn;
  }

  /// Sentry environment tag (e.g. `production`, `development`). Defaults to `development` in debug builds.
  static String get sentryEnvironment {
    final fromEnv = _pick(['SENTRY_ENVIRONMENT'], _cSentryEnvironment).trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return kDebugMode ? 'development' : 'production';
  }

  /// Performance trace sample rate (0–1). Default `0.1` when DSN is set.
  static double get sentryTracesSampleRate {
    final raw = _pick(['SENTRY_TRACES_SAMPLE_RATE'], _cSentryTracesSampleRate).trim();
    if (raw.isEmpty) return 0.1;
    final parsed = double.tryParse(raw);
    if (parsed == null) return 0.1;
    return parsed.clamp(0.0, 1.0);
  }

  /// Verbose Sentry SDK logs to console. Set `SENTRY_DEBUG=1` while debugging SDK wiring.
  static bool get sentryDebug {
    final raw = _pick(['SENTRY_DEBUG'], _cSentryDebug).trim();
    return raw == '1' || raw.toLowerCase() == 'true';
  }

  /// Dev override for public `t.me/...` post when API has no [providerBackupPostUrl] yet.
  static String get playbackProviderPostUrlOverride {
    const fromDefine = String.fromEnvironment(
      'OX_FALLBACK_PROVIDER_POST_URL_OVERRIDE',
      defaultValue: '',
    );
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    if (!OxplayerConfig.isEnabled) return '';
    return OxplayerDotenv.get('OX_FALLBACK_PROVIDER_POST_URL_OVERRIDE').trim();
  }
}
