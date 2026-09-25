# Shared settings for the static dependency recipes (deps/<name>/).
# Sourced by fetch.sh / build.sh / check.sh; bash only.
#
# Deliberately independent of scripts/env.sh and of Skia: another AROS port
# can copy scripts/deps/ + deps/ and drive them
# with its own environment. Everything below is an overridable default.
#
#   DEPS_ROOT      tree that holds upstream/ work/ staging/   (repo root)
#   DEPS_RECIPES   directory with <name>/recipe.env            ($DEPS_ROOT/deps)
#   DEPS_TARGET    ABI tag used in paths: one | mainline       (one)
#   DEPS_PREFIX    install prefix  ($DEPS_ROOT/staging/deps/$DEPS_TARGET)
#   AROS_GCC_ROOT  directory with x86_64-aros-gcc etc.
#   AROS_SDK       sysroot passed as --sysroot
#   DEPS_JOBS      parallel build jobs

DEPS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="${DEPS_ROOT:-$(cd "$DEPS_SCRIPT_DIR/../.." && pwd)}"
DEPS_RECIPES="${DEPS_RECIPES:-$DEPS_ROOT/deps}"
DEPS_TARGET="${DEPS_TARGET:-${AROS_TARGET:-one}}"

case "$DEPS_TARGET" in
  one) ;;
  mainline)
    # Not built or verified yet; a v1 prefix must never mix with ABIv11.
    echo "deps: mainline v1 recipes are unverified" >&2
    ;;
  *)
    echo "deps: unknown DEPS_TARGET '$DEPS_TARGET' (one|mainline)" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac
# No machine defaults: say which toolchain and SDK to use.
: "${AROS_GCC_ROOT:?deps: set AROS_GCC_ROOT to the directory holding x86_64-aros-gcc}"
: "${AROS_SDK:?deps: set AROS_SDK to the ABIv11 SDK (Development/ of AROS One: include/, lib/)}"
# Extra link flags for the check programs. GCC 13.4 needs its specs file on
# every link; C++ links also need -Wl,-u,__cxa_pure_virtual.
DEPS_LINK_FLAGS="${DEPS_LINK_FLAGS:-}"
DEPS_CXX_LINK_FLAGS="${DEPS_CXX_LINK_FLAGS:-}"
export DEPS_LINK_FLAGS DEPS_CXX_LINK_FLAGS

DEPS_UPSTREAM="${DEPS_UPSTREAM:-$DEPS_ROOT/upstream/deps}"
DEPS_WORK="${DEPS_WORK:-$DEPS_ROOT/work/deps}"
DEPS_BUILD="${DEPS_BUILD:-$DEPS_ROOT/build/deps/$DEPS_TARGET}"
DEPS_PREFIX="${DEPS_PREFIX:-$DEPS_ROOT/staging/deps/$DEPS_TARGET}"
DEPS_JOBS="${DEPS_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

AROS_CC="${AROS_CC:-$AROS_GCC_ROOT/x86_64-aros-gcc}"
AROS_CXX="${AROS_CXX:-$AROS_GCC_ROOT/x86_64-aros-g++}"
AROS_AR="${AROS_AR:-$AROS_GCC_ROOT/x86_64-aros-ar}"
AROS_RANLIB="${AROS_RANLIB:-$AROS_GCC_ROOT/x86_64-aros-ranlib}"
AROS_NM="${AROS_NM:-$AROS_GCC_ROOT/x86_64-aros-nm}"
AROS_STRIP="${AROS_STRIP:-$AROS_GCC_ROOT/x86_64-aros-strip}"

export DEPS_PREFIX AROS_SDK AROS_CC AROS_CXX AROS_AR AROS_RANLIB AROS_NM AROS_STRIP

DEPS_TOOLCHAIN_FILE="$DEPS_SCRIPT_DIR/aros-x86_64.cmake"

deps_die() { echo "deps: $*" >&2; exit 1; }

# Load deps/<name>/recipe.env into RECIPE_* variables. Recipes are bash.
deps_load_recipe() {
  local name="$1" file="$DEPS_RECIPES/$1/recipe.env"
  [ -f "$file" ] || deps_die "no recipe $file"
  unset RECIPE_NAME RECIPE_VERSION RECIPE_URL RECIPE_SHA256 RECIPE_ARCHIVE RECIPE_SRCDIR RECIPE_LICENSE_FILES
  RECIPE_CMAKE_ARGS=()
  # shellcheck disable=SC1090
  source "$file"
  [ "$RECIPE_NAME" = "$name" ] || deps_die "$file: RECIPE_NAME '$RECIPE_NAME' != '$name'"
  RECIPE_DIR="$DEPS_RECIPES/$name"
  RECIPE_PATCHES="$RECIPE_DIR/patches"
  RECIPE_TARBALL="$DEPS_UPSTREAM/$RECIPE_ARCHIVE"
  RECIPE_WORK="$DEPS_WORK/$RECIPE_SRCDIR"
  RECIPE_BUILD="$DEPS_BUILD/$name"
}

deps_sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

deps_all() {
  local d
  for d in "$DEPS_RECIPES"/*/recipe.env; do basename "$(dirname "$d")"; done
}
