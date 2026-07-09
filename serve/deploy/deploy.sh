#!/usr/bin/env bash
# Runs ON the VPS (invoked by the deploy-api workflow over SSH). The fresh DB has already
# been uploaded to $APP/data/registry.sqlite.new and serve/ has been rsync'd to $APP/serve.
# Render provenance from the new DB, swap DB + metadata into place ATOMICALLY (so a
# half-served file is never possible), then reload the stack. Read-only everywhere.
set -euo pipefail

APP="${AMR_APP_DIR:-/opt/amr-api}"
DATA="$APP/data"
SERVE="$APP/serve"

test -f "$DATA/registry.sqlite.new" || { echo "no uploaded DB at $DATA/registry.sqlite.new" >&2; exit 1; }

# Stamp git_sha/built_at from the NEW db into the rendered metadata (also .new).
bash "$SERVE/datasette/render_metadata.sh" \
  "$DATA/registry.sqlite.new" \
  "$SERVE/datasette/metadata.yaml" \
  "$DATA/metadata.rendered.yaml.new"

# Atomic swap (rename is atomic within a filesystem).
mv -f "$DATA/registry.sqlite.new"        "$DATA/registry.sqlite"
mv -f "$DATA/metadata.rendered.yaml.new" "$DATA/metadata.rendered.yaml"

# Reload: rebuild the MCP image (code may have changed), recreate services. Datasette and
# the MCP server both re-open the swapped read-only DB.
cd "$SERVE"
AMR_DATA_DIR="$DATA" docker compose up -d --build

echo "deployed git_sha=$(sqlite3 "$DATA/registry.sqlite" "select value from registry_meta where key='git_sha'")"
