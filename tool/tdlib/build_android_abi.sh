#!/usr/bin/env bash
# Build libtdjson.so for one Android ABI using official tdlib/td sources.
# Prerequisites: ANDROID_NDK_HOME (r26b), CMake 3.10+, checkout of td at TD_VERSION.json pin.
#
# For Android, TDLib CMake requires OpenSSL built for the target ABI. Prefer the
# upstream scripts in td/example/android (build-openssl.sh + build-tdlib.sh JSON),
# or set OPENSSL_ROOT_DIR to a path shaped like td's third-party/openssl/<ABI>/
# (lib/libcrypto.a, include/openssl/, ...).
#
# Usage:
#   export ANDROID_NDK_HOME=/opt/android-ndk
#   export TD_SRC=/path/to/td
#   export ABI=arm64-v8a
#   bash tool/tdlib/build_android_abi.sh
set -euo pipefail
ABI="${ABI:-arm64-v8a}"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME}"
: "${TD_SRC:?Set TD_SRC to tdlib/td checkout}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${OUT:-$ROOT/android/app/src/main/jniLibs/$ABI}"
mkdir -p "$OUT/build-$ABI"
CMAKE_EXTRA=()
if [[ -n "${OPENSSL_ROOT_DIR:-}" ]]; then
  CMAKE_EXTRA+=(-DOPENSSL_ROOT_DIR="$OPENSSL_ROOT_DIR")
fi
cmake -S "$TD_SRC" -B "$OUT/build-$ABI" \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ABI" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  "${CMAKE_EXTRA[@]}"
cmake --build "$OUT/build-$ABI" --target tdjson -j"$(nproc 2>/dev/null || echo 4)"
cp -f "$OUT/build-$ABI/tdjson/libtdjson.so" "$OUT/libtdjson.so"
echo "Built $OUT/libtdjson.so"
