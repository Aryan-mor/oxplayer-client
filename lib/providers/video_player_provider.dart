import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';
import 'package:fladder/oxplayer/oxplayer_verified_streams_client.dart';
import 'package:fladder/util/muxed_audio_from_player.dart';
import 'package:fladder/util/muxed_subtitle_from_player.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

final mediaPlaybackProvider = StateProvider<MediaPlaybackModel>((ref) => MediaPlaybackModel());

final playBackModel = StateProvider<PlaybackModel?>((ref) => null);

final videoPlayerProvider = StateNotifierProvider<VideoPlayerNotifier, MediaControlsWrapper>((ref) {
  final videoPlayer = VideoPlayerNotifier(ref);
  videoPlayer.init();
  return videoPlayer;
});

class VideoPlayerNotifier extends StateNotifier<MediaControlsWrapper> {
  VideoPlayerNotifier(this.ref) : super(MediaControlsWrapper(ref: ref));

  final Ref ref;

  List<StreamSubscription> subscriptions = [];
  StreamSubscription<List<SubStreamModel>>? _muxedSubtitleDiscoverySubscription;
  StreamSubscription<List<AudioStreamModel>>? _muxedAudioDiscoverySubscription;
  int _muxedDiscoveryGeneration = 0;
  String? _muxedDiscoveryMediaUrl;
  Timer? _verifiedStreamsUploadTimer;
  bool _sawMuxedAudioDiscovery = false;
  bool _sawMuxedSubtitleDiscovery = false;

  late final mediaState = ref.read(mediaPlaybackProvider.notifier);

  MediaPlaybackModel get playbackState => ref.read(mediaPlaybackProvider);

  Future<void> init() async {
    await state.dispose();
    await state.init();

    for (final s in subscriptions) {
      s.cancel();
    }

    final subscription = state.stateStream?.listen((value) {
      updateBuffering(value.buffering);
      updateBuffer(value.buffer);
      updatePlaying(value.playing);
      updatePosition(value.position);
      updateDuration(value.duration);
    });

    if (subscription != null) {
      subscriptions.add(subscription);
    }

    _wireMuxedSubtitleDiscovery();
    oxMuxedStreamsLog('VideoPlayerNotifier.init done (mux wiring)');
  }

  void _scheduleVerifiedStreamsUpload() {
    if (!OxplayerConfig.isEnabled) return;
    _verifiedStreamsUploadTimer?.cancel();
    _verifiedStreamsUploadTimer = Timer(const Duration(milliseconds: 700), () {
      _verifiedStreamsUploadTimer = null;
      _tryPostVerifiedStreamsManifest();
    });
  }

  Future<void> _tryPostVerifiedStreamsManifest() async {
    if (!OxplayerConfig.isEnabled) {
      oxMuxedStreamsLog('verified POST: skip OxplayerConfig.isEnabled=false');
      return;
    }
    final expectUrl = _muxedDiscoveryMediaUrl;
    if (expectUrl == null) {
      oxMuxedStreamsLog('verified POST: skip _muxedDiscoveryMediaUrl=null');
      return;
    }
    if (!_sawMuxedAudioDiscovery && !_sawMuxedSubtitleDiscovery) {
      oxMuxedStreamsLog('verified POST: skip no mux discovery flags yet');
      return;
    }

    final playback = ref.read(playBackModel);
    if (playback == null || playback.media?.url != expectUrl) {
      oxMuxedStreamsLog(
        'verified POST: skip playback=${playback == null} or url no longer matches session',
      );
      return;
    }

    final mediaId =
        playback.media?.libraryMediaFileId ?? parseOxplayerTelegramMediaId(expectUrl);
    if (mediaId == null) {
      oxMuxedStreamsLog(
        'verified POST: skip no libraryMediaFileId (set when Path is oxplayer://telegram/…) '
        'and URL is not oxplayer scheme=${Uri.tryParse(expectUrl)?.scheme} len=${expectUrl.length}',
      );
      return;
    }

    final vs = playback.mediaStreams?.currentVersionStream;
    if (vs == null) {
      oxMuxedStreamsLog('verified POST: skip no currentVersionStream');
      return;
    }

    final audio =
        vs.audioStreams.where((a) => !a.isExternal && a.demuxerTrackId != null).toList();
    final subtitles = _sawMuxedSubtitleDiscovery
        ? vs.subStreams.where((s) => !s.isExternal && s.index >= 0).toList()
        : <SubStreamModel>[];

    if (audio.isEmpty && subtitles.isEmpty) {
      oxMuxedStreamsLog(
        'verified POST: skip empty payload audio=${audio.length} subs=${subtitles.length} '
        'sawSub=$_sawMuxedSubtitleDiscovery sawAud=$_sawMuxedAudioDiscovery',
      );
      return;
    }

    oxMuxedStreamsLog(
      'verified POST: calling API mediaId=$mediaId audio=${audio.length} subs=${subtitles.length}',
    );
    await postVerifiedStreamsManifestIfNeeded(
      ref,
      mediaId: mediaId,
      audio: audio,
      subtitles: subtitles,
    );
  }

  void _wireMuxedSubtitleDiscovery() {
    _muxedAudioDiscoverySubscription?.cancel();
    _muxedAudioDiscoverySubscription = null;
    final audioStream = state.muxedAudioDiscoveryStream;
    if (audioStream != null) {
      _muxedAudioDiscoverySubscription = audioStream.listen(
        _onMuxedAudioTracksDiscovered,
        onError: (Object e, _) => oxMuxedStreamsLog('muxedAudio stream error: $e'),
      );
    }
    _muxedSubtitleDiscoverySubscription?.cancel();
    _muxedSubtitleDiscoverySubscription = null;
    final stream = state.muxedSubtitleDiscoveryStream;
    final backend = state.backend;
    if (stream == null) {
      oxMuxedStreamsLog(
        'wire mux discovery: subtitle stream is null (backend=$backend; e.g. NativePlayer, or player disposed between dispose/init)',
      );
      return;
    }
    oxMuxedStreamsLog('wire mux discovery: backend=$backend sub+audio listeners attached');
    _muxedSubtitleDiscoverySubscription = stream.listen(
      _onMuxedSubtitleTracksDiscovered,
      onError: (Object e, _) => oxMuxedStreamsLog('muxedSubtitle stream error: $e'),
    );
  }

  Future<void> _onMuxedAudioTracksDiscovered(List<AudioStreamModel> muxed) async {
    if (muxed.isEmpty) {
      oxMuxedStreamsLog('muxedAudio event: empty list (ignored)');
      return;
    }
    oxMuxedStreamsLog('muxedAudio event: count=${muxed.length} gen=$_muxedDiscoveryGeneration');
    final token = _muxedDiscoveryGeneration;
    final expectedUrl = _muxedDiscoveryMediaUrl;
    final playback = ref.read(playBackModel);
    if (playback == null) {
      oxMuxedStreamsLog('muxedAudio: abort playback=null');
      return;
    }
    if (expectedUrl != null && playback.media?.url != expectedUrl) {
      oxMuxedStreamsLog(
        'muxedAudio: abort url mismatch expect=${expectedUrl.length} actual=${(playback.media?.url ?? '').length}',
      );
      return;
    }
    final ms = playback.mediaStreams;
    if (!muxedAudioListChanged(ms, muxed)) return;
    final merged = ms?.mergeMuxedAudioStreamsFromContainer(muxed);
    if (merged == null) {
      oxMuxedStreamsLog('muxedAudio: abort merge returned null');
      return;
    }
    final updated = playbackWithMergedMediaStreams(playback, merged);
    if (updated == null) return;
    oxMuxedStreamsLog(
      'muxedAudio applied defaultAudio=${merged.defaultAudioStreamIndex} '
      'audioRows=${merged.audioStreams.length}',
    );
    ref.read(playBackModel.notifier).update((_) => updated);
    if (token != _muxedDiscoveryGeneration) return;
    if (expectedUrl != null && updated.media?.url != expectedUrl) return;
    await state.setAudioTrack(null, updated);
    _sawMuxedAudioDiscovery = true;
    _scheduleVerifiedStreamsUpload();
    await state.syncNativePlaybackAfterMuxMerge(updated);
  }

  Future<void> _onMuxedSubtitleTracksDiscovered(List<SubStreamModel> muxed) async {
    if (muxed.isEmpty) {
      oxMuxedStreamsLog('muxedSubtitle event: empty list (ignored)');
      return;
    }
    oxMuxedStreamsLog('muxedSubtitle event: count=${muxed.length} gen=$_muxedDiscoveryGeneration');
    final token = _muxedDiscoveryGeneration;
    final expectedUrl = _muxedDiscoveryMediaUrl;
    final playback = ref.read(playBackModel);
    if (playback == null) {
      oxMuxedStreamsLog('muxedSubtitle: abort playback=null');
      return;
    }
    if (expectedUrl != null && playback.media?.url != expectedUrl) {
      oxMuxedStreamsLog(
        'muxedSubtitle: abort url mismatch expect=${expectedUrl.length} actual=${(playback.media?.url ?? '').length}',
      );
      return;
    }
    final ms = playback.mediaStreams;
    if (!muxedSubtitleListChanged(ms, muxed)) return;
    final merged = ms?.mergeMuxedSubtitleStreamsFromContainer(muxed);
    if (merged == null) {
      oxMuxedStreamsLog('muxedSubtitle: abort merge returned null');
      return;
    }
    final updated = playbackWithMergedMediaStreams(playback, merged);
    if (updated == null) return;
    oxMuxedStreamsLog(
      'muxedSubtitle applied defaultSub=${merged.defaultSubStreamIndex} '
      'subRows=${merged.subStreams.length}',
    );
    ref.read(playBackModel.notifier).update((_) => updated);
    if (token != _muxedDiscoveryGeneration) return;
    if (expectedUrl != null && updated.media?.url != expectedUrl) return;
    await state.setSubtitleTrack(null, updated);
    _sawMuxedSubtitleDiscovery = true;
    _scheduleVerifiedStreamsUpload();
    await state.syncNativePlaybackAfterMuxMerge(updated);
  }

  Future<void> updateBuffering(bool event) async =>
      mediaState.update((state) => state.buffering == event ? state : state.copyWith(buffering: event));

  Future<void> updateBuffer(Duration buffer) async {
    mediaState.update(
      (state) => (state.buffer - buffer).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              buffer: buffer,
            ),
    );
  }

  Future<void> updateDuration(Duration duration) async {
    mediaState.update((state) {
      // libmpv can emit 0 briefly over loopback/HTTP while demuxing; do not clobber a
      // duration we already have (e.g. seeded from Telegram or a prior probe).
      if (duration <= Duration.zero && state.duration > const Duration(seconds: 5)) {
        return state;
      }
      return (state.duration - duration).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              duration: duration,
            );
    });
  }

  Future<void> updatePlaying(bool event) async {
    final currentState = playbackState;
    if (!state.hasPlayer || currentState.playing == event) return;
    if (currentState.state == VideoPlayerState.disposed) return;
    mediaState.update(
      (state) => state.copyWith(playing: event),
    );
    ref.read(playBackModel)?.updatePlaybackPosition(currentState.position, currentState.playing, ref);
  }

  Future<void> updatePosition(Duration event) async {
    if (!state.hasPlayer) return;
    if (playbackState.playing == false) return;
    final currentState = playbackState;
    if (currentState.state == VideoPlayerState.disposed) return;
    final currentPosition = currentState.position;

    if ((currentPosition - event).inSeconds.abs() < 1) return;

    final position = event;

    final lastPosition = currentState.lastPosition;
    final diff = (position.inMilliseconds - lastPosition.inMilliseconds).abs();

    if (diff > const Duration(seconds: 10).inMilliseconds) {
      mediaState.update((value) => value.copyWith(
            position: event,
            lastPosition: position,
          ));
      ref.read(playBackModel)?.updatePlaybackPosition(position, playbackState.playing, ref);
    } else {
      mediaState.update((value) => value.copyWith(
            position: event,
          ));
    }
  }

  Future<bool> loadPlaybackItem(PlaybackModel model, Duration startPosition) async {
    _muxedDiscoveryGeneration++;
    _muxedDiscoveryMediaUrl = model.media?.url;
    _sawMuxedAudioDiscovery = false;
    _sawMuxedSubtitleDiscovery = false;
    _verifiedStreamsUploadTimer?.cancel();
    _verifiedStreamsUploadTimer = null;
    final u = model.media?.url ?? '';
    oxMuxedStreamsLog(
      'loadPlaybackItem gen=$_muxedDiscoveryGeneration ox=${OxplayerConfig.isEnabled} '
      'backend=${state.backend} urlScheme=${Uri.tryParse(u)?.scheme ?? "?"} '
      'libraryMediaFileId=${model.media?.libraryMediaFileId ?? "null"} '
      'subRows=${model.mediaStreams?.subStreams.length ?? 0}',
    );
    ref.read(playBackModel)?.dispose();
    final nextUrl = model.media?.url ?? '';
    final nextUsesOxLoopback = nextUrl.contains('127.0.0.1');
    await state.stopWithPlaybackOptions(releaseOxTelegramCache: !nextUsesOxLoopback);
    ref.read(playbackRateProvider.notifier).state = 1.0;
    mediaState.update((state) => state.copyWith(
          state: VideoPlayerState.fullScreen,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
        ));

    final media = model.media;
    PlaybackModel? newPlaybackModel = model;

    if (media != null) {
      ref.read(playBackModel.notifier).update((_) => newPlaybackModel);
      await state.loadVideo(model, startPosition, true);
      await state.setVolume(ref.read(videoPlayerSettingsProvider).volume);

      await state.setAudioTrack(null, model);
      await state.setSubtitleTrack(null, model);

      await state.play();
      _wireMuxedSubtitleDiscovery();
      oxMuxedStreamsLog('loadPlaybackItem finished play(); mux discovery re-wired');
      return true;
    }

    mediaState.update((state) => state.copyWith(errorPlaying: true));
    return false;
  }

  Future<void> openPlayer(BuildContext context) async => state.openPlayer(context);

  Future<bool> takeScreenshot() async {
    final syncPath = ref.read(clientSettingsProvider).syncPath;
    // Early return here if we don't have a set/valid path. Skips actually taking the screenshot
    // which would be discarded.
    if (syncPath == null) {
      return false;
    }

    final screenshotsPath = p.join(syncPath, "Screenshots");
    final screenshotBuf = await state.takeScreenshot();

    if (screenshotBuf != null) {
      final savePathDirectory = Directory(screenshotsPath);

      // Should we try to create the directory instead?
      if (!await savePathDirectory.exists()) {
        return false;
      }

      final fileExtension = "png";
      final paddingAmount = 3;

      int maxNumber = 0;

      await for (var file in savePathDirectory.list()) {
        final finalSegment = file.uri.pathSegments.last;

        if (file is File && p.extension(finalSegment) == ".$fileExtension") {
          final match = RegExp(r'(\d+)').firstMatch(finalSegment);

          if (match != null) {
            final fileNumber = int.parse(match.group(0)!);

            if (fileNumber > maxNumber) {
              maxNumber = fileNumber;
            }
          }
        }
      }

      maxNumber += 1;

      final maxNumberStr = maxNumber.toString().padLeft(paddingAmount, '0');
      final screenshotName = '$maxNumberStr.$fileExtension';
      final screenshotPath = p.join(screenshotsPath, screenshotName);

      final screenshotFile = File(screenshotPath);
      await screenshotFile.writeAsBytes(screenshotBuf);

      return true;
    }

    return false;
  }
}
