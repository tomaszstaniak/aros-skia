#!/bin/bash
# Configure, build and install one or more pinned dependencies (static only)
# into $DEPS_PREFIX (default staging/deps/<target>/).
#
#   scripts/deps/build.sh [name ...]      (default: every recipe)
#
# Runs fetch.sh first, so a clean checkout needs only this command. The
# build tree is recreated each time; these libraries build in seconds to
# a couple of minutes and a stale CMake cache has hidden seeded HAVE_*
# values before.
set -euo pipefail
DEPS_BIN="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$DEPS_BIN/common.sh"

[ -x "$AROS_CC" ] || deps_die "no compiler at $AROS_CC (set AROS_GCC_ROOT)"
[ -d "$AROS_SDK/include" ] || deps_die "no SDK at $AROS_SDK (set AROS_SDK)"

# Rewrite an installed .pc so the prefix follows the file (tarball-safe) and
# no absolute path of this machine is baked in. ${aros_sdk} is left for the
# consumer: pkg-config --define-variable=aros_sdk="$AROS_SDK" --static ...
relocate_pc() {
  local pc="$1"
  python3 - "$pc" "$DEPS_PREFIX" "$AROS_SDK" <<'PY'
import os, re, sys
path, prefix, sdk = sys.argv[1:4]
text = open(path).read()
text = re.sub(r'(?m)^prefix=.*$', 'prefix=${pcfiledir}/../..', text, count=1)
text = text.replace(prefix, '${prefix}')
if sdk in text:
    text = text.replace(sdk, '${aros_sdk}')
    if 'aros_sdk=' not in text:
        text = text.replace('prefix=${pcfiledir}/../..',
                            'prefix=${pcfiledir}/../..\n# pkg-config --define-variable=aros_sdk="$AROS_SDK"\naros_sdk=${aros_sdk}', 1)
# The AROS GCC driver puts $AROS_SDK/lib *before* user -L paths, and the
# SDK ships link stubs under common names (libjpeg.a -> jfif.library), so
# "-L${libdir} -ljpeg" silently links the stub. Name our archives by path.
def by_path(m):
    def repl(l):
        name = l.group(1)
        if os.path.exists(os.path.join(prefix, 'lib', 'lib%s.a' % name)):
            return '${libdir}/lib%s.a' % name
        return l.group(0)
    line = re.sub(r'-l([A-Za-z0-9_+.-]+)', repl, m.group(0))
    if not re.search(r'\$\{libdir\}/lib|-l', line.split(':', 1)[1].replace('-L${libdir}', '')):
        return line
    return re.sub(r'\s*-L\$\{libdir\}', '', line)
text = re.sub(r'(?m)^Libs:.*$', by_path, text)
open(path, 'w').write(text)
PY
}

build_one() {
  "$DEPS_BIN/fetch.sh" "$1"
  deps_load_recipe "$1"
  rm -rf "$RECIPE_BUILD"
  mkdir -p "$RECIPE_BUILD" "$DEPS_PREFIX"

  echo "build: $RECIPE_NAME $RECIPE_VERSION -> $DEPS_PREFIX ($("$AROS_CC" -dumpversion))"
  cmake -S "$RECIPE_WORK" -B "$RECIPE_BUILD" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$DEPS_TOOLCHAIN_FILE" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR=include \
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    "${RECIPE_CMAKE_ARGS[@]}" \
    > "$RECIPE_BUILD/configure.log" 2>&1 || {
      tail -40 "$RECIPE_BUILD/configure.log" >&2
      deps_die "$RECIPE_NAME: configure failed (full log $RECIPE_BUILD/configure.log)"
    }
  cmake --build "$RECIPE_BUILD" -j "$DEPS_JOBS" > "$RECIPE_BUILD/build.log" 2>&1 || {
    tail -40 "$RECIPE_BUILD/build.log" >&2
    deps_die "$RECIPE_NAME: build failed (full log $RECIPE_BUILD/build.log)"
  }
  # An implicit declaration compiles, then becomes an undefined symbol at
  # the consumer's link (libwebp AVX2 on GCC 10). Surface them here.
  grep -ho "implicit declaration of function '[^']*'" "$RECIPE_BUILD/build.log" \
    | sort | uniq -c | sed "s/^/build: $RECIPE_NAME warning: /" || true
  cmake --install "$RECIPE_BUILD" > "$RECIPE_BUILD/install.log"

  if declare -F recipe_post_install >/dev/null; then recipe_post_install; fi
  local pc
  for pc in $(grep -o "$DEPS_PREFIX/lib/pkgconfig/[^ ]*\.pc" "$RECIPE_BUILD/install.log" | sort -u); do
    relocate_pc "$pc"
  done
  # Drop what a static cross prefix cannot use (host tools, man pages).
  rm -rf "$DEPS_PREFIX/bin" "$DEPS_PREFIX/share/man"
  # Licence texts travel with the static archives; a package made from
  # $DEPS_PREFIX must not need the source tree. Each recipe names its files.
  mkdir -p "$DEPS_PREFIX/share/licenses/$RECIPE_NAME"
  for lf in ${RECIPE_LICENSE_FILES:-}; do
    cp "$RECIPE_WORK/$lf" "$DEPS_PREFIX/share/licenses/$RECIPE_NAME/"
  done
  printf '%s %s\n%s\n%s\n' "$RECIPE_NAME" "$RECIPE_VERSION" "$RECIPE_SHA256" "$RECIPE_LICENSE" \
    >"$DEPS_PREFIX/share/licenses/$RECIPE_NAME/SOURCE"
  unset -f recipe_post_install 2>/dev/null || true
  echo "build: $RECIPE_NAME installed"
}

if [ $# -eq 0 ]; then set -- $(deps_all); fi
for n in "$@"; do build_one "$n"; done
