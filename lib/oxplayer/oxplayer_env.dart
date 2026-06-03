import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

abstract final class OxplayerEnv {
  static const String _cApiBaseUrl = String.fromEnvironment('OXPLAYER_API_BASE_URL', defaultValue: '');
  static const String _cBotUsername = String.fromEnvironment('OXPLAYER_BOT_USERNAME', defaultValue: '');

  static String _pick(List<String> keys, String define) {
    final d = define.trim();
    if (d.isNotEmpty) return d;
    for (final k in keys) {
      final v = OxplayerDotenv.get(k).trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String? get apiBaseUrl {
    final t = _pick(['OXPLAYER_API_BASE_URL', 'OXPLAYER_API_BASE'], _cApiBaseUrl);
    if (t.isEmpty) return null;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  static String? get effectiveMediaServerUrl => apiBaseUrl;

  static String? get botUsername {
    final t = _pick(['OXPLAYER_BOT_USERNAME', 'BOT_USERNAME'], _cBotUsername)
        .replaceFirst(RegExp(r'^@'), '');
    return t.isEmpty ? null : t;
  }

  static String? get telegramBotOpenLink {
    final b = botUsername;
    return b == null ? null : 'https://t.me/$b';
  }

  static String? get telegramBotLoginLink {
    final b = botUsername;
    return b == null ? null : 'https://t.me/$b?start=login';
  }
}
