Place `libtdjson.so` here for Android (not committed at scale — use registry fetch):

  arm64-v8a/libtdjson.so
  armeabi-v7a/libtdjson.so
  x86_64/libtdjson.so

  (x86 32-bit is not packaged — see ndk.abiFilters in android/app/build.gradle)

Build or download artifacts that match [tool/tdlib/TD_VERSION.json](../../tool/tdlib/TD_VERSION.json) (`commit_sha`).

Preferred: `dart run tool/tdlib/fetch_artifacts.dart` after configuring `tool/tdlib/artifact_config.yaml` (see `artifact_config.example.yaml`).

See [docs/tdlib-official-build.md](../../docs/tdlib-official-build.md) for NDK / Emscripten matrix and Docker image.

The app loads via `dart:ffi` ([td_json_official_client.dart](../../lib/oxplayer/telegram/td_json_official_client.dart)); `MainActivity` still calls `System.loadLibrary("tdjson")`.
