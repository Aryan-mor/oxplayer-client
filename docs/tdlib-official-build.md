# Official TDLib build & artifact layout

Single source: [tdlib/td](https://github.com/tdlib/td). The pin used by OXPlayer lives in [`TD_VERSION.json`](../tool/tdlib/TD_VERSION.json) (`git_ref`, `commit_sha`, `toolchain`).

## Toolchain matrix (hardcoded)

| Component | Version |
|-----------|---------|
| Android NDK | **r26b** — `26.1.10909125` (`ANDROID_NDK_HOME`) |
| Emscripten | **3.1.56** (`emsdk install 3.1.56 && emsdk activate 3.1.56`) |

When bumping the TD git pin, re-read `example/web/README.md` **at that commit**; if upstream requires different NDK/emsdk, update this table and [`Dockerfile`](Dockerfile) in the same PR.

## Native Android (`libtdjson.so`)

Per-ABI helper: [`tool/tdlib/build_android_abi.sh`](../tool/tdlib/build_android_abi.sh) (requires `TD_SRC`, `ANDROID_NDK_HOME`, `ABI`). Verify CMake target name for your TD pin (`tdjson` vs upstream layout).

1. Install the pinned NDK (see table).
2. Check out [tdlib/td](https://github.com/tdlib/td) at `commit_sha` from `TD_VERSION.json`.
3. Per ABI, configure CMake with the Android toolchain file from `$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake` and build target **`tdjson`**.
4. Upload each `libtdjson.so` to object storage:

`{baseUrl}{commit_sha}/android/{arm64-v8a|armeabi-v7a|x86|x86_64}/libtdjson.so`

5. Optional `manifest.json` at `{baseUrl}{commit_sha}/manifest.json` listing `{ "path", "sha256" }` per file.

## Web (WASM / `example/web`)

1. Use Linux or **WSL2** (Emscripten scripts are Unix-oriented).
2. Activate the pinned **emsdk** version.
3. From `td/example/web` at the pinned TD commit, run the sequence documented there (typically OpenSSL → TDLib WASM → copy → tdweb bundle).
4. Pack the browser `dist/` as `dist.tar.gz` and upload to:

`{baseUrl}{commit_sha}/web/dist.tar.gz`

## Consuming artifacts (no Git LFS)

From `oxplayer-client/`:

```bash
cp tool/tdlib/artifact_config.example.yaml tool/tdlib/artifact_config.yaml
# edit base_url (+ optional headers for auth)

dart run tool/tdlib/fetch_artifacts.dart
```

This hydrates `android/app/src/main/jniLibs/<abi>/libtdjson.so` and extracts the web bundle into `web/tdweb/`.

**GitHub Releases (Option 1):** set `url_layout: github_release` and `base_url` to `https://github.com/<org>/<repo>/releases/download/tdlib-artifacts-<commit_sha>/` where `<commit_sha>` matches `TD_VERSION.json`. CI publishes unique asset names (`libtdjson-<abi>.so`, `dist.tar.gz`); `init-artifacts-config.mjs` generates this layout by default.

## Dart `td_api` types (codegen)

From `oxplayer-client/` after bumping `tool/tdlib/TD_VERSION.json`:

```bash
dart run tool/generator/generate.dart --fetch
```

Writes `lib/td_api_generated/` (including `td_api.dart`). The analyzer excludes that tree from style lints; app code imports `package:fladder/td_api_generated/td_api.dart`.

## Merge checklist (Telegram foundation)

Before merging TDLib / `td_api` changes to the default branch:

1. **CI parity**: `td_api.tl` is not committed as Dart sources — run `dart run tool/generator/generate.dart --fetch` in CI (see `.github/workflows/tdlib-artifacts.yml`) so `dart analyze` sees `lib/td_api_generated/`.
2. **Web**: run `flutter build web --release` locally and smoke-test in **Chrome** (login + receive at least one update) so `dart:js_interop` + WASM match the pinned `TD_VERSION.json` artifacts.
3. **Android**: smoke login on a device/emulator after refreshing native `.so` via `fetch_artifacts.dart`.

## Fail-fast

If `artifact_config.yaml` is missing, invalid, or any download/extract step fails, the script exits with code **1** so CI and local builds do not “succeed” without native `.so` files and the web bundle (which would only surface as runtime load errors).

## Web: cross-origin isolation (COOP / COEP)

Official TDLib for the browser uses **WASM with threading** (`SharedArrayBuffer`, workers). Browsers only expose that in a **[cross-origin isolated](https://developer.mozilla.org/en-US/docs/Web/API/crossOriginIsolated)** context:

- **`Cross-Origin-Opener-Policy: same-origin`**
- **`Cross-Origin-Embedder-Policy: require-corp`** (or `credentialless` if you deliberately relax third-party embeds)

**Production:** set these on the **HTTP response** for `index.html` and static assets (reverse proxy, CDN, or `flutter run` dev server if it supports custom headers). Relying on `<meta http-equiv="...">` in [`web/index.html`](../web/index.html) is a **development convenience**; support varies, and some setups ignore meta for COOP/COEP.

**Subresources:** anything loaded into the isolated document (scripts, workers, WASM) must be **same-origin** or served with **`Cross-Origin-Resource-Policy`** (and CORS where applicable). If you host `tdweb.js` / `.wasm` on another origin, that origin must send appropriate CORP/CORS headers or the page will fail to load them under `require-corp`.

## Docker

**CI:** the image build (NDK + emsdk smoke) does **not** run on every PR. Use [tdlib-toolchain-producer.yml](../.github/workflows/tdlib-toolchain-producer.yml) via **workflow_dispatch** or push tag `tdlib-artifacts-*`. Day-to-day codegen + `dart analyze` use [tdlib-artifacts.yml](../.github/workflows/tdlib-artifacts.yml) on PR/push path filters.

```bash
docker build -f tool/tdlib/Dockerfile -t oxplayer-tdlib-build tool/tdlib
```

The image installs the pinned NDK + emsdk. Mount or clone `td` sources at build time to run `example/web` scripts inside the container (see comments in the Dockerfile).
