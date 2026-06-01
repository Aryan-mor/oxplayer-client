import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/offline_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/transcode_playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/oxplayer/native_exo_muxed_discovery.dart';
import 'package:fladder/oxplayer/native_playback_trace_log.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';
import 'package:fladder/src/video_player_helper.g.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

bool nativeActivityStarted = false;

class NativePlayer extends BasePlayer implements VideoPlayerListenerCallback {
  final player = VideoPlayerApi();
  final activity = NativeVideoActivity();

  StreamController<List<AudioStreamModel>>? _muxedAudioTracksController;
  StreamController<List<SubStreamModel>>? _muxedSubtitleTracksController;

  @override
  Stream<List<AudioStreamModel>>? get muxedAudioDiscoveryStream => _muxedAudioTracksController?.stream;

  @override
  Stream<List<SubStreamModel>>? get muxedSubtitleDiscoveryStream => _muxedSubtitleTracksController?.stream;

  @override
  Future<void> dispose() async {
    nativeActivityStarted = false;
    await _muxedSubtitleTracksController?.close();
    _muxedSubtitleTracksController = null;
    await _muxedAudioTracksController?.close();
    _muxedAudioTracksController = null;
    return activity.disposeActivity();
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    await _muxedSubtitleTracksController?.close();
    await _muxedAudioTracksController?.close();
    _muxedSubtitleTracksController = StreamController<List<SubStreamModel>>.broadcast();
    _muxedAudioTracksController = StreamController<List<AudioStreamModel>>.broadcast();
    VideoPlayerListenerCallback.setUp(this);
  }

  @override
  Future<void> loop(bool loop) {
    return player.setLooping(loop);
  }

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    oxNativePlaybackTrace(
      'NativePlayer.loadVideo enter play=$play startMs=${startPosition.inMilliseconds} '
      '${oxNativePlaybackUrlHint(url)}',
    );
    try {
      final ok = await player.open(url, play);
      oxNativePlaybackTrace('NativePlayer.loadVideo pigeon open returned ok=$ok');
      if (!ok) {
        oxNativePlaybackTrace(
          'NativePlayer.loadVideo WARNING: native open returned false '
          '(Exo prepare may still be running; check Android OX_NATIVE_PLY / onPlayerError)',
        );
      }
    } catch (e, st) {
      oxNativePlaybackTrace('NativePlayer.loadVideo ERROR: $e');
      oxNativePlaybackTrace('NativePlayer.loadVideo stack: $st');
      rethrow;
    }
  }

  @override
  Future<StartResult> open(BuildContext newContext) async {
    oxNativePlaybackTrace('NativePlayer.open launchActivity');
    nativeActivityStarted = true;
    final result = await activity.launchActivity();
    oxNativePlaybackTrace('NativePlayer.open launchActivity result=$result');
    return result;
  }

  @override
  Future<void> pause() {
    return player.pause();
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> playOrPause() async {
    if (lastState.playing) {
      return player.pause();
    } else {
      return player.play();
    }
  }

  @override
  Future<void> seek(Duration position) {
    return player.seekTo(position.inMilliseconds);
  }

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    return model?.index ?? 0;
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    return model?.index ?? 0;
  }

  @override
  Future<void> setVolume(double volume) async {
    return player.setVolume(volume);
  }

  @override
  Future<void> stop() async {
    nativeActivityStarted = false;
    return player.stop();
  }

  @override
  Future<Uint8List?> takeScreenshot() async {
    return null;
  }

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey<State<StatefulWidget>>? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => null;

  @override
  void onPlaybackStateChanged(PlaybackState state) {
    lastState = lastState.update(
      playing: state.playing,
      position: Duration(milliseconds: state.position),
      buffer: Duration(milliseconds: state.buffered),
      buffering: state.buffering,
      completed: state.completed,
      duration: Duration(milliseconds: state.duration),
    );
    _stateController.add(lastState);
  }

  @override
  void onMuxedTracksDiscovered(List<NativeMuxedAudioRow> audio, List<NativeMuxedSubtitleRow> subtitles) {
    final audioModels = audioStreamsFromNativeExoRows(audio);
    final subModels = subStreamsFromNativeExoRows(
      subtitles,
      firstJellyfinIndex: 1 + audioModels.length,
    );
    oxMuxedStreamsLog(
      'Native Exo muxed: raw audio=${audio.length} sub=${subtitles.length} '
      '→ models audio=${audioModels.length} sub=${subModels.length}',
    );
    final ac = _muxedAudioTracksController;
    if (ac != null && !ac.isClosed && audioModels.isNotEmpty) {
      ac.add(audioModels);
    }
    final sc = _muxedSubtitleTracksController;
    if (sc != null && !sc.isClosed && subModels.isNotEmpty) {
      sc.add(subModels);
    }
  }

  final StreamController<PlayerState> _stateController = StreamController.broadcast();

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  Future<void> sendTVGuideModel(TVGuideModel guide) async {
    await player.sendTVGuideModel(guide);
  }

  Future<void> sendPlaybackDataToNative(
    BuildContext? context,
    PlaybackModel model,
    Duration startPosition,
  ) async {
    oxNativePlaybackTrace(
      'NativePlayer.sendPlaybackDataToNative start itemId=${model.item.id} name=${model.item.name} '
      'startMs=${startPosition.inMilliseconds} ${oxNativePlaybackUrlHint(model.media?.url)}',
    );
    final playableData = PlayableData(
      currentItem: model.item.toSimpleItem(context),
      startPosition: startPosition.inMilliseconds,
      description: model.item.overview.summary,
      defaultAudioTrack: model.mediaStreams?.defaultAudioStreamIndex ?? 1,
      nextVideo: model.nextVideo?.toSimpleItem(context),
      previousVideo: model.previousVideo?.toSimpleItem(context),
      audioTracks: model.audioStreams
              ?.map(
                (audio) => AudioTrack(
                  name: audio.displayTitle,
                  languageCode: audio.language,
                  codec: audio.codec,
                  index: audio.index,
                  external: false,
                ),
              )
              .toList() ??
          [],
      defaultSubtrack: model.mediaStreams?.defaultSubStreamIndex ?? 1,
      subtitleTracks: model.subStreams
              ?.map(
                (sub) => SubtitleTrack(
                  name: sub.displayTitle,
                  languageCode: sub.language,
                  codec: sub.codec,
                  index: sub.index,
                  external: sub.isExternal,
                  url: sub.url,
                ),
              )
              .toList() ??
          [],
      segments: model.mediaSegments?.segments
              .map(
                (e) => MediaSegment(
                  type: MediaSegmentType.values.firstWhere((element) => element.name == e.type.name),
                  name: context != null ? e.type.label(context) : e.type.name,
                  start: e.start.inMilliseconds,
                  end: e.end.inMilliseconds,
                ),
              )
              .toList() ??
          [],
      trickPlayModel: model.trickPlay != null
          ? TrickPlayModel(
              width: model.trickPlay!.width,
              height: model.trickPlay!.height,
              tileWidth: model.trickPlay!.tileWidth,
              tileHeight: model.trickPlay!.tileHeight,
              thumbnailCount: model.trickPlay!.thumbnailCount,
              interval: model.trickPlay!.interval.inMilliseconds,
              images: model.trickPlay?.images ?? [])
          : null,
      chapters: model.chapters
              ?.map((e) => Chapter(name: e.name, url: e.imageUrl, time: e.startPosition.inMilliseconds))
              .toList() ??
          [],
      mediaInfo: MediaInfo(
        playbackType: switch (model) {
          DirectPlaybackModel() => PlaybackType.direct,
          OfflinePlaybackModel() => PlaybackType.offline,
          TranscodePlaybackModel() => PlaybackType.transcoded,
          TvPlaybackModel() => PlaybackType.tv,
          _ => PlaybackType.direct,
        },
        videoInformation: model.item.streamModel?.mediaInfoTag ?? " ",
      ),
      url: model.media?.url ?? "",
    );
    final sentOk = await player.sendPlayableModel(playableData);
    oxNativePlaybackTrace(
      'NativePlayer.sendPlaybackDataToNative sendPlayableModel ok=$sentOk '
      'audioRows=${playableData.audioTracks.length} subRows=${playableData.subtitleTracks.length} '
      'playbackType=${playableData.mediaInfo.playbackType}',
    );
  }

  /// After Flutter merges muxed streams into [model], push updated `PlayableData` and re-apply Exo track selection.
  Future<void> applyMergedPlaybackModelToHost(
    BuildContext? context,
    PlaybackModel model,
    Duration currentPosition,
  ) async {
    await sendPlaybackDataToNative(context, model, currentPosition);
    await player.refreshDefaultTrackSelection();
  }
}
