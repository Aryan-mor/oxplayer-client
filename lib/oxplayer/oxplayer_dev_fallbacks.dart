import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

/// Toggle branches inside [telegram_media_file_locator_resolver] for dev/testing.
///
/// Defaults are **enabled** (`true`) when unset so production behaves like before.
/// Set keys to `false` in `assets/env/default.env` (or `--dart-define=KEY=false`) to
/// disable specific TDLib locator fallbacks — e.g. while testing provider backup playback.
///
/// **Web:** `String.fromEnvironment` may only be invoked with a **compile-time constant**
/// name (per dart2js). This file uses one `const String.fromEnvironment` per key; runtime
/// keys like `String.fromEnvironment(defineKey, …)` are invalid on web.
abstract final class OxplayerDevFallbacks {
  /// Stored chat/message locator path (`CHAT_MESSAGE`): GetMessage candidates, etc.
  /// Env: `OX_FALLBACK_LOCATOR_STORED_CHAT` or legacy `OX_FALLBACK_PRIMARY_LIBRARY_LOCATOR`.
  static bool get locatorStoredChatBranch => _branchEnabled(
        constDefine: _kEnvLocatorStoredChat,
        defineKey: 'OX_FALLBACK_LOCATOR_STORED_CHAT',
        dotAliases: const ['OX_FALLBACK_PRIMARY_LIBRARY_LOCATOR'],
        legacyConstDefines: const [_kEnvLegacyPrimaryLibraryLocator],
      );

  /// `GetRemoteFile` via stored `remoteFileId`.
  static bool get locatorRemoteFile => _branchEnabled(
        constDefine: _kEnvLocatorRemoteFile,
        defineKey: 'OX_FALLBACK_LOCATOR_REMOTE_FILE',
      );

  /// Direct `GetMessage` loops over chat/message id candidates.
  static bool get locatorDirectGetMessage => _branchEnabled(
        constDefine: _kEnvLocatorDirectGet,
        defineKey: 'OX_FALLBACK_LOCATOR_DIRECT_GET',
      );

  /// `SearchChatMessages` on env bot chats for locator tag (`#oxm_*`).
  static bool get locatorEnvSearchTag => _branchEnabled(
        constDefine: _kEnvLocatorEnvSearch,
        defineKey: 'OX_FALLBACK_LOCATOR_ENV_SEARCH',
      );

  /// Global `SearchMessages` for locator tag.
  static bool get locatorGlobalSearch => _branchEnabled(
        constDefine: _kEnvLocatorGlobalSearch,
        defineKey: 'OX_FALLBACK_LOCATOR_GLOBAL_SEARCH',
      );

  /// Paginated chat history scan for file unique id / locator tag.
  static bool get locatorHistoryScan => _branchEnabled(
        constDefine: _kEnvLocatorHistoryScan,
        defineKey: 'OX_FALLBACK_LOCATOR_HISTORY_SCAN',
      );

  static const String _kEnvLocatorStoredChat = String.fromEnvironment(
    'OX_FALLBACK_LOCATOR_STORED_CHAT',
    defaultValue: '',
  );
  static const String _kEnvLegacyPrimaryLibraryLocator = String.fromEnvironment(
    'OX_FALLBACK_PRIMARY_LIBRARY_LOCATOR',
    defaultValue: '',
  );
  static const String _kEnvLocatorRemoteFile = String.fromEnvironment(
    'OX_FALLBACK_LOCATOR_REMOTE_FILE',
    defaultValue: '',
  );
  static const String _kEnvLocatorDirectGet = String.fromEnvironment(
    'OX_FALLBACK_LOCATOR_DIRECT_GET',
    defaultValue: '',
  );
  static const String _kEnvLocatorEnvSearch = String.fromEnvironment(
    'OX_FALLBACK_LOCATOR_ENV_SEARCH',
    defaultValue: '',
  );
  static const String _kEnvLocatorGlobalSearch = String.fromEnvironment(
    'OX_FALLBACK_LOCATOR_GLOBAL_SEARCH',
    defaultValue: '',
  );
  static const String _kEnvLocatorHistoryScan = String.fromEnvironment(
    'OX_FALLBACK_LOCATOR_HISTORY_SCAN',
    defaultValue: '',
  );

  static bool _branchEnabled({
    required String constDefine,
    required String defineKey,
    List<String> dotAliases = const [],
    List<String> legacyConstDefines = const [],
    bool defaultWhenUnset = true,
  }) {
    final fromConst = _parseTriState(constDefine);
    if (fromConst != null) return fromConst;

    for (final legacy in legacyConstDefines) {
      final fromLegacy = _parseTriState(legacy);
      if (fromLegacy != null) return fromLegacy;
    }

    final primaryDot = _parseTriState(OxplayerDotenv.get(defineKey));
    if (primaryDot != null) return primaryDot;

    for (final alias in dotAliases) {
      final a = _parseTriState(OxplayerDotenv.get(alias));
      if (a != null) return a;
    }

    return defaultWhenUnset;
  }

  /// `true` / `false` when explicit; `null` when blank / unrecognized.
  static bool? _parseTriState(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
    if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
    return null;
  }
}
