# Registry Wiki — Activity Log

Append-only, reverse-chronological. Newest entries on top.

---

## [2026-07-09] build | Tier 1 serverless slice: serve/vercel — validated on the real corpus (22/22)

**Action:** build (ADR-012 rev 1, Tier 1)

- **New `serve/vercel/`** — the D1 query contract as Vercel functions, TypeScript over the
  bundled read-only `registry.sqlite`. Five REST endpoints
  (`/api/{schema,query,metadata,compare,changes}`) + the five MCP tools over **stateless
  streamable-http** at `/mcp` (fresh `McpServer` + transport per request,
  `sessionIdGenerator: undefined`, `enableJsonResponse: true`). `lib/registry-db.ts` is a
  line-faithful port of `serve/mcp/registry_db.py` (SELECT-only guard, `MAX_ROWS`,
  SHA-stamped envelope); `lib/tools.ts` ports the 5 tools so REST and MCP share one
  implementation (shapes = `serve/mcp/tool_schemas.json`).
- **SQLite engine: `node:sqlite`, not `better-sqlite3`.** The native addon does not build
  against current Node (V8 header removals; no prebuild), and a native binary must compile
  in the Vercel build image besides. `node:sqlite` is a Node builtin (≥ 22.5; stable and
  flag-free on 24, which `engines.node` now pins), so the function bundle carries no `.node`
  artifact. Read-only semantics are preserved (`new DatabaseSync(path, { readOnly: true })`
  rejects writes at the driver layer); the guard, `MAX_ROWS`, and envelope are byte-for-byte
  the same contract.
- **Validated locally, 22/22 smoke checks against the REAL `amrr::build_registry()` output**
  (`scripts/smoke.mjs`, re-runnable against a deployed URL): REST parity + error statuses;
  guard rejections (delete / multi-statement / pragma / insert-via-WITH) **and** a positive
  control (keyword-substring identifiers allowed); `git_sha`-stamped envelopes everywhere;
  real MCP client round-trip (initialize → list_tools = 5 → all tools) plus a second
  independent client proving no session affinity. `tsc --noEmit` clean.
- **Corpus-dependent checks are self-discovering.** `smoke.mjs` asks `/api/query` which
  `(content_area, year)` cell actually spans ≥ 2 jurisdictions, then compares on that cell.
  A hard-coded cell only ever held for one corpus: the fixture has `ELA/2024 → IN,SC`,
  while the real registry has **no IN∩SC year at all** (SC ELA ends 2017, IN ELA begins 2019)
  and resolves to `MATHEMATICS/2025 → IN,SD`. The suite is now green against the fixture,
  the real corpus, and any future corpus.
- **`.vercelignore` is load-bearing.** `data/*.sqlite` is git-ignored by design, but must be
  uploaded for `functions.includeFiles` to bundle it; absent a `.vercelignore` the CLI falls
  back to `.gitignore` and every endpoint fails `db_not_found`.
- **Fixture discipline:** local iteration may use a fixture DB generated from the **real
  DDL** (`schemas/sql/amr-registry.v1.sql`) and stamped `registry_meta.fixture=true`; the
  deployed DB must be `amrr::build_registry()` output (`make build` → copy). The build
  pipeline was not duplicated.
- **Handoff:** `serve/vercel/DEPLOY.md` — `vercel deploy` steps + live-URL smoke. The Tier 1
  milestone ("validate stateless streamable-http MCP on the serverless platform") completes
  on the first green live-URL smoke run.

**Next:** `vercel deploy` + live smoke; then extract the generic half of `lib/` toward the
dataimago L1 store contract / `database` producer driver (the five tools are domain, the
guard + envelope + read-only substrate are generic); per-SHA Release-asset DB stays deferred.

---

## [2026-07-09] decision (revision) | ADR-012 rev 1: host-agnostic query contract, serverless-first tiers

**Action:** decision revision (no code changes)

- **ADR-012 revised** ([[012-query-api-mcp-backend]]), prompted by a same-day workspace-level
  dataimago decision: runtime data exposure is **serverless-first** (a blessed always-on
  Datasette would hand a VPS back to every vertical; dataimago's producer-driver architecture
  reserves a deferred `database` driver as the seam). Restructured as D1–D4:
  - **D1 — the durable query contract** (host-agnostic): immutable read-only
    `registry.sqlite` + SELECT-only guard + `git_sha`-stamped envelope + dual REST/MCP with a
    single tool-schema source of truth + self-describing surface.
  - **D2 — Datasette as the local/CI authoring–exploration engine** (unconditional;
    `serve-native`/`serve-local` carry forward unchanged).
  - **D3 — deployment tiers:** Tier 0 local/CI (done); **Tier 1 serverless default**
    (bundled read-only SQLite behind serverless functions, REST + stateless streamable-http
    MCP; graduation path = dataimago's `database` producer driver; milestone: validate
    stateless MCP on-platform); Tier 2 = the existing VPS+Docker+Caddy Datasette stack,
    demoted to opt-in (`AMR_API_DEPLOY_ENABLED`), retained as working code.
  - **D4 — placement:** the registry is a standalone upstream **attribute registry**, not a
    dataimago vertical. SGPc-ai consumes it via `amrr` SHA-pinned reads and will host its own
    **second instance** of the D1 contract over SGPc's aggregate-classified output bundles
    (SGPc ADR-009); the contract + explorer graduate into the dataimago L1 toolkit, with this
    registry as instance #1 / validation case.
- Reproducibility posture unchanged (convenience/latest, SHA-stamped, never the pin); the
  deferred per-SHA Release-asset follow-on now also serves Tier 1. Prior M3–M6 (VPS) next
  steps are re-scoped to Tier-2-optional; the new critical path is the Tier 1 serverless
  slice.

**Next:** validate stateless streamable-http MCP serverless; extract `serve/datasette/` into
the dataimago L1 explorer toolkit; spec the `data`/`store` block in `@dataimago/spec`.

---

## [2026-07-09] decision + build | ADR-012: query API + MCP backend — Track B, M1+M2 (local stack green)

**Action:** decision + build (new parallel Track B)

- **ADR-012 proposed** ([[012-query-api-mcp-backend]]). A read-only query API + MCP backend
  for building product against the registry and for AI-guided exploration. Realizes ADR-000
  D7.4 (the long-anticipated optional read-only, SHA-stamped API). Grounded by exploring the
  early dataimago app `HelloWorld-ai` — whose reusable value is a **contract + governance
  model** (response envelope, self-describing surface, dual REST+MCP contract), not its
  R/RestRserve server (the large per-language JSON / Noto fonts / map UI there are documented
  *vision*, not built).
- **New Tier C `serve/`** (sibling of `metadata/`,`schemas/`,`site/`,`r-pkg/`): **Datasette**
  over the immutable `build/registry.sqlite` (JSON, SQL-over-HTTP, canned queries, browse UI)
  + a thin **Python MCP server** (FastMCP, `mcp>=1.28`) reading the same DB `mode=ro`. Both
  read-only; every response is `git_sha`-stamped. Pinned Datasette 0.65.2; official image
  used as-is (metadata rendered per-SHA as data).
- **MCP tools:** `describe_schema`, `query_registry(sql)` (SELECT-only guard over the
  read-only connection), `get_metadata`, `compare_jurisdictions`, `list_changes`. stdio (local
  Claude Code) + streamable-http `/mcp` (VPS behind Caddy).
- **Deploy scaffolding (M3–M4, untested pending a box):** `docker-compose.yml` (Datasette +
  MCP + Caddy auto-TLS), `Dockerfile.mcp`, `Caddyfile`, `deploy/{bootstrap-vps,deploy}.sh`,
  and an **independent** `.github/workflows/deploy-api.yml` (own `api-deploy` concurrency,
  opt-in via repo var `AMR_API_DEPLOY_ENABLED`, never touches `build-publish`). New Makefile
  targets: `api-render`, `serve-native`, `serve-local`, `serve-down`, `api-image`, `mcp-local`.
- **Verified locally (no Docker on the dev box):** Datasette run natively — jurisdiction/
  provenance/SQL/canned-query endpoints, CORS header, and a `delete` via `?sql=` refused
  ("Statement must be a SELECT"). MCP — all 5 tools exercised directly and over a real **stdio
  protocol round-trip** (initialize → list_tools → call_tool), git_sha-stamped envelopes, and
  the SELECT-only guard firing through the protocol (write/multi-statement/pragma rejected).
- **Reproducibility posture:** convenience/latest + SHA-stamped, **not** the pin (the
  `github://…`+SHA remote of [[011-remote-sha-pinning]] stays canonical for pinned reads);
  per-SHA retention deferred. Honors all bright lines: read-only/no write path, no microdata,
  federation, never on the critical path. Branch `serve-datasette-api`.

**Next:** M3 provision the VPS + Caddy TLS on a hostname; M4 wire `deploy-api` secrets + smoke
test; M5 validate MCP over HTTPS with a real agent; M6 finalize docs. Track A (WIDA authoring
etc.) proceeds in parallel, unblocked.

---

## [2026-07-08] fix | github:// remote tolerates raw.githubusercontent 429 throttling (amrr 0.5.1)

**Action:** bugfix

- **Symptom:** a live `get_metadata("IN", system="ilearn", year=2024,
  registry="github://…", ref="b824b20")` aborted with `HTTP 429` on
  `raw.githubusercontent.com/.../ilearn-in-2019.json`.
- **Root cause:** a `github://` read fetches the *whole* jurisdiction's sidecars (24 raw
  files for IN) sequentially, and `.gh_http_get()` fired each request exactly once with no
  retry. Unauthenticated `raw.githubusercontent.com` 429-throttles that burst; the first
  throttled request tripped the (correct) fail-closed abort with no chance to recover.
- **Fix (`R/remote.R`):** split the single attempt into a mockable `.gh_http_attempt()` and
  wrapped it in `.gh_http_get()` with bounded exponential-backoff retry — retries a 429 /
  403 / transient 5xx, honoring a `Retry-After` header (both waits capped at 60s). Tunable
  via `options(amrr.github_max_tries=)` (default 4) and `options(amrr.github_retry_base=)`
  (default 1s). Retry applies to *every* github request (SHA resolve + git-trees + raw), all
  of which route through `.gh_http_get()`. The 403/429 error now points at
  `AMRR_GITHUB_TOKEN` (a token both raises the limit and eases the throttle) and the retry
  knob. Fail-closed still holds — after retries are exhausted it errors.
- **Verification:** new unit tests (retry-then-succeed, give-up-after-max, no-retry-on-404,
  `.gh_retryable`, `.gh_backoff_seconds` cap + Retry-After) mock `.gh_http_attempt`/`.gh_sleep`
  so they run network-free. Full `testthat` suite green; the guarded **live** read now
  reproduces the user's exact call successfully (ELA g3 target 497, pin resolved to a full
  SHA). `amrr` 0.5.0 → **0.5.1** (+ NEWS). No contract surface touched (schema alias,
  resolver source, manifest pins, target re-merge all unchanged) — run `consumption-lint`
  before merge as usual.

**Next:** unchanged — Phase G SGPc resolver wiring; optional on-disk cache *store* for the
`github://` remote (the immutable-read seam still sits at `.gh_get_json`/`.gh_get_raw`);
real WIDA_IN / EOC authoring; ADR-006 governance.

---

## [2026-07-08] build + docs | Remote modes shipped, local auto-discovery, docs refresh

**Action:** build + docs

- **Shipped the remote-consumption work** (both PRs merged to `main`):
  - **PR #13** — `amrr` 0.4.0 derived-URL remote (`registry = <base>` → `dist/<jur>.json`,
    convenience/latest) **and** 0.5.0 reproducible `github://` remote (canonical sidecars
    raw-by-SHA, [[011-remote-sha-pinning]]). Squash-merged `8245c0a`.
  - **PR #14** — `amrr` 0.5.0 **local registry auto-discovery**: when no `registry` is given
    (and neither `option("amrr.registry")` nor `AMRR_REGISTRY` is set), `amrr_registry_root()`
    walks up from the working directory to the nearest checkout (a dir with both `metadata/`
    and `schemas/`). So running R anywhere inside a clone just works with no `registry` arg;
    `options(amrr.registry=)` in `.Rprofile` gives a machine-wide default. Strictly additive
    (only fires where the function previously errored). Squash-merged `048da0a`. Caught one
    pre-existing test that assumed no discovery — fixed to run outside any checkout.
  - Resolution order is now: `registry=` arg → `option("amrr.registry")` → `AMRR_REGISTRY` →
    auto-discovery → a not-found error naming every option (incl. the `github://` remote).
- **Branch hygiene:** deleted the stale merged branches `remote-registry` (PR #13) and
  `v2-implementation` (PR #10) from GitHub — both squash-merged and strictly behind `main`
  (merging `v2-implementation` would have reverted ADR-010/011). `main` is the only branch.
- **Docs refreshed for currency:** the `amrr` package README now documents all three
  `registry` forms + auto-discovery (and drops the machine-specific `~/GitHub/...` path);
  top-level README + `site/usage.qmd` gained the reproducible-remote / auto-discovery
  sections; [[index]] status line updated; **`HANDOFF.md` rewritten** for the next agent
  (the previous one covered the long-since-shipped v2/ADR-009 work).
- **Local toolchain note:** the dev machine's R was upgraded to 4.6.1 with a bare package
  library, so `make test`/`make check` could not run locally this session — CI R-CMD-check
  (full `testthat` suite + `--as-cran`) is the authoritative gate and is green on `main`.
  Restore local runs with `make setup`.

**Next:** SGPc resolver adopts a `registry` source, ideally the `github://` remote (Phase G,
[[sgpc-registry-consumption-contract]]); optional on-disk cache *store* for the remote;
real WIDA_IN / EOC authoring; ADR-006 governance.

---

## [2026-07-06] decision + build | ADR-011: reproducible remote consumption (amrr 0.5.0)

**Action:** decision + build

- **ADR-011 accepted** ([[011-remote-sha-pinning]]). Resolves the deferred remote-pinning
  **Open item** in the [[sgpc-registry-consumption-contract]]. `get_metadata()` gains a
  third `registry` kind: `registry = "github://owner/repo"` (also `https://github.com/...`)
  + the existing `ref` (SHA | branch | tag | `NULL`→HEAD). It reads the **canonical Tier A
  sidecars** straight from GitHub **pinned to an exact commit SHA** — no checkout,
  byte-for-byte reconstructable. Because only `metadata/`/`schemas/` are committed per SHA
  (the derived `dist/` is git-ignored), reproducibility must come from the sidecars, not the
  bundle: enumerate `metadata/<jur>/*.json` via the git-trees API, fetch each blob's raw
  content at the SHA (both immutable), parse identically to a local read, then run the
  unchanged filter/attach pipeline.
- **Resolve-then-pin:** `ref` resolves to a concrete 40-hex SHA (full SHA short-circuits;
  branch/tag/HEAD via the commits API) that is fetched and recorded as `amrr_registry_ref()`
  — even "latest" is pinned. **Fail-closed:** a missing jurisdiction or any failed
  fetch/parse aborts (never a partial jurisdiction). Read-only, no microdata, federation
  preserved. Optional token (`AMRR_GITHUB_TOKEN`/`GITHUB_PAT`/`GITHUB_TOKEN`) raises the API
  rate limit; `curl` is a soft dep (Suggests) with a base-R unauthenticated fallback.
- **Build:** new `r-pkg/amrr/R/remote.R` (classifier `.registry_kind`, `.parse_github_registry`,
  HTTP primitives = cache seam, `.gh_resolve_sha`, git-trees enumeration w/ truncation
  subtree-walk, `.fetch_github_records`); 3-way dispatch in `R/get_metadata.R`; DESCRIPTION
  0.4.0→0.5.0 (+`curl`), NEWS. Tests: mocked assemble-equals-local + classifier/parse/
  short-circuit/rate-limit/fail-closed, plus a guarded **live** read at `b824b20` (ELA g3
  target 497). `make test` 182 pass; `make check` OK. Cache *store* and blob-SHA
  verification deferred (seam shipped).
- Positions the two remotes clearly: `github://`+SHA = **reproducible**; derived-URL
  (0.4.0) = **convenience/latest** only.

**Next:** SGPc resolver may adopt the `github://` source (Phase G); optional on-disk cache
store; real WIDA_IN / EOC authoring.

---

## [2026-07-06] decision + build | ADR-010: reconcile colleague config spec (amrr 0.3.0)

**Action:** decision + build

- **ADR-010 accepted** ([[010-config-view-reconciliation]]). A colleague sent an
  alternative `amr.assessment_config.v1` spec right after v2 shipped. Review found ~90% of
  it is the same facts in a different arrangement; ADR-008 already framed it as a
  naming/structural input, not a canonical format. Decision: **refine v2 additively, offer
  the compact shape as an `amrr` projection, do not re-model canonical.**
- **Adopted (additive, non-breaking):** `achievement_levels[ca].proficient_from` (the
  lowest proficient label) replacing the fragile positional `proficient[]` mask — fixes a
  smell v2 shared (positional coupling; policy bundled into measurement, contra ADR-002).
  Legacy mask still accepted; validator checks agreement; `.proficient_mask()` derives it
  for `proficiency_boundary` resolution + SQLite. **Corpus folded** to `proficient_from`
  (27 assessment records); `migrate_registry()` now emits it. Also: EOC instrument-level
  `"eoc"` cut key (validator-gated to `end-of-course`; exemplar added), and
  `provenance.verified_by`.
- **Config view:** `as_config()` / `read_config()` project a `jurisdiction × system` into
  the compact shape (deduped named `level_schemes`, `tests`, `content_area × grade` `map`,
  unified `{loss,hoss,values}` cuts) and back — a lens on canonical, not a second source of
  truth (ADR-008 tier-3). `build_registry()` emits `build/config/*.json`; the site gains a
  **Config view** page. The projection preserves v2's `fixed|variable` axis explicitly (the
  colleague's `intended_grades` alone can't).
- **Rejected as canonical (rationale in ADR):** `tests`+`map` container, unified `cuts`,
  the single-file program container; `level_schemes` deferred to the authoring layer.
- **Verification:** `make all` green (48 files, 0 errors, no dual-window warning); **132
  tests** pass; R CMD check OK; build parity held (ILEARN ELA `[0,0,1,1]`, ELA g3
  boundary = 497, WIDA g5/2024 = 364.4). `amrr` 0.3.0.

**Next:** a `read_config()` sidecar *writer* (authoring CLI); Phase G SGPc resolver; real
WIDA_IN / EOC Tier A authoring.

---

## [2026-07-06] build | v2 verified + corpus migrated (first R execution; PR #10)

**Action:** build + release

- **Ran the v2 R code for the first time** (Cowork wrote it without R). `make test` →
  **91 tests pass** (0 fail/0 warn), including 47 in `test-v2.R`. `make check` →
  **R CMD check Status: OK** (0/0/0); roxygen regenerated `NAMESPACE` (+11 exports) and
  `man/*.Rd` for the new exports (committed).
- **Migrated the corpus v1→v2** via `amrr::migrate_registry(".")` — all 48 sidecars in one
  reviewed commit. Diff is purely mechanical: `schema_version` restamp, `assessment_type`
  normalization (`state-summative→summative`, `english-language-proficiency→elp`),
  `enrollment` block seeded from cutscore grade keys (`fixed` for ILEARN/summative grades
  3–8; `variable` + **empty** `enrolled_grades_tested` for WIDA — no facts invented). Every
  removed line verified to be a `schema_version`/`assessment_type` restamp or a comma-only
  `scale_name` reformat (no value drift).
- **`make all` green on the all-v2 corpus** with **no** dual-window warning. **Build parity
  preserved** (rebuilt pre- and post-migration): **45 targets, 177 exit thresholds, WIDA
  g5/2024 = 364.4**, identical before/after. (The handoff's "21/117" was the stale IN-only
  ADR-002 figure; the full 3-jurisdiction corpus is 45 targets, per the ADR-004 parity log.)
- **`make site`** — spec page renders all four schemas (v2 primary, v1 marked "migration
  window"); migrated record pages show the enrollment section; the v1 JSON fetch bundles
  still resolve under `_site/` (additive deploy, ADR-007 preserved).
- **Committed on `v2-implementation`** (3 commits: ADR-008 taxonomy docs; v2 implementation
  amrr 0.2.0; corpus v1→v2 migration) and opened **PR #10** → `main`. Awaiting green
  `validate` + `R-CMD-check` before merge.

**Next:** merge PR #10 behind green CI; then the §4 follow-ups (WIDA_IN real authoring,
Phase G SGPc resolver, ADR-006 governance draft).

**PR:** https://github.com/CenterForAssessment/assessment-metadata-registry/pull/10

---

## [2026-07-06] build | v2 implemented (ADR-009 accepted; amrr 0.2.0, Phases B–F)

**Action:** decision + build

- **ADR-009 accepted** (binary `fixed|variable` enum confirmed at sign-off; three-value
  `grade-span` variant explicitly rejected — assessment terminology is murky and
  "grade-span" would not describe ACT despite its cross-grade use; rationale recorded in
  the ADR's Alternatives table).
- **Phase B — schemas:** `schemas/amr.assessment.v2.schema.json` +
  `amr.accountability.v2.schema.json`. v2 adds: required `content_areas[].enrollment`
  block, `scale_bounds[ca][enrolled grade]` (`{loss, hoss, source}`), optional
  `cutscores_source[ca][grade]` (per-value confidence enum), canonical `assessment_type`
  enum with schema-enforced conditional `measurement.elp`/`measurement.alternate` blocks,
  `source_documents[]`; accountability v2 adds `growth_targets` (provisional shape),
  `timelines`, `participation`. `validate_registry()` routes v1/v2, enforces the **axis
  rule** + scale-envelope invariants on v2 records, and warns on v1 stragglers once any
  v2 record exists (dual-window nudge, D6).
- **Phase C — migrator:** `amrr::migrate_registry(registry, write = FALSE|TRUE)` —
  mechanical restamp, `assessment_type` normalization (`state-summative→summative`,
  `english-language-proficiency→elp`, colleague `general→summative`), enrollment seeded
  from cutscore grade keys (`elp→variable`, else `fixed`); never invents facts. **Corpus
  migration NOT yet run** — it is the user's local step (sandbox has no R; see Next).
- **Phase D — accessors:** `amrr_enrollment()`, `amrr_scale_bounds()`, `amrr_elp()`,
  `amrr_alternate()`, `amrr_source_documents()`, `amrr_growth_targets()`,
  `amrr_timelines()`, `amrr_participation()`.
- **Phase E — derived/site:** index rows carry `intended_enrollment_grade`,
  `enrolled_grades_tested`, `has_scale_bounds`; site `spec.qmd` renders all four schemas
  (v2 primary, v1 marked migration-window); `_common.R` fixed a latent v2 bug
  (`amr_is_accountability` matched only the v1 string) and Display now renders
  enrollment columns, scale-bounds tables, ELP/alternate measurement sections, and
  source documents.
- **Phase F — materialization:** `amrr_materialize()` → `.rds`/`.rda` carrying the
  registry SHA + `materialized_at` (the colleague-bridge demo artifact).
- **Tests:** fixture registry gains v2 schemas + `wida-access-in-2025.json` (v2);
  `helper-registry.R` shared fixture helper; new `test-v2.R` (schema routing, axis-rule +
  envelope negatives, migrator dry-run/write/idempotence, accessors, materialize
  round-trip); `test-tooling.R` counts updated (6 records) + dual-window warning
  expectations. `amrr` 0.2.0, NEWS.md added.
- **Verification (sandbox, no R):** Python jsonschema cross-check — 54 corpus+fixture
  records validate under routing; WIDA_IN exemplar validates as v2 (caught + fixed:
  `comparability.prior_scale_name` now nullable); 7 negative schema cases reject; a
  throwaway shadow of the migration transform over all 48 corpus records validates as
  v2; invariant logic cross-checked. **R suite not yet run locally.**

**Next (local, in order):** (1) `make validate` (corpus still v1 — expect clean);
(2) `Rscript -e 'pkgload::load_all("r-pkg/amrr"); amrr::migrate_registry(".", write=FALSE)'`
then `write=TRUE`, review diff; (3) `make all` + `make check` (roxygenise regenerates
man/); (4) commit corpus migration as one reviewed commit; (5) `make site`; (6) Phase G
(SGPc resolver) in the SGPc repo; ADR-006 governance draft can proceed in parallel.

---

## [2026-07-06] decision | ADR sign-offs (000/004/007/008) + ADR-009 drafted (v2 implementation)

**Action:** decision + design

- **Sign-offs recorded (Damian, 2026-07-06):** ADR-000, ADR-004, ADR-007, ADR-008 flipped
  `proposed → accepted`. Colleague confirmed **API-first consumption** (query + accessors +
  optional `.rda` materialization) in place of sourced `.R` spec files — ADR-008's primary
  adoption risk resolved. Near-term proof point: SGPc sidecar consumption.
- **ADR-009 drafted (proposed):** the v2 implementation ADR required by ADR-008 §8. Key
  refinement from sign-off review: the **enrollment-grade model** — every content area
  carries `enrollment` (`intended_enrollment_grade: fixed|variable`,
  `enrolled_grades_tested[]`, `note`), disentangling instrument target grade, enrolled
  grade, and cut keys (motivating cases: ILEARN Grade 8 Math = fixed/8; ACT =
  variable/10-12; WIDA-ACCESS K-2 = variable/grade-span). Axis rule: `cutscores` and the
  new `scale_bounds[ca][grade]` (`{loss, hoss, source}`, mirrors cutscore keying) are
  always keyed by **enrolled grade**. Supersedes the crosswalk's bare
  `content_areas[].grades`; [[metadata-taxonomy]] and [[schema-crosswalk]] amended.
- **Dogfood exemplar:** `schemas/examples/wida-access-in-2024.v2.example.json` — concrete
  `amr.assessment.v2` shape for WIDA-ACCESS IN (enrollment block, `measurement.elp` with
  domains/composites/weights/grade-clusters, scale_bounds with provisional placeholder,
  `source_documents[]`, accountability cross-reference). Design artifact only — outside
  `metadata/`, not a live record.
- Updated [[index]] (statuses + ADR-009 row + status line).

**Next:** review/accept ADR-009, then Phase B (v2 JSON Schemas + invariants) riffing
against the WIDA_IN exemplar; ADR-006 (governance) draftable in parallel; ADR-005 (AI
authoring) deferred until v2 lands.

---

## [2026-07-03] amend | ADR-008 consumption-priority revision

**Action:** amend (wiki only)

- Revised [[008-unified-metadata-taxonomy]] after review: colleague `assessment_spec.R` reframed
  as SGPstateData-style R-object analog (naming input), not a co-equal authoring path.
- Recorded consumption priority: (1) naming/taxonomy alignment, (2) registry API via `amrr`
  with function-argument queries (SGPc pattern), (3) optional binary materialization from
  pinned API responses.
- Deprioritized parallel `to_assessment_spec()` round-trip layer; `amrr` growth path is
  query → accessors → optional `.rda` export.

**Why:** the unified approach is API-first; building against the registry should be easier
than maintaining sourced R spec files that duplicate JSON facts.

---

## [2026-07-03] design | Unified metadata taxonomy alignment (ADR-008)

**Action:** design (wiki only — no schema or code changes)

- Added [[008-unified-metadata-taxonomy]] (proposed): greenfield target model
  `amr.assessment.v2` / `amr.accountability.v2` superseding three overlapping vocabularies
  (registry `amr.*` v1, SGPc `sgpc.assessment_metadata.v0.1`, colleague `assessment_spec.R`).
- Added [[metadata-taxonomy]] pattern: five domains (jurisdiction, assessment-system identity,
  measurement, accountability, governance), projection layers (canonical → SGPc sidecar /
  R spec view), consumer-plumbing exclusion, naming conventions.
- Added [[schema-crosswalk]] analysis: field-level mapping with conflicts, gaps, and
  reclassifications (ELP exit/growth/timelines → accountability per ADR-002 heuristic).
- Added [[colleague-assessment-spec-r]] source summary.
- Updated [[index]].

**Why:** marry SGPc's narrow analysis sidecar with a broader state-program metadata registry
(SGPstateData-style) without duplicating facts or mixing measurement with policy.

**Next:** sign-off on ADR-008; follow-up implementation ADR for v2 JSON Schemas and
round-trip adapters (`to_assessment_spec()`, `project_sgpc_metadata()`).

---

## [2026-07-02] feature | Human-readable GitHub Pages catalog (Quarto site, ADR-007)

**Action:** feature

- Built a **Quarto `website`** under `site/` that renders the derived `build/**` JSON into a
  human-readable, read-only catalog and published it additively on GitHub Pages. Borrows the
  polished mechanics of the `dataimago/HelloWorld` template but carries a **neutral** identity
  (Public Sans / Fraunces / IBM Plex Mono; warm-paper light + slate dark) — an "archival data
  instrument" look.
- Views: a **`reactable`** browse catalog (search/filter/sort); per-record **Display**
  (R-rendered identity, achievement levels, cutscore grade×boundary matrix, targets,
  provenance), **Explore** (vendored MIT `@andypf/json-viewer`, a JSON-Hero-like tree), and
  **Raw** (native ```json); a **spec viewer** that renders both JSON Schemas as documentation;
  and a **changelog** viewer. Record pages are generated flat by a `pre-render` R script.
- The site consumes the JSON directly via `jsonlite` (no `amrr` dependency). Deploy is additive:
  `build-publish` now validate → build → `quarto render site` → copy `build/` into `_site/` →
  deploy `_site/`, so every existing JSON fetch URL still resolves (ADR-000 D7 preserved).
- Gotchas handled: `output: asis` HTML wrapped in Pandoc `{=html}` raw blocks (else `>=` etc.
  get re-parsed as markdown); free-text `htmlEscape`d; flat site-root pages so relative asset
  paths resolve on the project subpath. Verified end-to-end with headless-Chrome screenshots of
  the catalog, an assessment record, an accountability record, the spec, and the changelog.

**Why:** make the registry inspectable by colleagues (spec review) and clients, not just
machines. See [[007-pages-catalog]].

**Next:** merge behind green CI; iterate on identity/branding; optionally a dark-mode andypf
theme sync and per-record deep-links.

---

## [2026-07-02] harness | Auto-validate hook + loop-command allowlist (sign-off received)

**Action:** harness

- Added the previously-deferred, self-modifying harness piece on explicit sign-off:
  `.claude/settings.json` now allow-lists the safe loop commands
  (`make validate|build|check|test|all`, read-only `git status`/`diff`/`log`) and wires a
  `PostToolUse` hook, `.claude/hooks/validate-metadata.sh`.
- The hook fires on `Edit`/`Write`/`MultiEdit`, parses the edited path, and runs
  `amrr::validate_registry(".")` only when a live `metadata/`/`schemas/` file changed
  (ignores the `r-pkg/**` package fixture). Clean registry → silent, exit 0; validation
  failure → the errors go to stderr and exit 2, surfacing them to the agent to fix. Missing R
  toolchain (no `jsonvalidate`/`amrr`/`pkgload`) → graceful no-op, so it never blocks editing.
- Verified all four paths: gate-skip (non-registry + fixture), clean-pass, failure
  (`cutscores[ELA][3] not monotonic` → exit 2), and graceful degrade. Uses installed `amrr`
  when present, else `pkgload::load_all("r-pkg/amrr")`.

**Why:** the tightest authoring feedback loop, and the last item of the dogfooding harness
build-out. See [[development-harness]].

**Deferred (unchanged):** schema review with a colleague (later today); flip ADR-000/ADR-004
`proposed` → `accepted` after that review.

---

## [2026-07-02] refactor | Fold the R tooling into the amrr package (ADR-004 revised)

**Action:** refactor

- Moved the derivation/validation tooling **into `amrr`** as exported functions:
  `amrr::validate_registry()` and `amrr::build_registry()` (mirroring `get_metadata()`'s
  `registry =` arg). Deleted `tools/*.R`; `tools/` now holds only `archive/`. All the
  registry's R lives in one package with one test suite and one `R CMD check`.
- **Producer/consumer split preserved by dependency scoping:** the build/validate-only
  packages (`jsonvalidate`, `DBI`, `RSQLite`, `digest`) are `Suggests` with
  `requireNamespace()` checks, so a `get_metadata()` consumer still installs only `jsonlite`.
  The shared Tier A internals (`is_assessment_record`, `as_logical_flag`,
  `amrr_registry_root`, `amrr_git_sha_of`) are reused — no duplication.
- **Parity re-verified:** `amrr::build_registry` output == the pre-refactor `tools/build.R`
  output (0 artifacts diverged across all JSON + SQLite). New `test-tooling.R` runs
  validate/build against a bundled fixture registry (`inst/extdata/registry` now carries
  schemas + DDL). `R CMD check` clean (0/0/0); full testthat green.
- CI (`validate.yml`, `build-publish.yml`) now `R CMD INSTALL r-pkg/amrr` then call
  `amrr::validate_registry(".")` / `amrr::build_registry(".", "build")`; Makefile uses
  `pkgload::load_all`. ADR-004 revised to record the in-package placement (supersedes the
  standalone-`tools/` form); docs retargeted.

**Why:** user preference — "much more tidy to keep all of the R in the amrr package." See
[[004-tooling-language]].

**Next:** merge behind green CI (validate + R-CMD-check + build-publish); then the deferred
settings/hook; flip ADR-000/ADR-004 to accepted after sign-off.

---

## [2026-07-02] decision + build | ADR-004: complete R build (tooling ported off Python)

**Action:** decision + build

- **ADR-004 (proposed):** single-language R. Ported the Tier A→B tooling off Python — the
  registry now has one toolchain (R), matching the R-shop and killing the PEP 668 friction.
- **New `tools/*.R`:** `_shared.R` (constants, `as_bool`, `git_provenance`, `load_records`,
  arg parser), `validate.R` (schema via `jsonvalidate`/ajv with `$schema` normalized to
  draft-07 — the schemas use only draft-07 vocabulary — plus the ported invariants), and
  `build.R` (all `build/` artifacts via `jsonlite` + `DBI`/`RSQLite` + `digest`). The tooling
  stays standalone (not folded into `amrr`), preserving ADR-000's producer/consumer split.
- **Semantic parity proven** by `tools/parity_check.R`: R vs Python builds are identical
  across all 16 JSON artifacts and all 12 SQLite tables (10 changelog events, 45 index rows,
  45 targets); both validators agree file-for-file (48/0). Byte parity is intentionally not a
  goal (consumers pin the git SHA; `amrr` reads raw sidecars).
- **Removed** `validate.py`, `build.py`, `requirements.txt`; **archived** the one-time seed
  scripts to `tools/archive/`. **CI + Makefile** switched to `setup-r` + `Rscript`; a
  `jsonvalidate`→`V8`/libv8 dep is now pulled in CI (cached).
- **Docs retargeted** Python→R (README, `derivation-pipeline`, `development-harness`, AGENTS,
  HANDOFF pointer); ADR index renumbered the unwritten placeholders (AI→005, Governance→006).

**Next:** merge behind green CI; then the deferred `.claude/settings.json` + auto-validate
hook (now `Rscript tools/validate.R`); flip ADR-000/ADR-004 to accepted after sign-off.

---

## [2026-07-02] harness | CI hardening, main branch protection, dogfooding loop

**Action:** harness + build

- **CI hardening (PR #3, `a531657`):** bumped all GitHub Actions to Node 24-native majors
  (`checkout@v7`, `setup-python@v6`, `configure-pages@v6`, `upload-pages-artifact@v5`,
  `deploy-pages@v5`), silencing the Node 20 deprecation annotation (0 annotations on the
  re-run). Dropped the `pull_request` paths filter on `validate.yml` so `validate` runs on
  every PR — a prerequisite for using it as a required check without the paths-filter
  deadlock.
- **Branch protection on `main`:** PR required (0 approvals, so solo self-merge works),
  `validate` a required status check (strict/up-to-date), conversation resolution +
  linear history required, force-pushes and deletions blocked, `enforce_admins: off`
  (owner keeps an escape hatch). Guards the reproducibility pins.
- **Dogfooding loop:** added `Makefile` (`make validate | build | check | test | all`,
  bootstraps the `.venv` for the PEP 668 issue) as the single local entry point, and the
  three `.claude/agents/` subagents the harness pattern designed —
  [[development-harness]] `metadata-author` (draft-only, cited), `registry-librarian`
  (regenerate + diff, read-only on Tier A), `consumption-lint` (SGPc contract holds).
- **Freshness:** dropped the stale `[planned]` on `amrr` in the README; updated
  `development-harness.md` and the AGENTS.md harness section to present tense; `.gitignore`
  now covers `r-pkg/*.tar.gz` and personal `.claude/settings.local.json`.
- **Deferred (needs explicit sign-off):** a checked-in `.claude/settings.json` permission
  allow-list + `PostToolUse` auto-validate hook. Correctly blocked by the auto-mode
  self-modification guard; proposed for human review rather than forced.

**Next:** sign off (or decline) the settings allow-list + auto-validate hook; flip ADR-000
to accepted; close the SGPc consumption loop (HANDOFF §5).

---

## [2026-07-02] github integration | Foundation committed, PR merged, Pages live

**Action:** build + release

- Executed the CLI handoff's GitHub-integration task (HANDOFF.md §4, §6). Renamed the
  default branch **`master` → `main`** so the three workflows' `push`/Pages triggers fire.
- Verified locally before pushing: `tools/validate.py` → 48 files, 0 errors;
  `tools/build.py` → 48 records across 3 jurisdictions; **`amrr`** — regenerated `man/` +
  `NAMESPACE` via roxygen, `R CMD check` **Status: OK** (0/0/0), testthat **28 tests pass**
  (first real execution of the R package).
- Committed all previously-untracked work on `phase-1-3-registry-foundation`, opened
  **PR #1**, both PR checks green (`validate` 8s, `R-CMD-check` 1m45s), squash-merged to
  `main` as **`ccd1890`** — the first real reproducibility pin.
- Enabled **GitHub Pages** (Source: GitHub Actions). `build-publish` deployed the derived
  layer; published `manifest.json` carries `git_sha: ccd1890…`, `dirty: false`, 48 records
  (27 assessment + 21 accountability), 3 jurisdictions. Site:
  `https://centerforassessment.github.io/assessment-metadata-registry/`.
- Refreshed `README.md` with a shareable top-of-file overview (tagline, what/why,
  three-tier table, quick start). ADR-000 left `status: proposed` per deciders' call.

**Next:** flip ADR-000 to accepted after sign-off; close the SGPc consumption loop
(HANDOFF §5); optionally bump CI actions off deprecated Node 20 and add `main` branch
protection.

---

## [2026-07-02] handoff | Prep for CLI transfer (GitHub + close consumption loop)

**Action:** documentation

- Wrote `HANDOFF.md` (repo root) for transfer to the Claude Code CLI, where R and an
  authorized GitHub connector are available. Covers: local verification (Python + R CMD
  check), GitHub integration (branch/commit/push/PR, the three CI workflows, enabling
  Pages), and the core task — closing the SGPc consumption loop via `amrr` (schema alias,
  `registry` resolver source, manifest pin, and proving it with `testSGPc()` State D
  first). Flags the SC baseline-digest caveat and the open remote-SHA-pinning decision.

**Next (CLI):** verify amrr under R; open the PR; wire SGPc; run testSGPc against the
registry.

---

## [2026-07-02] decision + build | ADR-003: demo jurisdictions + comparability

**Action:** decision + ingest

- **ADR-003 (accepted):** authored demonstration jurisdictions from testSGPc scenarios —
  **State D** (`SD`, vertical scale, COVID gap at 2020, proficiency_boundary targets) and
  **State C** (`SC`, scale transition at 2015, scale_score exit targets) — via
  `tools/seed_demo.py` (24 sidecars: assessment + accountability).
- **Schema extension:** added optional `comparability` block to
  `amr.assessment_system.v1` (`scale_transition`, `comparable_to_prior_year`,
  `prior_scale_name`, `administered`, `notes`); projected to `index.json` + a
  `comparability` SQLite table; surfaced in R via `amrr_comparability()`.
- **Registry now spans 3 jurisdictions (IN, SC, SD); 48 sidecars validate.**
- **Changelog exercised with real signal:** SC 2014->2015 scale break (cutscores + exit
  target) and the ILEARN COVID gap (target disappears 2020, returns 2021).
- **Bug fixed:** accountability target changelog keyed the target map by the tuple
  `(assessment_system_id, content_area)` but looked it up by `assessment_system_id`
  alone, so it silently reported no target changes. Now correct; demo data covers it.
- **amrr:** added `amrr_comparability()` accessor + `test-demo.R` (second jurisdiction,
  scale_score exit on a summative, comparability surface); fixture gains SC 2015.

**Next:** push Phases 1-3 + demo via CLI (validate + build-publish + R-CMD-check green);
then wire testSGPc to consume the registry, or seed Massachusetts (MCAS + WIDA).

---

## [2026-07-02] build | Phase 3: amrr R consumption package (Tier C)

**Action:** build + connection

- **`r-pkg/amrr`** (monorepo): `get_metadata(jurisdiction, system, year, registry, ref,
  attach_targets)` reads a local registry checkout (pinnable by commit SHA), filters to a
  cell, and re-merges accountability targets onto the assessment record under
  `achievement_targets` (ADR-002 consumption seam). Accessors: `amrr_cutscores`,
  `amrr_achievement_levels`, `amrr_targets`, `amrr_vendor`, `amrr_registry_ref`.
- **Target resolution:** `scale_score` targets pass through explicit per-grade thresholds;
  `proficiency_boundary` targets resolve from the record's own cutscores + proficient mask
  (scale score entering the first proficient level). Verified in Python parity check:
  ILEARN ELA grade 3 → 497 (entering "At Proficiency"), not 525.
- **Tests + fixture:** testthat suite over an `inst/extdata/registry` fixture (ILEARN +
  WIDA + accountability 2024); covers filtering, both target bases, attach_targets=FALSE,
  accessors, error paths.
- **CI:** `R-CMD-check.yml` gains a roxygen `document` step (man/ generated in CI, not
  committed). R not available in this sandbox → R CMD check is the verification gate.
- **Contract:** [[sgpc-registry-consumption-contract]] documents the three additive
  SGPc-side changes (resolver `registry` source; schema alias; `registry_ref` in outputs).

**Next:** push Phases 1–3 via CLI; confirm validate + build-publish + R-CMD-check are green;
then either seed a second jurisdiction (Massachusetts, MCAS + WIDA) or wire SGPc's resolver.

---

## [2026-07-02] decision | ADR-002: accountability record + target relocation

**Action:** decision + ingest

- **ADR-002 (accepted):** new `amr.accountability_system.v1` record type
  (`jurisdiction × accountability_system × year`, `targets[]` cross-linking
  `assessment_system_id` + `content_area`). Established the general "what goes where" rule:
  standard-setting facts (scales, levels, cutscores) = assessment; policy goals (exit,
  accountability proficiency) = accountability.
- **Worked example:** the WIDA-ACCESS ELP **exit target** — state policy, not a property
  of WIDA — was relocated out of the assessment sidecars. `tools/split_accountability.py`
  extracted `achievement_targets` from the 15 assessment sidecars into 9 per-year
  `in-accountability` records and stripped them from the assessment sidecars;
  `achievement_targets` removed from `amr.assessment_system.v1`.
- **Tooling now record-type aware:** `validate.py` routes by `schema_version` and enforces
  a cross-link integrity invariant (every target resolves to an existing assessment
  record + content area); `build.py` + DDL project `accountability_system`,
  `accountability_target`, `accountability_target_scale_score`, and add a `target`
  changelog field.
- **Verified:** 24 records (15 assessment + 9 accountability) validate; build emits 21
  targets + 117 per-grade exit thresholds; WIDA exit g5/2024 = 364.4; ILEARN targets
  resolve as `proficiency_boundary`.
- **Consumption seam (Phase 3):** `get_metadata(..., attach_targets=TRUE)` will re-merge
  targets onto the assessment record so SGPc sees its expected `achievement_targets` shape.

**Next:** Phase 3 — `amrr` R package.

---

## [2026-07-02] pattern + build | Phase 2: derived layer (Tier B) + publish CI

**Action:** pattern + build

- **Derivation tool** `tools/build.py`: reads Tier A sidecars and emits `build/`
  (git-ignored) — `index.json` (flat searchable index), `changelog.json` (year-over-year
  diffs per series), `dist/<JUR>.json` + `dist/<JUR>/<system>.json` (static bundles for
  `amrr::get_metadata`), `tables/*.json` (vendor-by-year, vertical-scale),
  `registry.sqlite` (self-contained projection), and `manifest.json`.
- **Reproducibility pin:** every bundle carries `_registry` = {schema_version, git_sha,
  dirty, built_at}. CI builds are clean/publishable; local dirty builds are flagged.
- **DDL** `schemas/sql/amr-registry.v1.sql`: standalone year-keyed projection (identity
  dims + program/vendor/vertical_scale/achievement_level/cutscore/achievement_target).
- **Verified locally:** 15 records → 216 cutscores, 102 achievement levels, 117 WIDA exit
  targets, 21 vertical-scale rows; example cross-cutting query works. Changelog = 0 events
  (seed values are uniform placeholders — nothing to diff yet; logic exercised).
- **CI** `.github/workflows/build-publish.yml`: validate → build → deploy `build/` to
  GitHub Pages on merge to main (SHA-stamped). Documented in
  [[derivation-pipeline]].
- **Note:** SQLite is built in local temp then byte-copied (FUSE mounts reject SQLite
  journaling); no-op on CI.

**Next:** Phase 3 (`amrr` R package: `get_metadata(..., ref=)` over the static bundles +
local SHA cache; wire SGPc's resolver `registry` source). Then ADR-002 accountability.

---

## [2026-07-02] decision + build | Phase 1: schema, seed corpus, validation CI

**Action:** decision + ingest

- **ADR-001 (accepted):** `amr.assessment_system.v1` schema
  (`schemas/amr.assessment_system.v1.schema.json`) — ported the SGPc sidecar surface,
  added the governance block (`status`/`source_confidence`/`provenance`) with a
  conditional requiring `source_citation` for non-draft records, and accepts the legacy
  `sgpc.assessment_metadata.v0.1` string as an alias.
- **Seed corpus:** migrated 15 Indiana sidecars (ILEARN summative 2019–2025, WIDA-ACCESS
  ELP 2017–2025) into `metadata/IN/<system>/` via `tools/migrate_sgpc_sidecars.py`. All
  land as `status: draft` (ILEARN cutscores are placeholders → low; WIDA exit targets
  preliminary → low/medium) pending review.
- **Validation:** `tools/validate.py` (JSON Schema + registry invariants: filename==id,
  path==identity, cut count == levels−1, monotonic cutscores, citation-required). All 15
  pass locally.
- **CI:** `.github/workflows/validate.yml` (Tier A gate on every metadata/schema change)
  and `.github/workflows/R-CMD-check.yml` (paths-filtered to `r-pkg/**`, dormant until
  Phase 3). Added `.gitignore` (derived artifacts never committed) and `tools/requirements.txt`.
- **Stealth:** removed all `dataimago` references from repo docs (SGPc references retained).

**Next:** deciders sign off ADR-000; authorize the GitHub connector to enable PR/CI
workflows from here; Phase 2 (derived index/changelog + static bundles) or Phase 3 (`amrr`).

---

## [2026-07-02] decision + scaffold | Founding architecture and harness seeded

**Action:** decision

- Authored **ADR-000: Assessment Metadata Registry — Foundational Architecture**
  (`wiki/decisions/000-registry-architecture.md`, status: proposed). Confirmed forks:
  static-canonical + optional-later API, monorepo `amrr` package, separate cross-linked
  accountability records, neutral `amr.*` schema namespace with SGPc alias. Adopted the
  deciders' insight that Git commit SHA is the reproducibility pin.
- Seeded the LLM wiki: `AGENTS.md`, `CLAUDE.md` (import shim), `purpose.md`,
  `wiki/index.md`, `wiki/schema.md`, this log, and `wiki/patterns/development-harness.md`
  (ported SGPc harness wisdom).
- Source of design: SGPc three-tier metadata layer (ADR-011) and vertical development
  harness pattern.

**Next:** deciders review ADR-000 → accept → Phase 1 (schema + migrate Indiana seed
corpus + CI validation).
