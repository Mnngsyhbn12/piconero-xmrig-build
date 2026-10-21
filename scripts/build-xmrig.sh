#!/usr/bin/env bash
#
# Piconero — reproducible XMRig build for Android/arm64-v8a.
#
#   XMRig v6.26.0   commit b2ca72480c58d197e18c885d9fc1a0c8d517e60a   (pinned, never master)
#   libuv 1.51.0    the version XMRig's own scripts/build.uv.sh pins
#
# GPLv3: XMRig source is NOT modified by this script. See "Why the stub
# archives exist" below — the Android link fix is done with linker search
# paths, not a patch, so there is nothing to publish as a diff. If anyone
# later edits XMRig, the diff MUST land in the public piconero-xmrig-build
# repo (README §GPL obligations).
#
# Usage (Git Bash on this machine):
#   export ANDROID_HOME="$HOME/AppData/Local/Android/Sdk"
#   bash scripts/build-xmrig.sh
#
# Prereqs, all already installed here: NDK 28.2.13676358, SDK CMake 3.22.1
# (its bin/ also ships ninja.exe), curl, tar, coreutils (sha256sum).
set -euo pipefail

XMRIG_TAG=v6.26.0
XMRIG_VER=${XMRIG_TAG#v}          # GitHub strips the leading "v" in the tarball root:
XMRIG_SRC=xmrig-${XMRIG_VER}      # archive unpacks to xmrig-6.26.0/, not xmrig-v6.26.0/
XMRIG_COMMIT=b2ca72480c58d197e18c885d9fc1a0c8d517e60a
XMRIG_URL=https://github.com/xmrig/xmrig/archive/refs/tags/${XMRIG_TAG}.tar.gz
# Recorded from the official tag archive (GitHub regenerates tarballs on every
# request, so these pins are only valid for THIS download; re-record deliberately
# and say so in the public repo if GitHub ever changes them).
XMRIG_SHA256=5005144e78571f26586410c2b2ede2b0c72afe22f97f1708ea24cfb253c3939b

UV_VERSION=1.51.0
UV_URL=https://dist.libuv.org/dist/v${UV_VERSION}/libuv-v${UV_VERSION}.tar.gz
UV_SHA256=5f0557b90b1106de71951a3c3931de5e0430d78da1d9a10287ebc7a3f78ef8eb

ANDROID_ABI=arm64-v8a
ANDROID_PLATFORM=android-26      # == minSdk 26 (clock_gettime/pthread live in libc here)

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/AppData/Local/Android/Sdk}}"
NDK="$SDK/ndk/28.2.13676358"
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
LLVM="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin"
CMAKE="$SDK/cmake/3.22.1/bin/cmake.exe"
NINJA="$SDK/cmake/3.22.1/bin/ninja.exe"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$REPO_ROOT/build/xmrig"
DEPS="$WORK/deps"
OUT_LIB="$REPO_ROOT/android/app/src/main/jniLibs/arm64-v8a/libxmrig.so"

# Every path below crosses from MSYS to a Windows-native compiler, and MSYS
# silently rewrites /c/... into something clang cannot read. cygpath -w is
# mandatory, not cosmetic.
w() { cygpath -w "$1"; }

for t in "$TOOLCHAIN" "$LLVM/clang.exe" "$LLVM/llvm-ar.exe" "$LLVM/llvm-strip.exe" "$CMAKE" "$NINJA"; do
    [ -e "$t" ] || { echo "MISSING: $t" >&2; exit 1; }
done

mkdir -p "$WORK" "$DEPS/include" "$DEPS/lib"
cd "$WORK"

# ---------------------------------------------------------------- fetch ----
check_sha() { # <file> <expected> — a build you cannot trust the inputs of is not reproducible
    echo "$2  $1" | sha256sum -c --status - || {
        echo "ERROR: $1 does not match its pinned sha256 ($2)" >&2
        echo "       got: $(sha256sum "$1" | cut -d' ' -f1)" >&2
        exit 1
    }
    echo "==> sha256 OK: $1"
}

if [ ! -d "$XMRIG_SRC" ]; then
    echo "==> downloading XMRig ${XMRIG_TAG}"
    curl -sSL --retry 3 -o xmrig.tar.gz "$XMRIG_URL"
    check_sha xmrig.tar.gz "$XMRIG_SHA256"
    tar xzf xmrig.tar.gz
fi
# The build would otherwise silently use whatever tree is sitting in build/.
grep -q "define APP_VERSION   \"${XMRIG_VER}\"" "$XMRIG_SRC/src/version.h" || {
    echo "ERROR: $XMRIG_SRC/src/version.h is not ${XMRIG_VER} -- refusing to build an unpinned tree" >&2
    exit 1
}
[ -f "$XMRIG_SRC/LICENSE" ] || { echo "ERROR: GPLv3 LICENSE missing upstream" >&2; exit 1; }
echo "==> verified pinned source tree: XMRig ${XMRIG_VER}"

if [ ! -d libuv-v${UV_VERSION} ]; then
    echo "==> downloading libuv ${UV_VERSION}"
    curl -sSL --retry 3 -o libuv.tar.gz "$UV_URL"
    check_sha libuv.tar.gz "$UV_SHA256"
    tar xzf libuv.tar.gz
fi

# ------------------------------------------------------------- build uv ----
# XMRig's own scripts/build.uv.sh uses autotools, which does not exist on this
# host and cannot target Android anyway. libuv ships a CMake build, so we drive
# it with the same NDK toolchain and drop the artifact into $DEPS.
echo "==> building libuv ${UV_VERSION} for ${ANDROID_ABI}"
"$CMAKE" -S libuv-v${UV_VERSION} -B build-uv -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$(w "$TOOLCHAIN")" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
    -DANDROID_STL=c++_static \
    -DBUILD_SHARED_LIBS=OFF \
    -DLIBUV_BUILD_SHARED=OFF \
    -DBUILD_TESTING=OFF \
    -DLIBUV_BUILD_TESTS=OFF \
    -DLIBUV_BUILD_BENCH=OFF \
    -DCMAKE_MAKE_PROGRAM="$(w "$NINJA")"
"$CMAKE" --build build-uv --config Release
cp -fr libuv-v${UV_VERSION}/include/* "$DEPS/include/"
find build-uv -name 'libuv.a' -exec cp -f {} "$DEPS/lib/" \;

# ------------------------------------- Why the stub archives exist ---------
# XMRig's root CMakeLists hardcodes, for Android only:
#     set(EXTRA_LIBS pthread rt dl log)
# The NDK sysroot has liblog.so and libdl.so, but there is NO librt and NO
# libpthread anywhere: on Android both were folded into libc long ago. So the
# link dies with "cannot find -lpthread / -lrt".
#
# Two ways out. (a) patch that line and publish the patch under GPLv3. (b) put
# two empty archives on the linker search path so -lpthread/-lrt resolve and
# every symbol still comes from libc. (b) needs zero source changes, keeps the
# upstream tree byte-identical, and is what we ship.
echo "==> writing pthread/rt link stubs (no XMRig source modification)"
printf '/* empty: symbols resolve from Bionic libc */\n' > "$WORK/stub.c"
"$LLVM/clang.exe" --target=aarch64-linux-android26 -c "$(w "$WORK/stub.c")" -o "$(w "$WORK/stub.o")"
for name in libpthread.a librt.a; do
    rm -f "$DEPS/lib/$name"
    "$LLVM/llvm-ar.exe" rcs "$(w "$DEPS/lib/$name")" "$(w "$WORK/stub.o")"
done

# ---------------------------------------------------------- build xmrig ----
# Flags chosen for a phone, each one for a reason:
#   WITH_HWLOC OFF   topology/NUMA is meaningless on Android and hwloc needs autotools
#   WITH_TLS   OFF   no OpenSSL-for-Android prerequisite (see KNOWN GAP below)
#   WITH_ASM   OFF   x86 asm only; avoids a nasm/yasm build-time dependency
#   WITH_OPENCL/CUDA/NVML/ADL OFF  no desktop GPU backends on a phone
#   WITH_KAWPOW/GHOSTRIDER/CN_* OFF  Monero is RandomX; smaller binary
#   WITH_BENCHMARK ON  required for the M1 exec proof (--bench=1M on device)
#   WITH_HTTP    ON  the localhost control API the app talks to
#   WITH_MSR/SSE4_1/AVX2/VAES are force-disabled by cmake/{randomx,cpu}.cmake on
#   aarch64, so we do not fight them.
# NOTE XMRig's cmake/randomx.cmake hardcodes `set(WITH_ARGON2 ON)`; argon2 is
# vendored in-tree, so it compiles regardless of what we pass.
echo "==> configuring XMRig ${XMRIG_TAG}"
# Upstream bug in v6.26.0, only reachable with THIS combination (Clang +
# CMAKE_BUILD_TYPE=Release + non-WIN32 + WITH_TLS=OFF): cmake/OpenSSL.cmake:64
# renames CMAKE_PROJECT_NAME to "xmrig-notls", so add_executable() at :239
# creates target "xmrig-notls", but the POST_BUILD strip at :255 still refers to
# ${PROJECT_NAME} ("xmrig") -> configure dies with "No TARGET 'xmrig'".
#
# We do not patch it (GPL diff) and we do not lose -Ofast: XMRig puts -Ofast in
# CMAKE_CXX_FLAGS_RELEASE only, and leaves RELWITHDEBINFO alone for Clang. So we
# build as RelWithDebInfo (skipping the buggy strip block, which we do ourselves
# with llvm-strip anyway) and put the Release optimization level back by hand.
#
# Reproducibility flags, all four needed to make a third party's rebuild match
# ours byte for byte (verified: two clean clones in different directories, built
# minutes apart, cmp gives no differences):
#   -g0                 no DWARF. We strip it anyway; leaving it in would let the
#                       absolute clone path reach the linker's build-id.
#   -D__DATE__ shim     XMRig's version banner (src/base/kernel/Entry.cpp:52)
#                       concatenates __DATE__, so a build one day later produced a
#                       different binary. Force-including a header that redefines
#                       the macro is a compiler flag, not a source patch.
#   --build-id=none     lld seeds the 20-byte .note.gnu.build-id with its own
#                       output path, which is the last path-dependent byte left.
#                       The APK ships a stripped library and no symbol package, so
#                       there is nothing for a build-id to match against.
#   -Wno-builtin-macro-redefined  keeps the shim above warning-free.
REDACT_HEADER="$REPO_ROOT/scripts/reproducible/redact-date.h"
[ -r "$REDACT_HEADER" ] || { echo "MISSING: $REDACT_HEADER" >&2; exit 1; }
"$CMAKE" -S "$XMRIG_SRC" -B build-xmrig -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_FLAGS_RELWITHDEBINFO="-Ofast -g0 -DNDEBUG -Wno-builtin-macro-redefined -include \"$(w "$REDACT_HEADER")\"" \
    -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-Ofast -g0 -DNDEBUG -Wno-builtin-macro-redefined -include \"$(w "$REDACT_HEADER")\"" \
    -DCMAKE_TOOLCHAIN_FILE="$(w "$TOOLCHAIN")" \
    -DANDROID_ABI="$ANDROID_ABI" \
    -DANDROID_PLATFORM="$ANDROID_PLATFORM" \
    -DANDROID_STL=c++_static \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DBUILD_STATIC=OFF \
    -DXMRIG_DEPS="$(w "$DEPS")" \
    -DCMAKE_MAKE_PROGRAM="$(w "$NINJA")" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$(w "$DEPS/lib") -Wl,-z,max-page-size=16384 -Wl,--build-id=none" \
    -DWITH_HWLOC=OFF \
    -DWITH_TLS=OFF \
    -DWITH_ASM=OFF \
    -DWITH_OPENCL=OFF \
    -DWITH_CUDA=OFF \
    -DWITH_NVML=OFF \
    -DWITH_ADL=OFF \
    -DWITH_KAWPOW=OFF \
    -DWITH_GHOSTRIDER=OFF \
    -DWITH_CN_LITE=OFF \
    -DWITH_CN_HEAVY=OFF \
    -DWITH_CN_PICO=OFF \
    -DWITH_CN_FEMTO=OFF \
    -DWITH_MSR=OFF \
    -DWITH_DMI=OFF \
    -DWITH_ENV_VARS=OFF \
    -DWITH_EMBEDDED_CONFIG=OFF \
    -DWITH_DEBUG_LOG=OFF \
    -DWITH_PROFILING=OFF \
    -DWITH_SECURE_JIT=OFF \
    -DWITH_HTTP=ON \
    -DWITH_BENCHMARK=ON \
    -DWITH_RANDOMX=ON

echo "==> building XMRig"
"$CMAKE" --build build-xmrig --config Release -j 2

# ----------------------------------------------------------- install -------
# NDK clang emits a PIE executable; renaming it to libxmrig.so is deliberate:
# Android only extracts lib*.so from jniLibs into nativeLibraryDir, and that
# directory is the one place an app-owned file stays exec-able at every API
# level (exec'ing from filesDir is blocked by W^X on Android 10+).
# WITH_TLS=OFF makes upstream name the target "xmrig-notls" (see the note at
# the configure step), so accept either spelling.
BIN=$(find build-xmrig -maxdepth 1 -type f \( -name 'xmrig' -o -name 'xmrig.exe' -o -name 'xmrig-notls' -o -name 'xmrig-notls.exe' \) | head -1)
[ -n "$BIN" ] || { echo "build produced no xmrig binary" >&2; exit 1; }

mkdir -p "$(dirname "$OUT_LIB")"
"$LLVM/llvm-strip.exe" -s "$(w "$BIN")" -o "$(w "$OUT_LIB")"

SIZE=$(stat -c%s "$OUT_LIB")
SHA=$(sha256sum "$OUT_LIB" | cut -d' ' -f1)

mkdir -p "$REPO_ROOT/licenses"
cat > "$REPO_ROOT/licenses/xmrig-build-info.json" <<EOF
{
  "project": "XMRig",
  "upstream": "https://github.com/xmrig/xmrig",
  "tag": "${XMRIG_TAG}",
  "commit": "${XMRIG_COMMIT}",
  "license": "GPLv3",
  "sourceModified": false,
  "ndk": "28.2.13676358",
  "cmake": "3.22.1",
  "androidAbi": "${ANDROID_ABI}",
  "androidPlatform": "${ANDROID_PLATFORM}",
  "androidStl": "c++_static",
  "dependency": { "libuv": "${UV_VERSION}", "static": true },
  "linkStubs": ["libpthread.a", "librt.a"],
  "donateLevel": "1 (kMinimumDonateLevel=1 in src/donate.h; Pools::setDonateLevel rejects 0, so upstream always donates ~1%)",
  "strippedBytes": ${SIZE},
  "strippedSha256": "${SHA}",
  "reproduce": "bash scripts/build-xmrig.sh"
}
EOF

# The Lisensi & Open Source screen reads its provenance out of the APK instead of
# a hand-typed Kotlin constant, so the legal notice can never drift from the
# binary that is actually shipped. Absent when building from the standalone
# piconero-xmrig-build repo, which contains no app.
if [ -d "$REPO_ROOT/android/app/src/main/assets" ]; then
    cp "$REPO_ROOT/licenses/xmrig-build-info.json" "$REPO_ROOT/android/app/src/main/assets/xmrig-build-info.json"
    echo "==> refreshed android/app/src/main/assets/xmrig-build-info.json"
else
    echo "==> no app assets dir: provenance written to licenses/ only"
fi

echo
echo "==> $OUT_LIB"
echo "    $(numfmt --to=iec "$SIZE")  sha256=$SHA"
echo
echo "Exec proof after install. applicationIdSuffix=\".debug\" appends to the full"
echo "applicationId, so the debug package is com.piconero.app.debug:"
echo "  adb shell pm path com.piconero.app.debug"
echo "    # prints /data/app/~~<H>/com.piconero.app.debug-<H>/base.apk"
echo "    # nativeLibraryDir is that same directory + /lib/arm64"
echo "  adb shell run-as com.piconero.app.debug <nativeLibraryDir>/libxmrig.so --version"
# --benchmark does not exist; the real flag is --bench=N with N from 1M to 10M
# (read off the binary's own --help on device, 2026-10-20).
echo "  adb shell run-as com.piconero.app.debug <nativeLibraryDir>/libxmrig.so --bench=1M --no-color --print-time=10"
