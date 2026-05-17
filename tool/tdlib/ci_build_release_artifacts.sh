#!/usr/bin/env bash
# Build Android libtdjson.so (4 ABIs) + pack example/web dist for GitHub Releases.
# Intended to run *inside* tool/tdlib/Dockerfile image with this repo mounted at /workspace.
#
# Android: upstream example/android/build-openssl.sh + build-tdlib.sh (JSON).
# Web: upstream example/web scripts (requires Emscripten; sourced immediately before web).
# Skip whole Android or whole Web phase when final artifacts already exist (host Actions cache).
set -euo pipefail

WORKSPACE_INPUT="${1:-/workspace}"
WORKSPACE="$(cd "$WORKSPACE_INPUT" && pwd -P)"
cd "$WORKSPACE"

MIN_SO_BYTES="${MIN_SO_BYTES:-4096}"
MIN_WEB_TGZ_BYTES="${MIN_WEB_TGZ_BYTES:-1024}"

TD_VER="$(python3 -c "import json; print(json.load(open('tool/tdlib/TD_VERSION.json'))['commit_sha'])")"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk}"
ANDROID_NDK_REV="${ANDROID_NDK_REV:-26.1.10909125}"

TD_SRC="/tmp/tdlib-src"
rm -rf "$TD_SRC"
mkdir -p "$TD_SRC"
cd "$TD_SRC"
git init
git remote add origin https://github.com/tdlib/td.git
git fetch --depth 1 origin "$TD_VER"
git checkout FETCH_HEAD

# --- Android -----------------------------------------------------------------
FAKE_SDK="/opt/android-sdk"
mkdir -p "$FAKE_SDK/ndk"
ln -sfn "$ANDROID_NDK_HOME" "$FAKE_SDK/ndk/${ANDROID_NDK_REV}"

ANDROID_EXAMPLE="$TD_SRC/example/android"
chmod +x "$ANDROID_EXAMPLE"/*.sh 2>/dev/null || true

ANDROID_CACHE_HIT=true
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  dest_so="$WORKSPACE/build/artifacts/android/$abi/libtdjson.so"
  if [[ ! -f "$dest_so" ]]; then
    ANDROID_CACHE_HIT=false
    break
  fi
  sz=$(wc -c <"$dest_so")
  if [[ "$sz" -lt "$MIN_SO_BYTES" ]]; then
    ANDROID_CACHE_HIT=false
    break
  fi
done

mkdir -p "$WORKSPACE/build/artifacts/android"

if [[ "$ANDROID_CACHE_HIT" == true ]]; then
  echo "[Cache Hit] Skipping Android OpenSSL+TDLib build (all libtdjson.so present under ${WORKSPACE}/build/artifacts/android/)"
else
  cd "$ANDROID_EXAMPLE"
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
fi

# --- Web (Emscripten must match TD example/web check; do not source emsdk before Android NDK builds) ---
WEB_TGZ="$WORKSPACE/build/artifacts/web/dist.tar.gz"
mkdir -p "$WORKSPACE/build/artifacts/web"

WEB_CACHE_HIT=false
if [[ -f "$WEB_TGZ" ]]; then
  wsz=$(wc -c <"$WEB_TGZ")
  if [[ "$wsz" -ge "$MIN_WEB_TGZ_BYTES" ]]; then
    WEB_CACHE_HIT=true
  fi
fi

if [[ "$WEB_CACHE_HIT" == true ]]; then
  echo "[Cache Hit] Skipping Web TDLib build (${WEB_TGZ} present)"
else
  # shellcheck disable=SC1091
  source /opt/emsdk/emsdk_env.sh
  echo "[ci] emcc for Web build:"
  emcc --version

  cd "$TD_SRC/example/web"
  chmod +x ./*.sh 2>/dev/null || true
  ./build-openssl.sh
  ./build-tdlib.sh
  ./copy-tdlib.sh
  ./build-tdweb.sh

  if [[ -d tdweb/dist ]]; then
    tar -czf "$WEB_TGZ" -C tdweb dist
  elif [[ -d dist ]]; then
    tar -czf "$WEB_TGZ" dist
  else
    echo "::error::Expected tdweb/dist or dist under example/web after build-tdweb.sh"
    ls -la
    exit 1
  fi
fi

echo "[ci_build_release_artifacts] OK — Android .so x4 + web/dist.tar.gz"
