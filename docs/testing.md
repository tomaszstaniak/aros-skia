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

Built from commit `ab4685e` with a GCC 13.4.0 toolchain made by
`toolchain/build-gcc13.sh` from scratch; the dependencies were built with
the same compiler. SDK: AROS One 1.3. Target: AROS One x86_64 in QEMU, Mesa
20.0.8 softpipe.

| package | SHA-256 |
|---|---|
| `skia-aros-m154-raster-release-abiv11-588b550a4dd8.tar.gz` | `72d57129da737915f550759e69f39aca409a967d1f7b154e8eeba4ad9ed2cb00` |
| `skia-aros-m154-codecs-release-abiv11-588b550a4dd8.tar.gz` | `8e23bf959e50fbfe4b11557f45dcce5204d80881078c13df17b79d28dd3f27d5` |
| `skia-aros-m154-gl-release-abiv11-588b550a4dd8.tar.gz` | `8f3600b06c431db6f09d16d54ca810baad600bc849d53ae4f25d367626053942` |
| `skia-aros-m154-raster-debug-abiv11-588b550a4dd8.tar.gz` | `5b8a08280361dbc8b6c30175bb6164ed3474da438277ceb0e66bd58493be4a14` |
| `skia-aros-m154-codecs-debug-abiv11-588b550a4dd8.tar.gz` | `cb0121c0fbebd823e7b09ff01c70e252055eeebf584efb8242201add35e855a0` |
| `skia-aros-m154-gl-debug-abiv11-588b550a4dd8.tar.gz` | `85e2a6bba0a7be2c7d07c7518416211c6e5a5c9f5e4028e84b91a34b514b1aea` |

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

Release and debug give identical results.

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
against Skia's raster backend, in three runs:

| run | raster | Ganesh | ratio |
|---|---|---|---|
| development build | 19 ms | 450 ms | about 24x |
| package check | 42 ms | 608 ms | about 14x |
| release run above (release package) | 87 ms | 2014 ms | about 23x |

These are measurements of one scene on a software rasteriser in an
emulated machine, not a performance characteristic of the port. No
hardware GL driver has been tested.

## Not tested

Other hosts than macOS on Apple Silicon; mainline AROS (ABIv1); real
hardware; `SkShaper` (primitive or HarfBuzz); PNG decoding through
`SkPngDecoder`; `SkFontMgr_New_Custom_Directory`; many surfaces or long
runs on Ganesh; multi-threaded use of Skia.
