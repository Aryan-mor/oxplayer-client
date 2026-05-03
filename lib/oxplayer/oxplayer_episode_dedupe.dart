import 'package:collection/collection.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

UserData _mergeOxEpisodeGroupUserData(List<EpisodeModel> group, EpisodeModel canon) {
  if (group.length == 1) return canon.userData;
  DateTime? latestLp;
  for (final e in group) {
    final lp = e.userData.lastPlayed;
    if (lp != null && (latestLp == null || lp.isAfter(latestLp))) {
      latestLp = lp;
    }
  }
  return canon.userData.copyWith(
    played: group.any((e) => e.userData.played),
    progress: group.map((e) => e.userData.progress).max,
    playbackPositionTicks: group.map((e) => e.userData.playbackPositionTicks).max,
    isFavourite: group.any((e) => e.userData.isFavourite),
    playCount: group.map((e) => e.userData.playCount).max,
    lastPlayed: latestLp,
  );
}

/// One row per (season, episode) when the library has multiple items for the same slot.
/// Fills [EpisodeModel.oxLinkedEpisodeIds] with every duplicate Jellyfin id (including [id])
/// so play-state actions can sync all files.
List<EpisodeModel> mergeOxDuplicateEpisodes(
  List<EpisodeModel> episodes, {
  String? preferEpisodeId,
}) {
  if (!OxplayerConfig.isEnabled || episodes.isEmpty) return episodes;

  final groups = <String, List<EpisodeModel>>{};
  for (final ep in episodes) {
    final key = '${ep.season}_${ep.episode}';
    groups.putIfAbsent(key, () => []).add(ep);
  }

  EpisodeModel pickCanon(List<EpisodeModel> group) {
    final prefer = group.firstWhereOrNull((e) => e.id == preferEpisodeId);
    if (prefer != null) return prefer;
    return group.first;
  }

  final seen = <String>{};
  final out = <EpisodeModel>[];
  for (final ep in episodes) {
    final key = '${ep.season}_${ep.episode}';
    if (seen.contains(key)) continue;
    seen.add(key);
    final group = groups[key]!;
    final canon = pickCanon(group);
    if (group.length == 1) {
      out.add(canon);
    } else {
      final ids = group.map((e) => e.id).where((id) => id.isNotEmpty).toList()..sort();
      out.add(
        canon.copyWith(
          userData: _mergeOxEpisodeGroupUserData(group, canon),
          oxLinkedEpisodeIds: ids,
        ),
      );
    }
  }
  return out;
}

/// One card per (season, episode) when the library has multiple Jellyfin items for the same episode
/// (e.g. two uploads). Version choice stays on the detail header.
List<EpisodeModel> dedupeOxEpisodesForPosters(
  List<EpisodeModel> episodes, {
  String? preferEpisodeId,
}) =>
    mergeOxDuplicateEpisodes(episodes, preferEpisodeId: preferEpisodeId);
