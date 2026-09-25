#!/bin/bash
# Pack one installed variant: dist/skia-aros-m154-<variant>-<type>-abiv11-<pin12>.tar.gz
# plus a .sha256. Local package; publishing is a separate decision.
set -euo pipefail
source "$(dirname "$0")/env.sh"
[ -f "$M154_PREFIX/share/skia-aros-m154/MANIFEST.json" ] || { echo "package: run scripts/m154/install.sh" >&2; exit 1; }
NAME="skia-aros-m154-$M154_TAG-abiv11-${M154_PIN:0:12}"
mkdir -p "$M154_DIST"
# Fixed owner and mtime order so two packs of the same prefix compare equal.
tar -C "$(dirname "$M154_PREFIX")" --uid 0 --gid 0 -s "|^$M154_TAG|$NAME|" -czf "$M154_DIST/$NAME.tar.gz" "$M154_TAG"
(cd "$M154_DIST" && shasum -a 256 "$NAME.tar.gz" >"$NAME.tar.gz.sha256")
echo "package: $M154_DIST/$NAME.tar.gz ($(wc -c <"$M154_DIST/$NAME.tar.gz") bytes)"
