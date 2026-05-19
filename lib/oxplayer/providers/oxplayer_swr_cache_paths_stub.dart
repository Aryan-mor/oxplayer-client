/// Web: [OxplayerSwrCache] returns before any FS call — this must never run.
Future<String> applicationSupportPathForSwr() async {
  throw UnsupportedError('oxplayer_swr_cache: paths unavailable on web');
}
