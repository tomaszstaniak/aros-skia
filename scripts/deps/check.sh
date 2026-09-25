#!/bin/bash
# Host-side verification of an installed dependency prefix. Does not run
# anything on AROS and does not touch a VM.
#
#   scripts/deps/check.sh [name ...]      (default: every recipe)
#
# Per library: archives exist, x86_64-aros-nm finds the expected public
# symbols, no archive needs _GLOBAL_OFFSET_TABLE_ (PIC objects do not link
# on AROS), the .pc files carry no machine path, and deps/<name>/check/*
# compiles and LINKS through collect-aros using only pkg-config output.
# collect-aros fails on any undefined symbol, so a link is a real check.
# Executables go to $DEPS_WORK/tests/ for a later guest run.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

TESTS="$DEPS_WORK/tests"
mkdir -p "$TESTS"
export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig"   # never the host's
fail=0

pc() { pkg-config --define-variable=aros_sdk="$AROS_SDK" --static "$@"; }

need_symbols() {
  local lib="$1" archive="$DEPS_PREFIX/lib/$1"; shift
  if [ ! -f "$archive" ]; then echo "  BAD missing $archive"; fail=1; return; fi
  local defined s
  defined="$("$AROS_NM" -g --defined-only "$archive" 2>/dev/null | awk 'NF==3{print $3}')"
  for s in "$@"; do
    if grep -qx "$s" <<<"$defined"; then echo "  ok  $lib $s"
    else echo "  BAD $lib lacks $s"; fail=1; fi
  done
  if "$AROS_NM" -u "$archive" 2>/dev/null | grep -q _GLOBAL_OFFSET_TABLE_; then
    echo "  BAD $lib has PIC objects (_GLOBAL_OFFSET_TABLE_)"; fail=1
  fi
}

check_pc() {
  local m f
  for m in "$@"; do
    f="$DEPS_PREFIX/lib/pkgconfig/$m.pc"
    if [ ! -f "$f" ]; then echo "  BAD no $m.pc"; fail=1; continue; fi
    if grep -qE "/Users/|/Volumes/|$DEPS_ROOT" "$f"; then echo "  BAD $m.pc has a machine path"; fail=1; fi
    pc --exists "$m" || { echo "  BAD pkg-config cannot resolve $m"; fail=1; }
  done
}

link_test() {
  local driver="$1" src="$2" exe="$3"; shift 3
  local cflags libs
  cflags="$(pc --cflags "$@")"
  libs="$(pc --libs "$@")"
  # shellcheck disable=SC2086
  local extra="$DEPS_LINK_FLAGS"
  [ "$driver" = "$AROS_CXX" ] && extra="$extra $DEPS_CXX_LINK_FLAGS"
  if "$driver" --sysroot="$AROS_SDK" -O2 $cflags "$src" -o "$TESTS/$exe" $libs $extra \
       > "$TESTS/$exe.link.log" 2>&1 && [ -s "$TESTS/$exe" ]; then
    echo "  ok  linked $TESTS/$exe ($(wc -c < "$TESTS/$exe" | tr -d ' ') bytes)"
  else
    echo "  BAD link $exe:"; sed 's/^/      /' "$TESTS/$exe.link.log" | tail -20; fail=1
  fi
}

check_harfbuzz() {
  need_symbols libharfbuzz.a hb_shape hb_buffer_create hb_ft_font_create \
    hb_ft_font_create_referenced hb_ot_layout_has_substitution hb_version_string
  check_pc harfbuzz
  link_test "$AROS_CXX" "$DEPS_RECIPES/harfbuzz/check/hb-check.cc" hb-check harfbuzz
  if [ -f "$DEPS_PREFIX/lib/libharfbuzz-icu.a" ]; then   # HB_WITH_ICU=ON build
    need_symbols libharfbuzz-icu.a hb_icu_get_unicode_funcs
    check_pc harfbuzz-icu
    link_test "$AROS_CXX" "$DEPS_RECIPES/harfbuzz/check/hb-icu-check.cc" hb-icu-check harfbuzz-icu
  fi
}

check_libjpeg-turbo() {
  need_symbols libjpeg.a jpeg_start_decompress jpeg_read_scanlines \
    jpeg_crop_scanline jpeg_skip_scanlines jpeg_mem_src jpeg_mem_dest \
    jpeg_start_compress
  if grep -q '#define WITH_SIMD 1' "$DEPS_PREFIX/include/jconfig.h"; then
    echo "  info SIMD on: $("$AROS_NM" -g --defined-only "$DEPS_PREFIX/lib/libjpeg.a" | grep -c ' T jsimd_') jsimd_* entry points"
  fi
  local h="$DEPS_PREFIX/include/jpeglib.h" c="$DEPS_PREFIX/include/jconfig.h"
  # The SDK has its own jpeglib.h and a libjpeg.a *stub*; the link test
  # below fails with undefined jpeg_skip_scanlines if the stub wins.
  grep -q 'JCS_EXT_RGBA' "$h" && grep -q 'JCS_RGB565' "$h" &&
    grep -q '#define JCS_EXTENSIONS' "$h" && grep -q '#define JCS_ALPHA_EXTENSIONS' "$h" &&
    echo "  ok  jpeglib.h/jconfig.h: JCS_EXT_RGBA, JCS_RGB565, JCS_(ALPHA_)EXTENSIONS" ||
    { echo "  BAD turbo colour-space extensions missing"; fail=1; }
  echo "  info $(grep -E '#define JPEG_LIB_VERSION' "$c" | tr -s ' ')"
  check_pc libjpeg
  link_test "$AROS_CC" "$DEPS_RECIPES/libjpeg-turbo/check/jpeg-check.c" jpeg-check libjpeg
}

check_libwebp() {
  need_symbols libwebp.a WebPDecodeRGBA WebPEncodeRGBA WebPEncodeLosslessRGBA WebPGetDecoderVersion
  need_symbols libwebpdecoder.a WebPDecodeRGBA
  need_symbols libwebpdemux.a WebPDemuxInternal WebPDemuxGetI
  need_symbols libwebpmux.a WebPMuxCreateInternal WebPMuxAssemble
  need_symbols libsharpyuv.a SharpYuvConvert SharpYuvGetVersion
  check_pc libwebp libwebpdecoder libwebpdemux libwebpmux libsharpyuv
  link_test "$AROS_CC" "$DEPS_RECIPES/libwebp/check/webp-check.c" webp-check \
    libwebp libwebpdemux libwebpmux libsharpyuv
}

# The installed CMake packages, consumed the way another CMake project would:
# find_package + imported targets, same toolchain file, full collect-aros link.
check_cmake_packages() {
  local dir="$DEPS_BUILD/cmake-consumer" have=()
  rm -rf "$dir"; mkdir -p "$dir"
  {
    echo 'cmake_minimum_required(VERSION 3.16)'
    echo 'project(deps_consumer C CXX)'
    if [ -f "$DEPS_PREFIX/lib/libharfbuzz.a" ]; then
      echo 'find_package(harfbuzz REQUIRED)'
      echo "add_executable(hb-check-cmake \"$DEPS_RECIPES/harfbuzz/check/hb-check.cc\")"
      echo 'target_link_libraries(hb-check-cmake PRIVATE harfbuzz::harfbuzz)'
      echo 'separate_arguments(_cxx_link UNIX_COMMAND "$ENV{DEPS_CXX_LINK_FLAGS}")'
      echo 'target_link_options(hb-check-cmake PRIVATE ${_cxx_link})'
      have+=(hb-check-cmake)
    fi
    if [ -f "$DEPS_PREFIX/lib/libjpeg.a" ]; then
      echo 'find_package(libjpeg-turbo REQUIRED)'
      echo "add_executable(jpeg-check-cmake \"$DEPS_RECIPES/libjpeg-turbo/check/jpeg-check.c\")"
      echo 'target_link_libraries(jpeg-check-cmake PRIVATE libjpeg-turbo::jpeg-static)'
      have+=(jpeg-check-cmake)
    fi
    if [ -f "$DEPS_PREFIX/lib/libwebp.a" ]; then
      echo 'find_package(WebP REQUIRED)'
      echo "add_executable(webp-check-cmake \"$DEPS_RECIPES/libwebp/check/webp-check.c\")"
      echo 'target_link_libraries(webp-check-cmake PRIVATE WebP::webp WebP::webpdemux WebP::libwebpmux WebP::sharpyuv)'
      have+=(webp-check-cmake)
    fi
  } > "$dir/CMakeLists.txt"
  [ ${#have[@]} -gt 0 ] || return 0
  if cmake -S "$dir" -B "$dir/b" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$DEPS_TOOLCHAIN_FILE" \
       -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$DEPS_PREFIX" > "$dir/log" 2>&1 &&
     cmake --build "$dir/b" >> "$dir/log" 2>&1; then
    echo "  ok  CMake find_package + link: ${have[*]}"
  else
    echo "  BAD CMake consumer (log $dir/log):"; tail -15 "$dir/log" | sed 's/^/      /'; fail=1
  fi
}

if [ $# -eq 0 ]; then set -- $(deps_all); fi
for n in "$@"; do
  echo "check: $n"
  "check_$n"
done
echo "check: cmake packages"
check_cmake_packages
[ "$fail" = 0 ] && echo "check: all passed (host only; nothing was run on AROS)" || { echo "check: FAILED" >&2; exit 1; }
