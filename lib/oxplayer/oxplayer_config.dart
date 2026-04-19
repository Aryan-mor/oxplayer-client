import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

/// OXPlayer distribution flags (keep OX-only behavior behind this).
///
/// Priority: compile-time `--dart-define=OXPLAYER=...`, then `assets/env/default.env`.
/// Default is **on** (Telegram-first).
abstract final class OxplayerConfig {
  static bool get isEnabled {
    const fromDefine = bool.fromEnvironment(
      'OXPLAYER',
      defaultValue: true,
    );
    if (fromDefine == false) return false;

    if (OxplayerDotenv.isLoaded) {
      final v = OxplayerDotenv.get('OXPLAYER').trim().toLowerCase();
      if (v == 'false' || v == '0' || v == 'no') return false;
      if (v == 'true' || v == '1' || v == 'yes') return true;
    }
    return fromDefine;
  }
}
