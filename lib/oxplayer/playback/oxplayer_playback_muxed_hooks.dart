// OXPLAYER — hooks Fladder playback → verified-stream manifest on oxplayer-be.
// Entry: [oxplayerPlaybackAttachMuxedDiscovery] from the single upstream hook in
// `media_control_wrapper.dart` (search `OXPLAYER_HOOK`).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/transcode_playback_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';
import 'package:fladder/oxplayer/playback/oxplayer_player_verified_streams_api.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/muxed_audio_from_player.dart';
import 'package:fladder/util/muxed_subtitle_from_player.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/lib_mpv.dart';
import 'package:fladder/wrappers/players/native_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

/// Attaches muxed-track listeners for the active [player]. Call from Fladder
/// [MediaControlsWrapper.loadVideo] only (see `OXPLAYER_HOOK` there).
void oxplayerPlaybackAttachMuxedDiscovery(Ref ref, BasePlayer? player) {
  if (!OxplayerConfig.isEnabled) return;
  _OxplayerPlaybackMuxedCoordinator.instance.attach(ref, player);
}

/// Cancels listeners when switching players or leaving playback.
void oxplayerPlaybackDetachMuxedDiscovery() {
  _OxplayerPlaybackMuxedCoordinator.instance.detach();
}

final class _OxplayerPlaybackMuxedCoordinator {
  _OxplayerPlaybackMuxedCoordinator._();
  static final _OxplayerPlaybackMuxedCoordinator instance = _OxplayerPlaybackMuxedCoordinator._();

  Ref? _ref;
  final Set<String> _postedVariantIds = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _debounce;
  List<AudioStreamModel> _pendingAudio = [];
  List<SubStreamModel> _pendingSubs = [];
  bool _mpvSampled = false;

  void attach(Ref ref, BasePlayer? player) {
    detach();
    _ref = ref;
    _mpvSampled = false;

    if (player is NativePlayer) {
      final audioSub = player.muxedAudioDiscoveryStream?.listen(_onAudioMuxed);
      final subSub = player.muxedSubtitleDiscoveryStream?.listen(_onSubtitleMuxed);
      if (audioSub != null) _subscriptions.add(audioSub);
      if (subSub != null) _subscriptions.add(subSub);
      oxMuxedStreamsLog('muxed hooks: attached NativePlayer discovery streams');
      return;
    }

    if (player is LibMPV) {
      final sub = player.stateStream.listen((state) => _onMpvState(state, player));
      _subscriptions.add(sub);
      oxMuxedStreamsLog('muxed hooks: attached LibMPV stateStream sampler');
    }
  }

  void detach() {
    _debounce?.cancel();
    _debounce = null;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _pendingAudio = [];
    _pendingSubs = [];
    _ref = null;
    _mpvSampled = false;
  }

  void _onAudioMuxed(List<AudioStreamModel> rows) {
    if (rows.isEmpty) return;
    _pendingAudio = rows;
    _scheduleFlush();
  }

  void _onSubtitleMuxed(List<SubStreamModel> rows) {
    if (rows.isEmpty) return;
    _pendingSubs = rows;
    _scheduleFlush();
  }

  void _onMpvState(PlayerState state, LibMPV player) {
    if (_mpvSampled) return;
    if (state.buffering) return;
    if (state.duration <= Duration.zero) return;
    _mpvSampled = true;

    final audio = audioStreamsFromMpvMuxedTracks(player.audioTracks);
  final subs = subStreamsFromMpvMuxedTracks(
      player.subTracks,
      firstJellyfinIndex: 1 + audio.length,
    );
    oxMuxedStreamsLog(
      'muxed hooks: LibMPV sample audio=${audio.length} sub=${subs.length}',
    );
    _pendingAudio = audio;
    _pendingSubs = subs;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _flush);
  }

  Future<void> _flush() async {
    final ref = _ref;
    if (ref == null) return;
    final audio = _pendingAudio;
    final subs = _pendingSubs;
    if (audio.isEmpty && subs.isEmpty) return;

    final model = ref.read(playBackModel);
    final variantId = oxplayerVariantIdFromMediaSourceId(
      model?.mediaStreams?.currentVersionStream?.id,
    );
    if (variantId == null) {
      oxMuxedStreamsLog('muxed hooks: skip POST (no ms_ mediaSourceId)');
      return;
    }

    _applyMergedStreamsToPlayback(ref, model, audio, subs);

    if (_postedVariantIds.contains(variantId)) {
      oxMuxedStreamsLog('muxed hooks: skip POST variant=$variantId (session cache)');
      return;
    }

    final already = await oxplayerFetchVariantStreamsAlreadyVerified(
      ref: ref,
      variantId: variantId,
    );
    if (already) {
      _postedVariantIds.add(variantId);
      oxMuxedStreamsLog('muxed hooks: skip POST variant=$variantId (server already verified)');
      return;
    }

    final result = await oxplayerPostPlayerVerifiedStreams(
      ref: ref,
      variantId: variantId,
      embeddedAudio: audio,
      embeddedSubtitles: subs,
    );
    if (result != null) {
      _postedVariantIds.add(variantId);
      oxMuxedStreamsLog(
        'muxed hooks: POST variant=$variantId stored=${result.stored} '
        'already=${result.alreadyVerified} audio=${audio.length} sub=${subs.length}',
      );
    }
  }

  void _applyMergedStreamsToPlayback(
    Ref ref,
    PlaybackModel? model,
    List<AudioStreamModel> audio,
    List<SubStreamModel> subs,
  ) {
    if (model == null) return;
    var ms = model.mediaStreams;
    if (ms == null) return;

    if (audio.isNotEmpty && muxedAudioListChanged(ms, audio)) {
      ms = ms.mergeMuxedAudioStreamsFromContainer(audio);
    }
    if (subs.isNotEmpty && muxedSubtitleListChanged(ms, subs)) {
      ms = ms.mergeMuxedSubtitleStreamsFromContainer(subs);
    }
  if (ms == model.mediaStreams) return;

    final updated = _playbackModelWithMediaStreams(model, ms);
    if (updated == null) return;
    ref.read(playBackModel.notifier).state = updated;
    oxMuxedStreamsLog('muxed hooks: merged streams into playBackModel');
  }
}

PlaybackModel? _playbackModelWithMediaStreams(PlaybackModel model, MediaStreamsModel ms) {
  return switch (model) {
    DirectPlaybackModel m => m.copyWith(mediaStreams: () => ms),
    TranscodePlaybackModel m => m.copyWith(mediaStreams: () => ms),
    _ => null,
  };
}

// Fix: I used PlayerState from wrong import - LibMPV uses wrappers/players/player_states.dart
// and I imported mpv by mistake in _onMpvState
