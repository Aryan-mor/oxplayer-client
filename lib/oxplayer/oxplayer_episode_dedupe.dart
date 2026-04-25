import 'package:collection/collection.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// One card per (season, episode) when the library has multiple Jellyfin items for the same episode
/// (e.g. two uploads). Version choice stays on the detail header.
List<EpisodeModel> dedupeOxEpisodesForPosters(
  List<EpisodeModel> episodes, {
  String? preferEpisodeId,
}) {
  if (!OxplayerConfig.isEnabled || episodes.length < 2) return episodes;

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
    final g = groups[key];
    if (g == null) continue;
    out.add(pickCanon(g));
  }
  return out;
}
