import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/oxplayer/providers/oxplayer_swr_cache.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/home_library_order.dart';

//Known supported collection types
const enableCollectionTypes = {
  CollectionType.movies,
  CollectionType.books,
  CollectionType.tvshows,
  CollectionType.homevideos,
  CollectionType.boxsets,
  CollectionType.playlists,
  CollectionType.photos,
  CollectionType.livetv,
  CollectionType.folders,
};

final viewsProvider = StateNotifierProvider<ViewsNotifier, ViewsModel>((ref) {
  return ViewsNotifier(ref);
});

class ViewsNotifier extends StateNotifier<ViewsModel> {
  ViewsNotifier(this.ref) : super(ViewsModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  /// Concurrent callers await the same in-flight request (avoids `await` resolving early with null).
  Future<ViewsModel?>? _fetchViewsInFlight;

  /// When [force] is true, waits for any in-flight fetch then runs a new request so
  /// explicit refresh (pull-to-refresh, tab return) is not swallowed by deduplication.
  Future<ViewsModel?> fetchViews({bool force = false}) async {
    // User pull-to-refresh passes [force]: still attempt a fetch so coming back online works.
    if (ref.read(effectiveOfflineModeProvider) && !force) return state;
    if (!force && _fetchViewsInFlight != null) {
      return _fetchViewsInFlight!;
    }
    if (force && _fetchViewsInFlight != null) {
      try {
        await _fetchViewsInFlight!;
      } catch (_) {}
    }
    final run = _runFetchViews();
    _fetchViewsInFlight = run;
    try {
      return await run;
    } finally {
      if (identical(_fetchViewsInFlight, run)) {
        _fetchViewsInFlight = null;
      }
    }
  }

  Future<ViewsModel?> _runFetchViews() async {
    state = state.copyWith(loading: true);
    try {
      return await oxplayerTrackSwrRequest(ref, () async {
        final showAllCollections = ref.read(clientSettingsProvider.select((value) => value.showAllCollectionTypes));
        final response = await api.usersUserIdViewsGet();
        final createdViews = response.body?.items?.map((e) => ViewModel.fromBodyDto(e, ref)).where((element) {
          return showAllCollections ? true : enableCollectionTypes.contains(element.collectionType);
        });

        List<ViewModel> newList = [];

        if (createdViews != null) {
          newList = await Future.wait(createdViews.map((e) async {
            if (ref.read(userProvider)?.latestItemsExcludes.contains(e.id) == true) return e;
            final recents = await api.usersUserIdItemsLatestGet(
              parentId: e.id,
              imageTypeLimit: 1,
              limit: 16,
              includeItemTypes:
                  (e.collectionType == CollectionType.books && !showAllCollections) ? [BaseItemKind.book] : null,
              enableImageTypes: [
                ImageType.primary,
                ImageType.backdrop,
                ImageType.thumb,
              ],
              fields: [
                ItemFields.parentid,
                ItemFields.mediastreams,
                ItemFields.mediasources,
                ItemFields.candelete,
                ItemFields.candownload,
                ItemFields.primaryimageaspectratio,
                ItemFields.overview,
              ],
            );
            return e.copyWith(recentlyAdded: recents.body?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList());
          }));
        }

        state = state.copyWith(
            views: _applyLibraryOrdering(newList),
            dashboardViews: _applyLibraryOrdering(newList
                .where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? false))
                .toList()),
            loading: false);
        return state;
      });
    } catch (_) {
      state = state.copyWith(loading: false);
      return state;
    }
  }

  List<ViewModel> _applyLibraryOrdering(List<ViewModel> views) {
    final orderedViews = ref.read(userProvider)?.userConfiguration?.orderedViews ?? [];
    if (orderedViews.isEmpty) return applyDefaultHomeLibraryOrdering(views);

    final viewMap = {for (var v in views) v.id: v};
    final ordered = <ViewModel>[];

    for (final id in orderedViews) {
      final view = viewMap.remove(id);
      if (view != null) ordered.add(view);
    }
    ordered.addAll(viewMap.values);
    return ordered;
  }

  void clear() {
    state = ViewsModel();
  }
}
