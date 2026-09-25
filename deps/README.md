# Static dependency recipes (AROS x86_64)

Pinned, patched, static-only builds of C/C++ libraries that Skia m154,
WebKit 2.54 and other AROS ports need but the AROS SDK does not provide
(or provides only as shared-library stubs).

| Recipe | Version | Libraries | Build | Patches |
|---|---|---|---|---|
| `harfbuzz` | 14.5.0 | `libharfbuzz.a` (+ `libharfbuzz-icu.a` with `HB_WITH_ICU=ON`) | CMake | none |
| `libjpeg-turbo` | 3.2.0 | `libjpeg.a` (libjpeg v6b API, SIMD) | CMake + NASM | none |
| `libwebp` | 1.6.0 | `libwebp.a`, `libwebpdecoder.a`, `libwebpdemux.a`, `libwebpmux.a`, `libsharpyuv.a` | CMake | 2 |

Each `deps/<name>/` holds `recipe.env` (version, URL, SHA-256, CMake
options with the reason for each non-default), `patches/series` +
`patches/*.patch` (same header format as `patches/skia-m154/`), and `check/`
(small programs that must link through collect-aros and, later, write
`pass=1` on AROS).

## Commands

```sh
scripts/deps/build.sh                 # fetch + verify + patch + build + install, all recipes
scripts/deps/build.sh libwebp         # one recipe
scripts/deps/check.sh                 # host checks: nm symbols, .pc files, links, CMake packages
HB_WITH_ICU=ON scripts/deps/build.sh harfbuzz   # optional ICU 61 integration
```

`fetch.sh` downloads into `upstream/deps/`, refuses a tarball whose
SHA-256 differs from the recipe, and unpacks + patches into
`work/deps/<srcdir>/` (regenerated when the tarball or series changes).
`build.sh` builds in `build/deps/<target>/<name>/` and installs into
`staging/deps/<target>/` (`include/`, `lib/`, `lib/pkgconfig/`,
`lib/cmake/`, `share/WebP/cmake/`). `check.sh` leaves linked test
executables in `work/deps/tests/`, to be run on AROS. All four
directories are gitignored.

## Reuse from another port

`scripts/deps/` does not source `scripts/env.sh` and knows nothing about
Skia. Copy `scripts/deps/` and `deps/` (or point at them) and set:

| Variable | Default |
|---|---|
| `DEPS_ROOT` | two levels above `scripts/deps/` |
| `DEPS_RECIPES` | `$DEPS_ROOT/deps` |
| `DEPS_TARGET` | `$AROS_TARGET`, else `one` (ABIv11) |
| `DEPS_PREFIX` | `$DEPS_ROOT/staging/deps/$DEPS_TARGET` |
| `AROS_GCC_ROOT`, `AROS_SDK` | required: toolchain directory, ABIv11 SDK |
| `DEPS_LINK_FLAGS`, `DEPS_CXX_LINK_FLAGS` | extra link flags for the check programs (GCC 13.4: `-specs=...`, and `-Wl,-u,__cxa_pure_virtual` for C++) |
| `AROS_CC` … `AROS_STRIP` | `$AROS_GCC_ROOT/x86_64-aros-*` |

`scripts/m154/chain.sh` builds these with the same GCC 13.4 toolchain as
Skia (libwebp patch 0002 is then a no-op; it is kept for GCC 10.5, the stock
ABIv11 compiler, with which these recipes also build).
`DEPS_TARGET=mainline` is wired but unbuilt: never mix its prefix with
ABIv11.

## Consuming the prefix

pkg-config (relocatable; `${aros_sdk}` is supplied by the consumer):

```sh
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
pkg-config --define-variable=aros_sdk="$AROS_SDK" --static --cflags --libs harfbuzz libjpeg libwebp libwebpdemux
```

CMake: `find_package(harfbuzz)` → `harfbuzz::harfbuzz`,
`find_package(libjpeg-turbo)` → `libjpeg-turbo::jpeg-static`,
`find_package(WebP)` → `WebP::webp`, `WebP::webpdemux`,
`WebP::libwebpmux`, `WebP::sharpyuv`. Use `scripts/deps/aros-x86_64.cmake`
(or an equivalent that sets `CMAKE_SYSROOT` and the Threads answers in it);
the HarfBuzz package names SDK archives relative to `CMAKE_SYSROOT`.

## AROS traps these recipes work around

- **The driver searches `$AROS_SDK/lib` before any `-L`.** The SDK's
  `libjpeg.a` is a stub for `jfif.library`, so `-L$PREFIX/lib -ljpeg`
  links the stub and fails on `jpeg_skip_scanlines`. The installed `.pc`
  files therefore name every archive by path (`${libdir}/libjpeg.a`).
  Put `-I$PREFIX/include` first too: the SDK has its own `jpeglib.h`.
- **No PIC.** collect-aros leaves `_GLOBAL_OFFSET_TABLE_` undefined for
  `-fPIC` objects. `aros-rules.cmake` blanks CMake's PIC/PIE flags even
  where a project forces `POSITION_INDEPENDENT_CODE` (libwebp does).
- **No `-pthread`.** GCC rejects it; pthreads are the static
  `libpthread.a`. The toolchain file seeds FindThreads so
  `Threads::Threads` = `-lpthread` (libwebp patch 0001 stops it adding
  the flag anyway).
- **Configure checks compile only.** `check_function_exists` then says yes
  to everything; recipes seed the real `HAVE_*` answers (HarfBuzz: no
  `mmap`, `mprotect`, `getpagesize`, `newlocale`/`uselocale`).
- **FreeType** is `libfreetype2.static.a` + `libpng_nostdio.a` +
  `libz.static.a` by path. `-lfreetype2`/`-lpng`/`-lz` are stubs; the SDK
  `freetype2.pc` has unsubstituted `%PKGCONFIG_*%` fields.
- **GCC 10 lacks `_mm256_cvtsi256_si32`** (libwebp AVX2): compiles as an
  implicit declaration, fails at the consumer's link. `build.sh` prints
  every implicit declaration it sees. libjpeg-turbo's remaining one
  (`setenv` in an unused static helper in `jinclude.h`) leaves no
  undefined symbol in `libjpeg.a`.

## Decisions

- **HarfBuzz ICU off by default.** The SDK's ICU 61.1 static archives work
  (`HB_WITH_ICU=ON` builds `libharfbuzz-icu.a` and `hb-icu-check` links),
  but WebKitGTK 2.54 requires ICU >= 70.1. Choosing and building a newer
  ICU is a separate recipe.
- **libjpeg-turbo API v62, not `WITH_JPEG8`.** Skia m154 needs only the
  turbo extensions present at every API level (`JCS_EXT_RGBA/BGRA/RGBX`,
  `JCS_RGB565`, `jpeg_crop_scanline`, `jpeg_skip_scanlines`); Chromium and
  distributions also ship v62. TurboJPEG (`tj*`) off.
- **SIMD on** for libjpeg-turbo (NASM elf64, `JPEG_TURBO_SIMD=OFF` to drop)
  and libwebp (SSE2/SSE4.1/AVX2 intrinsics, `WEBP_SIMD=OFF`); both select
  code paths at run time with cpuid. Not yet exercised on AROS.

## Status

Host verification only (2026-09-24): archives, `x86_64-aros-nm` symbols,
no GOT references, relocatable `.pc`, pkg-config links and CMake-package
links of `check/*` through collect-aros. **Nothing has been run on AROS.**
The executables in `work/deps/tests/` (`hb-check [font.ttf]`,
`jpeg-check`, `webp-check`) write `RAM:<name>.txt` with `pass=1`.
