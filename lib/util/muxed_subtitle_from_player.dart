import 'package:collection/collection.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/transcode_playback_model.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';
import 'package:media_kit/media_kit.dart' as mpv;

/// True when [muxed] differs from current non-external subtitle rows on the active media version.
bool muxedSubtitleListChanged(MediaStreamsModel? mediaStreams, List<SubStreamModel> muxed) {
  if (muxed.isEmpty) return false;
  final cur = mediaStreams?.currentVersionStream?.subStreams.where((s) => !s.isExternal).toList() ?? [];
  if (cur.length != muxed.length) return true;
  for (var i = 0; i < muxed.length; i++) {
    if (cur[i].id != muxed[i].id || cur[i].index != muxed[i].index) return true;
  }
  oxMuxedStreamsLog(
    'muxedSubtitleListChanged: skip (model already matches demuxer) cur=${cur.length}',
  );
  return false;
}

/// Maps muxed [mpv.SubtitleTrack]s (excluding auto/no and URI external loads) to [SubStreamModel].
/// Uses mpv track [SubtitleTrack.id] so [LibMPV.setSubtitleTrack] can select by id.
/// [firstJellyfinIndex] is the first global stream index for subtitles (after video + all muxed audios).
///
/// Note: do not filter on [SubtitleTrack.data]; demuxer-reported embedded subs often set it.
List<SubStreamModel> subStreamsFromMpvMuxedTracks(
  List<mpv.SubtitleTrack> all, {
  int firstJellyfinIndex = 1,
}) {
  final muxed = all
      .where(
        (s) => s.id != 'auto' && s.id != 'no' && !s.uri,
      )
      .toList();
  if (muxed.isEmpty) return [];
  var jellyIndex = firstJellyfinIndex;
  final out = muxed.map((t) {
    final lang = (t.language ?? '').trim();
    final parts = [t.title, t.language, t.codec].whereType<String>().where((x) => x.trim().isNotEmpty).toList();
    final display = parts.isEmpty ? 'Subtitle' : parts.join(' — ');
    return SubStreamModel(
      name: t.title ?? '',
      id: t.id,
      title: t.title ?? '',
      displayTitle: display,
      language: lang,
      codec: t.codec ?? '',
      isDefault: false,
      isExternal: false,
      index: jellyIndex++,
      supportsExternalStream: false,
      url: null,
    );
  }).toList();
  return [out.first.copyWith(isDefault: true), ...out.skip(1)];
}

extension MediaStreamsModelMuxedMerge on MediaStreamsModel {
  /// Replaces embedded subtitle rows with demuxer-reported muxed tracks; keeps server external rows.
  MediaStreamsModel mergeMuxedSubtitleStreamsFromContainer(List<SubStreamModel> muxedFromDemuxer) {
    if (muxedFromDemuxer.isEmpty) return this;
    final vidx = versionStreamIndex ?? 0;
    final cur = versionStreams.elementAtOrNull(vidx);
    if (cur == null) return this;

    final external = cur.subStreams.where((s) => s.isExternal).toList();
    final merged = [...muxedFromDemuxer, ...external].sortByExternal();

    final prevIdx = defaultSubStreamIndex;
    final prevStill = prevIdx != null && prevIdx != -1 && merged.any((s) => s.index == prevIdx);
    int? newDef;
    if (prevStill) {
      newDef = prevIdx;
    } else {
      // Jellyfin/Ox video-only stub often uses -1 / null = "no row"; demuxer still has muxed subs.
      final preferred = muxedFromDemuxer.firstWhereOrNull((s) => s.isDefault) ?? muxedFromDemuxer.firstOrNull;
      newDef = preferred?.index ?? -1;
    }
    oxMuxedStreamsLog(
      'mergeMuxedSubtitle: prevDef=$prevIdx prevStill=$prevStill '
      'muxed=${muxedFromDemuxer.length} merged=${merged.length} newDef=$newDef',
    );

    final newVersion = VersionStreamModel(
      name: cur.name,
      oxTelegramCaption: cur.oxTelegramCaption,
      oxLocatorPath: cur.oxLocatorPath,
      index: cur.index,
      id: cur.id,
      defaultAudioStreamIndex: cur.defaultAudioStreamIndex,
      defaultSubStreamIndex: newDef,
      videoStreams: cur.videoStreams,
      audioStreams: cur.audioStreams,
      subStreams: merged,
    );

    final vs = List<VersionStreamModel>.from(versionStreams);
    vs[vidx] = newVersion;
    return MediaStreamsModel(
      versionStreamIndex: versionStreamIndex,
      defaultAudioStreamIndex: defaultAudioStreamIndex,
      defaultSubStreamIndex: newDef,
      versionStreams: vs,
    );
  }
}

PlaybackModel? playbackWithMergedMediaStreams(PlaybackModel? playback, MediaStreamsModel merged) {
  if (playback == null) return null;
  return switch (playback) {
    DirectPlaybackModel d => d.copyWith(mediaStreams: () => merged),
    TranscodePlaybackModel t => t.copyWith(mediaStreams: () => merged),
    _ => playback,
  };
}
