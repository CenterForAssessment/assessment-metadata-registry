# `serve/` — registry query API + MCP backend (Tier C)

A **read-only** JSON/SQL query surface plus an **MCP server** over the registry, for
building product against and for AI-guided exploration/comparison of the metadata.
Decision + rationale: [`wiki/decisions/012-query-api-mcp-backend.md`](../wiki/decisions/012-query-api-mcp-backend.md).

This is **Tier C** — derived and disposable. It serves `build/registry.sqlite`, a
projection of the canonical JSON sidecars produced by `amrr::build_registry()`. It is
**never** a source of truth and has **no write path**:

- Datasette runs immutable (`-i`); the MCP server opens the DB `mode=ro`; the container
  mounts the DB `:ro`.
- Responses are **SHA-stamped** (`git_sha` from `registry_meta`) but this is the **latest
  build, not the reproducibility pin** — pin with
  `amrr::get_metadata(registry = "github://CenterForAssessment/assessment-metadata-registry", ref = <SHA>)`
  (ADR-011) or a checkout at a SHA.

## Layout

| Path | What |
|------|------|
| `datasette/metadata.yaml` | Datasette 0.65.x config: human metadata, per-table docs, canned queries, `{{GIT_SHA}}` slot |
| `datasette/render_metadata.sh` | Stamps `git_sha`/`built_at` from the DB into a rendered metadata file (deploy-time) |
| `mcp/server.py` | FastMCP server — the 5 read-only tools |
| `mcp/registry_db.py` | Read-only (`mode=ro`) connection + SELECT-only guard + git_sha envelope |
| `mcp/tool_schemas.json` | Machine-readable dual REST+MCP contract |
| `docker-compose.yml`, `Dockerfile.mcp`, `Caddyfile` | The VPS stack: Datasette + MCP + Caddy (auto-TLS) |
| `deploy/bootstrap-vps.sh` | One-time box setup (human) |
| `deploy/deploy.sh` | Runs on the box: render → atomic-swap DB → `compose up` |

## Run locally

**Without Docker** (quickest — needs `pipx install datasette`):

```bash
make serve-native      # builds the DB, renders metadata, runs Datasette on :8001
```

Then:

```bash
curl -s 'localhost:8001/registry/jurisdiction.json?_shape=objects'
curl -s 'localhost:8001/registry.json?_shape=objects' --data-urlencode \
  "sql=select jurisdiction_id, year, vendor from administration where year='2024'" -G
curl -s 'localhost:8001/registry/provenance.json'                 # git_sha
curl -s 'localhost:8001/registry/compare_achievement_levels.json?content_area=ELA&year=2024&_shape=objects'
```

**MCP server over stdio** (for Claude Code):

```bash
make mcp-local         # AMRR_REGISTRY_DB=build/registry.sqlite python3 serve/mcp/server.py
```

Register it with Claude Code (needs `pip install "mcp>=1.28,<2"` in the invoking Python):

```json
{ "mcpServers": {
  "amr-registry": {
    "command": "python3",
    "args": ["serve/mcp/server.py"],
    "env": { "AMRR_REGISTRY_DB": "build/registry.sqlite", "PYTHONPATH": "serve/mcp" }
  }
}}
```

Tools: `describe_schema`, `query_registry(sql)`, `get_metadata(jurisdiction, system, year)`,
`compare_jurisdictions(jurisdictions[], content_area, year, dimension)`,
`list_changes(jurisdiction?, system?, since_year?)`. Content areas are UPPER-CASE
(`ELA`, `MATHEMATICS`, `READING`, `ELP_COMPOSITE`).

**Full stack via Docker** (needs Docker; mirrors the VPS):

```bash
make serve-local       # Datasette + MCP + Caddy via docker compose (AMR_DATA_DIR=build)
```

## Deploy (self-managed VPS)

1. Provision a box; run `sudo bash serve/deploy/bootstrap-vps.sh` on it.
2. Point a DNS A record at it (ports 80/443 open); set `AMR_API_HOST=<hostname>` in
   `/opt/amr-api/serve/.env`.
3. In the GitHub repo set variable `AMR_API_DEPLOY_ENABLED=true` and secrets `VPS_HOST`,
   `VPS_USER`, `VPS_SSH_KEY`.
4. Push to `main` (touching `serve/**`) or run the **deploy-api** workflow manually. CI
   builds `registry.sqlite`, rsyncs it + `serve/` to the box, then renders + atomically
   swaps the DB and restarts the stack.

The deploy workflow is **independent** of `build-publish` (Pages) and no-ops until
`AMR_API_DEPLOY_ENABLED` is set, so it is safe to merge before the box exists.
