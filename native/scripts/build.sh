#!/usr/bin/env bash
# Builds libsippier_core for one target: OpenSSL, Opus, libg722, libre and
# baresip as static libraries, linked into one shared library. On macOS also
# WebRTC audio processing (with abseil) for echo cancellation; it needs Meson.
#
# Usage: build.sh <os> <arch> [min-version]
#   os           macos | android | windows
#   arch         arm64 | x64 | arm | ia32 (Dart architecture names)
#   min-version  macOS deployment target (default 12.0) or Android API
#                level (default 28); unused on Windows
#
# Android uses ANDROID_NDK_ROOT, else the newest NDK in the Android SDK.
# Windows runs in MSYS2's CLANGARM64 (arm64) or CLANG64 (x64) environment,
# which the build hook starts.
# Output: build/<os>-<arch>/lib/libsippier_core.{dylib,so}, sippier_core.dll
set -euo pipefail

OPENSSL_VERSION=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
OPUS_VERSION=1.6.1
OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
# Content identical to the v1.3 tag archive on gitlab.freedesktop.org
WAP_VERSION=1.3
WAP_SHA256=95552fc17faa0202133707bbb3727e8c2cf64d4266fe31bfdb2298d769c1db75
ABSL_DIR=abseil-cpp-20230125.1   # pinned by WAP's subprojects/abseil-cpp.wrap

TARGET_OS=${1:?usage: build.sh <os> <arch> [min-version]}
ARCH=${2:?usage: build.sh <os> <arch> [min-version]}
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TP="$ROOT/third_party"
OUT="$ROOT/build/$TARGET_OS-$ARCH"
PREFIX="$OUT/prefix"
SRC="$OUT/src"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

# Dart build hooks pass a reduced environment
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Only our own static libraries, never Homebrew's
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH

if [[ ! -f "$TP/baresip/CMakeLists.txt" ]]; then
  echo "third_party is empty, run: git submodule update --init" >&2
  exit 1
fi

case "$TARGET_OS-$ARCH" in
  macos-arm64)   OSSL_TARGET=darwin64-arm64-cc;  APPLE_ARCH=arm64;  MESON_CPU=aarch64 ;;
  macos-x64)     OSSL_TARGET=darwin64-x86_64-cc; APPLE_ARCH=x86_64; MESON_CPU=x86_64 ;;
  android-arm64) OSSL_TARGET=android-arm64;      ABI=arm64-v8a ;;
  android-arm)   OSSL_TARGET=android-arm;        ABI=armeabi-v7a ;;
  android-x64)   OSSL_TARGET=android-x86_64;     ABI=x86_64 ;;
  android-ia32)  OSSL_TARGET=android-x86;        ABI=x86 ;;
  windows-arm64) OSSL_TARGET=mingwarm64;         MSYS_ENV=CLANGARM64 ;;
  windows-x64)   OSSL_TARGET=mingw64;            MSYS_ENV=CLANG64 ;;
  *) echo "unsupported target: $TARGET_OS-$ARCH" >&2; exit 2 ;;
esac

if [[ $TARGET_OS == windows && ${MSYSTEM:-} != "$MSYS_ENV" ]]; then
  echo "windows-$ARCH builds in MSYS2's $MSYS_ENV environment" \
    "(MSYSTEM=$MSYS_ENV bash -l), not ${MSYSTEM:-plain bash}" >&2
  exit 2
fi

OPUS_FLAGS=()
CMAKE=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_PREFIX_PATH="$PREFIX"
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DOPENSSL_ROOT_DIR="$PREFIX"
  -DOPENSSL_USE_STATIC_LIBS=ON
)

if [[ $TARGET_OS == macos ]]; then
  MIN=${3:-12.0}
  # Xcode's build phase puts its toolchain's clang first on PATH, which,
  # unlike /usr/bin/clang, needs to be told the SDK (the hook drops SDKROOT)
  SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  export SDKROOT
  CMAKE+=(-DCMAKE_OSX_ARCHITECTURES=$APPLE_ARCH
          -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN")
  OSSL_FLAGS=(-mmacosx-version-min="$MIN")
  AUDIO_MODULE=audiounit
  LIB=libsippier_core.dylib
  # The audiounit module has no echo cancellation on macOS; sippier_core adds
  # it with WebRTC audio processing. A cross file also for the native arch: it
  # sets the deployment target and keeps x64 builds on arm64 hosts right.
  ECHO_CANCEL=yes
  MESON_ARGS="'-arch', '$APPLE_ARCH', '-mmacosx-version-min=$MIN'"
  MESON_CROSS_FILE="$OUT/meson-cross.ini"
  MESON_CROSS="[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'

[built-in options]
c_args = [$MESON_ARGS]
cpp_args = [$MESON_ARGS]
c_link_args = [$MESON_ARGS]
cpp_link_args = [$MESON_ARGS]

[host_machine]
system = 'darwin'
cpu_family = '$MESON_CPU'
cpu = '$MESON_CPU'
endian = 'little'"
elif [[ $TARGET_OS == windows ]]; then
  # MSYS2's clang for the environment's architecture, so no cross files.
  # The MinGW-w64 runtime and libc++ are linked statically (CMakeLists.txt),
  # so the DLL needs nothing next to it.
  # libre takes zlib (for crc32 only) when it finds one, and MSYS2's is a DLL
  CMAKE+=(-DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
          -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=ON)
  OSSL_FLAGS=()
  if [[ $ARCH == arm64 ]]; then
    OSSL_FLAGS=(--config="$ROOT/native/scripts/openssl-mingwarm64.conf" no-asm)
    # Opus presumes NEON only for "aarch64"; Windows says ARM64, and Opus
    # can't detect CPU features at runtime there with MinGW. As its autotools
    # build does: NEON presumed, the NEON functions declared, no detection.
    OPUS_FLAGS=(-DOPUS_MAY_HAVE_NEON=OFF -DOPUS_PRESUME_NEON=ON
                -DCMAKE_C_FLAGS=-DOPUS_ARM_MAY_HAVE_NEON_INTR)
  fi
  export CC=clang CXX=clang++
  AUDIO_MODULE=wasapi
  LIB=sippier_core.dll
  # wasapi has no echo cancellation; aec.c adds it as on macOS
  ECHO_CANCEL=yes
else
  API=${3:-28}
  SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  NDK="${ANDROID_NDK_ROOT:-$(ls -d "$SDK"/ndk/* | sort -V | tail -1)}"
  CMAKE+=(-DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
          -DANDROID_ABI=$ABI
          -DANDROID_PLATFORM=android-"$API"
          -DCMAKE_FIND_ROOT_PATH="$PREFIX")
  OSSL_FLAGS=(-D__ANDROID_API__="$API")
  export ANDROID_NDK_ROOT="$NDK"
  # OpenSSL's Configure looks for clang on PATH
  OSSL_PATH="$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/bin | head -1):$PATH"
  AUDIO_MODULE=aaudio
  LIB=libsippier_core.so
  # aaudio's VOICE_COMMUNICATION preset brings the platform's
  ECHO_CANCEL=no
fi

# Downloads a release tarball once (checksum verified), extracts it into $SRC.
# Download servers fail now and then (a 504, a dropped TLS connection), and
# release builds download everything afresh, so it tries again.
fetch() {
  local url=$1 sha=$2
  local tarball="$ROOT/build/downloads/${url##*/}"
  if [[ ! -f $tarball ]]; then
    mkdir -p "${tarball%/*}"
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors \
      --connect-timeout 30 "$url" -o "$tarball.$$"
    if ! echo "$sha  $tarball.$$" | shasum -a 256 -c --status; then
      rm -f "$tarball.$$"
      echo "checksum mismatch: $url" >&2
      exit 1
    fi
    mv "$tarball.$$" "$tarball"
  fi
  mkdir -p "$SRC"
  tar -xzf "$tarball" -C "$SRC"
}

cmake_build() { # <name> <source dir> [cmake args...]
  local name=$1 src=$2
  shift 2
  echo "==> $name"
  cmake -S "$src" -B "$OUT/$name" "${CMAKE[@]}" "$@"
  cmake --build "$OUT/$name"
  cmake --install "$OUT/$name"
}

if [[ ! -f $PREFIX/lib/libssl.a ]]; then
  echo "==> openssl"
  fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" \
    $OPENSSL_SHA256
  mkdir -p "$OUT/openssl"
  (
    cd "$OUT/openssl"
    [[ -n ${OSSL_PATH:-} ]] && export PATH="$OSSL_PATH"
    "$SRC/openssl-$OPENSSL_VERSION/Configure" $OSSL_TARGET \
      no-shared no-module no-tests no-docs \
      --prefix="$PREFIX" --libdir=lib ${OSSL_FLAGS[@]+"${OSSL_FLAGS[@]}"}
    make -j"$JOBS" build_libs
    make install_dev
  )
fi

# ${a[@]+"${a[@]}"} for arrays that may be empty: macOS's bash 3.2 (what
# Xcode's build phase finds) calls an empty array unbound under set -u
if [[ ! -f $PREFIX/lib/libopus.a ]]; then
  fetch "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" \
    $OPUS_SHA256
  cmake_build opus "$SRC/opus-$OPUS_VERSION" \
    -DBUILD_SHARED_LIBS=OFF -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF \
    ${OPUS_FLAGS[@]+"${OPUS_FLAGS[@]}"}
fi

# Meson fetches abseil as a subproject (hash-checked by its wrap file) but
# doesn't install it, so its static libraries and headers are copied over.
if [[ $ECHO_CANCEL == yes && ! -f $PREFIX/lib/libwebrtc-audio-processing-1.a ]]; then
  echo "==> webrtc-audio-processing"
  fetch "https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/webrtc-audio-processing-$WAP_VERSION.tar.gz" \
    $WAP_SHA256
  wap_src="$SRC/webrtc-audio-processing-$WAP_VERSION"
  wap_out="$OUT/webrtc-audio-processing"
  meson_cross=()
  if [[ -n ${MESON_CROSS_FILE:-} ]]; then
    echo "$MESON_CROSS" > "$MESON_CROSS_FILE"
    meson_cross=(--cross-file "$MESON_CROSS_FILE")
  fi
  rm -rf "$wap_out"
  meson setup "$wap_out" "$wap_src" ${meson_cross[@]+"${meson_cross[@]}"} \
    --prefix "$PREFIX" --libdir lib --buildtype release \
    -Ddefault_library=static
  meson compile -C "$wap_out"
  meson install -C "$wap_out"
  find "$wap_out/subprojects/$ABSL_DIR" -name 'libabsl_*.a' \
    -exec cp {} "$PREFIX/lib/" \;
  (cd "$wap_src/subprojects/$ABSL_DIR" &&
    find absl -name '*.h' -o -name '*.inc' | cpio -pdm "$PREFIX/include" 2>/dev/null)
fi

cmake_build libg722 "$TP/libg722" -DBUILD_SHARED_LIBS=OFF
# libg722 builds a shared library too; keep only the static one. On Windows
# it's libg722_static.a, next to the DLL's import library libg722.dll.a, and
# baresip looks for libg722.a.
rm -f "$PREFIX"/lib/libg722*.dylib "$PREFIX"/lib/libg722*.so* \
  "$PREFIX"/lib/libg722*.dll.a "$PREFIX"/bin/libg722*.dll
if [[ -f $PREFIX/lib/libg722_static.a ]]; then
  mv -f "$PREFIX/lib/libg722_static.a" "$PREFIX/lib/libg722.a"
fi

cmake_build re "$TP/re" \
  -DLIBRE_BUILD_SHARED=OFF -DLIBRE_BUILD_STATIC=ON \
  -DUSE_BFCP=OFF -DUSE_PCP=OFF -DUSE_RTMP=OFF

# baresip with our patches, as a copy so the submodule stays clean.
# Refreshed when the pinned commit or a patch changes.
key="$(git -C "$TP/baresip" rev-parse HEAD) $(cat "$ROOT"/native/patches/baresip-*.patch | shasum -a 256)"
if [[ "$(cat "$SRC/baresip/.sippier-key" 2>/dev/null)" != "$key" ]]; then
  rm -rf "$SRC/baresip"
  mkdir -p "$SRC/baresip"
  git -C "$TP/baresip" archive HEAD | tar -x -C "$SRC/baresip"
  for p in "$ROOT"/native/patches/baresip-*.patch; do
    patch -s -d "$SRC/baresip" -p1 < "$p"
  done
  echo "$key" > "$SRC/baresip/.sippier-key"
fi
# Not baresip's webrtc_aec filter: sippier_core cancels echo at the audio
# device itself (aec.c) with the library built above
cmake_build baresip "$SRC/baresip" \
  -DSTATIC=ON \
  -DMODULES="g711;libg722;opus;srtp;$AUDIO_MODULE;stun;turn;ice" \
  -DLIBG722_HINTS="$PREFIX" \
  -DRE_INCLUDE_DIR="$PREFIX/include/re" -DRE_LIBRARY="$PREFIX/lib/libre.a"

echo "==> sippier_core"
cmake -S "$ROOT/native/sippier_core" -B "$OUT/sippier_core" "${CMAKE[@]}"
cmake --build "$OUT/sippier_core"
mkdir -p "$OUT/lib"
# Replace instead of overwriting in place: macOS kills processes whose
# loaded code signature changes under the same inode.
rm -f "$OUT/lib/$LIB"
cp "$OUT/sippier_core/$LIB" "$OUT/lib/"

echo "Built $OUT/lib/$LIB"
