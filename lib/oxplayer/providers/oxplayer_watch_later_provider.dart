import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';

class WatchLaterState {
  final String? playlistId;
  // Map of underlying itemId to the playlist entryId (playlistItemId)
  final Map<String, String> itemsMap;
  final bool isLoading;

  const WatchLaterState({
    this.playlistId,
    this.itemsMap = const {},
    this.isLoading = false,
  });

  WatchLaterState copyWith({
    String? playlistId,
    Map<String, String>? itemsMap,
    bool? isLoading,
  }) {
    return WatchLaterState(
      playlistId: playlistId ?? this.playlistId,
      itemsMap: itemsMap ?? this.itemsMap,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final oxplayerWatchLaterProvider =
    StateNotifierProvider<OxplayerWatchLaterNotifier, WatchLaterState>((ref) {
  return OxplayerWatchLaterNotifier(ref);
});

class OxplayerWatchLaterNotifier extends StateNotifier<WatchLaterState> {
  final Ref ref;
  late final JellyService api = ref.read(jellyApiProvider);

  /// Completes once _init() has finished so toggleWatchLater always waits for
  /// the server lookup before deciding to create or reuse the playlist.
  final Completer<void> _initCompleter = Completer<void>();

  OxplayerWatchLaterNotifier(this.ref) : super(const WatchLaterState()) {
    _init();
  }

  Future<void> _init() async {
    final user = ref.read(userProvider);
    if (user == null) {
      _initCompleter.complete();
      return;
    }

    state = state.copyWith(isLoading: true);
    try {
      final playlistsResponse = await api.usersUserIdItemsGet(
        includeItemTypes: [BaseItemKind.playlist],
        recursive: true,
      );

      final playlists = playlistsResponse.body?.items ?? [];
      final watchLaterList = playlists.firstWhereOrNull(
        (p) => p.name?.toLowerCase() == 'watch later' || p.name?.toLowerCase() == 'watchlater',
      );

      if (watchLaterList != null && watchLaterList.id != null) {
        state = state.copyWith(playlistId: watchLaterList.id);
        await _loadPlaylistItems(watchLaterList.id!);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    } finally {
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  Future<void> _loadPlaylistItems(String playlistId) async {
    try {
      final itemsResponse = await api.playlistsPlaylistIdItemsGet(
        playlistId: playlistId,
      );

      final items = itemsResponse.body?.items ?? [];
      final Map<String, String> newMap = {};
      
      for (final item in items) {
        if (item.id != null && item.playlistId != null) {
          newMap[item.id!] = item.playlistId!;
        }
      }

      state = state.copyWith(itemsMap: newMap, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> toggleWatchLater(ItemBaseModel item) async {
    final user = ref.read(userProvider);
    if (user == null) return;

    // Wait for _init() to finish so we always know whether the playlist already exists.
    await _initCompleter.future;

    final itemId = item.id;
    if (state.itemsMap.containsKey(itemId)) {
      // Remove from watch later
      final playlistId = state.playlistId;
      final entryId = state.itemsMap[itemId];
      if (playlistId != null && entryId != null) {
        try {
          await api.playlistsPlaylistIdItemsDelete(
            playlistId: playlistId,
            entryIds: [entryId],
          );
          final updatedMap = Map<String, String>.from(state.itemsMap)..remove(itemId);
          state = state.copyWith(itemsMap: updatedMap);
        } catch (e) {
          // Handle error if needed
        }
      }
    } else {
      // Add to watch later. The backend POST /Playlists is idempotent by name:
      // it returns the existing playlist's ID if one already exists, so we never
      // need to branch on whether state.playlistId is set — the server handles it.
      try {
        final createResponse = await api.playlistsPost(
          name: "Watch Later",
          ids: [itemId],
          body: null,
        );
        final resolvedPlaylistId = createResponse.body?.id ?? state.playlistId;
        if (resolvedPlaylistId != null) {
          state = state.copyWith(playlistId: resolvedPlaylistId);
          // Reload items to get the up-to-date entryId map.
          await _loadPlaylistItems(resolvedPlaylistId);
        }
      } catch (e) {
        // Handle error if needed
      }
    }
  }
}
