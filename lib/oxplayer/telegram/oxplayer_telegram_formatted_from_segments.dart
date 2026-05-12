import 'package:tdlib/td_api.dart' as td;

/// Builds TDLib [td.FormattedText] from API `telegramMessageSegments` (UTF-16 offsets match Dart [String.length] for BMP text).
///
/// Full share copy (expandable catalog blockquote + links) is in [telegramMessageHtml]; use TDLib
/// [td.ParseTextEntities] with [td.TextParseModeHTML] to build [td.FormattedText] for sending.
///
/// Newer TDLib returns entity types the `tdlib` Dart package does not model; those deserialize as
/// base [td.TextEntityType] with [td.TextEntityType.toJson] `{}` (no `@type`), which makes
/// [td.SendMessage] fail with "Can't find field \"@type\"". This helper drops only those entities.
td.FormattedText oxplayerSanitizeFormattedTextForTdSend(td.FormattedText input) {
  final safe = input.entities.where((e) {
    final m = e.type.toJson();
    final t = m['@type'];
    return t is String && t.isNotEmpty;
  }).toList();
  return td.FormattedText(text: input.text, entities: safe);
}

td.FormattedText oxplayerFormattedTextFromShareSegments(List<Map<String, dynamic>> segments) {
  final buf = StringBuffer();
  final entities = <td.TextEntity>[];
  var offset = 0;

  for (final m in segments) {
    final t = m['t']?.toString();
    if (t == 'text') {
      final v = m['v']?.toString() ?? '';
      buf.write(v);
      offset += v.length;
    } else if (t == 'link') {
      final label = m['label']?.toString() ?? '';
      final url = m['url']?.toString() ?? '';
      final start = offset;
      buf.write(label);
      entities.add(
        td.TextEntity(
          offset: start,
          length: label.length,
          type: td.TextEntityTypeTextUrl(url: url),
        ),
      );
      offset += label.length;
    }
  }

  return td.FormattedText(text: buf.toString(), entities: entities);
}
