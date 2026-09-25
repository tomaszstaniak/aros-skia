#!/bin/bash
# Fetch Skia at the m154 pin and produce a freshly patched source tree.
#
#   scripts/m154/fetch.sh
#
# upstream/skia-m154  shallow clone at the pin (reused if already at the pin)
# work/skia-m154-src  recreated from it on every run, patches applied in
#                     series order; nothing else in work/ is read.
# M154_LOCAL_PIN may point at an existing checkout at the same commit to
# avoid the network.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if [ -d "$M154_UPSTREAM/.git" ] && [ "$(git -C "$M154_UPSTREAM" rev-parse HEAD 2>/dev/null)" = "$M154_PIN" ]; then
  echo "fetch: $M154_UPSTREAM already at $M154_PIN"
else
  rm -rf "$M154_UPSTREAM"
  mkdir -p "$M154_UPSTREAM"
  git -C "$M154_UPSTREAM" init -q
  src="$M154_URL"
  if [ -n "${M154_LOCAL_PIN:-}" ]; then src="$M154_LOCAL_PIN"; fi
  echo "fetch: $src @ $M154_PIN"
  git -C "$M154_UPSTREAM" fetch -q --depth 1 "$src" "$M154_PIN"
  git -C "$M154_UPSTREAM" checkout -q --detach FETCH_HEAD
fi
[ "$(git -C "$M154_UPSTREAM" rev-parse HEAD)" = "$M154_PIN" ] || { echo "fetch: pin mismatch" >&2; exit 1; }
[ -z "$(git -C "$M154_UPSTREAM" status --porcelain)" ] || { echo "fetch: $M154_UPSTREAM is dirty" >&2; exit 1; }

rm -rf "$M154_WORK"
git clone -q --no-hardlinks "$M154_UPSTREAM" "$M154_WORK"
while IFS= read -r p || [ -n "$p" ]; do
  case "$p" in ''|\#*) continue ;; esac
  git -C "$M154_WORK" apply --whitespace=nowarn "$M154_PATCHES/$p"
  echo "fetch: applied $p"
done <"$M154_PATCHES/series"
echo "fetch: $M154_WORK ready ($(git -C "$M154_WORK" diff --stat | tail -1))"
