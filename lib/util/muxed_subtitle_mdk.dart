import 'package:fvp/mdk.dart' show SubtitleStreamInfo;

import 'package:fladder/models/items/media_streams_model.dart';

/// Maps MDK demuxer subtitle streams from [getMediaInfo] to [SubStreamModel] (ids stable for UI).
/// Kept separate from [muxed_subtitle_from_player] so web builds never pull `package:fvp`.
List<SubStreamModel> subStreamsFromMdkSubtitleInfos(
  List<SubtitleStreamInfo>? subs, {
  int firstJellyfinIndex = 1,
}) {
  if (subs == null || subs.isEmpty) return [];
  var jellyIndex = firstJellyfinIndex;
  final out = subs.map((s) {
    final meta = s.metadata;
    String metaVal(String k) {
      final v = meta[k] ?? meta[k.toUpperCase()] ?? meta[k.toLowerCase()];
      return (v ?? '').trim();
    }

    final lang = metaVal('language');
    final title = metaVal('title');
    final parts = [title, lang, s.codec.codec].where((x) => x.isNotEmpty).toList();
    final display = parts.isEmpty ? 'Subtitle' : parts.join(' — ');
    return SubStreamModel(
      name: title,
      id: 'mdk-mux-${s.index}',
      title: title,
      displayTitle: display,
      language: lang,
      codec: s.codec.codec,
      isDefault: false,
      isExternal: false,
      index: jellyIndex++,
      supportsExternalStream: false,
      url: null,
    );
  }).toList();
  if (out.isEmpty) return out;
  return [out.first.copyWith(isDefault: true), ...out.skip(1)];
}
