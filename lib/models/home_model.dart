// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:fladder/models/item_base_model.dart';

class HomeModel {
  final bool loading;
  final List<ItemBaseModel> resumeVideo;
  final List<ItemBaseModel> resumeAudio;
  final List<ItemBaseModel> resumeBooks;
  final List<ItemBaseModel> activePrograms;
  final List<ItemBaseModel> nextUp;
  final List<ItemBaseModel> bannerCurated;
  final List<ItemBaseModel> bannerGlobalLatest;
  /// Home-banner pins from `HomeBannerDiscovery` when the server includes them (same payload order as API).
  final List<ItemBaseModel> bannerCustom;
  /// TMDB daily trending from `HomeBannerDiscovery.TrendingTop10` when present.
  final List<ItemBaseModel> bannerTrendingTop10;

  HomeModel({
    this.loading = false,
    this.resumeVideo = const [],
    this.resumeAudio = const [],
    this.resumeBooks = const [],
    this.activePrograms = const [],
    this.nextUp = const [],
    this.bannerCurated = const [],
    this.bannerGlobalLatest = const [],
    this.bannerCustom = const [],
    this.bannerTrendingTop10 = const [],
  });

  HomeModel copyWith({
    bool? loading,
    List<ItemBaseModel>? resumeVideo,
    List<ItemBaseModel>? resumeAudio,
    List<ItemBaseModel>? resumeBooks,
    List<ItemBaseModel>? activePrograms,
    List<ItemBaseModel>? nextUp,
    List<ItemBaseModel>? nextUpBooks,
    List<ItemBaseModel>? bannerCurated,
    List<ItemBaseModel>? bannerGlobalLatest,
    List<ItemBaseModel>? bannerCustom,
    List<ItemBaseModel>? bannerTrendingTop10,
  }) {
    return HomeModel(
      loading: loading ?? this.loading,
      resumeVideo: resumeVideo ?? this.resumeVideo,
      resumeAudio: resumeAudio ?? this.resumeAudio,
      resumeBooks: resumeBooks ?? this.resumeBooks,
      activePrograms: activePrograms ?? this.activePrograms,
      nextUp: nextUp ?? this.nextUp,
      bannerCurated: bannerCurated ?? this.bannerCurated,
      bannerGlobalLatest: bannerGlobalLatest ?? this.bannerGlobalLatest,
      bannerCustom: bannerCustom ?? this.bannerCustom,
      bannerTrendingTop10: bannerTrendingTop10 ?? this.bannerTrendingTop10,
    );
  }
}
