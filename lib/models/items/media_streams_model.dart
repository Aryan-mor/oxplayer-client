import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/oxplayer/oxplayer_media_source_caption.dart';
import 'package:fladder/oxplayer/oxplayer_media_versions_log.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/video_properties.dart';

/// Hides `unknown` / `und` / `unknown2`-style tokens from audio track labels.
String _audioLangForJoinedTitle(String language) {
  final s = language.trim();
  if (s.isEmpty) return '';
  final compact = s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (compact == 'und' || compact == 'mis' || compact == 'zxx' || compact == 'un') return '';
  if (RegExp(r'^unknown\d*$').hasMatch(compact)) return '';
  return s;
}

String _audioChannelLayoutForUi(String channelLayout) {
  final s = channelLayout.trim();
  if (s.isEmpty) return '';
  final compact = s.replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^unknown\d*$', caseSensitive: false).hasMatch(compact)) return '';
  return s;
}

class MediaStreamsModel {
  final int? versionStreamIndex;
  final int? defaultAudioStreamIndex;
  final int? defaultSubStreamIndex;
  final List<VersionStreamModel> versionStreams;
  MediaStreamsModel({
    this.versionStreamIndex,
    this.defaultAudioStreamIndex,
    this.defaultSubStreamIndex,
    required this.versionStreams,
  });

  VersionStreamModel? get currentVersionStream => versionStreams.elementAtOrNull(versionStreamIndex ?? 0);

  List<VideoStreamModel> get videoStreams => currentVersionStream?.videoStreams ?? [];
  List<AudioStreamModel> get audioStreams => currentVersionStream?.audioStreams ?? [];
  List<SubStreamModel> get subStreams => currentVersionStream?.subStreams ?? [];

  bool get isNull {
    return defaultAudioStreamIndex == null ||
        defaultSubStreamIndex == null ||
        audioStreams.isEmpty ||
        subStreams.isEmpty;
  }

  bool get isNotEmpty {
    return audioStreams.isNotEmpty && subStreams.isNotEmpty;
  }

  /// Detail header stream/version row: show when there are multiple Jellyfin media sources
  /// (e.g. several Ox uploads) or classic Jellyfin audio+subtitle rows.
  /// [isNotEmpty] alone hides multi-version Ox stubs that have no subtitle streams.
  bool get shouldShowDetailStreamSelectors =>
      versionStreams.length > 1 || (audioStreams.isNotEmpty && subStreams.isNotEmpty);

  AudioStreamModel? get currentAudioStream {
    if (defaultAudioStreamIndex == -1 || defaultAudioStreamIndex == null) {
      return AudioStreamModel.no();
    }
    return audioStreams.firstWhereOrNull((element) => element.index == defaultAudioStreamIndex) ??
        audioStreams.firstOrNull;
  }

  SubStreamModel? get currentSubStream {
    if (defaultSubStreamIndex == -1 || defaultSubStreamIndex == null) {
      return SubStreamModel.no();
    }
    return subStreams.firstWhereOrNull((element) => element.index == defaultSubStreamIndex) ?? subStreams.firstOrNull;
  }

  DisplayProfile? get displayProfile {
    return DisplayProfile.fromVideoStreams(videoStreams);
  }

  Resolution? get resolution {
    return Resolution.fromVideoStream(videoStreams.firstOrNull);
  }

  String? get resolutionText {
    final stream = videoStreams.firstOrNull;
    if (stream == null) return null;
    return "${stream.width}x${stream.height}";
  }

  String? get mediaInfoTag => '${displayProfile?.value} ${resolution?.value}';

  Widget? audioIcon(
    BuildContext context,
    Function()? onTap,
  ) {
    final audioStream = audioStreams.firstWhereOrNull((element) => element.isDefault) ?? audioStreams.firstOrNull;
    if (audioStream == null) return null;
    return DefaultVideoInformationBox(
      onTap: onTap,
      child: Text(
        audioStream.title,
      ),
    );
  }

  Widget subtitleIcon(
    BuildContext context,
    Function()? onTap,
  ) {
    return DefaultVideoInformationBox(
      onTap: onTap,
      child: Icon(
        subStreams.isNotEmpty ? Icons.subtitles_rounded : Icons.subtitles_off_outlined,
      ),
    );
  }

  static MediaStreamsModel fromMediaStreamsList(
    List<dto.MediaSourceInfo>? mediaSource,
    Ref ref,
  ) {
    final versionStreams = mediaSource
            ?.mapIndexed(
              (index, element) {
                final streams = element.mediaStreams ?? [];
                final nameParts = parseOxMediaSourceNameParts(element.name);
                final qualityLabel =
                    nameParts.qualityLabel.isNotEmpty ? nameParts.qualityLabel : (element.name ?? "");
                return VersionStreamModel(
                    name: qualityLabel,
                    oxTelegramCaption: nameParts.telegramCaption,
                    oxLocatorPath: element.path,
                    index: index,
                    id: element.id,
                    defaultAudioStreamIndex: element.defaultAudioStreamIndex,
                    defaultSubStreamIndex: element.defaultSubtitleStreamIndex,
                    videoStreams: streams
                        .where((element) => element.type == dto.MediaStreamType.video)
                        .map(
                          (e) => VideoStreamModel.fromMediaStream(e),
                        )
                        .sortByExternal(),
                    audioStreams: streams
                        .where((element) => element.type == dto.MediaStreamType.audio)
                        .map(
                          (e) => AudioStreamModel.fromMediaStream(e),
                        )
                        .sortByExternal(),
                    subStreams: streams
                        .where((element) => element.type == dto.MediaStreamType.subtitle)
                        .map(
                          (sub) => SubStreamModel.fromMediaStream(sub, ref),
                        )
                        .sortByExternal());
              },
            )
            .toList() ??
        [];
    final summary = versionStreams
        .map((v) => '${v.id ?? "?"}:${(v.name).isEmpty ? "(no name)" : v.name}')
        .join(' | ');
    final paths = mediaSource?.map((e) => e.path ?? "").join(' | ') ?? '';
    oxMediaVersionsLog(
      'fromMediaStreamsList count=${versionStreams.length} paths=[$paths] streams=[$summary]',
    );
    return MediaStreamsModel(
      defaultAudioStreamIndex: mediaSource?.firstOrNull?.defaultAudioStreamIndex,
      defaultSubStreamIndex: mediaSource?.firstOrNull?.defaultSubtitleStreamIndex,
      versionStreams: versionStreams,
    );
  }

  MediaStreamsModel copyWith({
    int? versionStreamIndex,
    int? defaultAudioStreamIndex,
    int? defaultSubStreamIndex,
    List<VersionStreamModel>? versionStreams,
  }) {
    final streamIndexChanged = versionStreamIndex != this.versionStreamIndex && versionStreamIndex != null;
    final currentVersionStreams = versionStreams ?? this.versionStreams;
    return MediaStreamsModel(
      versionStreamIndex: versionStreamIndex ?? this.versionStreamIndex,
      defaultAudioStreamIndex: streamIndexChanged
          ? currentVersionStreams.elementAtOrNull(versionStreamIndex)?.defaultAudioStreamIndex
          : defaultAudioStreamIndex ?? this.defaultAudioStreamIndex,
      defaultSubStreamIndex: streamIndexChanged
          ? currentVersionStreams.elementAtOrNull(versionStreamIndex)?.defaultSubStreamIndex
          : defaultSubStreamIndex ?? this.defaultSubStreamIndex,
      versionStreams: versionStreams ?? this.versionStreams,
    );
  }

  @override
  String toString() {
    return 'MediaStreamsModel(defaultAudioStreamIndex: $defaultAudioStreamIndex, defaultSubStreamIndex: $defaultSubStreamIndex, videoStreams: $videoStreams, audioStreams: $audioStreams, subStreams: $subStreams)';
  }
}

/// Re-applies version / audio / subtitle choices from a previous detail state onto a
/// freshly fetched [incoming] model (e.g. after playback when [fetchDetails] runs).
MediaStreamsModel mergePreservedMediaStreamSelection(
  MediaStreamsModel? previous,
  MediaStreamsModel incoming,
) {
  if (previous == null) return incoming;

  var merged = incoming;

  if (incoming.versionStreams.length > 1) {
    final prevIdx = previous.versionStreamIndex ?? 0;
    final prevPick = previous.versionStreams.elementAtOrNull(prevIdx);
    final prevId = prevPick?.id;

    int? targetIdx;
    if (prevId != null && prevId.isNotEmpty) {
      final byId = incoming.versionStreams.indexWhere((v) => v.id == prevId);
      if (byId >= 0) targetIdx = byId;
    }
    targetIdx ??= (prevIdx < incoming.versionStreams.length) ? prevIdx : null;
    if (targetIdx != null) {
      merged = merged.copyWith(versionStreamIndex: targetIdx);
    }
  }

  final current = merged.versionStreams.elementAtOrNull(merged.versionStreamIndex ?? 0);
  if (current == null) return merged;

  int? audio = previous.defaultAudioStreamIndex;
  if (audio != null && audio != -1 && !current.audioStreams.any((a) => a.index == audio)) {
    audio = null;
  }

  int? sub = previous.defaultSubStreamIndex;
  if (sub != null && sub != -1 && !current.subStreams.any((s) => s.index == sub)) {
    sub = null;
  }

  return merged.copyWith(
    defaultAudioStreamIndex: audio ?? merged.defaultAudioStreamIndex,
    defaultSubStreamIndex: sub ?? merged.defaultSubStreamIndex,
  );
}

/// Indices saved per library item so stream/version picks survive leaving the detail screen.
class PersistedStreamIndexes {
  final int? versionStreamIndex;
  final int? defaultAudioStreamIndex;
  final int? defaultSubStreamIndex;

  const PersistedStreamIndexes({
    this.versionStreamIndex,
    this.defaultAudioStreamIndex,
    this.defaultSubStreamIndex,
  });
}

/// Applies in-memory detail state first, then persisted disk prefs (for returning from Home, etc.).
MediaStreamsModel mergeMediaStreamsFromSources(
  MediaStreamsModel incoming, {
  MediaStreamsModel? memoryPrev,
  PersistedStreamIndexes? persisted,
}) {
  var merged = mergePreservedMediaStreamSelection(memoryPrev, incoming);
  if (persisted != null) {
    final synthetic = MediaStreamsModel(
      versionStreams: incoming.versionStreams,
      versionStreamIndex: persisted.versionStreamIndex,
      defaultAudioStreamIndex: persisted.defaultAudioStreamIndex,
      defaultSubStreamIndex: persisted.defaultSubStreamIndex,
    );
    merged = mergePreservedMediaStreamSelection(synthetic, merged);
  }
  return merged;
}

class StreamModel {
  final String name;
  final String codec;
  final bool isDefault;
  final bool isExternal;
  final int index;
  StreamModel({
    required this.name,
    required this.codec,
    required this.isDefault,
    required this.isExternal,
    required this.index,
  });
}

class AudioAndSubStreamModel extends StreamModel {
  final String language;
  final String displayTitle;
  AudioAndSubStreamModel({
    required this.displayTitle,
    required super.name,
    required super.codec,
    required super.isDefault,
    required super.isExternal,
    required super.index,
    required this.language,
  });
}

class VersionStreamModel {
  final String name;
  /// Telegram message caption for this upload (from API `MediaSourceInfo.Name` suffix).
  final String? oxTelegramCaption;
  /// Jellyfin `MediaSourceInfo.path` when present (e.g. `oxplayer://telegram/<mediaId>`).
  final String? oxLocatorPath;
  final int index;
  final String? id;
  final int? defaultAudioStreamIndex;
  final int? defaultSubStreamIndex;
  final List<VideoStreamModel> videoStreams;
  final List<AudioStreamModel> audioStreams;
  final List<SubStreamModel> subStreams;

  String get detailedResolutionLabel {
    final stream = videoStreams.firstOrNull;
    if (stream == null) return "Unknown";
    final resolution = Resolution.fromVideoStream(stream)?.value ?? "Unknown";
    final displayProfile = DisplayProfile.fromVideoStream(stream).value;
    return "$resolution $displayProfile";
  }

  VersionStreamModel({
    required this.name,
    this.oxTelegramCaption,
    this.oxLocatorPath,
    required this.index,
    this.id,
    required this.defaultAudioStreamIndex,
    required this.defaultSubStreamIndex,
    required this.videoStreams,
    required this.audioStreams,
    required this.subStreams,
  });
}

class VideoStreamModel extends StreamModel {
  final int width;
  final int height;
  final int? bitRate;
  final double frameRate;
  final String? videoDoViTitle;
  final VideoRangeType? videoRangeType;
  VideoStreamModel({
    required super.name,
    required super.codec,
    required super.isDefault,
    required super.isExternal,
    required super.index,
    required this.videoDoViTitle,
    required this.videoRangeType,
    required this.bitRate,
    required this.width,
    required this.height,
    required this.frameRate,
  });

  factory VideoStreamModel.fromMediaStream(dto.MediaStream stream) {
    return VideoStreamModel(
      name: stream.title ?? "",
      isDefault: stream.isDefault ?? false,
      codec: stream.codec ?? "",
      videoDoViTitle: stream.videoDoViTitle,
      bitRate: stream.bitRate,
      videoRangeType: stream.videoRangeType,
      width: stream.width ?? 0,
      height: stream.height ?? 0,
      frameRate: stream.realFrameRate ?? 24,
      isExternal: stream.isExternal ?? false,
      index: stream.index ?? -1,
    );
  }
  String get prettyName {
    return "${Resolution.fromVideoStream(this)?.value} - ${DisplayProfile.fromVideoStream(this).value} - (${codec.toUpperCase()})";
  }

  @override
  String toString() {
    return 'VideoStreamModel(width: $width, height: $height, frameRate: $frameRate, videoDoViTitle: $videoDoViTitle, videoRangeType: $videoRangeType)';
  }
}

//Instead of using sortBy(a.isExternal etc..) this one seems to be more consistent for some reason
extension SortByExternalExtension<T extends StreamModel> on Iterable<T> {
  List<T> sortByExternal() {
    return [...where((element) => !element.isExternal), ...where((element) => element.isExternal)];
  }
}

class AudioStreamModel extends AudioAndSubStreamModel {
  final String channelLayout;

  /// When set, matches the demuxer/player track id (e.g. libmpv [AudioTrack.id]) for selection.
  final String? demuxerTrackId;

  AudioStreamModel({
    required super.displayTitle,
    required super.name,
    required super.codec,
    required super.isDefault,
    required super.isExternal,
    required super.index,
    required super.language,
    required this.channelLayout,
    this.demuxerTrackId,
  });

  factory AudioStreamModel.fromMediaStream(dto.MediaStream stream) {
    return AudioStreamModel(
      displayTitle: stream.displayTitle ?? "",
      name: stream.title ?? "",
      isDefault: stream.isDefault ?? false,
      codec: stream.codec ?? "",
      language: stream.language ?? "Unknown",
      channelLayout: stream.channelLayout ?? "",
      isExternal: stream.isExternal ?? false,
      index: stream.index ?? -1,
      demuxerTrackId: null,
    );
  }

  String label(BuildContext context) {
    if (index == -1) {
      return context.localized.off;
    } else {
      return displayTitle;
    }
  }

  String get title {
    final lang = _audioLangForJoinedTitle(language);
    final ch = _audioChannelLayoutForUi(channelLayout);
    return [name, lang, codec, ch].nonNulls.where((element) => element.isNotEmpty).join(' - ');
  }

  String get shortTitle {
    final lang = _audioLangForJoinedTitle(language);
    final ch = _audioChannelLayoutForUi(channelLayout);
    final parts = [lang, ch].nonNulls.where((element) => element.isNotEmpty).toList();
    if (parts.isEmpty) {
      return displayTitle;
    } else {
      return parts.nonNulls.where((element) => element.isNotEmpty).join(' - ').toUpperCase();
    }
  }

  AudioStreamModel.no({
    super.name = 'Off',
    super.displayTitle = 'Off',
    super.language = '',
    super.codec = '',
    this.channelLayout = '',
    super.isDefault = false,
    super.isExternal = false,
    super.index = -1,
    this.demuxerTrackId,
  });

  AudioStreamModel copyWith({
    String? name,
    String? displayTitle,
    String? language,
    String? codec,
    bool? isDefault,
    bool? isExternal,
    int? index,
    String? channelLayout,
    String? demuxerTrackId,
  }) {
    return AudioStreamModel(
      name: name ?? this.name,
      displayTitle: displayTitle ?? this.displayTitle,
      language: language ?? this.language,
      codec: codec ?? this.codec,
      isDefault: isDefault ?? this.isDefault,
      isExternal: isExternal ?? this.isExternal,
      index: index ?? this.index,
      channelLayout: channelLayout ?? this.channelLayout,
      demuxerTrackId: demuxerTrackId ?? this.demuxerTrackId,
    );
  }
}

class SubStreamModel extends AudioAndSubStreamModel {
  String id;
  String title;
  String? url;
  bool supportsExternalStream;
  SubStreamModel({
    required super.name,
    required this.id,
    required this.title,
    required super.displayTitle,
    required super.language,
    this.url,
    required super.codec,
    required super.isDefault,
    required super.isExternal,
    required super.index,
    this.supportsExternalStream = false,
  });

  SubStreamModel.no({
    super.name = 'Off',
    this.id = 'Off',
    this.title = 'Off',
    super.displayTitle = 'Off',
    super.language = '',
    this.url = '',
    super.codec = '',
    super.isDefault = false,
    super.isExternal = false,
    super.index = -1,
    this.supportsExternalStream = false,
  });

  String label(BuildContext context) {
    if (index == -1) {
      return context.localized.off;
    } else {
      return displayTitle;
    }
  }

  String get shortTitle {
    final parts = [language].nonNulls.where((element) => element.isNotEmpty).toList();
    if (parts.isEmpty) {
      return displayTitle;
    } else {
      return parts.nonNulls.where((element) => element.isNotEmpty).join(' - ').toUpperCase();
    }
  }

  factory SubStreamModel.fromMediaStream(dto.MediaStream stream, Ref ref) {
    final deliveryUrl = stream.deliveryUrl;
    final deliveryUri = Uri.tryParse(deliveryUrl ?? '');
    final relativeSrtUrl = deliveryUri?.replace(path: deliveryUri.path.replaceAll('.vtt', '.srt')).toString();

    final subStreamUrl = relativeSrtUrl == null ? null : buildServerUrl(ref, relativeUrl: relativeSrtUrl);

    return SubStreamModel(
      name: stream.title ?? "",
      title: stream.title ?? "",
      displayTitle: stream.displayTitle ?? "",
      language: stream.language ?? "Unknown",
      isDefault: stream.isDefault ?? false,
      codec: stream.codec ?? "",
      id: stream.hashCode.toString(),
      supportsExternalStream: stream.supportsExternalStream ?? false,
      url: subStreamUrl,
      isExternal: stream.isExternal ?? false,
      index: stream.index ?? -1,
    );
  }

  SubStreamModel copyWith({
    String? name,
    String? id,
    String? title,
    String? displayTitle,
    String? language,
    ValueGetter<String?>? url,
    String? codec,
    bool? isDefault,
    bool? isExternal,
    int? index,
    bool? supportsExternalStream,
  }) {
    return SubStreamModel(
      name: name ?? this.name,
      id: id ?? this.id,
      title: title ?? this.title,
      displayTitle: displayTitle ?? this.displayTitle,
      language: language ?? this.language,
      url: url != null ? url() : this.url,
      supportsExternalStream: supportsExternalStream ?? this.supportsExternalStream,
      codec: codec ?? this.codec,
      isDefault: isDefault ?? this.isDefault,
      isExternal: isExternal ?? this.isExternal,
      index: index ?? this.index,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'id': id,
      'title': title,
      'displayTitle': displayTitle,
      'language': language,
      'url': url,
      'supportsExternalStream': supportsExternalStream,
      'codec': codec,
      'isExternal': isExternal,
      'isDefault': isDefault,
      'index': index,
    };
  }

  factory SubStreamModel.fromMap(Map<String, dynamic> map) {
    return SubStreamModel(
      name: map['name'] ?? '',
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      displayTitle: map['displayTitle'] ?? '',
      language: map['language'] ?? '',
      url: map['url'],
      supportsExternalStream: map['supportsExternalStream'] ?? false,
      codec: map['codec'] ?? '',
      isDefault: map['isDefault'] ?? false,
      isExternal: map['isExternal'] ?? false,
      index: map['index'] ?? -1,
    );
  }

  String toJson() => json.encode(toMap());

  factory SubStreamModel.fromJson(String source) => SubStreamModel.fromMap(json.decode(source));

  @override
  String toString() {
    return 'SubFile(title: $title, displayTitle: $displayTitle, language: $language, url: $url, isExternal: $isExternal)';
  }
}
