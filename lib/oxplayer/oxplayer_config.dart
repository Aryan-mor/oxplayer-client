/// OXPlayer distribution flags (keep OX-only behavior behind this).
///
/// Enable hooks with:
/// `flutter run --dart-define=OXPLAYER=true`
/// or set `OXPLAYER=true` in your IDE run configuration.
abstract final class OxplayerConfig {
  static const bool isEnabled = bool.fromEnvironment(
    'OXPLAYER',
    defaultValue: false,
  );
}
