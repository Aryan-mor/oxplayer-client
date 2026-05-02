import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mpv;
import 'package:media_kit_video/media_kit_video.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/subtitle_settings_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/settings/subtitle_settings_provider.dart';
import 'package:fladder/screens/video_player/video_player.dart' as video_screen;
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';
import 'package:fladder/util/muxed_audio_from_player.dart';
import 'package:fladder/util/muxed_subtitle_from_player.dart';
import 'package:fladder/util/subtitle_position_calculator.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

class LibMPV extends BasePlayer {
  mpv.Player? _player;
  VideoController? _controller;
  String _currentSubtitleCodec = '';

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  StreamSubscription<bool>? _onCompleted;

  RestartableTimer? _retryTimer;
  DateTime _firstLoadAttempt = DateTime.now();
  final Duration _maxRetryDuration = const Duration(minutes: 1);
  final Duration _currentRetryDuration = const Duration(seconds: 5);
  Completer<void>? _loadCompleter;

  StreamController<List<SubStreamModel>>? _muxedSubtitleTracksController;
  StreamController<List<AudioStreamModel>>? _muxedAudioTracksController;
  StreamSubscription<mpv.Tracks>? _muxedTracksSubscription;

  @override
  Stream<List<SubStreamModel>>? get muxedSubtitleDiscoveryStream =>
      _muxedSubtitleTracksController?.stream;

  @override
  Stream<List<AudioStreamModel>>? get muxedAudioDiscoveryStream =>
      _muxedAudioTracksController?.stream;

  void _emitMuxedTracks(mpv.Tracks tracks) {
    final audioMuxed = audioStreamsFromMpvMuxedTracks(tracks.audio);
    // Align with Jellyfin indices: video=0, muxed audio starts at 1 (no fake server audio row).
    final firstSubIdx = 1 + audioMuxed.length;
    final subMuxed = subStreamsFromMpvMuxedTracks(tracks.subtitle, firstJellyfinIndex: firstSubIdx);

    oxMuxedStreamsLog(
      'MPV tracks: raw audio=${tracks.audio.length} sub=${tracks.subtitle.length} '
      '→ muxed audio=${audioMuxed.length} sub=${subMuxed.length} firstSubJellyIdx=$firstSubIdx',
    );
    if (tracks.subtitle.isNotEmpty && subMuxed.isEmpty) {
      for (var i = 0; i < tracks.subtitle.length && i < 6; i++) {
        final t = tracks.subtitle[i];
        oxMuxedStreamsLog(
          'MPV sub[$i] id=${t.id} uri=${t.uri} data=${t.data} codec=${t.codec} lang=${t.language}',
        );
      }
    }

    final ac = _muxedAudioTracksController;
    if (ac != null && !ac.isClosed && audioMuxed.isNotEmpty) {
      ac.add(audioMuxed);
    }

    final sc = _muxedSubtitleTracksController;
    if (sc != null && !sc.isClosed && subMuxed.isNotEmpty) {
      sc.add(subMuxed);
    }
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    await dispose();

    mpv.MediaKit.ensureInitialized();

    _player = mpv.Player(
      configuration: mpv.PlayerConfiguration(
        title: "de.aryanmo.oxplayer",
        libassAndroidFont: libassFallbackFont,
        libass: !kIsWeb && settings.useLibass,
        bufferSize: settings.bufferSize * 1024 * 1024, // MPV uses buffer size in bytes
      ),
    );

    if (_player != null) {
      _controller = VideoController(
        _player!,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: settings.hardwareAccel,
        ),
      );

      _player!.stream.playing.listen((value) => setState(lastState.update(playing: value)));
      _player!.stream.buffering.listen((value) => setState(lastState.update(buffering: value)));
      _player!.stream.position.listen((value) => setState(lastState.update(position: value)));
      _player!.stream.duration.listen((value) => setState(lastState.update(duration: value)));
      _player!.stream.volume.listen((value) => setState(lastState.update(volume: value)));
      _player!.stream.rate.listen((value) => setState(lastState.update(rate: value)));
      _player!.stream.buffer.listen((value) => setState(lastState.update(buffer: value)));

      _muxedSubtitleTracksController = StreamController<List<SubStreamModel>>.broadcast();
      _muxedAudioTracksController = StreamController<List<AudioStreamModel>>.broadcast();
      _muxedTracksSubscription = _player!.stream.tracks.listen(_emitMuxedTracks);
      _emitMuxedTracks(_player!.state.tracks);
    }

    if (_player?.platform is mpv.NativePlayer) {
      final nativePlayer = _player!.platform as dynamic;
      await nativePlayer.setProperty('force-seekable', 'yes');

      if (defaultTargetPlatform == TargetPlatform.android) {
        await nativePlayer.setProperty('ao', 'audiotrack');
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _muxedTracksSubscription?.cancel();
    _muxedTracksSubscription = null;
    await _muxedSubtitleTracksController?.close();
    _muxedSubtitleTracksController = null;
    await _muxedAudioTracksController?.close();
    _muxedAudioTracksController = null;
    _onCompleted?.cancel();
    _onCompleted = null;
    _player?.stop();
    _player?.dispose();
    _player = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void setState(PlayerState state) {
    lastState = state;
    _stateController.add(state);
  }

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    _loadCompleter = Completer<void>();
    _firstLoadAttempt = DateTime.now();

    await setStartPosition(startPosition);

    await _player?.open(mpv.Media(url), play: play);

    _retryTimer?.cancel();
    _retryTimer = null;

    _retryTimer = RestartableTimer(
      _currentRetryDuration,
      () async {
        await Future.delayed(const Duration(milliseconds: 150));
        if (DateTime.now().isAfter(_firstLoadAttempt.add(_maxRetryDuration))) {
          log("Max retry duration reached, stopping retries.");
          _retryTimer?.cancel();
          _retryTimer = null;
        } else {
          log("Retrying to load video $url");
          await setStartPosition(startPosition);
          await _player?.open(mpv.Media(url), play: play);
          _retryTimer?.reset();
        }
      },
    );

    // Wait for the player to be ready
    if (_loadCompleter?.isCompleted == false) {
      StreamSubscription? subBuffering;
      StreamSubscription? subDuration;

      void onReady() {
        if (_loadCompleter?.isCompleted == true) return;
        _finishedLoading();
        subBuffering?.cancel();
        subDuration?.cancel();
      }

      // Do not require duration>0: loopback/HTTP (e.g. Ox Telegram range server) can report
      // buffering==false before MPV has probed duration, which left load stuck and retried
      // [open] every 5s.
      subBuffering = _player?.stream.buffering.listen((event) {
        if (event == false) {
          onReady();
        }
      });
      subDuration = _player?.stream.duration.listen((event) {
        if (event > Duration.zero) onReady();
      });
    }

    _loadCompleter?.future.then(
      (value) async {
        // Backup seek in case property didn't work
        if (startPosition != Duration.zero && (_player?.state.position.inSeconds ?? 0) < startPosition.inSeconds - 5) {
          await _player?.seek(startPosition);
        }
      },
    );
    return setState(lastState.update(buffering: true));
  }

  Future<void> setStartPosition(Duration position) async {
    if (_player?.platform is mpv.NativePlayer) {
      await (_player?.platform as dynamic).setProperty(
        'start',
        '${position.inMilliseconds / 1000}',
      );
    }
  }

  void _finishedLoading() {
    _loadCompleter?.complete();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  Future<void> open(BuildContext context) async => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (context) => const video_screen.VideoPlayer(),
        ),
      );

  List<mpv.SubtitleTrack> get subTracks => _player?.state.tracks.subtitle ?? [];
  mpv.SubtitleTrack get subtitleTrack => _player?.state.track.subtitle ?? mpv.SubtitleTrack.no();

  List<mpv.AudioTrack> get audioTracks => _player?.state.tracks.audio ?? [];
  mpv.AudioTrack get audioTrack => _player?.state.track.audio ?? mpv.AudioTrack.no();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> playOrPause() async => _player?.playOrPause();

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    final embedded =
        (playbackModel.audioStreams ?? []).where((s) => !s.isExternal && s.index >= 0).toList();
    var wantedAudioStream = model ?? effectiveDefaultAudioStreamForPlayback(playbackModel);
    if (wantedAudioStream.index == AudioStreamModel.no().index && embedded.isNotEmpty) {
      wantedAudioStream = embedded.first;
    }
    final hasAdvertisedAudio = (playbackModel.mediaStreams?.audioStreams ?? []).isNotEmpty;
    if (wantedAudioStream.index == AudioStreamModel.no().index) {
      if (!hasAdvertisedAudio) {
        return -1;
      }
      await _player?.setAudioTrack(mpv.AudioTrack.no());
    } else {
      final id = wantedAudioStream.demuxerTrackId;
      if (id != null && id.isNotEmpty) {
        final match = audioTracks.firstWhereOrNull((t) => t.id == id && !t.uri);
        if (match != null) {
          await _player?.setAudioTrack(match);
          return wantedAudioStream.index;
        }
      }
      final internalTracks = audioTracks.getRange(2, audioTracks.length).toList();
      final audioTrack =
          internalTracks.elementAtOrNull((playbackModel.audioStreams?.indexOf(wantedAudioStream) ?? -1) - 1);
      if (audioTrack != null) {
        await _player?.setAudioTrack(audioTrack);
      }
    }
    return wantedAudioStream.index;
  }

  @override
  Future<void> setSpeed(double speed) async => _player?.setRate(speed);

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    if (_player == null) return -1;
    final wantedSubtitle = model ?? playbackModel.defaultSubStream;
    if (wantedSubtitle == null || wantedSubtitle.index == SubStreamModel.no().index) {
      final hasAdvertisedSubs = (playbackModel.mediaStreams?.subStreams ?? []).isNotEmpty;
      if (!hasAdvertisedSubs) {
        return -1;
      }
      await _player?.setSubtitleTrack(mpv.SubtitleTrack.no());
      return -1;
    }
    _currentSubtitleCodec = wantedSubtitle.codec;
    if (wantedSubtitle.isExternal && wantedSubtitle.url != null) {
      await _player?.setSubtitleTrack(mpv.SubtitleTrack.uri(wantedSubtitle.url!));
      return wantedSubtitle.index;
    }
    final match = subTracks.firstWhereOrNull(
      (t) => t.id == wantedSubtitle.id && !t.uri,
    );
    if (match != null) {
      await _player?.setSubtitleTrack(match);
      return wantedSubtitle.index;
    }
    final internalTrack = subTracks.getRange(2, subTracks.length).toList();
    final index = playbackModel.subStreams?.sublist(1).indexWhere((element) => element.id == wantedSubtitle.id);
    final subTrack = internalTrack.elementAtOrNull(index ?? -1);
    if (subTrack != null) {
      await _player?.setSubtitleTrack(subTrack);
    }
    return wantedSubtitle.index;
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<Uint8List?> takeScreenshot() async {
    return _player?.screenshot(format: "image/png", includeLibassSubtitles: true);
  }

  @override
  Widget? videoWidget(
    Key key,
    BoxFit fit,
  ) =>
      _controller == null
          ? null
          : Video(
              key: key,
              controller: _controller!,
              wakelock: false,
              fill: Colors.transparent,
              fit: fit,
              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
              controls: NoVideoControls,
            );

  @override
  Widget? subtitles(
    bool showOverlay, {
    GlobalKey? controlsKey,
  }) =>
      _controller != null
          ? _VideoSubtitles(
              controller: _controller!,
              showOverlay: showOverlay,
              controlsKey: controlsKey,
              currentSubtitleCodec: _currentSubtitleCodec,
            )
          : null;

  @override
  Future<void> setVolume(double volume) async => _player?.setVolume(volume);

  @override
  Future<void> loop(bool loop) async {
    if (loop && _onCompleted == null) {
      _onCompleted = _player?.stream.completed.listen((completed) {
        if (completed) {
          _player?.play();
        }
      });
    } else {
      _onCompleted?.cancel();
    }
  }
}

class _VideoSubtitles extends ConsumerStatefulWidget {
  final VideoController controller;
  final bool showOverlay;
  final GlobalKey? controlsKey;
  final String currentSubtitleCodec;

  const _VideoSubtitles({
    required this.controller,
    this.showOverlay = false,
    this.controlsKey,
    this.currentSubtitleCodec = '',
  });

  @override
  _VideoSubtitlesState createState() => _VideoSubtitlesState();
}

class _VideoSubtitlesState extends ConsumerState<_VideoSubtitles> {
  late List<String> subtitle;
  String _cachedSubtitleText = '';
  List<String>? _lastSubtitleList;
  StreamSubscription<List<String>>? subscription;

  double? _cachedMenuHeight;

  @override
  void initState() {
    super.initState();
    subtitle = widget.controller.player.state.subtitle;
    subscription = widget.controller.player.stream.subtitle.listen((value) {
      if (mounted) {
        setState(() {
          subtitle = value;
          _lastSubtitleList = null;
        });
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measureMenuHeight();

    final settings = ref.watch(subtitleSettingsProvider);
    final padding = MediaQuery.paddingOf(context);

    if (!const ListEquality().equals(subtitle, _lastSubtitleList)) {
      _lastSubtitleList = List<String>.from(subtitle);
      _cachedSubtitleText = subtitle.where((line) => line.trim().isNotEmpty).map((line) => line.trim()).join('\n');
    }

    final text = _cachedSubtitleText;

    final bool isLibassEnabled = widget.controller.player.platform?.configuration.libass ?? false;

    if (isLibassEnabled) {
      // On desktop (Linux/Windows/macOS), mpv burns ALL subtitle formats into the video when libass is enabled.
      // On mobile (Android/iOS), only ASS/SSA subs are burned in by libass; other formats need the Flutter overlay.
      final bool isDesktop = defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS;
      if (isDesktop) {
        return const SizedBox.shrink();
      }
      final currentSubCodec = widget.currentSubtitleCodec.toLowerCase();
      final bool isAssSubtitle = currentSubCodec.contains('ass') || currentSubCodec.contains('ssa');
      if (isAssSubtitle || text.isEmpty) {
        return const SizedBox.shrink();
      }
    } else if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final offset = SubtitlePositionCalculator.calculateOffset(
      settings: settings,
      showOverlay: widget.showOverlay,
      screenHeight: MediaQuery.sizeOf(context).height,
      menuHeight: _cachedMenuHeight,
    );

    return SubtitleText(
      subModel: settings,
      padding: padding,
      offset: offset,
      text: text,
    );
  }

  void _measureMenuHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controlsKey == null) return;

      final RenderBox? renderBox = widget.controlsKey?.currentContext?.findRenderObject() as RenderBox?;
      final newHeight = renderBox?.size.height;

      if (newHeight != _cachedMenuHeight && newHeight != null) {
        setState(() {
          _cachedMenuHeight = newHeight;
        });
      }
    });
  }
}
