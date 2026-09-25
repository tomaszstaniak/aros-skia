#!/bin/bash
# Build libskia.a for one m154 variant from the patched tree and the frozen
# source list config/m154/sources-$M154_VARIANT.txt.
#
#   M154_VARIANT=codecs M154_BUILD_TYPE=release scripts/m154/build.sh
#
# Output: build/m154/<variant>-<type>/libskia.a, build.log, flags.txt.
# Compile only; no guest run.
set -euo pipefail
source "$(dirname "$0")/env.sh"

[ -f "$M154_WORK/include/core/SkCanvas.h" ] || { echo "build: no $M154_WORK, run scripts/m154/fetch.sh" >&2; exit 1; }
[ -x "$M154_CXX" ] || { echo "build: no $M154_CXX (GCC 13.4 toolchain)" >&2; exit 1; }
if [ "$M154_VARIANT" != raster ]; then
  for f in libjpeg.a libwebp.a; do
    [ -f "$DEPS_PREFIX/lib/$f" ] || { echo "build: no $DEPS_PREFIX/lib/$f, run scripts/deps/build.sh" >&2; exit 1; }
  done
fi

rm -rf "$M154_BUILD"
mkdir -p "$M154_BUILD"
FLAGS=(--sysroot="$AROS_SDK" -std=c++20 $(m154_opt_flags) -fno-exceptions -fno-rtti -w
       -I "$M154_WORK")
while read -r d; do FLAGS+=("-D$d"); done < <(m154_public_defs; m154_private_defs)
if [ "$M154_VARIANT" != raster ]; then FLAGS+=(-I "$DEPS_PREFIX/include"); fi
printf '%s\n' "${FLAGS[@]}" >"$M154_BUILD/flags.txt"

python3 - "$M154_WORK" "$M154_CONFIG/sources-$M154_VARIANT.txt" "$M154_BUILD" "$M154_CXX" "$M154_AR" "$M154_BUILD/flags.txt" <<'PY'
import concurrent.futures as cf, os, subprocess, sys
skia, lst, out, cxx, ar, flagfile = sys.argv[1:]
flags = open(flagfile).read().split("\n")[:-1]
per_file = {
    "modules/skcms/src/skcms_TransformHsw.cc": ["-ffp-contract=off", "-mf16c", "-mavx2"],
    "modules/skcms/src/skcms_TransformSkx.cc": ["-ffp-contract=off", "-mavx512f", "-mavx512dq",
                                                "-mavx512cd", "-mavx512bw", "-mavx512vl"],
}
srcs = [l.strip() for l in open(lst) if l.strip() and not l.startswith("#")]
def one(path):
    obj = os.path.join(out, "obj", path + ".o")
    os.makedirs(os.path.dirname(obj), exist_ok=True)
    r = subprocess.run([cxx, *flags, *per_file.get(path, []), "-c", os.path.join(skia, path), "-o", obj],
                       capture_output=True, text=True)
    return path, obj, r.returncode, r.stderr
with cf.ThreadPoolExecutor(os.cpu_count()) as ex:
    res = list(ex.map(one, srcs))
bad = [r for r in res if r[2]]
with open(os.path.join(out, "build.log"), "w") as log:
    for path, _, rc, err in res:
        log.write(f"{'ok' if rc == 0 else 'FAIL'} {path}\n")
        if rc: log.write(err + "\n")
if bad:
    for path, _, _, err in bad:
        print("build: FAIL", path, next((l for l in err.splitlines() if "error" in l), ""))
    sys.exit(1)
lib = os.path.join(out, "libskia.a")
subprocess.run([ar, "rcs", lib, *[r[1] for r in res]], check=True)
print(f"build: {len(res)}/{len(srcs)} -> {lib} ({os.path.getsize(lib)} bytes)")
PY
