#!/bin/bash
# Assemble a test-VM payload that runs every m154 example from the unpacked
# packages of a chain checkout, one result file per program.
#
#   scripts/m154/make-guest-run.sh <checkout> <payload-dir> <run-id>
#
# Also a C++ throw test built with the same toolchain.
# Payload: <tag>/<example> (debug copies --strip-debug, which AROS loads
# correctly), <tag>/PKGID (package name + SHA-256), fonts, and `run`, an
# AROS script. On the guest: UnZip to RAM:s, then `Execute RAM:s/run`.
# Each program writes RAM:s/res/<run-id>-<tag>-<example>.txt with its own
# output, its return code and the package id; `run` copies them to Results:.
set -euo pipefail
C="$1"; OUT="$2"; RID="$3"
source "$(dirname "$0")/env.sh"
STRIP="$AROS_GCC13_ROOT/x86_64-aros-strip"
FONTS="${M154_TEST_FONTS:-$PROJECT_ROOT/examples/m154/fonts}"
rm -rf "$OUT"; mkdir -p "$OUT"
cp "$FONTS/VeraSans.ttf" "$FONTS/SourceSans3-Regular.ttf" "$OUT/"
{
  echo "; m154 SDK examples, run $RID"
  echo "Stack 8000000"
  echo "FailAt 30"
  echo "CD RAM:s"
  echo "MakeDir RAM:s/res"
} >"$OUT/run"
for t in release debug; do
  for v in raster codecs gl; do
    tag="$v-$t"
    ex="$C/build/m154/$tag/package-examples"
    [ -d "$ex" ] || { echo "make-guest-run: no $ex" >&2; exit 1; }
    name="skia-aros-m154-$tag-abiv11-$(cd "$C" && source scripts/m154/env.sh && echo "${M154_PIN:0:12}")"
    mkdir -p "$OUT/$tag"
    (cd "$C/dist" && cat "$name.tar.gz.sha256") >"$OUT/$tag/PKGID"
    # raster: raster; codecs: raster and codecs; gl: gl (8 runs in total).
    case "$v" in raster) exs="raster" ;; codecs) exs="raster codecs" ;; gl) exs="gl" ;; esac
    for e in $exs; do
      case "$e" in raster) args="VeraSans.ttf $tag/out.png" ;;
                   codecs) args="SourceSans3-Regular.ttf $tag/" ;;
                   gl)     args="VeraSans.ttf $tag/ 10" ;; esac
      cp "$ex/$e" "$OUT/$tag/$e"
      [ "$t" = debug ] && "$STRIP" --strip-debug "$OUT/$tag/$e"
      r="res/$RID-$tag-$e.txt"
      {
        echo "Protect $tag/$e +e"
        echo "Type $tag/PKGID >$r"
        echo "$tag/$e $args >>$r"
        echo "Echo \"rc=\$RC\" >>$r"
      } >>"$OUT/run"
    done
  done
done
# The toolchain itself: a C++ throw must be caught (toolchain/patches/0001).
"$M154_CXX" -specs="$M154_SPECS" --sysroot="$AROS_SDK" -O2 \
  "$PROJECT_ROOT/toolchain/check/throw.cpp" -o "$OUT/throw" -Wl,-u,__cxa_pure_virtual
{
  echo "Protect throw +e"
  echo "Echo \"$("$M154_CXX" --version | head -1)\" >res/$RID-toolchain-throw.txt"
  echo "throw >>res/$RID-toolchain-throw.txt"
  echo "Echo \"rc=\$RC\" >>res/$RID-toolchain-throw.txt"
} >>"$OUT/run"
echo "Copy RAM:s/res/#? Results:" >>"$OUT/run"
echo "make-guest-run: $OUT ($(du -sh "$OUT" | cut -f1))"
