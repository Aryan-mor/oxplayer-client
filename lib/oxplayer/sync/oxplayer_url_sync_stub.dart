import 'package:shared_preferences/shared_preferences.dart';

/// Compile-time fallback for targets that expose neither `dart.library.js_interop`
/// nor `dart.library.io`.
abstract final class OxplayerPersistedUrlSync {
  static Future<void> syncAccountsIfNeeded(SharedPreferences prefs) {
    return Future<void>.error(
      UnsupportedError('Oxplayer URL sync has no implementation for this platform.'),
    );
  }
}
