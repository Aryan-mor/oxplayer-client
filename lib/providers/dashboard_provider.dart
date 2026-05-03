import 'dart:developer' show log;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/oxplayer/oxplayer_online_status.dart';
import 'package:fladder/oxplayer/oxplayer_resume_watching_dedupe.dart';
import 'package:fladder/oxplayer/providers/oxplayer_swr_cache.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/list_extensions.dart';

final dashboardProvider = StateNotifierProvider<DashboardNotifier, HomeModel>((ref) {
  return DashboardNotifier(ref);
});

class DashboardNotifier extends StateNotifier<HomeModel> {
  DashboardNotifier(this.ref) : super(HomeModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  /// Concurrent callers await the same in-flight request instead of no-op'ing while loading.
  Future<void>? _fetchDashboardInFlight;

  /// When [force] is true, waits for any in-flight fetch then runs again (see [ViewsNotifier.fetchViews]).
  Future<void> fetchNextUpAndResume({bool force = false}) async {
    if (ref.read(effectiveOfflineModeProvider) && !force) return;
    if (!force && _fetchDashboardInFlight != null) {
      return _fetchDashboardInFlight!;
    }
    if (force && _fetchDashboardInFlight != null) {
      try {
        await _fetchDashboardInFlight!;
      } catch (_) {}
    }
    final run = _runFetchNextUpAndResume();
    _fetchDashboardInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_fetchDashboardInFlight, run)) {
        _fetchDashboardInFlight = null;
      }
    }
  }

  Future<void> _runFetchNextUpAndResume() async {
    state = state.copyWith(loading: true);
    try {
      await oxplayerTrackSwrRequest(ref, () async {
        final viewTypes =
            ref.read(viewsProvider.select((value) => value.dashboardViews)).map((e) => e.collectionType).toSet().toList();
        final limit = 16;

        final imagesToFetch = {
          ImageType.logo,
          ImageType.primary,
          ImageType.backdrop,
          ImageType.banner,
        }.toList();

        final fieldsToFetch = {
          ItemFields.parentid,
          ItemFields.mediastreams,
          ItemFields.mediasources,
          ItemFields.candelete,
          ItemFields.candownload,
          ItemFields.primaryimageaspectratio,
          ItemFields.overview,
          ItemFields.airtime,
        };

    if (viewTypes.containsAny([CollectionType.livetv])) {
      List<ChannelModel> channels = (await api.liveTvChannelsGet(limit: limit))
              .body
              ?.items
              ?.map((e) => ChannelModel.fromBaseDto(e, ref))
              .toList() ??
          [];

      channels = await Future.wait(
        channels.map(
          (e) async {
            final programs = await ref.read(liveTvProvider.notifier).fetchProgramsForChannel(e);
            return e.copyChannelWith(
              programs: programs,
            );
          },
        ),
      );

      state = state.copyWith(activePrograms: channels);
    } else {
      state = state.copyWith(activePrograms: []);
    }

    if (viewTypes.containsAny([CollectionType.movies, CollectionType.tvshows])) {
      final resumeVideoResponse = await api.usersUserIdItemsResumeGet(
        enableImageTypes: imagesToFetch,
        fields: fieldsToFetch.toList(),
        mediaTypes: [MediaType.video],
        enableTotalRecordCount: false,
        limit: limit,
      );
      final rawItems = resumeVideoResponse.body?.items ?? [];
      final mapped = rawItems.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
      final deduped = dedupeResumeWatchingVideos(mapped);
      log(
        '[DEBUG_WL] UserItems/Resume video: status=${resumeVideoResponse.statusCode} '
        'rawCount=${rawItems.length} afterDedupe=${deduped.length} '
        'firstIds=${deduped.take(5).map((e) => e.id).join(",")}',
        name: 'continue_watching',
      );

      state = state.copyWith(
        resumeVideo: deduped,
      );
    }

    if (viewTypes.contains(CollectionType.music)) {
      final resumeAudioResponse = await api.usersUserIdItemsResumeGet(
        enableImageTypes: imagesToFetch,
        fields: fieldsToFetch.toList(),
        mediaTypes: [MediaType.audio],
        enableTotalRecordCount: false,
        limit: limit,
      );

      state = state.copyWith(
        resumeAudio: resumeAudioResponse.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList(),
      );
    }

    if (viewTypes.contains(CollectionType.books)) {
      final resumeBookResponse = await api.usersUserIdItemsResumeGet(
        enableImageTypes: imagesToFetch,
        fields: fieldsToFetch.toList(),
        mediaTypes: [MediaType.book],
        enableTotalRecordCount: false,
        limit: limit,
      );

      state = state.copyWith(
        resumeBooks: resumeBookResponse.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList(),
      );
    }

    final nextResponse = await api.showsNextUpGet(
      nextUpDateCutoff: DateTime.now().subtract(
          ref.read(clientSettingsProvider.select((value) => value.nextUpDateCutoff ?? const Duration(days: 28)))),
      fields: fieldsToFetch.toList(),
    );

    final next = nextResponse.body?.items
            ?.map(
              (e) => ItemBaseModel.fromBaseDto(e, ref),
            )
            .toList() ??
        [];

        var bannerCurated = <ItemBaseModel>[];
        var bannerGlobalLatest = <ItemBaseModel>[];
        final disc = await api.userItemsHomeBannerDiscoveryGet();
        if (disc != null) {
          bannerCurated = disc.curated.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
          bannerGlobalLatest = disc.globalLatest.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
        }

        state = state.copyWith(
          nextUp: next,
          loading: false,
          bannerCurated: bannerCurated,
          bannerGlobalLatest: bannerGlobalLatest,
        );
      });
    } catch (e, st) {
      log('[DEBUG_WL] fetchNextUpAndResume failed: $e\n$st', name: 'continue_watching');
      state = state.copyWith(loading: false);
    }
  }

  void clear() {
    state = HomeModel();
  }
}
