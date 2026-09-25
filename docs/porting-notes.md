# Porting notes: Skia and its dependencies on AROS x86_64 ABIv11

Things that differ from a Linux build, what was done about each, and how it
was checked. Useful for porting other C and C++ libraries to AROS.

## Compiler and linking

- **C++20 needs GCC 13.4.** Built from the ABIv11 AROS tree; see
  [toolchain/README.md](../toolchain/README.md) for the unwinder fix and
  the link specs it needs.
- **`collect-aros` rejects any undefined symbol**, including weak ones. A
  successful link is therefore a real check. C++ programs need
  `-Wl,-u,__cxa_pure_virtual` so the weak reference from libstdc++ resolves.
- **The SDK's `libjpeg.a`, `libpng.a`, `libz.a`, `libfreetype2.a` and
  `libGL.a` are link stubs** for shared AROS libraries (`jfif.library`,
  `png.library`, `z1.library`, `freetype2.library`, `gl.library`). This port
  links FreeType, libpng and zlib statically from the SDK's
  `libfreetype2.static.a`, `libpng_nostdio.a` and `libz.static.a`, by path.
  The GCC driver searches the SDK's `lib/` before any `-L` directory, so
  `-ljpeg` would pick the stub even with a private libjpeg on `-L`: name
  static archives by full path.
- **No position-independent code.** Objects built with `-fPIC` leave
  `_GLOBAL_OFFSET_TABLE_` undefined in `collect-aros`. The dependency CMake
  toolchain file strips PIC/PIE flags.
- **`-pthread` is rejected** by the AROS GCC driver. Threads come from the
  SDK's static `libpthread.a` (`-lpthread`); libwebp's CMake needed a patch
  to stop adding `-pthread` unconditionally.
- **Header order.** `<inline/exec.h>` (pulled in by `<proto/exec.h>`)
  defines a function-like `Allocate(a, b)` macro that rewrites Skia's
  `SkTArray::Allocate`. Include AROS headers after Skia headers.
- **`struct List`.** Anything that includes `<pthread.h>` also gets
  `exec/lists.h` and its `struct List`; a file-scope `using List = ...`
  collides with it (Skia patch 0002).

## C library

- **Platform detection.** GCC for AROS defines `__AROS__` but not
  `__unix__`; Skia would fall through to its macOS branch. Patch 0001 maps
  AROS to the UNIX family.
- **No `mmap`, `pread`, `malloc_usable_size`.** Patch 0001 reads files into
  memory instead of mapping them and implements `pread` with seek and read.
- **No `_SC_NPROCESSORS_ONLN`.** Patch 0002 sizes Skia's thread pool with
  `std::thread::hardware_concurrency()`.
- **No `newlocale`/`uselocale`.** `locale_t` exists, the functions do not.
  AROS's C library formats and parses numbers in the C locale whatever
  `setlocale` says (`printf` uses a constant `"."`, `strtod` accepts only
  `'.'`), so Skia's existing no-op path for C libraries without `locale_t`
  keeps the behaviour it needs (patch 0003). A process-wide `setlocale`
  substitute was rejected because it would affect other threads.
- **No `dlopen` for FreeType.** Not needed: with a static FreeType,
  `SK_FREETYPE_MINIMUM_RUNTIME_VERSION_IS_BUILD_VERSION` is exactly right.

## Dependencies

- **libjpeg-turbo** reports three output components for `JCS_RGB565`
  (two bytes per pixel); a test that expected two was wrong, not the
  library. SIMD (NASM) objects link fine; the linker warns about a missing
  `.note.GNU-stack`, which has no effect on AROS.
- **HarfBuzz**: `mmap`, `mprotect` and `getpagesize` are absent; the recipe
  sets the corresponding `HAVE_*` answers from link probes.

## OpenGL

- AROS exposes GL through GLA (`<GL/gla.h>`): `glACreateContextTags` on a
  window, `glAMakeCurrent`, and `glAGetProcAddress`, which returns core GL
  1.x entry points as well as extensions. Skia's
  `GrGLMakeAssembledInterface` over `glAGetProcAddress` resolved 178 of 179
  names (only `eglQueryString`, optional, is missing).
- `GrGLMakeAssembledInterface` also references the WebGL assembler, so
  `GrGLAssembleWebGLInterfaceAutogen.cpp` is built even with
  `SK_DISABLE_WEBGL_INTERFACE`.
- WebKit's Skia build assumes GLES (`SK_ASSUME_GL_ES=1`); AROS gives
  desktop GL (3.1 compatibility, GLSL 1.40 on Mesa 20.0.8), so the `gl`
  variant does not set it.
- At the default Shell stack, GL programs corrupted memory and crashed
  later (in the Shell's `UnLoadSeg` after exit, or with a jump to address 0
  in the next GL program). With `Stack 8000000` repeated runs were clean.
  Stack overflow in the software rasteriser is the likely explanation; the
  requirement is: run GL programs with a large stack.
