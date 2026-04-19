/// Parses Telegram Mini App material for [POST /auth/telegram](https://core.telegram.org/bots/webapps#initializing-mini-apps).
///
/// Accepts either the raw `initData` string, or an `https://…` URL whose query or
/// URL fragment contains `tgWebAppData=` (same idea as extracting from a WebApp open link).
String oxplayerNormalizeTelegramInitDataInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return trimmed;
  }

  final fromQuery = uri.queryParameters['tgWebAppData'];
  if (fromQuery != null && fromQuery.isNotEmpty) {
    return fromQuery;
  }

  if (uri.hasFragment) {
    try {
      final fromFragment = Uri.splitQueryString(uri.fragment)['tgWebAppData'];
      if (fromFragment != null && fromFragment.isNotEmpty) {
        return fromFragment;
      }
    } catch (_) {
      // ignore malformed fragment
    }
  }

  return trimmed;
}
