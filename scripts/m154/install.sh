#!/bin/bash
# Install one built m154 variant into its own prefix.
#
#   M154_VARIANT=codecs M154_BUILD_TYPE=release scripts/m154/install.sh
#
# Layout (the prefix is the Skia include root, as in the m124 SDK):
#   include/ modules/skcms/ modules/skshaper/include/   Skia headers
#   lib/libskia.a                                       this variant
#   lib/pkgconfig/skia-aros-m154.pc                     consumer flags
#   deps/include deps/lib                               codecs, gl: static deps
#   share/skia-aros-m154/MANIFEST.{json,txt}            features, deps, flags
#   share/skia-aros-m154/aros-v11-gcc13.specs           link specs for GCC 13.4
#   share/licenses/                                     Skia and deps
set -euo pipefail
source "$(dirname "$0")/env.sh"

LIB="$M154_BUILD/libskia.a"
[ -f "$LIB" ] || { echo "install: no $LIB, run scripts/m154/build.sh" >&2; exit 1; }
for f in libfreetype2.static.a libpng_nostdio.a libz.static.a; do
  [ -f "$AROS_SDK/lib/$f" ] || { echo "install: missing $AROS_SDK/lib/$f" >&2; exit 1; }
done

P="$M154_PREFIX"
rm -rf "$P"
mkdir -p "$P/lib/pkgconfig" "$P/share/skia-aros-m154" "$P/share/licenses/skia"
cp -a "$M154_WORK/include" "$P/include"
for dir in modules/skcms modules/skshaper/include; do
  (cd "$M154_WORK" && find "$dir" -name '*.h' -print0) | while IFS= read -r -d '' h; do
    mkdir -p "$P/$(dirname "$h")"; cp "$M154_WORK/$h" "$P/$h"
  done
done
cp "$LIB" "$P/lib/libskia.a"
cp "$M154_SPECS" "$P/share/skia-aros-m154/aros-v11-gcc13.specs"
cp "$M154_WORK/LICENSE" "$P/share/licenses/skia/LICENSE"

DEPLIBS=()
if [ "$M154_VARIANT" != raster ]; then
  mkdir -p "$P/deps/include" "$P/deps/lib"
  cp -a "$DEPS_PREFIX/include/." "$P/deps/include/"
  # Link order: webp users first, then webp, sharpyuv, jpeg; harfbuzz is for
  # the application's own shaping (Skia's HarfBuzz SkShaper is not built).
  DEPLIBS=(libwebpdemux.a libwebpmux.a libwebp.a libsharpyuv.a libjpeg.a libharfbuzz.a)
  for a in "${DEPLIBS[@]}"; do cp "$DEPS_PREFIX/lib/$a" "$P/deps/lib/$a"; done
  cp -a "$DEPS_PREFIX/share/licenses/." "$P/share/licenses/"
fi

python3 - "$PROJECT_ROOT" "$P" "$M154_VARIANT" "$M154_BUILD_TYPE" "$M154_PIN" "$M154_MILESTONE" \
  "$M154_SPECS" "$M154_PATCHES" "$M154_CONFIG/sources-$M154_VARIANT.txt" \
  "$(m154_public_defs | tr '\n' ' ')" "$(m154_private_defs | tr '\n' ' ')" "${DEPLIBS[*]:-}" \
  "$("$M154_CXX" -dumpversion)" <<'PY'
import hashlib, json, os, sys
(root, prefix, variant, btype, pin, milestone, specs, patches, srclist,
 pubdefs, privdefs, deplibs, gccver) = sys.argv[1:]
pubdefs, privdefs, deplibs = pubdefs.split(), privdefs.split(), deplibs.split()
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
series = [l.strip() for l in open(os.path.join(patches, "series")) if l.strip() and not l.startswith("#")]

tested = {
    "raster": [
        "CPU raster backend (SkSurfaces::Raster): shapes, AA paths, linear gradient",
        "FreeType typefaces from a file or data (SkFontMgr_New_Custom_Empty), text drawing",
        "PNG encode (SkPngEncoder)",
    ],
    "codecs": [
        "JPEG encode/decode through Skia (libjpeg-turbo 3.2.0)",
        "WebP lossless/lossy encode/decode through Skia (libwebp 1.6.0)",
        "HarfBuzz 14.5.0 shaping by the application (hb_shape) drawn as Skia glyph runs: ligature, kerning, Polish text",
    ],
    "gl": [
        "Ganesh on GL through a caller-assembled GrGLInterface (GrGLMakeAssembledInterface + GLA glAGetProcAddress)",
        "Matches the raster backend except anti-aliased edges",
    ],
}
built_untested = {
    "raster": ["PNG decode (SkPngDecoder)", "skcms colour management", "SkShaper primitive shaper (modules/skshaper, no HarfBuzz)",
               "SkFontMgr_New_Custom_Directory", "threads in Skia's own executor"],
    "codecs": [], "gl": ["many surfaces, GPU text atlas under load, context loss"],
}
not_included = ["SkShaper HarfBuzz backend and SkUnicode (need ICU or libgrapheme)",
                "fontconfig font manager", "SVG module, PDF backend", "EGL/epoxy GL glue, Vulkan, Graphite",
                "mainline v1 (ABIv11 only)"]
if variant != "gl":
    not_included.insert(0, "Ganesh GPU backend (use the gl variant)")
if variant == "raster":
    not_included.insert(0, "JPEG and WebP codecs, HarfBuzz (use the codecs variant)")

feat_tested = tested["raster"] + (tested["codecs"] if variant in ("codecs", "gl") else []) + (tested["gl"] if variant == "gl" else [])
feat_untested = built_untested["raster"] + (built_untested["gl"] if variant == "gl" else [])

deps = [{"name": "FreeType 2 (static, from the ABIv11 SDK)", "link": "${aros_sdk}/lib/libfreetype2.static.a"},
        {"name": "libpng (static, SDK)", "link": "${aros_sdk}/lib/libpng_nostdio.a"},
        {"name": "zlib (static, SDK)", "link": "${aros_sdk}/lib/libz.static.a"}]
lic = os.path.join(prefix, "share", "licenses")
for d in sorted(os.listdir(lic)):
    src = os.path.join(lic, d, "SOURCE")
    if os.path.exists(src):
        name_ver, srcsha, license = open(src).read().split("\n")[:3]
        deps.append({"name": name_ver, "source_sha256": srcsha, "license": license, "bundled": True})
if variant == "gl":
    deps.append({"name": "gl.library via the SDK's libGL.a stub (Mesa at runtime)", "link": "-lGL"})

manifest = {
    "id": "skia-aros-m154", "variant": variant, "build_type": btype,
    "default_variant": variant == "codecs",
    "status": "release: the default SDK" if btype == "release" else "debug: diagnostic variant (SK_DEBUG assertions, -g); use release for normal work",
    "optional": variant == "gl",
    "target": "AROS x86_64 ABIv11 (AROS One)",
    "skia": {"commit": pin, "milestone": int(milestone), "source": "skia.googlesource.com",
             "why_this_commit": "the Skia WebKitGTK 2.54.0 bundles"},
    "patches": [{"file": p, "sha256": sha(os.path.join(patches, p))} for p in series],
    "sources": {"list": os.path.basename(srclist), "count": sum(1 for l in open(srclist) if l.strip() and not l.startswith("#"))},
    "toolchain": {"compiler": f"x86_64-aros GCC {gccver}, built with toolchain/build-gcc13.sh (includes the libgcc unwinder fix)",
                  "specs": "share/skia-aros-m154/aros-v11-gcc13.specs", "specs_sha256": sha(specs),
                  "rule": "Use one tested set: this GCC 13.4 for everything (Skia, its dependencies and your program), its libstdc++/libgcc, and the SDK's C libraries. Other combinations are not supported."},
    "consumer": {
        "cxxflags": ["-std=c++20", f"-I<prefix>"] + (["-I<prefix>/deps/include"] if variant != "raster" else []) + [f"-D{d}" for d in pubdefs],
        "link": ["-specs=<prefix>/share/skia-aros-m154/aros-v11-gcc13.specs", "-L<prefix>/lib -lskia"]
                + [f"<prefix>/deps/lib/{a}" for a in deplibs]
                + ["<aros_sdk>/lib/libfreetype2.static.a", "<aros_sdk>/lib/libpng_nostdio.a", "<aros_sdk>/lib/libz.static.a"]
                + (["-lGL"] if variant == "gl" else []) + ["-Wl,-u,__cxa_pure_virtual"],
        "public_defines_must_match": pubdefs,
        "runtime": ["run GL programs with Stack 8000000 or more (Mesa softpipe)"] if variant == "gl" else [],
    },
    "private_defines": privdefs,
    "features_tested_on_aros_one": feat_tested,
    "features_built_not_tested": feat_untested,
    "not_included": not_included,
    "dependencies": deps,
    "evidence": "docs/testing.md in the skia-aros source repository",
    "gl_performance_note": "Two measurements of one benchmark (10 frames of the gl example scene, Mesa 20.0.8 softpipe in QEMU): Ganesh was about 14x and about 24x slower than the raster backend. Not a general performance figure; no hardware GL driver was tested." if variant == "gl" else None,
    "files": {"lib/libskia.a": sha(os.path.join(prefix, "lib", "libskia.a"))},
}
out = os.path.join(prefix, "share", "skia-aros-m154")
json.dump(manifest, open(os.path.join(out, "MANIFEST.json"), "w"), indent=2)
with open(os.path.join(out, "MANIFEST.txt"), "w") as f:
    f.write(f"skia-aros-m154  variant={variant}  build={btype}  {manifest['status']}\n")
    f.write(f"Skia {pin} (m{milestone}); {manifest['target']}\n")
    if variant == "gl": f.write("OPTIONAL variant: Ganesh on GL through GLA works on Mesa softpipe (software GL, not hardware acceleration).\n" + manifest["gl_performance_note"] + "\n")
    if variant == "codecs": f.write("DEFAULT variant.\n")
    f.write(manifest["status"] + "\n")
    for title, key in (("Tested on AROS One", "features_tested_on_aros_one"),
                       ("Built, not tested", "features_built_not_tested"), ("Not included", "not_included")):
        f.write(f"\n{title}:\n" + "".join(f"  - {x}\n" for x in manifest[key]))
    f.write("\nDependencies:\n" + "".join(f"  - {d['name']}\n" for d in deps))
    f.write("\nConsumer compile flags:\n  " + " ".join(manifest["consumer"]["cxxflags"]) + "\n")
    f.write("Consumer link:\n  " + " ".join(manifest["consumer"]["link"]) + "\n")
    f.write("\n" + manifest["toolchain"]["rule"] + "\n")

# pkg-config: prefix relative to the .pc file; the ABIv11 SDK is supplied by
# the consumer (--define-variable=aros_sdk=...).
cflags = "-std=c++20 -I${prefix}" + (" -I${prefix}/deps/include" if variant != "raster" else "") + " " + " ".join(f"-D{d}" for d in pubdefs)
libs_private = " ".join([f"${{prefix}}/deps/lib/{a}" for a in deplibs] +
                        ["${aros_sdk}/lib/libfreetype2.static.a", "${aros_sdk}/lib/libpng_nostdio.a", "${aros_sdk}/lib/libz.static.a"] +
                        (["-lGL"] if variant == "gl" else []))
pc = f"""prefix=${{pcfiledir}}/../..
libdir=${{prefix}}/lib
aros_sdk=${{aros_sdk}}
specs=${{prefix}}/share/skia-aros-m154/aros-v11-gcc13.specs

Name: skia-aros-m154
Description: Skia m154 for AROS x86_64 ABIv11, variant {variant} ({btype}). GCC 13.4 only; link with -specs=${{specs}}
Version: {milestone}.0
URL: https://skia.org

# Pin {pin}. Consumers: pkg-config --define-variable=aros_sdk="$AROS_SDK" --static
Cflags: {cflags}
Libs: -L${{libdir}} -lskia -Wl,-u,__cxa_pure_virtual
Libs.private: {libs_private}
"""
open(os.path.join(prefix, "lib", "pkgconfig", "skia-aros-m154.pc"), "w").write(pc)
PY
echo "install: $P"
sed -n 1,4p "$P/share/skia-aros-m154/MANIFEST.txt"
