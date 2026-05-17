import 'package:fvp/mdk.dart' show AudioStreamInfo;

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/util/muxed_audio_from_player.dart';

/// Maps MDK demuxer audio streams from [getMediaInfo] to [AudioStreamModel].
/// Kept separate from [muxed_audio_from_player] so web builds never pull `package:fvp`.
List<AudioStreamModel> audioStreamsFromMdkAudioInfos(List<AudioStreamInfo>? audios) {
  if (audios == null || audios.isEmpty) return [];
  var jellyIndex = 1;
  final out = audios.map((a) {
    final meta = a.metadata;
    String metaVal(String k) {
      final v = meta[k] ?? meta[k.toUpperCase()] ?? meta[k.toLowerCase()];
      return (v ?? '').trim();
    }

    final lang = muxedAudioLangForDemuxerRaw(metaVal('language'));
    final title = metaVal('title');
    final ch = a.codec.channels > 0 ? '${a.codec.channels}ch' : '';
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (lang.isNotEmpty) lang,
      if (a.codec.codec.isNotEmpty) a.codec.codec,
      if (ch.isNotEmpty) ch,
    ];
    final display = parts.isEmpty ? 'Audio' : parts.join(' — ');
    return AudioStreamModel(
      displayTitle: display,
      name: title,
      codec: a.codec.codec,
      isDefault: false,
      isExternal: false,
      index: jellyIndex++,
      language: lang,
      channelLayout: ch,
      demuxerTrackId: 'mdk-audio-${a.index}',
    );
  }).toList();
  if (out.isEmpty) return out;
  return [out.first.copyWith(isDefault: true), ...out.skip(1)];
}
