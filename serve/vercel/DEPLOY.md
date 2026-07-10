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

## Vercel's Git integration must stay OFF

**Vercel can never build this project.** `registry.sqlite` is a derived artifact produced by
`amrr::build_registry()` — it needs R and the `amrr` package, which the Vercel build image does
not have, and it is git-ignored so it is not in the repo either. A Git-triggered build can
therefore only ever produce a broken deployment, and it would promote that to production.

Deploys happen **only** from `.github/workflows/deploy-vercel.yml`, which has R, rebuilds the DB
from the canonical sidecars, and then asserts the result.

Two files enforce this, and **both are needed** — do not delete either as redundant:

| File | Read when | Why |
|---|---|---|
| `vercel.json` (repo root) | Vercel project **Root Directory = `.`** | Kills Git-triggered builds even with the default root setting |
| `serve/vercel/vercel.json` | Root Directory = `serve/vercel` | Kills them once the root is set correctly |

Both set `"git": { "deploymentEnabled": false }`. This governs *Git-triggered* deployments only —
an explicit `vercel deploy` from the CLI (what CI does) is unaffected.

If you connect the repo in the Vercel dashboard, also set **Root Directory = `serve/vercel`**,
or a Git build would try to publish the repository root — `metadata/`, `wiki/`, and all — as a
static site.

## `.vercelignore` is load-bearing

`data/*.sqlite` is **git-ignored** (the DB is a derived, disposable projection and must
not enter git). But it **must be uploaded** so `vercel.json`'s `functions.includeFiles`
can bundle it. Absent a `.vercelignore`, the CLI falls back to `.gitignore` and the DB
never reaches the build — every endpoint then fails `db_not_found`. Do not delete it.

## Deploy (human steps)

1. **Real DB, not the fixture:**
   ```sh
   make build                                  # repo root: amrr::build_registry()
   mkdir -p serve/vercel/data     # only .gitkeep is tracked there; the DB is git-ignored
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
npm run smoke       # 22 checks
npm run test:guard  # SELECT-only guard vs the shared corpus (no DB needed)
```

## The guard corpus is shared with dataimago-ai

`lib/__fixtures__/select-only-cases.json` specifies `assertSelectOnly()` by example.
A byte-identical copy lives in `dataimago-ai` at
`packages/shared-utils/src/store/__fixtures__/`, where the Level-1 port of this guard
(`@dataimago/shared-utils/store`) runs the same cases. Two independent implementations,
one specification — which is what makes it safe to eventually consume the L1 primitives
here instead of `lib/registry-db.ts`.

To change guard behaviour, change the corpus and **both** implementations, and bump
`_corpus_version`. Nothing checks byte-identity across the two orgs automatically;
`_corpus_version` is the tripwire. `.github/workflows/serve-checks.yml` runs the corpus
on every pull request that touches `serve/vercel/`, and `deploy-vercel.yml` runs it again
before deploying.

One case is a **deliberate false positive**: `select ';' as x` is rejected as
`multiple_statements`, because the guard does not tokenize string literals. It is locked
in the corpus so both implementations fail identically. The real backstop is the
read-only connection, not the guard.

## Invariants (D1 contract — do not relax)

- DB opened `readonly: true` everywhere; fresh connection per call.
- `assertSelectOnly()` on every SQL-accepting surface (single statement, SELECT/WITH
  only, whole-word forbidden-keyword rejection).
- Every response carries `git_sha` — convenience/latest, **never** the reproducibility
  pin (that remains `github://…` + SHA, ADR-011).
- The deployed DB is always `amrr::build_registry()` output; the fixture never ships
  (`registry_meta.fixture = "true"` marks it).

## CI (the normal path — prefer it over deploying by hand)

`.github/workflows/deploy-vercel.yml` runs on every push to `main` that touches `metadata/`,
`schemas/`, `r-pkg/amrr/`, or `serve/vercel/`. It rebuilds the DB from the canonical sidecars,
deploys, and then **asserts**: 22/22 smoke against the live URL · `live git_sha == GITHUB_SHA` ·
HTTP 404 on `/data/registry.sqlite`.

Deploy by hand only when you must, and understand what you are giving up: `build_registry()`
stamps the DB from the checked-out HEAD, so a hand-deploy's `git_sha` is orphaned by the next
rebase or squash-merge, and every API response then cites a commit that no longer exists. If you
do deploy by hand, re-verify:

```sh
[ "$(curl -s "$PROD/api/schema" | jq -r .git_sha)" = "$(git rev-parse HEAD)" ] && echo ok
```

Enable the workflow with the repo variable `AMR_VERCEL_DEPLOY_ENABLED=true` and these secrets:

| Secret | Where to find it |
|---|---|
| `VERCEL_TOKEN` | Vercel → Account Settings → Tokens |
| `VERCEL_ORG_ID` | `serve/vercel/.vercel/project.json` → `orgId` |
| `VERCEL_PROJECT_ID` | `serve/vercel/.vercel/project.json` → `projectId` |

Optional repo variable `AMR_VERCEL_URL` overrides the production alias.

## Follow-ons (deferred)

- Publish `registry-<sha>.sqlite` as a Release asset (per-SHA retention, ADR-012).
- Graduate the **generic** half of `lib/` into the dataimago L1 store primitives
  (`@dataimago/shared-utils/store`) and consume it here. The five tools are domain and stay.
  Contract: `dataimago.store.v1` (dataimago-design `data-store-contract`).
