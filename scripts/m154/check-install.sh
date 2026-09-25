#!/bin/bash
# Build the examples for one installed variant using only its prefix:
# flags come from lib/pkgconfig/skia-aros-m154.pc, the link specs from
# share/skia-aros-m154/. Nothing is read from work/ or build/.
#
#   M154_VARIANT=codecs scripts/m154/check-install.sh [prefix] [outdir]
#
# Examples per variant: raster -> raster; codecs -> raster, codecs;
# gl -> raster, codecs, gl. Executables go to outdir (default
# build/m154/<tag>/examples) for a guest run. Compile + link only.
set -euo pipefail
source "$(dirname "$0")/env.sh"
P="${1:-$M154_PREFIX}"
OUT="${2:-$M154_BUILD/examples}"
PC="$P/lib/pkgconfig/skia-aros-m154.pc"
[ -f "$PC" ] || { echo "check-install: no $PC" >&2; exit 1; }
# The .pc must not name this machine's paths.
if grep -qE '/Users/|/Volumes/|staging/|work/' "$PC"; then echo "check-install: machine path in $PC" >&2; exit 1; fi
export PKG_CONFIG_PATH="$P/lib/pkgconfig"
CFLAGS=$(pkg-config --cflags skia-aros-m154)
LIBS=$(pkg-config --define-variable=aros_sdk="$AROS_SDK" --static --libs skia-aros-m154)
SPECS=$(pkg-config --variable=specs skia-aros-m154)
case "$M154_VARIANT" in raster) EX=(raster) ;; codecs) EX=(raster codecs) ;; gl) EX=(raster codecs gl) ;; esac
mkdir -p "$OUT"
for e in "${EX[@]}"; do
  src=$(ls "$PROJECT_ROOT/examples/m154/$e/"*.cpp)
  "$M154_CXX" -specs="$SPECS" --sysroot="$AROS_SDK" -O2 -w $CFLAGS "$src" -o "$OUT/$e" $LIBS
  echo "check-install: ok $e -> $OUT/$e ($(wc -c <"$OUT/$e") bytes)"
done
