# Settings for the Skia m154 line (the commit WebKitGTK 2.54 bundles).
# Sourced by every scripts/m154 script.
# Override anything with the environment or the ignored local.env.
# Supported shell: bash.

M154_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$M154_SCRIPT_DIR/../.." && pwd)"

if [ -f "$PROJECT_ROOT/local.env" ]; then
  # Same local.env rules as scripts/env.sh: environment wins, relative paths
  # resolve against the file.
  eval "$(python3 - "$PROJECT_ROOT/local.env" <<'PY'
import os, shlex, sys
from pathlib import Path
path = Path(sys.argv[1])
for raw in path.read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, val = (s.strip() for s in line.split("=", 1))
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
        val = val[1:-1]
    if not key or key in os.environ:
        continue
    if val and not Path(val).is_absolute():
        val = str((path.parent / val).resolve())
    print(f"export {key}={shlex.quote(val)}")
PY
)"
fi

# ABIv11 only. mainline v1 is not built for this line.
AROS_TARGET="${AROS_TARGET:-one}"
[ "$AROS_TARGET" = one ] || { echo "m154: only AROS_TARGET=one (ABIv11) is supported" >&2; return 1 2>/dev/null || exit 1; }

# Toolchain: x86_64-aros GCC 13.4.0 for ABIv11, built with
# toolchain/build-gcc13.sh. The SDK is the Development/ directory of AROS One
# (include/, lib/). No machine defaults: set both, or put them in local.env.
: "${AROS_GCC13_ROOT:?m154: set AROS_GCC13_ROOT to the GCC 13.4 toolchain (toolchain/build-gcc13.sh)}"
: "${AROS_SDK:?m154: set AROS_SDK to the ABIv11 SDK (Development/ of AROS One: include/, lib/)}"
M154_CXX="${M154_CXX:-$AROS_GCC13_ROOT/x86_64-aros-g++}"
M154_AR="${M154_AR:-$AROS_GCC13_ROOT/x86_64-aros-ar}"
M154_SPECS="${M154_SPECS:-$PROJECT_ROOT/toolchain/aros-v11.specs}"

# Pin (upstreams.json "skia-m154") and inputs.
M154_PIN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repositories"]["skia-m154"]["commit"])' "$PROJECT_ROOT/upstreams.json")"
M154_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repositories"]["skia-m154"]["url"])' "$PROJECT_ROOT/upstreams.json")"
M154_MILESTONE=154
M154_UPSTREAM="$PROJECT_ROOT/upstream/skia-m154"
M154_WORK="$PROJECT_ROOT/work/skia-m154-src"
M154_PATCHES="$PROJECT_ROOT/patches/skia-m154"
M154_CONFIG="$PROJECT_ROOT/config/m154"
DEPS_PREFIX="${DEPS_PREFIX:-$PROJECT_ROOT/staging/deps/one}"

# Variant (raster | codecs | gl) and build type (release | debug).
M154_VARIANT="${M154_VARIANT:-codecs}"
M154_BUILD_TYPE="${M154_BUILD_TYPE:-release}"
case "$M154_VARIANT" in raster|codecs|gl) ;; *) echo "m154: M154_VARIANT must be raster|codecs|gl" >&2; return 1 2>/dev/null || exit 1 ;; esac
case "$M154_BUILD_TYPE" in release|debug) ;; *) echo "m154: M154_BUILD_TYPE must be release|debug" >&2; return 1 2>/dev/null || exit 1 ;; esac
M154_TAG="$M154_VARIANT-$M154_BUILD_TYPE"
M154_BUILD="$PROJECT_ROOT/build/m154/$M154_TAG"
M154_PREFIX="${M154_PREFIX:-$PROJECT_ROOT/staging/m154/$M154_TAG}"
M154_DIST="$PROJECT_ROOT/dist"

# Definitions. PUBLIC ones change what headers mean and are exported to
# consumers (pkg-config, manifest); PRIVATE ones only affect the library.
m154_public_defs() {
  local d=(SK_DISABLE_TRACING SK_DISABLE_LEGACY_IMAGE_READBUFFER
           SK_DISABLE_LEGACY_INIT_DECODERS SK_DISABLE_LEGACY_PNG_WRITEBUFFER)
  if [ "$M154_BUILD_TYPE" = debug ]; then d+=(SK_DEBUG); else d+=(SK_RELEASE); fi
  if [ "$M154_VARIANT" = gl ]; then
    d+=(SK_GL SK_GANESH SK_DISABLE_WEBGL_INTERFACE SK_DISABLE_LEGACY_GL_MAKE_NATIVE_INTERFACE)
  fi
  printf '%s\n' "${d[@]}"
}
m154_private_defs() {
  local d=(SKIA_IMPLEMENTATION=1 SKSHAPER_IMPLEMENTATION=1 SK_GAMMA_APPLY_TO_A8
           SK_ENABLE_AVX512_OPTS SK_CODEC_DECODES_PNG
           SK_FREETYPE_MINIMUM_RUNTIME_VERSION_IS_BUILD_VERSION)
  if [ "$M154_VARIANT" != raster ]; then d+=(SK_CODEC_DECODES_JPEG SK_CODEC_DECODES_WEBP); fi
  printf '%s\n' "${d[@]}"
}
m154_opt_flags() {
  if [ "$M154_BUILD_TYPE" = debug ]; then echo "-O1 -g"; else echo "-O2"; fi
}
