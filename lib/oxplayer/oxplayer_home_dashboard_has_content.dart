import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/models/view_model.dart';

/// True when the home dashboard shows a banner or at least one poster row.
bool oxplayerHomeDashboardHasVisibleContent({
  required bool homeBanner,
  required List<ItemBaseModel> homeCarouselItems,
  required List<ItemBaseModel> tvChannels,
  required List<ItemBaseModel> resumeVideo,
  required List<ItemBaseModel> resumeAudio,
  required List<ItemBaseModel> resumeBooks,
  required List<ItemBaseModel> nextUp,
  required HomeNextUp nextUpSetting,
  required List<ViewModel> dashboardViews,
}) {
  if (homeBanner && homeCarouselItems.isNotEmpty) {
    return true;
  }
  final allResume = [...resumeVideo, ...resumeAudio, ...resumeBooks];
  if (tvChannels.isNotEmpty) return true;
  if (resumeVideo.isNotEmpty &&
      (nextUpSetting == HomeNextUp.cont || nextUpSetting == HomeNextUp.separate)) {
    return true;
  }
  if (resumeAudio.isNotEmpty &&
      (nextUpSetting == HomeNextUp.cont || nextUpSetting == HomeNextUp.separate)) {
    return true;
  }
  if (resumeBooks.isNotEmpty &&
      (nextUpSetting == HomeNextUp.cont || nextUpSetting == HomeNextUp.separate)) {
    return true;
  }
  if (nextUp.isNotEmpty &&
      (nextUpSetting == HomeNextUp.nextUp || nextUpSetting == HomeNextUp.separate)) {
    return true;
  }
  if ([...allResume, ...nextUp].isNotEmpty && nextUpSetting == HomeNextUp.combined) {
    return true;
  }
  if (dashboardViews.any(
        (v) => v.recentlyAdded.isNotEmpty && v.collectionType != CollectionType.livetv,
      )) {
    return true;
  }
  return false;
}
