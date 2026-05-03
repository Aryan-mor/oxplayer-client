import 'package:fladder/models/items/item_stream_model.dart';
import 'package:fladder/oxplayer/oxplayer_verified_streams_client.dart';

extension OxplayerItemStreamOxIds on ItemStreamModel {
  /// First `oxplayer://telegram/<id>` path from any media source version, if present.
  String? get oxTelegramLibraryMediaId {
    for (final v in mediaStreams.versionStreams) {
      final path = v.oxLocatorPath;
      if (path == null || path.isEmpty) continue;
      final id = parseOxplayerTelegramMediaId(path);
      if (id != null) return id;
    }
    return null;
  }
}
