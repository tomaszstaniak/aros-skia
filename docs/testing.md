# Testing

## How the packages are checked

1. `scripts/m154/chain.sh <fresh clone> both` builds the dependencies and
   all six packages (three variants, release and debug) and, for each one,
   builds the examples twice: from the installed prefix, and from the
   archive unpacked into an empty temporary directory. `collect-aros` fails
   on any undefined symbol, so a successful link is itself a check.
2. `scripts/m154/make-guest-run.sh` packs the examples built from the
   unpacked archives, plus a C++ `throw` test built with the same compiler,
   into a payload for an AROS One virtual machine. On AROS the `run` script
   executes every program with `Stack 8000000` and writes one result file
   per program: the package's SHA-256 line, the program's own output, and
   its return code.

The examples check pixels they can predict (an exact fill colour, gradient
end points, drawn text), codec round trips (JPEG within a tolerance, WebP
lossless exactly), HarfBuzz shaping results (a ligature, kerning), and for
the `gl` variant that Ganesh output matches the raster backend.

## Release run (packages attached to the first release)

Built from commit `7ded975` with a GCC 13.4.0 toolchain made by
`toolchain/build-gcc13.sh` from scratch; the dependencies were built with
the same compiler. SDK: AROS One 1.3. Target: AROS One x86_64 in QEMU, Mesa
20.0.8 softpipe.

| package | SHA-256 |
|---|---|
| `skia-aros-m154-raster-release-abiv11-588b550a4dd8.tar.gz` | `e8ef6073b1bb49a1875375c2ab02f5475fb52aa21b29efe84cdaa802264e664c` |
| `skia-aros-m154-codecs-release-abiv11-588b550a4dd8.tar.gz` | `3ba2438a31c5cab2ffcca4245c22f7bca7f6e6199822e90f728acfb471462831` |
| `skia-aros-m154-gl-release-abiv11-588b550a4dd8.tar.gz` | `cfe4cfaf0cbb542f3019d8e322bb4dedc4162e146237a6862f58edcdd06c8b77` |
| `skia-aros-m154-raster-debug-abiv11-588b550a4dd8.tar.gz` | `c21499af0aef0c4bf6968103a576c1dd5aacaca8be85863caf2539afd79ee9e6` |
| `skia-aros-m154-codecs-debug-abiv11-588b550a4dd8.tar.gz` | `591beee20cebba9bb754d566d67bef172e94cfb58619813483cdb23ae6b13ce3` |
| `skia-aros-m154-gl-debug-abiv11-588b550a4dd8.tar.gz` | `1c761d4cc5afd3dcee25c71db119942b5873240f26ecad7a264a63c2ba4cd638` |

| program | package | result |
|---|---|---|
| raster | raster-release | all checks pass, rc 0 |
| raster | codecs-release | all checks pass, rc 0 |
| codecs | codecs-release | all checks pass, rc 0 |
| gl | gl-release | all checks pass, rc 0 |
| raster | raster-debug | all checks pass, rc 0 |
| raster | codecs-debug | all checks pass, rc 0 |
| codecs | codecs-debug | all checks pass, rc 0 |
| gl | gl-debug | all checks pass, rc 0 |
| throw (toolchain) | GCC 13.4.0 | `caught 7`, rc 0 |

Release and debug give identical results. `check-package.sh` also confirmed that no file in any package contains an absolute path of the build machine.

Details from the `codecs` example: JPEG quality 95 round trip within 1 per
channel; WebP lossless round trip pixel-exact; WebP lossy within 1; HarfBuzz
shapes "office" (6 characters) to 5 glyphs and applies kerning to "AV"
(Source Sans 3); a shaped Polish line is drawn with Skia.

Details from the `gl` example: the `GrGLInterface` assembled from
`glAGetProcAddress` validates (178 of 179 entry points; only the optional
`eglQueryString` is missing). Ganesh output differs from the raster backend
in 126 of 65536 pixels, all on anti-aliased edges (largest channel difference
41). Fill, gradient and text pixels match.

## GL speed, for the record

Time for 10 frames of the `gl` example scene, Ganesh on Mesa softpipe
against Skia's raster backend, in four runs:

| run | raster | Ganesh | ratio |
|---|---|---|---|
| development build | 19 ms | 450 ms | about 24x |
| package check | 42 ms | 608 ms | about 14x |
| earlier package build | 87 ms | 2014 ms | about 23x |
| release run above (release package) | 63 ms | 2275 ms | about 36x |

These are measurements of one scene on a software rasteriser in an
emulated machine, not a performance characteristic of the port. No
hardware GL driver has been tested.

## Not tested

Other hosts than macOS on Apple Silicon; mainline AROS (ABIv1); real
hardware; `SkShaper` (primitive or HarfBuzz); PNG decoding through
`SkPngDecoder`; `SkFontMgr_New_Custom_Directory`; many surfaces or long
runs on Ganesh; multi-threaded use of Skia.
