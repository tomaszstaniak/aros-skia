#!/bin/bash
# Build the x86_64-aros GCC 13.4.0 cross toolchain for ABIv11 (AROS One).
#
#   toolchain/build-gcc13.sh <workdir> <prefix>
#
# <workdir>  scratch space on a CASE-SENSITIVE filesystem (on macOS, e.g. an
#            APFS (Case-sensitive) disk image); needs about 10 GB.
# <prefix>   where the toolchain is installed (x86_64-aros-gcc etc. land at
#            the top of it, as AROS crosstools do). Absolute path; the
#            installed collect-aros refers to it, so do not move it later.
#
# Source: deadwood2/AROS at the commit below, which carries the AROS patches
# for GCC 13.4.0 and binutils 2.45. Two corrections are applied:
#  - patches/0001: drop the libgcc hunk of gcc-13.4.0-aros.diff that leaves
#    the unwinder's register size table empty on x86_64 (every C++ throw
#    aborts without it);
#  - patches/0002 (macOS hosts only): zlib's zutil.h in the binutils and GCC
#    trees, whose TARGET_OS_MAC test breaks the host build.
# Then aros-v11.specs is installed next to the compiler: the 13.4 diff links
# library names that only mainline AROS has.
set -euo pipefail

AROS_REPO="${AROS_REPO:-https://github.com/deadwood2/AROS.git}"
AROS_COMMIT="${AROS_COMMIT:-e33ca77d6c3b61a8feb641f89072fe0f716fce75}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:?usage: build-gcc13.sh <workdir> <prefix>}"
PREFIX="${2:?usage: build-gcc13.sh <workdir> <prefix>}"
case "$PREFIX" in /*) ;; *) echo "build-gcc13: prefix must be absolute" >&2; exit 1 ;; esac
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

# Case sensitivity: crosstools builds fail in odd ways otherwise.
t="$WORK/.case-test"; rm -f "$t" "$t.X"; touch "$t"
if [ -e "$WORK/.CASE-TEST" ]; then rm -f "$t"; echo "build-gcc13: $WORK is not case-sensitive" >&2; exit 1; fi
rm -f "$t"

if [ ! -d "$WORK/AROS/.git" ]; then
  git -C "$WORK" init -q AROS
  git -C "$WORK/AROS" fetch -q --depth 1 "$AROS_REPO" "$AROS_COMMIT"
  git -C "$WORK/AROS" checkout -q --detach FETCH_HEAD
fi
[ "$(git -C "$WORK/AROS" rev-parse HEAD)" = "$AROS_COMMIT" ] || { echo "build-gcc13: AROS tree not at $AROS_COMMIT" >&2; exit 1; }
if ! git -C "$WORK/AROS" diff --quiet; then
  echo "build-gcc13: AROS tree already patched"
else
  git -C "$WORK/AROS" apply "$HERE/patches/0001-gcc-13.4.0-aros-libgcc-reg-size-table.patch"
fi

mkdir -p "$WORK/build" "$WORK/portssources"
if [ ! -f "$WORK/build/Makefile" ]; then
  (cd "$WORK/build" && ../AROS/configure --target=pc-x86_64 \
     --with-gcc-version=13.4.0 --with-binutils-version=2.45 \
     --with-aros-toolchain-install="$PREFIX" \
     --with-portssources="$WORK/portssources" >"$WORK/configure.log" 2>&1) ||
    { echo "build-gcc13: configure failed, see $WORK/configure.log" >&2; exit 1; }
fi

# The zlib fix can only be applied once the tarballs are unpacked, so make is
# rerun after each unpack that needs it (macOS only; elsewhere one run).
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
for attempt in 1 2 3 4; do
  if make -C "$WORK/build" -j"$JOBS" tools-crosstools-gnu-x86_64 >"$WORK/make-$attempt.log" 2>&1; then
    echo "build-gcc13: crosstools built (attempt $attempt)"; break
  fi
  patched=0
  if [ "$(uname -s)" = Darwin ]; then
    while IFS= read -r z; do
      if grep -q 'defined(TARGET_OS_MAC)' "$z"; then
        sed -i '' 's/#if defined(MACOS) || defined(TARGET_OS_MAC)/#if defined(MACOS)/' "$z"
        echo "build-gcc13: host fix applied to ${z#$WORK/}"; patched=1
      fi
    done < <(find "$WORK/build/bin" -path '*/Ports/host/*/zlib/zutil.h' 2>/dev/null)
  fi
  [ "$patched" = 1 ] || { echo "build-gcc13: make failed, see $WORK/make-$attempt.log" >&2; exit 1; }
done

cp "$HERE/aros-v11.specs" "$PREFIX/aros-v11.specs"
"$PREFIX/x86_64-aros-gcc" --version | head -1
echo "build-gcc13: installed to $PREFIX; use -specs=$PREFIX/aros-v11.specs"
