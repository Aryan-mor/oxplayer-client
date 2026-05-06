import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_stream_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/collections/add_to_collection.dart';
import 'package:fladder/screens/metadata/edit_item.dart';
import 'package:fladder/screens/metadata/identifty_screen.dart';
import 'package:fladder/screens/metadata/info_screen.dart';
import 'package:fladder/screens/metadata/refresh_metadata.dart';
import 'package:fladder/screens/playlists/add_to_playlists.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/screens/syncing/sync_button.dart';
import 'package:fladder/screens/syncing/sync_item_details.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/clipboard_helper.dart';
import 'package:fladder/util/file_downloader.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_after_watch_state.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/widgets/pop_up/delete_file.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_item_stream_ox_ids.dart';
import 'package:fladder/oxplayer/oxplayer_library_media_api.dart';
import 'package:fladder/oxplayer/providers/oxplayer_watch_later_provider.dart';

extension ItemBaseModelsBooleans on List<ItemBaseModel> {
  Map<FladderItemType, List<ItemBaseModel>> get groupedItems {
    Map<FladderItemType, List<ItemBaseModel>> groupedItems = {};
    for (int i = 0; i < length; i++) {
      FladderItemType type = this[i].type;
      if (!groupedItems.containsKey(type)) {
        groupedItems[type] = [this[i]];
      } else {
        groupedItems[type]?.add(this[i]);
      }
    }
    return groupedItems;
  }

  FladderItemType get getMostCommonType {
    if (isEmpty) return FladderItemType.movie;
    final Map<FladderItemType, int> counts = {};

    for (final item in this) {
      final type = item.type;
      counts[type] = (counts[type] ?? 0) + 1;
    }

    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  double? getMostCommonAspectRatio({double tolerance = 0.01}) {
    final Map<int, List<double>> buckets = {};

    for (final item in this) {
      final aspectRatio = item.primaryRatio;
      if (aspectRatio == null) continue;

      final bucketKey = (aspectRatio / tolerance).round();

      buckets.putIfAbsent(bucketKey, () => []).add(aspectRatio);
    }

    if (buckets.isEmpty) return null;

    final mostCommonBucket = buckets.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);

    final average = mostCommonBucket.value.reduce((a, b) => a + b) / mostCommonBucket.value.length;
    return average;
  }
}

extension ItemBaseModelOxGeneralVideo on ItemBaseModel {
  /// OX [ProviderIds] from Jellyfin: `OX=general_video`, `OXMedia=<db media id>`.
  String? get oxMediaIdForGeneralVideoThumb {
    if (this is! MovieModel) return null;
    final p = (this as MovieModel).providerIds;
    if (p == null) return null;
    if (p['OX']?.toString() != 'general_video') return null;
    final id = p['OXMedia']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }
}

/// After a library delete succeeds: run optional screen hook, otherwise pop one route (e.g. detail → previous).
Future<void> _navigateAfterLibraryItemDelete(
  BuildContext context,
  ItemBaseModel item,
  FutureOr<void> Function(ItemBaseModel item)? onDeleteSuccesFully,
) async {
  if (onDeleteSuccesFully != null) {
    await onDeleteSuccesFully(item);
  } else if (context.mounted) {
    await context.router.popBack();
  }
}

enum ItemActions {
  play,
  openShow,
  openParent,
  details,
  showAlbum,
  playFromStart,
  addCollection,
  addPlaylist,
  markPlayed,
  markUnplayed,
  setFavorite,
  refreshMetaData,
  editMetaData,
  mediaInfo,
  identify,
  download,
  watchLater,
}

void _debugWatchedLog(String message) {
  // Use debugPrint so lines appear under `I/flutter` in Android logcat (developer.log is easy to miss).
  debugPrint('[DEBUG_WATCHED] $message');
}

/// One of watched / unwatched in the item menu, not both (see [ItemBaseModelExtensions.generateActions]).
bool _showMarkWatchedMenuAction(ItemBaseModel item) {
  if (item is SeasonModel || item is SeriesModel) {
    final u = item.userData.unPlayedItemCount;
    if (u != null) return u > 0;
    return !item.userData.played;
  }
  return !item.userData.played;
}

extension ItemBaseModelExtensions on ItemBaseModel {
  List<ItemAction> generateActions(
    BuildContext context,
    WidgetRef ref, {
    List<ItemAction> otherActions = const [],
    Set<ItemActions> exclude = const {},
    Function(UserData? newData)? onUserDataChanged,
    Function(ItemBaseModel item)? onItemUpdated,
    FutureOr<void> Function(ItemBaseModel item)? onDeleteSuccesFully,
  }) {
    final isAdmin = ref.read(userProvider)?.policy?.isAdministrator ?? false;
    final downloadEnabled = ref.read(userProvider.select(
          (value) => value?.canDownload ?? false,
        )) &&
        syncAble &&
        (canDownload ?? false);
    final downloadUrl = ref.read(userProvider.notifier).createDownloadUrl(this);
    final syncedItemFuture = ref.read(syncProvider.notifier).getSyncedItem(id);
    final hasSeerrData = overview.seerrUrl?.isNotEmpty == true;
    final showMarkWatched = _showMarkWatchedMenuAction(this);
    _debugWatchedLog(
      'generateActions id=$id type=$runtimeType played=${userData.played} unPlayedCount=${userData.unPlayedItemCount} → ${showMarkWatched ? "menu:MarkWatched" : "menu:MarkUnwatched"}',
    );
    return [
      if (!exclude.contains(ItemActions.play))
        if (playAble)
          ItemActionButton(
            action: () => play(context, ref),
            icon: const Icon(IconsaxPlusLinear.play),
            label: Text(playButtonLabel(context.localized)),
          ),
      if (parentId?.isNotEmpty == true) ...[
        if (!exclude.contains(ItemActions.openShow) && this is EpisodeModel)
          ItemActionButton(
            icon: Icon(FladderItemType.series.icon),
            action: () => parentBaseModel.navigateTo(context),
            label: Text(context.localized.openShow),
          ),
        if (!exclude.contains(ItemActions.openParent) && this is! EpisodeModel && !galleryItem)
          ItemActionButton(
            icon: Icon(FladderItemType.folder.icon),
            action: () => parentBaseModel.navigateTo(context),
            label: Text(context.localized.openParent),
          ),
      ],
      if (!galleryItem && !exclude.contains(ItemActions.details))
        ItemActionButton(
          action: () async => await navigateTo(context),
          icon: const Icon(IconsaxPlusLinear.main_component),
          label: Text(context.localized.showDetails),
        )
      else if (!exclude.contains(ItemActions.showAlbum) && galleryItem)
        ItemActionButton(
          icon: Icon(FladderItemType.photoAlbum.icon),
          action: () => parentBaseModel.navigateTo(context),
          label: Text(context.localized.showAlbum),
        ),
      if (!exclude.contains(ItemActions.playFromStart))
        if ((userData.progress) > 0)
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.refresh),
            action: (this is BookModel)
                ? () => ((this as BookModel).play(context, ref, currentPage: 0))
                : () => play(context, ref, startPosition: Duration.zero),
            label: Text((this is BookModel)
                ? context.localized.readFromStart(name)
                : context.localized.playFromStart(subTextShort(context.localized) ?? name)),
          ),
      ItemActionDivider(),
      if (!exclude.contains(ItemActions.addCollection) && isAdmin)
        if (type != FladderItemType.boxset)
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.archive_add),
            action: () async {
              await addItemToCollection(context, [this]);
              if (context.mounted) {
                context.refreshData();
              }
            },
            label: Text(context.localized.addToCollection),
          ),
      if (!exclude.contains(ItemActions.addPlaylist))
        if (type != FladderItemType.playlist)
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.archive_add),
            action: () async {
              await addItemToPlaylist(context, [this]);
              if (context.mounted) {
                context.refreshData();
              }
            },
            label: Text(context.localized.addToPlaylist),
          ),
      if (!exclude.contains(ItemActions.markPlayed) && showMarkWatched)
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.eye),
          action: () async {
            _debugWatchedLog('tap markAsWatched id=$id type=$runtimeType');
            try {
              final userData = await ref.read(userProvider.notifier).markAsPlayedOxAware(true, this);
              _debugWatchedLog('markAsWatched done id=$id userData=${userData?.bodyOrThrow != null}');
              onUserDataChanged?.call(userData?.bodyOrThrow);
            } finally {
              await refreshAfterWatchStateChange(ref, this);
              if (context.mounted) context.refreshData();
            }
          },
          label: Text(context.localized.markAsWatched),
        ),
      if (!exclude.contains(ItemActions.markUnplayed) && !showMarkWatched)
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.eye_slash),
          label: Text(context.localized.markAsUnwatched),
          action: () async {
            _debugWatchedLog('tap markAsUnwatched id=$id type=$runtimeType');
            try {
              final userData = await ref.read(userProvider.notifier).markAsPlayedOxAware(false, this);
              _debugWatchedLog('markAsUnwatched done id=$id userData=${userData?.bodyOrThrow != null}');
              onUserDataChanged?.call(userData?.bodyOrThrow);
            } finally {
              await refreshAfterWatchStateChange(ref, this);
              if (context.mounted) context.refreshData();
            }
          },
        ),
      if (!exclude.contains(ItemActions.setFavorite))
        ItemActionButton(
          icon: Icon(userData.isFavourite ? IconsaxPlusLinear.heart_remove : IconsaxPlusLinear.heart_add),
          action: () async {
            try {
              final newData = await ref.read(userProvider.notifier).setAsFavorite(!userData.isFavourite, id);
              onUserDataChanged?.call(newData?.bodyOrThrow);
            } finally {
              context.refreshData();
            }
          },
          label: Text(userData.isFavourite ? context.localized.removeAsFavorite : context.localized.addAsFavorite),
        ),
      if (OxplayerConfig.isEnabled && !exclude.contains(ItemActions.watchLater))
        () {
          final watchLaterState = ref.read(oxplayerWatchLaterProvider);
          final isWatchLater = watchLaterState.itemsMap.containsKey(id);
          return ItemActionButton(
            icon: Icon(isWatchLater ? IconsaxPlusBold.clock : IconsaxPlusLinear.clock),
            action: () async {
              try {
                await ref.read(oxplayerWatchLaterProvider.notifier).toggleWatchLater(this);
              } finally {
                context.refreshData();
              }
            },
            label: Text(isWatchLater ? "Remove from Watch Later" : "Add to Watch Later"),
          );
        }(),
      ..._oxplayerLibraryIssueActions(
        context: context,
        ref: ref,
        item: this,
        onDeleteSuccesFully: onDeleteSuccesFully,
      ),
      ...otherActions,
      ItemActionDivider(),
      if (!exclude.contains(ItemActions.editMetaData) && isAdmin)
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.edit),
          action: () async {
            final newItem = await showEditItemPopup(context, id);
            if (newItem != null) {
              onItemUpdated?.call(newItem);
            }
          },
          label: Text(context.localized.editMetadata),
        ),
      if (!exclude.contains(ItemActions.refreshMetaData) && isAdmin)
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.global_refresh),
          action: () async {
            showRefreshPopup(context, id, detailedName(context.localized) ?? name);
          },
          label: Text(context.localized.refreshMetadata),
        ),
      if (!exclude.contains(ItemActions.download) && downloadEnabled) ...[
        if (!kIsWeb)
          ItemActionButton(
            icon: FutureBuilder(
              future: syncedItemFuture,
              builder: (context, snapshot) {
                final syncedItem = snapshot.data;
                if (syncedItem != null) {
                  return IgnorePointer(child: SyncButton(item: this, syncedItem: syncedItem));
                }
                return const Icon(IconsaxPlusLinear.arrow_down_2);
              },
            ),
            label: FutureBuilder(
              future: syncedItemFuture,
              builder: (context, snapshot) {
                final syncedItem = snapshot.data;
                if (syncedItem != null) {
                  return Text(
                    context.localized.syncDetails,
                  );
                }
                return Text(context.localized.sync);
              },
            ),
            action: () async {
              final syncedItem = await syncedItemFuture;
              if (syncedItem != null) {
                await showSyncItemDetails(context, syncedItem, ref);
              } else {
                await ref.read(syncProvider.notifier).addSyncItem(context, this);
              }
              context.refreshData();
            },
          )
        else if (downloadUrl != null) ...[
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.document_download),
            action: () => downloadFile(downloadUrl),
            label: Text(context.localized.downloadFile(type.label(context.localized).toLowerCase())),
          ),
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.link_21),
            action: () => context.copyToClipboard(downloadUrl),
            label: Text(context.localized.copyStreamUrl),
          )
        ],
      ],
      if (hasSeerrData && tmdbId != null)
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.link_21),
          action: () {
            context.pushRoute(SeerrDetailsRoute(
                mediaType: switch (this) {
                  MovieModel() => SeerrMediaType.movie,
                  SeriesModel() => SeerrMediaType.tvshow,
                  _ => SeerrMediaType.movie,
                }
                    .name,
                tmdbId: tmdbId!));
          },
          label: Text(context.localized.seerrDetails),
        ),
      if (canDelete == true)
        ItemActionButton(
          icon: Container(
            child: const Icon(
              IconsaxPlusLinear.trash,
            ),
          ),
          action: () async {
            final response = await FladderSnack.showResponse(
              showDeleteDialog(context, this, ref),
              successTitle: context.localized.deletedItem(name),
            );
            if (response.isSuccess) {
              await _navigateAfterLibraryItemDelete(context, this, onDeleteSuccesFully);
              if (context.mounted) {
                context.refreshData();
              }
            }
          },
          label: Text(context.localized.delete),
        ),
      if (!exclude.contains(ItemActions.identify) && identifiable && isAdmin)
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.search_normal),
          action: () async {
            showIdentifyScreen(context, this);
          },
          label: Text(context.localized.identify),
        ),
      if (!exclude.contains(ItemActions.mediaInfo))
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.info_circle),
          action: () async {
            showInfoScreen(context, this);
          },
          label: Text("${type.label(context.localized)} ${context.localized.info}"),
        ),
    ];
  }

  int? get tmdbId {
    final providerIds = this is MovieModel
        ? (this as MovieModel).providerIds
        : this is SeriesModel
            ? (this as SeriesModel).providerIds
            : null;

    if (providerIds == null || providerIds.isEmpty) return null;

    final value = providerIds['Tmdb'];
    final parsed = int.tryParse(value.toString());
    return parsed;
  }

  int? get tvdbId {
    final providerIds = this is MovieModel
        ? (this as MovieModel).providerIds
        : this is SeriesModel
            ? (this as SeriesModel).providerIds
            : null;

    if (providerIds == null || providerIds.isEmpty) return null;
    final value = providerIds['Tvdb'];
    final parsed = int.tryParse(value.toString());
    return parsed;
  }
}

Iterable<ItemAction> _oxplayerLibraryIssueActions({
  required BuildContext context,
  required WidgetRef ref,
  required ItemBaseModel item,
  FutureOr<void> Function(ItemBaseModel item)? onDeleteSuccesFully,
}) sync* {
  if (item is MovieModel && item.oxMediaIdForGeneralVideoThumb != null) {
    final mediaId = item.oxMediaIdForGeneralVideoThumb!;
    yield ItemActionButton(
      icon: const Icon(IconsaxPlusLinear.trash),
      label: Text(context.localized.oxplayerRemoveFromLibrary),
      action: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.localized.oxplayerRemoveGeneralVideoTitle),
            content: Text(ctx.localized.oxplayerRemoveGeneralVideoBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.localized.cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.localized.delete)),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        final removed = await oxplayerDeleteLibraryMedia(ref, mediaId);
        if (!context.mounted) return;
        if (removed) {
          FladderSnack.show(context.localized.oxplayerRemoveGeneralVideoSuccess, context: context);
          await _navigateAfterLibraryItemDelete(context, item, onDeleteSuccesFully);
          if (context.mounted) {
            context.refreshData();
          }
        } else {
          FladderSnack.show(context.localized.oxplayerRemoveGeneralVideoFailed, context: context);
        }
      },
    );
    return;
  }
  if (item is ItemStreamModel) {
    final mid = item.oxTelegramLibraryMediaId;
    if (mid == null) return;
    yield ItemActionButton(
      icon: const Icon(IconsaxPlusLinear.flag),
      label: Text(context.localized.oxplayerReportIssue),
      action: () async {
        final r = await oxplayerPostLibraryMediaReport(ref, mid);
        if (!context.mounted) return;
        if (!r.ok) {
          if (kDebugMode) {
            log(r.debugLine, name: 'oxplayer_library_report');
          }
          final msg = switch (r.httpStatus) {
            401 => context.localized.oxplayerReportIssueUnauthorized,
            404 => context.localized.oxplayerReportIssueNotFound,
            _ => context.localized.oxplayerReportIssueFailed,
          };
          FladderSnack.show(msg, context: context);
          return;
        }
        FladderSnack.show(
          r.adminNotified
              ? context.localized.oxplayerReportIssueSent
              : context.localized.oxplayerReportIssueRecordedWithoutAdmin,
          context: context,
        );
      },
    );
  }
}
