import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:fladder/oxplayer/providers/oxplayer_swr_cache_paths_stub.dart'
    if (dart.library.io) 'package:fladder/oxplayer/providers/oxplayer_swr_cache_paths_io.dart' as swr_paths;

final oxplayerSwrCacheProvider = Provider<OxplayerSwrCache>((ref) {
  return const OxplayerSwrCache();
});

class OxplayerSwrSnapshot<T> {
  const OxplayerSwrSnapshot({
    required this.data,
    required this.isFromCache,
    required this.isRefreshing,
    this.error,
  });

  final T data;
  final bool isFromCache;
  final bool isRefreshing;
  final Object? error;

  OxplayerSwrSnapshot<T> copyWith({
    T? data,
    bool? isFromCache,
    bool? isRefreshing,
    Object? error,
  }) {
    return OxplayerSwrSnapshot<T>(
      data: data ?? this.data,
      isFromCache: isFromCache ?? this.isFromCache,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error,
    );
  }
}

class OxplayerSwrCache {
  const OxplayerSwrCache();

  Future<T?> read<T>(
    String key, {
    required T Function(Object? json) decode,
  }) async {
    if (kIsWeb) return null;
    final file = await _fileForKey(key);
    if (!await file.exists()) return null;
    try {
      return decode(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String key, {
    required Object? json,
  }) async {
    if (kIsWeb) return;
    final file = await _fileForKey(key);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
  }

  Future<File> _fileForKey(String key) async {
    final basePath = await swr_paths.applicationSupportPathForSwr();
    final safeKey = base64Url.encode(utf8.encode(key));
    return File(p.join(basePath, 'oxplayer_swr_cache', '$safeKey.json'));
  }
}

Future<T> oxplayerTrackSwrRequest<T>(
  Ref ref,
  Future<T> Function() run,
) async {
  return run();
}
