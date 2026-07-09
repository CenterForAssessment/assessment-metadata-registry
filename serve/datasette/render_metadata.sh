#!/usr/bin/env bash
# Stamp the DB's provenance (git_sha, built_at) into a rendered Datasette metadata
# file, so the served instance always advertises the exact SHA of the DB it holds.
# Read-only on the DB. Runs at deploy time (on the VPS) or locally before a native run.
#
# Usage: render_metadata.sh <registry.sqlite> <template.yaml> <out.yaml>
set -euo pipefail

DB="${1:?usage: render_metadata.sh <registry.sqlite> <template.yaml> <out.yaml>}"
TEMPLATE="${2:?missing template.yaml}"
OUT="${3:?missing out.yaml}"

git_sha="$(sqlite3 "$DB" "select value from registry_meta where key='git_sha'")"
built_at="$(sqlite3 "$DB" "select value from registry_meta where key='built_at'")"

# '#' delimiter so ISO timestamps (with ':' and '+') substitute cleanly.
sed -e "s#{{GIT_SHA}}#${git_sha}#g" \
    -e "s#{{BUILT_AT}}#${built_at}#g" \
    "$TEMPLATE" > "$OUT"

echo "rendered ${OUT} (git_sha=${git_sha}, built_at=${built_at})"
