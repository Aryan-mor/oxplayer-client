import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/src/video_player_helper.g.dart';

String _muxedLang(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  final lower = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (lower == 'und' || lower == 'mis' || lower == 'zxx' || lower == 'un') return '';
  if (RegExp(r'^unknown\d*$').hasMatch(lower)) return '';
  return s;
}

/// Maps Exo-reported muxed audio rows to [AudioStreamModel] (Jellyfin-style indices from 1).
List<AudioStreamModel> audioStreamsFromNativeExoRows(List<NativeMuxedAudioRow> rows) {
  if (rows.isEmpty) return [];
  var jellyIndex = 1;
  final out = rows.map((r) {
    final lang = _muxedLang(r.languageCode);
    final title = r.title.trim();
    final codec = r.codec.trim();
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (lang.isNotEmpty) lang,
      if (codec.isNotEmpty) codec,
    ];
    final display = parts.isEmpty ? 'Audio' : parts.join(' — ');
    return AudioStreamModel(
      displayTitle: display,
      name: title,
      codec: codec,
      isDefault: false,
      isExternal: false,
      index: jellyIndex++,
      language: lang.isEmpty ? 'Unknown' : lang,
      channelLayout: '',
      demuxerTrackId: 'exo-audio-${r.trackId}',
    );
  }).toList();
  return [out.first.copyWith(isDefault: true), ...out.skip(1)];
}

/// Maps Exo-reported muxed subtitle rows to [SubStreamModel] (indices from [firstJellyfinIndex]).
List<SubStreamModel> subStreamsFromNativeExoRows(
  List<NativeMuxedSubtitleRow> rows, {
  required int firstJellyfinIndex,
}) {
  if (rows.isEmpty) return [];
  var jellyIndex = firstJellyfinIndex;
  final out = rows.map((r) {
    final lang = _muxedLang(r.languageCode);
    final title = r.title.trim();
    final codec = r.codec.trim();
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (lang.isNotEmpty) lang,
      if (codec.isNotEmpty) codec,
    ];
    final display = parts.isEmpty ? 'Subtitle' : parts.join(' — ');
    return SubStreamModel(
      name: title,
      id: 'exo-sub-${r.trackId}',
      title: title,
      displayTitle: display,
      language: lang.isEmpty ? 'Unknown' : lang,
      codec: codec,
      isDefault: false,
      isExternal: false,
      index: jellyIndex++,
      supportsExternalStream: false,
      url: null,
    );
  }).toList();
  return [out.first.copyWith(isDefault: true), ...out.skip(1)];
}
