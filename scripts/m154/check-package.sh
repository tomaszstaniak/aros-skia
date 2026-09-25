#!/bin/bash
# Unpack a package into an empty temporary directory and build its examples
# from there, so the test cannot see staging/, build/ or work/.
#
#   M154_VARIANT=codecs scripts/m154/check-package.sh [outdir]
set -euo pipefail
source "$(dirname "$0")/env.sh"
NAME="skia-aros-m154-$M154_TAG-abiv11-${M154_PIN:0:12}"
TGZ="$M154_DIST/$NAME.tar.gz"
[ -f "$TGZ" ] || { echo "check-package: no $TGZ" >&2; exit 1; }
(cd "$M154_DIST" && shasum -a 256 -c "$NAME.tar.gz.sha256" >/dev/null)
TMP="$(mktemp -d "${TMPDIR:-/tmp}/skia-m154-pkg.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
tar -C "$TMP" -xzf "$TGZ"
# A package must not carry the build machine's paths, in text or in binaries.
leaks=$(for f in $(find "$TMP/$NAME" -type f); do strings -a "$f" | grep -E "^/(Users|home|Volumes|private|tmp)/" | sed "s|^|${f#$TMP/}: |"; done | head -5)
if [ -n "$leaks" ]; then echo "check-package: host paths in $NAME:" >&2; echo "$leaks" >&2; exit 1; fi
OUT="${1:-$M154_BUILD/package-examples}"
M154_PREFIX="$TMP/$NAME" "$(dirname "$0")/check-install.sh" "$TMP/$NAME" "$OUT"
echo "check-package: $NAME ok"
