import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';

/// Jellyfin can surface multiple library items with resume progress for the same
/// episode or movie (e.g. alternate uploads). Keep a single Continue Watching row.
String resumeWatchingDedupeKey(ItemBaseModel item) {
  switch (item) {
    case EpisodeModel e:
      final endPart = e.episodeEnd != null && e.episodeEnd! > e.episode ? '_${e.episodeEnd}' : '';
      return 'ep|${e.parentId}|s${e.season}|e${e.episode}$endPart';
    case MovieModel m:
      final pid = _providerDedupeKey(m.providerIds);
      if (pid != null) return 'mv|$pid';
      final y = m.overview.productionYear?.toString() ?? '';
      return 'mv|${m.name}|$y';
    default:
      return 'id|${item.id}';
  }
}

String? _providerDedupeKey(Map<String, dynamic>? ids) {
  if (ids == null || ids.isEmpty) return null;
  for (final e in ids.entries) {
    final v = e.value?.toString().trim();
    if (v == null || v.isEmpty) continue;
    final k = e.key.toLowerCase();
    if (k.contains('tmdb') || k.contains('imdb') || k.contains('tvdb')) {
      return '${e.key}:$v';
    }
  }
  return null;
}

ItemBaseModel _pickPreferredResume(ItemBaseModel a, ItemBaseModel b) {
  final la = a.userData.lastPlayed;
  final lb = b.userData.lastPlayed;
  if (la != null && lb != null) {
    final c = la.compareTo(lb);
    if (c != 0) return c > 0 ? a : b;
  } else if (la != null) {
    return a;
  } else if (lb != null) {
    return b;
  }
  final ta = a.userData.playbackPositionTicks;
  final tb = b.userData.playbackPositionTicks;
  if (ta != tb) return ta > tb ? a : b;
  final pa = a.userData.progress;
  final pb = b.userData.progress;
  return pa >= pb ? a : b;
}

/// Deduplicates by logical title (episode slot or movie identity), preserving API order
/// of first-seen keys and preferring the most recently played / furthest progress.
List<ItemBaseModel> dedupeResumeWatchingVideos(List<ItemBaseModel> items) {
  if (items.length < 2) return items;

  final keys = items.map(resumeWatchingDedupeKey).toList();
  final winner = <String, ItemBaseModel>{};
  for (var i = 0; i < items.length; i++) {
    final k = keys[i];
    final it = items[i];
    final w = winner[k];
    winner[k] = w == null ? it : _pickPreferredResume(w, it);
  }

  final seen = <String>{};
  final out = <ItemBaseModel>[];
  for (var i = 0; i < items.length; i++) {
    final k = keys[i];
    if (!seen.add(k)) continue;
    out.add(winner[k]!);
  }
  return out;
}
