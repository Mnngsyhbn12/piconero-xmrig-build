# piconero-xmrig-build

Reproducible Android build of **XMRig v6.26.0** used by the
**Piconero** Monero mining app. Piconero ships XMRig as a
**separate child process**, so the GPLv3 obligations attach to XMRig and this
repository — not to Piconero's Kotlin app or backend, which are aggregated with
it rather than derived from it.

This repo is the complete corresponding source for the binary inside
`libxmrig.so` in the Piconero APK: the pinned upstream tag, the build script,
the exact flags, and the record of every deliberate deviation.

## Pinned source — nothing is "latest master"

| item | value |
| --- | --- |
| upstream | https://github.com/xmrig/xmrig |
| tag | `v6.26.0` |
| commit | `b2ca72480c58d197e18c885d9fc1a0c8d517e60a` |
| tarball SHA-256 | `5005144e78571f26586410c2b2ede2b0c72afe22f97f1708ea24cfb253c3939b` |
| license | GNU GPL v3.0 (`LICENSE`, verbatim) |
| source modified? | **No** — how that was checked: extract `xmrig.tar.gz` with `tar -xzf` into a clean directory and `diff -rq` it against the tree the build actually used. 1012 files, zero content differences. Two `scripts/*.cmd` examples cannot be opened under MSYS in *both* trees, so they are neither compared nor claimed. |

The build script refuses to run unless `src/version.h` says `6.26.0` and the
downloaded tarball matches the SHA-256 above.

## Build environment

| item | value |
| --- | --- |
| Android NDK | `28.2.13676358` (clang/LLVM 19.0.1) |
| CMake + Ninja | `3.22.1` (SDK-bundled, `bin/`) |
| ABI | `arm64-v8a` |
| API level | `android-26` (== Piconero `minSdk`) |
| C++ STL | `c++_static` (static, so no libc++ shared runtime is needed) |
| libuv | 1.51.0 from https://dist.libuv.org/dist/v1.51.0/libuv-v1.51.0.tar.gz, static, built by the same script — tarball SHA-256 `5f0557b90b1106de71951a3c3931de5e0430d78da1d9a10287ebc7a3f78ef8eb` |

## Reproduce it

```sh
# Windows: Git Bash. Linux: any bash. Set ANDROID_HOME to your SDK.
export ANDROID_HOME="$HOME/AppData/Local/Android/Sdk"
bash scripts/build-xmrig.sh
```

Expected output line:

```
==> android/app/src/main/jniLibs/arm64-v8a/libxmrig.so
    1.6M  sha256=1fa2701cc5c3512f5e71aaa21057ab003ba1651f5227c491a668f803d4f82abf
```

Verify your build matches the binary Piconero ships:

```sh
sha256sum android/app/src/main/jniLibs/arm64-v8a/libxmrig.so
# must print 1fa2701cc5c3512f5e71aaa21057ab003ba1651f5227c491a668f803d4f82abf
```

A different hash does not automatically mean the build is wrong — clang versions
and NDK point releases change bytes — but it does mean you should re-run with the
exact NDK above before trusting it.

This build is reproducible by construction: two clean clones of this repository,
in two different directories, produce the same bytes. Verified here before
publishing:

```sh
cmp clone-A/android/app/src/main/jniLibs/arm64-v8a/libxmrig.so \
    clone-B/android/app/src/main/jniLibs/arm64-v8a/libxmrig.so   # no output, exit 0
```

The `--version` banner of the shipped library prints `built on redacted` rather
than a compile date, for the same reason: an embedded `__DATE__` made every
day's build differ. See deviation 4 below.

## Exact CMake configure command

Nothing is hidden. This is what runs, verbatim:

```sh
cmake -S xmrig-6.26.0 -B build-xmrig -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_FLAGS_RELWITHDEBINFO="-Ofast -g0 -DNDEBUG -Wno-builtin-macro-redefined -include scripts/reproducible/redact-date.h" \
    -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-Ofast -g0 -DNDEBUG -Wno-builtin-macro-redefined -include scripts/reproducible/redact-date.h" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-26 \
    -DANDROID_STL=c++_static \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DBUILD_STATIC=OFF \
    -DXMRIG_DEPS="$WORK/deps" \
    -DCMAKE_MAKE_PROGRAM="$SDK/cmake/3.22.1/bin/ninja.exe" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$WORK/deps/lib -Wl,-z,max-page-size=16384 -Wl,--build-id=none" \
    -DWITH_HWLOC=OFF -DWITH_TLS=OFF -DWITH_ASM=OFF \
    -DWITH_OPENCL=OFF -DWITH_CUDA=OFF -DWITH_NVML=OFF -DWITH_ADL=OFF \
    -DWITH_KAWPOW=OFF -DWITH_GHOSTRIDER=OFF \
    -DWITH_CN_LITE=OFF -DWITH_CN_HEAVY=OFF -DWITH_CN_PICO=OFF -DWITH_CN_FEMTO=OFF \
    -DWITH_MSR=OFF -DWITH_DMI=OFF \
    -DWITH_BENCHMARK=ON -DWITH_HTTP=ON
```

libuv is built first, with the same toolchain, and handed to XMRig through
`-DXMRIG_DEPS=` (`cmake/FindUV.cmake` reads that cache variable):

```sh
cmake -S libuv-v1.51.0 -B build-uv -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=... \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static \
    -DBUILD_SHARED_LIBS=OFF -DLIBUV_BUILD_SHARED=OFF \
    -DBUILD_TESTING=OFF -DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF
```

## The deliberate deviations, all build-level, zero source edits

1. **Empty `libpthread.a` / `librt.a` on the linker path.** XMRig's
   `CMakeLists.txt` hardcodes `set(EXTRA_LIBS pthread rt dl log)` for Android,
   but the NDK sysroot has no `librt` and no `libpthread`: Bionic folded both
   into `libc` long ago, so the link dies on `cannot find -lpthread`. The option
   was to patch that line and publish the patch, or drop two empty archives on
   `-L` so the flags resolve while every symbol still comes from `libc`. We chose
   the archives: the source tree stays byte-identical to upstream.
2. **`RelWithDebInfo` instead of `Release`.** With Clang + non-WIN32 +
   `WITH_TLS=OFF`, upstream `cmake/OpenSSL.cmake` renames the project to
   `xmrig-notls`, so its own `POST_BUILD` strip step refers to a target that does
   not exist and configure fails. We avoid touching the file, restore the Release
   optimization level by hand (`-Ofast -g0 -DNDEBUG`, see deviation 4 for `-g0`),
   and strip ourselves with `llvm-strip`.
3. **`-DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF`.** `libuv/test/runner.c`
   calls `android_fdsan_set_error_level()`, which only exists from API 30, so the
   test runner cannot compile against `android-26`. `libuv.a` itself is fine; the
   fix is to disable the target, never to patch libuv.
4. **Reproducibility flags: `-g0`, `scripts/reproducible/redact-date.h`,
   `-Wl,--build-id=none`.** Without them the same commit builds a different binary
   every day and every clone directory, which would make "rebuild it and check our
   hash" an empty promise:
   - `src/base/kernel/Entry.cpp:52` concatenates `__DATE__` into the version
     banner. `redact-date.h` is force-included and redefines that builtin to
     `"redacted"` — a compiler flag, not an edit of XMRig's files.
   - `-g0`: debug info carries the absolute clone path. We strip it from the
     artifact anyway, so it only ever leaked the path into the linker's hash.
   - `--build-id=none`: lld seeds `.note.gnu.build-id` partly from its own output
     path, the last path-dependent bytes left. The APK ships a stripped library
     with no symbol package, so a build-id has nothing to match against.
   These are why the same source, same NDK and same flags give you byte-for-byte
   what we ship, and why `--version` says `built on redacted`.

`patches/` is empty because there is nothing to apply. If a future Piconero
build edits XMRig, the diff must land in `patches/` before that APK ships.

## donate-level: disclosed, not silently disabled

`src/donate.h` sets `kMinimumDonateLevel = 1` and `Pools::setDonateLevel()`
accepts only 1..99, so `--donate-level=0` is dropped without warning and the
effective value is **1**: roughly 1% of the miner's time goes to the XMRig
authors' development pool, every ~100 minutes, for one minute. Piconero keeps
that default and states it in the app's "Lisensi & Open Source" screen, in the
same place it states its own fee. We deliberately did not use
`donate-over-proxy` to make donation skip when pointed at our own pool: that
would defeat the mechanism the authors rely on to fund their work.

## Third-party licenses inside `libxmrig.so`

| component | license | in this binary |
| --- | --- | --- |
| XMRig v6.26.0 | GPL-3.0 | yes |
| RandomX (vendored `src/crypto/randomx`) | MIT | yes |
| libuv 1.51.0 | MIT (+ ISC/BSD for Joyent-era parts) | yes |
| Argon2 (`src/3rdparty/argon2`) | MIT | yes — forced ON by `cmake/randomx.cmake` |
| epee | BSD-3-Clause | yes |
| {fmt} | MIT | yes |
| RapidJSON | MIT | yes |
| llhttp | MIT | yes |
| BLAKE2 AVX2 (`randomx/blake2/avx2`) | CC0-1.0 | yes |
| hwloc | BSD-3-Clause | no — `WITH_HWLOC=OFF` |
| OpenSSL | Apache-2.0 | no — `WITH_TLS=OFF` |
| OpenCL headers (Khronos) | Khronos MIT-style | no — `WITH_OPENCL=OFF` |
| WinRing0 | BSD-3-Clause | no — Windows only |
| getopt (mingw-w64) | ISC-style | no — Bionic provides getopt |

Provenance of the exact binary this script produced is recorded in
`xmrig-build-info.json` (`1 (kMinimumDonateLevel=1 in src/donate.h; Pools::setDonateLevel rejects 0, so upstream always donates ~1%)`).

## How XMRig is used

Piconero launches `arm64-v8a/libxmrig.so` with `--config=<filesDir>/xmrig/config.json`
and talks to its HTTP API on `127.0.0.1` only, with a per-launch random port and
bearer token. The wallet address Piconero mines to is a **view-only** subaddress
held by the backend; no private key or seed is ever placed on the device.

Stratum is currently **unencrypted** (`WITH_TLS=OFF`): no key material crosses
that link, but the worker name and hashrate do. Enabling TLS is on the roadmap
with the production pool endpoint.
