/* Build-time determinism shim, force-included by scripts/build-xmrig.sh.
 *
 * XMRig's version banner (src/base/kernel/Entry.cpp:52) concatenates the
 * compiler-provided __DATE__, so two builds of the same commit produced two
 * different binaries purely because they ran on different days. Redefining the
 * macro here is a compiler flag, not an edit of XMRig's source, which keeps the
 * published source byte-for-byte upstream.
 *
 * The banner then reads "built on redacted". Cost: `--version` no longer says
 * when your copy was compiled; the build date lives in xmrig-build-info.json
 * instead. The redefinition warning is silenced with
 * -Wno-builtin-macro-redefined.
 */
#define __DATE__ "redacted"
