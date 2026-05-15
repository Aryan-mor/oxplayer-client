import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/view_model.dart';

/// Puts Jellyfin `homevideos` (OX general videos) after all other libraries on the home dashboard.
List<ViewModel> applyOxplayerHomeVideosLast(List<ViewModel> views) {
  final general = views.where((v) => v.collectionType == CollectionType.homevideos).toList();
  if (general.isEmpty) return views;
  final rest = views.where((v) => v.collectionType != CollectionType.homevideos).toList();
  return [...rest, ...general];
}
