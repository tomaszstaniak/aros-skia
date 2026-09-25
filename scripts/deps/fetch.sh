#!/bin/bash
# Download, verify and unpack pinned dependency tarballs, then apply the
# recipe's patch series.
#
#   scripts/deps/fetch.sh [name ...]      (default: every deps/*/recipe.env)
#
# Tarballs land in $DEPS_UPSTREAM and are never modified. The patched tree
# is $DEPS_WORK/<srcdir>; it is regenerated whenever the tarball hash or
# the patch series changes, so do not edit it in place without saving the
# change as a patch first.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

fetch_one() {
  deps_load_recipe "$1"
  mkdir -p "$DEPS_UPSTREAM" "$DEPS_WORK"

  if [ ! -f "$RECIPE_TARBALL" ]; then
    echo "fetch: $RECIPE_NAME $RECIPE_VERSION <- $RECIPE_URL"
    curl -fL --retry 3 -o "$RECIPE_TARBALL.part" "$RECIPE_URL"
    mv "$RECIPE_TARBALL.part" "$RECIPE_TARBALL"
  fi
  local got
  got="$(deps_sha256 "$RECIPE_TARBALL")"
  if [ "$got" != "$RECIPE_SHA256" ]; then
    deps_die "$RECIPE_ARCHIVE: sha256 $got != pinned $RECIPE_SHA256 (delete it to re-download)"
  fi

  local series="$RECIPE_PATCHES/series" stamp want
  want="$RECIPE_SHA256"
  if [ -f "$series" ]; then
    while IFS= read -r p; do
      case "$p" in ''|\#*) continue ;; esac
      want="$want $(deps_sha256 "$RECIPE_PATCHES/$p")"
    done < "$series"
  fi
  stamp="$RECIPE_WORK/.aros-deps-stamp"
  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$want" ]; then
    echo "fetch: $RECIPE_NAME work tree up to date ($RECIPE_WORK)"
    return 0
  fi

  rm -rf "$RECIPE_WORK"
  tar -xf "$RECIPE_TARBALL" -C "$DEPS_WORK"
  [ -d "$RECIPE_WORK" ] || deps_die "$RECIPE_ARCHIVE did not unpack to $RECIPE_SRCDIR"
  if [ -f "$series" ]; then
    while IFS= read -r p; do
      case "$p" in ''|\#*) continue ;; esac
      echo "fetch: $RECIPE_NAME applying $p"
      patch -d "$RECIPE_WORK" -p1 --forward --no-backup-if-mismatch < "$RECIPE_PATCHES/$p"
    done < "$series"
  fi
  printf '%s\n' "$want" > "$stamp"
  echo "fetch: $RECIPE_NAME $RECIPE_VERSION ready in $RECIPE_WORK"
}

if [ $# -eq 0 ]; then set -- $(deps_all); fi
for n in "$@"; do fetch_one "$n"; done
