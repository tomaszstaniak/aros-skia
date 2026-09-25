#!/bin/bash
# Full m154 chain in a given checkout (normally a fresh clone):
# deps fetch/build/check, m154 fetch, then build, install, check-install,
# package and check-package for every variant and build type.
#
#   scripts/m154/chain.sh <checkout> [release|debug|both]
set -euo pipefail
C="$1"; TYPES="${2:-both}"
cd "$C"
source scripts/m154/env.sh
# One toolchain for everything: the C dependencies are built with the same
# GCC 13.4 as Skia, and their check programs link through its specs file.
export AROS_GCC_ROOT="$AROS_GCC13_ROOT" AROS_SDK
export DEPS_LINK_FLAGS="-specs=$M154_SPECS" DEPS_CXX_LINK_FLAGS="-Wl,-u,__cxa_pure_virtual"
step(){ echo "=== $* ($(date +%H:%M:%S))"; }
step deps fetch; scripts/deps/fetch.sh
step deps build; scripts/deps/build.sh
step deps check; scripts/deps/check.sh | tail -2
step m154 fetch; scripts/m154/fetch.sh
case "$TYPES" in both) TYPES="release debug" ;; esac
for t in $TYPES; do
  for v in raster codecs gl; do
    export M154_VARIANT=$v M154_BUILD_TYPE=$t
    step build $v-$t; scripts/m154/build.sh
    step install $v-$t; scripts/m154/install.sh
    step check-install $v-$t; scripts/m154/check-install.sh
    step package $v-$t; scripts/m154/package.sh
    step check-package $v-$t; scripts/m154/check-package.sh
  done
done
step done
