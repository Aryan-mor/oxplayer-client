import 'package:collection/collection.dart';
import 'package:fvp/mdk.dart' show AudioStreamInfo;
import 'package:media_kit/media_kit.dart' as mpv;

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';

/// Demuxers often report `unknown`, `und`, or `unknown2` (language+channels junk) — omit from UI.
String _muxedAudioLangForModel(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  final lower = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (lower == 'und' || lower == 'mis' || lower == 'zxx' || lower == 'un') return '';
  if (RegExp(r'^unknown\d*$').hasMatch(lower)) return '';
  return s;
}

String _muxedAudioChannelLayoutFromMpv(mpv.AudioTrack t) {
  final ch = (t.channels ?? '').trim();
  final compact = ch.replaceAll(RegExp(r'\s+'), '');
  final looksLikeUnknownNoise =
      ch.isEmpty || RegExp(r'^unknown\d*$', caseSensitive: false).hasMatch(compact);
  if (!looksLikeUnknownNoise) return ch;
  if (t.channelscount != null && t.channelscount! > 0) {
    return '${t.channelscount}ch';
  }
  return '';
}

/// mpv sometimes appends ` - unknown2` or similar to the track title string.
String _stripTrailingUnknownNoiseFromTitle(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  final compact = s.replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^unknown\d*$', caseSensitive: false).hasMatch(compact)) return '';
  s = s.replaceAll(RegExp(r'\s*[\-–—]\s*(und|unknown)\d*\s*$', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'\s+(und|unknown)\d*$', caseSensitive: false), '');
  return s.trim();
}

bool _audioRowsEqualByDemuxer(AudioStreamModel a, AudioStreamModel b) {
  if (a.demuxerTrackId != null && b.demuxerTrackId != null) {
    return a.demuxerTrackId == b.demuxerTrackId;
  }
  return a.index == b.index && a.codec == b.codec && a.language == b.language;
}

/// True when [muxed] differs from current non-external audio rows on the active media version.
bool muxedAudioListChanged(MediaStreamsModel? mediaStreams, List<AudioStreamModel> muxed) {
  if (muxed.isEmpty) return false;
  final cur = mediaStreams?.currentVersionStream?.audioStreams.where((s) => !s.isExternal).toList() ?? [];
  if (cur.length != muxed.length) return true;
  for (var i = 0; i < muxed.length; i++) {
    if (!_audioRowsEqualByDemuxer(cur[i], muxed[i]) || cur[i].index != muxed[i].index) return true;
  }
  oxMuxedStreamsLog(
    'muxedAudioListChanged: skip (model already matches demuxer) cur=${cur.length}',
  );
  return false;
}

/// Maps muxed [mpv.AudioTrack]s (excluding auto/no and URI loads) to [AudioStreamModel].
List<AudioStreamModel> audioStreamsFromMpvMuxedTracks(List<mpv.AudioTrack> all) {
  final muxed = all.where((s) => s.id != 'auto' && s.id != 'no' && !s.uri).toList();
  if (muxed.isEmpty) return [];
  var jellyIndex = 1;
  final out = muxed.map((t) {
    final lang = _muxedAudioLangForModel(t.language);
    final chLayout = _muxedAudioChannelLayoutFromMpv(t);
    final title = _stripTrailingUnknownNoiseFromTitle(t.title ?? '');
    final codec = (t.codec ?? '').trim();
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (lang.isNotEmpty) lang,
      if (codec.isNotEmpty) codec,
      if (chLayout.isNotEmpty) chLayout,
    ];
    final display = parts.isEmpty ? 'Audio' : parts.join(' — ');
    return AudioStreamModel(
      displayTitle: display,
      name: title,
      codec: t.codec ?? '',
      isDefault: false,
      isExternal: false,
      index: jellyIndex++,
      language: lang,
      channelLayout: chLayout,
      demuxerTrackId: t.id,
    );
  }).toList();
  return [out.first.copyWith(isDefault: true), ...out.skip(1)];
}

/// Maps MDK demuxer audio streams from [getMediaInfo] to [AudioStreamModel].
List<AudioStreamModel> audioStreamsFromMdkAudioInfos(List<AudioStreamInfo>? audios) {
  if (audios == null || audios.isEmpty) return [];
  var jellyIndex = 1;
  final out = audios.map((a) {
    final meta = a.metadata;
    String metaVal(String k) {
      final v = meta[k] ?? meta[k.toUpperCase()] ?? meta[k.toLowerCase()];
      return (v ?? '').trim();
    }

    final lang = _muxedAudioLangForModel(metaVal('language'));
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

extension MediaStreamsModelMuxedAudioMerge on MediaStreamsModel {
  /// Replaces embedded audio rows with demuxer-reported muxed tracks; keeps server external rows.
  MediaStreamsModel mergeMuxedAudioStreamsFromContainer(List<AudioStreamModel> muxedFromDemuxer) {
    if (muxedFromDemuxer.isEmpty) return this;
    final vidx = versionStreamIndex ?? 0;
    final cur = versionStreams.elementAtOrNull(vidx);
    if (cur == null) return this;

    final external = cur.audioStreams.where((s) => s.isExternal).toList();
    final merged = [...muxedFromDemuxer, ...external].sortByExternal();

    final prevIdx = defaultAudioStreamIndex;
    final prevStill =
        prevIdx != null && prevIdx != -1 && merged.any((s) => s.index == prevIdx);
    int? newDef;
    if (prevStill) {
      newDef = prevIdx;
    } else {
      final preferred =
          muxedFromDemuxer.firstWhereOrNull((s) => s.isDefault) ?? muxedFromDemuxer.firstOrNull;
      final firstEmbedded = merged.firstWhereOrNull((s) => !s.isExternal);
      newDef = preferred?.index ?? firstEmbedded?.index ?? -1;
    }
    oxMuxedStreamsLog(
      'mergeMuxedAudio: prevDef=$prevIdx prevStill=$prevStill '
      'muxed=${muxedFromDemuxer.length} merged=${merged.length} newDef=$newDef',
    );

    final newVersion = VersionStreamModel(
      name: cur.name,
      oxTelegramCaption: cur.oxTelegramCaption,
      index: cur.index,
      id: cur.id,
      defaultAudioStreamIndex: newDef,
      defaultSubStreamIndex: cur.defaultSubStreamIndex,
      videoStreams: cur.videoStreams,
      audioStreams: merged,
      subStreams: cur.subStreams,
    );

    final vs = List<VersionStreamModel>.from(versionStreams);
    vs[vidx] = newVersion;
    return MediaStreamsModel(
      versionStreamIndex: versionStreamIndex,
      defaultAudioStreamIndex: newDef,
      defaultSubStreamIndex: defaultSubStreamIndex,
      versionStreams: vs,
    );
  }
}
