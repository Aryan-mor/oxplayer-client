#!/usr/bin/env bash
# Build Android libtdjson.so (4 ABIs) + pack example/web dist for GitHub Releases.
# Intended to run *inside* tool/tdlib/Dockerfile image with this repo mounted at /workspace.
#
# Android: uses upstream example/android/build-openssl.sh + build-tdlib.sh (JSON) so
# OpenSSL is built per-ABI before CMake (raw cmake without OPENSSL_ROOT_DIR fails).
set -euo pipefail

WORKSPACE="${1:-/workspace}"
cd "$WORKSPACE"

TD_VER="$(python3 -c "import json; print(json.load(open('tool/tdlib/TD_VERSION.json'))['commit_sha'])")"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk}"
# Must match the NDK revision installed in Dockerfile (r26b).
ANDROID_NDK_REV="${ANDROID_NDK_REV:-26.1.10909125}"

set +u
# shellcheck disable=SC1091
source /opt/emsdk/emsdk_env.sh
set -u

TD_SRC="/tmp/tdlib-src"
rm -rf "$TD_SRC"
mkdir -p "$TD_SRC"
cd "$TD_SRC"
git init
git remote add origin https://github.com/tdlib/td.git
git fetch --depth 1 origin "$TD_VER"
git checkout FETCH_HEAD

# example/android scripts expect $ANDROID_SDK_ROOT/ndk/<revision>/...
FAKE_SDK="/opt/android-sdk"
mkdir -p "$FAKE_SDK/ndk"
ln -sfn "$ANDROID_NDK_HOME" "$FAKE_SDK/ndk/${ANDROID_NDK_REV}"

OPENSSL_OUT="$WORKSPACE/build/openssl-android"
rm -rf "$OPENSSL_OUT"

ANDROID_EXAMPLE="$TD_SRC/example/android"
chmod +x "$ANDROID_EXAMPLE"/*.sh 2>/dev/null || true

cd "$ANDROID_EXAMPLE"
./build-openssl.sh "$FAKE_SDK" "$ANDROID_NDK_REV" "$OPENSSL_OUT"
./build-tdlib.sh "$FAKE_SDK" "$ANDROID_NDK_REV" "$OPENSSL_OUT" c++_static JSON

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  mkdir -p "$WORKSPACE/build/artifacts/android/$abi"
  cp -f "$ANDROID_EXAMPLE/tdlib/libs/$abi/libtdjson.so" "$WORKSPACE/build/artifacts/android/$abi/libtdjson.so"
done

cd "$TD_SRC/example/web"
chmod +x ./*.sh 2>/dev/null || true
./build-openssl.sh
./build-tdlib.sh
./copy-tdlib.sh
./build-tdweb.sh

mkdir -p "$WORKSPACE/build/artifacts/web"
if [[ -d tdweb/dist ]]; then
  tar -czf "$WORKSPACE/build/artifacts/web/dist.tar.gz" -C tdweb dist
elif [[ -d dist ]]; then
  tar -czf "$WORKSPACE/build/artifacts/web/dist.tar.gz" dist
else
  echo "::error::Expected tdweb/dist or dist under example/web after build-tdweb.sh"
  ls -la
  exit 1
fi

echo "[ci_build_release_artifacts] OK — Android .so x4 + web/dist.tar.gz"
