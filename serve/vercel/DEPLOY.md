# serve/vercel — Tier 1 serverless deploy (ADR-012)

The registry query contract (D1) as Vercel functions over the bundled read-only
`registry.sqlite`: five REST endpoints + the five MCP tools over **stateless
streamable-http** at `/mcp`. No VPS, no always-on process.

Local validation is green — **22/22 smoke checks against the real
`amrr::build_registry()` output** (REST parity, SELECT-only guard rejections +
positive control, SHA-stamped envelopes, MCP initialize → list_tools → all 5 tools,
second-independent-client statelessness).

SQLite access is **`node:sqlite`** (Node ≥ 22.5; stable and flag-free on 24, which
`engines.node` pins). Deliberately not `better-sqlite3`: a native addon has to compile
in the Vercel build image, and it does not build against current Node at all.

## Layout

```
serve/vercel/
├── api/                 one function per REST endpoint + mcp.ts (stateless MCP)
├── lib/
│   ├── registry-db.ts   port of serve/mcp/registry_db.py (guard, envelope, MAX_ROWS)
│   ├── tools.ts         the 5 tools, shared by REST + MCP (shapes = tool_schemas.json)
│   └── mcp.ts           fresh McpServer per request (stateless)
├── data/registry.sqlite the bundled DB (gitignored; see below)
├── scripts/
│   ├── make-fixture-db.mjs  fixture DB from the REAL DDL (dev/test only; stamped fixture=true)
│   └── smoke.mjs            re-runnable smoke test (local or deployed URL)
├── local-server.ts      Vercel-routing emulation for local runs
├── .vercelignore        LOAD-BEARING — see below
└── vercel.json          /mcp rewrite + includeFiles for the DB
```

## `.vercelignore` is load-bearing

`data/*.sqlite` is **git-ignored** (the DB is a derived, disposable projection and must
not enter git). But it **must be uploaded** so `vercel.json`'s `functions.includeFiles`
can bundle it. Absent a `.vercelignore`, the CLI falls back to `.gitignore` and the DB
never reaches the build — every endpoint then fails `db_not_found`. Do not delete it.

## Deploy (human steps)

1. **Real DB, not the fixture:**
   ```sh
   make build                                  # repo root: amrr::build_registry()
   cp build/registry.sqlite serve/vercel/data/registry.sqlite
   ```
2. **Deploy:**
   ```sh
   cd serve/vercel
   npm install
   npm run typecheck
   npx vercel deploy --prod                    # first run: link/create the project
   ```
3. **Smoke the live URL (same script as local):**
   ```sh
   node scripts/smoke.mjs https://<project>.vercel.app
   ```
   22/22 = the Tier 1 milestone ("validate stateless streamable-http MCP on the
   serverless platform") is met.

   The corpus-dependent checks are **self-discovering**: smoke asks `/api/query` which
   `(content_area, year)` cell actually spans ≥ 2 jurisdictions, then compares on that
   cell. So the suite is green against the fixture, against the real 48-sidecar corpus,
   and against any future corpus. Do not re-introduce a hard-coded cell — the fixture
   and the real registry do not share one (the fixture has `ELA/2024 → IN,SC`; the real
   corpus has no IN∩SC year at all, and resolves to `MATHEMATICS/2025 → IN,SD`).
4. **Wire an agent:** Claude/other MCP clients point at
   `https://<project>.vercel.app/mcp` (streamable-http, no auth — public metadata only).

## Local loop

```sh
npm run fixture     # data/registry.sqlite from the real DDL (fixture=true stamped)
npm run dev         # http://127.0.0.1:3000
npm run smoke       # 21 checks
```

## Invariants (D1 contract — do not relax)

- DB opened `readonly: true` everywhere; fresh connection per call.
- `assertSelectOnly()` on every SQL-accepting surface (single statement, SELECT/WITH
  only, whole-word forbidden-keyword rejection).
- Every response carries `git_sha` — convenience/latest, **never** the reproducibility
  pin (that remains `github://…` + SHA, ADR-011).
- The deployed DB is always `amrr::build_registry()` output; the fixture never ships
  (`registry_meta.fixture = "true"` marks it).

## Follow-ons (deferred)

- CI: build DB + `vercel deploy` in an opt-in workflow (mirror of `deploy-api.yml`).
- Publish `registry-<sha>.sqlite` as a Release asset (per-SHA retention, ADR-012).
- Graduate `lib/` into the dataimago L1 `database` producer driver and consume it here.
