import 'package:shared_preferences/shared_preferences.dart';

/// Web / targets without `dart:io`: never used — [OxplayerPersistedUrlSync] routes web to
/// [OxplayerWebUrlSync] first.
Future<void> syncAccountsIfNeededNative(SharedPreferences prefs) async {}
