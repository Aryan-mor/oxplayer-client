#!/usr/bin/env bash
# Build Android libtdjson.so (4 ABIs) + pack example/web dist for GitHub Releases.
# Intended to run *inside* tool/tdlib/Dockerfile image with this repo mounted at /workspace.
#
# Android: uses upstream example/android/build-openssl.sh + build-tdlib.sh (JSON).
# OpenSSL must exist per ABI before CMake; we verify layout after build-openssl and
# use the same third-party/openssl path layout as upstream TD docs.
set -euo pipefail

WORKSPACE_INPUT="${1:-/workspace}"
WORKSPACE="$(cd "$WORKSPACE_INPUT" && pwd -P)"
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

ANDROID_EXAMPLE="$TD_SRC/example/android"
chmod +x "$ANDROID_EXAMPLE"/*.sh 2>/dev/null || true

cd "$ANDROID_EXAMPLE"
# Match upstream default layout (example/android/third-party/openssl/<abi>/...).
# Absolute path avoids edge cases when normalizing OPENSSL_INSTALL_DIR inside TD scripts.
OPENSSL_REL="$(pwd -P)/third-party/openssl"
rm -rf "$OPENSSL_REL"

echo "[ci] Building OpenSSL for Android (NDK ${ANDROID_NDK_REV}) into ${OPENSSL_REL} ..."
./build-openssl.sh "$FAKE_SDK" "$ANDROID_NDK_REV" "$OPENSSL_REL"

echo "[ci] Verifying per-ABI OpenSSL trees (fail-fast before TDLib CMake) ..."
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  export OPENSSL_ROOT_DIR="${OPENSSL_REL}/${abi}"
  if [[ ! -d "${OPENSSL_ROOT_DIR}/include/openssl" ]]; then
    echo "::error::Missing OpenSSL headers: ${OPENSSL_ROOT_DIR}/include/openssl"
    exit 1
  fi
  if [[ -f "${OPENSSL_ROOT_DIR}/lib/libcrypto.a" && -f "${OPENSSL_ROOT_DIR}/lib/libssl.a" ]]; then
    echo "[ci] ${abi}: static OpenSSL OK (${OPENSSL_ROOT_DIR})"
  elif [[ -f "${OPENSSL_ROOT_DIR}/lib/libcrypto.so" && -f "${OPENSSL_ROOT_DIR}/lib/libssl.so" ]]; then
    echo "[ci] ${abi}: shared OpenSSL OK (${OPENSSL_ROOT_DIR})"
  else
    echo "::error::Missing OpenSSL libs under ${OPENSSL_ROOT_DIR}/lib"
    ls -la "${OPENSSL_ROOT_DIR}/lib" 2>/dev/null || true
    exit 1
  fi
done
unset OPENSSL_ROOT_DIR

echo "[ci] Building TDLib (JSON) with OPENSSL_INSTALL_DIR=${OPENSSL_REL} ..."
./build-tdlib.sh "$FAKE_SDK" "$ANDROID_NDK_REV" "$OPENSSL_REL" c++_static JSON

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
