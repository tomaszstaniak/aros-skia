# aros-skia

A port of [Skia](https://skia.org), Google's 2D graphics library, to AROS
x86_64 ABIv11 (AROS One), packaged as a static SDK for developers who want to
build AROS software on top of Skia.

The port tracks Skia commit `588b550a4dd8` (milestone 154), the Skia that
WebKitGTK 2.54 bundles. This repository is the Skia SDK only. It is not a
WebKit port and makes no claim about WebKit readiness; that integration is
future work elsewhere.

## What works

Everything below was run on AROS One x86_64 in QEMU from the packaged SDK.
See [docs/testing.md](docs/testing.md) for the exact runs.

| variant | contents | status |
|---|---|---|
| `codecs` | CPU raster, PNG, JPEG (libjpeg-turbo 3.2.0), WebP (libwebp 1.6.0), FreeType fonts; HarfBuzz 14.5.0 bundled for application-level shaping | **default** |
| `raster` | CPU raster, PNG, FreeType fonts from files or memory | minimal |
| `gl` | `codecs` plus the Ganesh GPU backend on OpenGL through AROS GLA | optional, see below |

Each variant is built as `release` (the default SDK) or `debug`
(diagnostic: Skia's `SK_DEBUG` assertions and debug info; much larger).

### Text shaping: what is and is not tested

- **HarfBuzz shaping done by the application is tested.** The `codecs`
  example calls `hb_shape()` itself and draws the positioned glyphs as an
  `SkTextBlob` (ligatures, kerning, Polish text). WebKit uses HarfBuzz the
  same way.
- **Skia's `SkShaper` module is not tested.** Only its primitive shaper is
  built, with no HarfBuzz behind it. The HarfBuzz backend of `SkShaper`
  (`SkShapers::HB`) is not built at all: it needs an `SkUnicode`
  implementation (ICU or libgrapheme), which this port does not provide yet.

### OpenGL: working, but software

The `gl` variant runs Skia's Ganesh backend on the OpenGL that AROS exposes
through GLA (`<GL/gla.h>`). The `GrGLInterface` is assembled from
`glAGetProcAddress`; no EGL or libepoxy is involved. On the tested systems GL
is Mesa 20.0.8 **softpipe, a software rasteriser**: this is not hardware
acceleration. In two runs of one benchmark (10 frames of the example scene)
Ganesh was about 14x and about 24x slower than Skia's own CPU raster backend.
Those are two measurements of one scene, not a general performance figure.
No hardware GL driver has been tested. GL programs need a large stack
(`Stack 8000000` in the Shell before running them).

## Not included

- mainline AROS (ABIv1): not built, not tested. ABIv11 binaries do not run there.
- `SkShaper` with HarfBuzz, `SkUnicode` (ICU, libgrapheme)
- fontconfig font manager (use `SkFontMgr_New_Custom_Empty()` or
  `SkFontMgr_New_Custom_Directory()` with font files)
- SVG module, PDF backend, Graphite, Vulkan, EGL/epoxy GL glue
- Shared libraries: everything is static.

## Requirements

| | |
|---|---|
| Host | Tested on macOS on Apple Silicon only. The scripts are bash and should work on Linux, but that is untested. Needs git, python3, cmake, ninja, pkg-config, nasm, curl. |
| Toolchain | x86_64-aros GCC 13.4.0, built from source with [`toolchain/build-gcc13.sh`](toolchain/README.md). The stock ABIv11 GCC 10.5 cannot build this Skia (C++20). |
| SDK | The ABIv11 SDK: the `Development` directory of an AROS One installation or ISO (`include/`, `lib/`). Tested with the SDK of AROS One 1.3. |
| Target | AROS One x86_64 (ABIv11). |

Tell the scripts where the toolchain and SDK are, in the environment or in
an untracked `local.env` in the repository root:

```sh
AROS_GCC13_ROOT=/path/to/gcc13        # contains x86_64-aros-g++
AROS_SDK=/path/to/AROS/Development    # contains include/ and lib/
```

## Build

```sh
toolchain/build-gcc13.sh /case-sensitive/work /opt/aros-gcc13   # once, about 10 minutes
scripts/m154/chain.sh "$PWD" release
```

`chain.sh` runs every step for every variant; the steps can also be run one
by one (`M154_VARIANT=codecs M154_BUILD_TYPE=release` selects the variant):

| step | script | result |
|---|---|---|
| dependencies | `scripts/deps/fetch.sh`, `build.sh`, `check.sh` | static HarfBuzz, libjpeg-turbo, libwebp in `staging/deps/one` (see [deps/README.md](deps/README.md)) |
| Skia source | `scripts/m154/fetch.sh` | Skia at the pin, patches applied, in `work/skia-m154-src` |
| library | `scripts/m154/build.sh` | `build/m154/<variant>-<type>/libskia.a` |
| install | `scripts/m154/install.sh` | SDK prefix `staging/m154/<variant>-<type>` |
| check | `scripts/m154/check-install.sh` | examples built from the installed prefix only |
| package | `scripts/m154/package.sh`, `check-package.sh` | `dist/skia-aros-m154-<variant>-<type>-abiv11-588b550a4dd8.tar.gz`, checked by building the examples from the unpacked archive |

Every input is pinned: the Skia commit in `upstreams.json`, the patch series
in `patches/skia-m154/`, the source list of each variant in `config/m154/`,
and each dependency's version and SHA-256 in `deps/<name>/recipe.env`.

## Using the SDK

An installed or unpacked SDK prefix contains:

```text
include/  modules/skcms/  modules/skshaper/include/   Skia headers (the prefix is the include root)
lib/libskia.a
lib/pkgconfig/skia-aros-m154.pc
deps/include/  deps/lib/                             codecs, gl: static JPEG, WebP, HarfBuzz
share/skia-aros-m154/MANIFEST.json, MANIFEST.txt     features, dependencies, flags
share/skia-aros-m154/aros-v11-gcc13.specs            link specs for GCC 13.4
share/licenses/                                      Skia and dependency licences
```

Compile and link with pkg-config; the ABIv11 SDK location is supplied at use
time, nothing in the package refers to the build machine:

```sh
export PKG_CONFIG_PATH=/path/to/sdk-prefix/lib/pkgconfig
CXXFLAGS=$(pkg-config --cflags skia-aros-m154)
LIBS=$(pkg-config --define-variable=aros_sdk="$AROS_SDK" --static --libs skia-aros-m154)
SPECS=$(pkg-config --variable=specs skia-aros-m154)
x86_64-aros-g++ -specs="$SPECS" --sysroot="$AROS_SDK" -O2 $CXXFLAGS app.cpp -o app $LIBS
```

Rules that matter:

- Use the same GCC 13.4 toolchain for your program; pass the `-specs` file
  on every link. Other compiler and runtime combinations are not supported.
- Keep the `-D` flags from the `.pc` file: `SK_RELEASE` or `SK_DEBUG` must
  match the library you link.
- Include AROS headers (`<proto/exec.h>` and friends) **after** Skia
  headers: `<inline/exec.h>` defines a function-like `Allocate()` macro that
  breaks Skia's `SkTArray`.

## Examples

`examples/m154/` holds the three programs used to test the SDK. They draw a
known scene, check pixels they can predict, and exit with 0 when every check
passes:

| example | shows |
|---|---|
| `raster` | raster surface, shapes, gradient, FreeType text, PNG encoding |
| `codecs` | JPEG and WebP round trips through Skia's codecs; HarfBuzz shaping drawn with Skia |
| `gl` | a GLA context, `GrGLMakeAssembledInterface` over `glAGetProcAddress`, a Ganesh render target compared with the raster result |

`scripts/m154/make-guest-run.sh` packs the examples of every variant, with
fonts and an AROS script that runs them and writes one result file each.

## Patches to Skia

Three small patches (`patches/skia-m154/`), each with its reasoning in the
header:

1. `0001-aros-posix-file-memory`: treat AROS as a UNIX-family platform; file
   mapping through malloc/read, `pread` through seek/read.
2. `0002-aros-list-and-nprocessors`: avoid a clash with AROS's `struct List`;
   thread count from `std::thread::hardware_concurrency()`.
3. `0003-aros-locale-setter-noop`: AROS has no `newlocale`/`uselocale`, and
   its C library formats and parses numbers in the C locale regardless of
   `setlocale`, so Skia's existing no-op path keeps the class's contract.

FreeType needs no patch: `SK_FREETYPE_MINIMUM_RUNTIME_VERSION_IS_BUILD_VERSION`
matches the static link and removes the `dlopen` path.

More platform notes: [docs/porting-notes.md](docs/porting-notes.md).

## Licences

Skia is BSD-3-Clause (`packaging/LICENSE.skia`). The bundled dependencies keep
their own licences, installed under `share/licenses/` in every SDK package:
HarfBuzz (MIT), libjpeg-turbo (IJG, BSD-3-Clause, zlib), libwebp
(BSD-3-Clause with a patent grant). The test fonts in `examples/m154/fonts`
are Bitstream Vera and Source Sans 3 (SIL OFL 1.1), with their licences. The
build scripts, patches and documentation of this repository are under the
licence in [LICENSE](LICENSE).
