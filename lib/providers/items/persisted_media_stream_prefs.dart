import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/providers/shared_provider.dart';

const _kPrefsKey = 'fladder_persisted_item_media_streams_v1';

final persistedMediaStreamPrefsProvider = Provider<PersistedMediaStreamPrefs>((ref) {
  return PersistedMediaStreamPrefs(ref.watch(sharedPreferencesProvider));
});

class PersistedMediaStreamPrefs {
  PersistedMediaStreamPrefs(this._prefs);

  final SharedPreferences _prefs;

  Map<String, dynamic> _readRaw() {
    final s = _prefs.getString(_kPrefsKey);
    if (s == null || s.isEmpty) return {};
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  void _writeRaw(Map<String, dynamic> map) {
    _prefs.setString(_kPrefsKey, jsonEncode(map));
  }

  PersistedStreamIndexes? readIndexes(String itemId) {
    final root = _readRaw()[itemId];
    if (root is! Map<String, dynamic>) return null;
    try {
      return PersistedStreamIndexes(
        versionStreamIndex: (root['versionStreamIndex'] as num?)?.toInt(),
        defaultAudioStreamIndex: (root['defaultAudioStreamIndex'] as num?)?.toInt(),
        defaultSubStreamIndex: (root['defaultSubStreamIndex'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  void writeForItem(String itemId, MediaStreamsModel ms) {
    final map = _readRaw();
    map[itemId] = <String, dynamic>{
      if (ms.versionStreamIndex != null) 'versionStreamIndex': ms.versionStreamIndex,
      if (ms.defaultAudioStreamIndex != null) 'defaultAudioStreamIndex': ms.defaultAudioStreamIndex,
      if (ms.defaultSubStreamIndex != null) 'defaultSubStreamIndex': ms.defaultSubStreamIndex,
    };
    _writeRaw(map);
  }
}
