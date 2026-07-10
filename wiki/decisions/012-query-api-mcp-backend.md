---
title: "ADR-012: Read-only query contract + MCP backend (Datasette-authored, host-agnostic)"
type: decision
created: 2026-07-09
updated: 2026-07-09
status: accepted
deciders: Damian Betebenner
curated: true
sources:
  - wiki/decisions/000-registry-architecture.md
  - wiki/decisions/007-pages-catalog.md
  - wiki/decisions/011-remote-sha-pinning.md
  - serve/
  - r-pkg/amrr/R/build.R
tags: [api, mcp, datasette, consumption, tier-c, serve, dataimago, sqlite, serverless]
---

# ADR-012: Read-only query contract + MCP backend

**Status:** Accepted (Damian Betebenner, 2026-07-09; revised same day — see Revision history). Accepted on the Tier 1 milestone: the stateless streamable-http MCP surface was validated on-platform, 22/22 against the live URL.

## Context

ADR-000 **D7.4** anticipated a *"later, additive, read-only, SHA-stamped REST API for
cross-jurisdiction queries… never on the critical path,"* and its security review fixed the
shape: *"API (if built) is read-only and unauthenticated for public metadata… every
response is SHA-stamped. No write path."* The substrate already exists: on every push,
`amrr::build_registry()` emits `build/registry.sqlite` — a full relational projection
(`amr.registry.v1`) with a `registry_meta` row carrying `git_sha`/`built_at` — today served
only as static, latest-only files on GitHub Pages (ADR-007).

Two needs motivate a live query surface: **building product** against the metadata, and
**AI-guided exploration/comparison** by agents. Motivation and framing come from the early
dataimago app `HelloWorld-ai`; its durable, reusable value is a **contract + governance
model** (consistent response envelope, self-describing surface, a **dual REST + MCP
contract**, a typed client), not its single-process R server.

**Revision context (2026-07-09).** The first draft of this ADR bound the query surface to a
specific host (self-managed VPS + Docker + Caddy). A workspace-level dataimago decision made
the same day fixed the runtime posture for all dataimago data exposure as
**serverless-first**: the deployed default must not require an always-on server, because the
no-VPS property is a core architectural win of the dataimago platform (its NextJS-canonical
producer-driver architecture reserves a deferred `database` driver as exactly this seam).
This revision therefore separates what is durable here (the **contract**) from what is a
deployment choice (the **host**), and re-ranks the hosts.

## Decision

Stand up a **read-only query contract + MCP backend** as a new Tier C component under
`serve/`. The decision has four parts, in order of durability:

### D1. The query contract (durable, host-agnostic)

The unit of reuse is a contract over the derived DB, independent of any host:

- **Substrate:** the immutable, disposable `build/registry.sqlite`, regenerable from
  `metadata/` alone; opened read-only everywhere (`mode=ro`, `:ro` mounts, immutable flags).
- **Guards:** read-only connection **plus** a defense-in-depth SELECT-only guard
  (single statement, forbidden-keyword rejection) on any SQL-accepting surface.
- **Envelope:** every response is provenance-stamped (`git_sha`, `built_at` from
  `registry_meta`).
- **Dual surface:** the same capabilities exposed as REST/JSON **and** as MCP tools —
  `describe_schema`, `query_registry(sql)`, `get_metadata`, `compare_jurisdictions`,
  `list_changes` — with a single source of tool truth (`serve/mcp/tool_schemas.json`).
- **Self-describing:** schema and canned queries are discoverable from the surface itself.

### D2. Datasette as the authoring/exploration engine (unconditional; local + CI)

Datasette over the immutable `registry.sqlite` (JSON, SQL-over-HTTP, canned queries in
`serve/datasette/metadata.yaml`, browse UI) is the **development and curation surface**:
`make serve-native` / `serve-local`, per-SHA provenance rendered as data
(`render_metadata.sh`). Pinned to `datasetteproject/datasette:0.65.2`; official image as-is.
This role costs nothing in production and is where Datasette is unbeatable; it holds
regardless of deployment tier.

### D3. Deployment tiers (default: serverless)

- **Tier 0 — local/CI (always on, costs nothing):** D2 above, plus the stdio MCP transport
  for local agents (Claude Code et al.). Already implemented and verified.
- **Tier 1 — serverless deploy (the default target): DELIVERED 2026-07-09.** The D1
  contract served without a persistent server — the read-only `registry.sqlite` bundled
  into serverless functions (the DB is metadata-scale, well under bundle limits) exposing
  the REST surface and MCP over stateless streamable-http. This is the registry-local
  instance of dataimago's deferred `database` producer driver, and the graduation path is
  to implement it **once** there and consume it here, rather than maintaining a bespoke
  function set long-term.

  *Milestone — MET.* Live at **`https://assessment-metadata-registry.vercel.app`**
  (MCP endpoint: `.../mcp`), **22/22 smoke checks green against the live URL**, including a
  real MCP `initialize → tools/list → call` round-trip and a **second independent client with
  no session carryover**, which is the statelessness property the milestone existed to prove.
  Every deploy rebuilds the DB from a clean tree at the deployed commit, so the envelope's
  `git_sha` names the code that is running. Implementation notes worth carrying:

  - **Engine: `node:sqlite`, not `better-sqlite3`.** The native addon does not build
    against current Node and would have to compile in the Vercel build image; the builtin
    removes that risk class entirely (`engines.node: "24.x"` pins a runtime where it is
    stable and flag-free). The function bundle carries no `.node` artifact. Read-only
    semantics, the SELECT-only guard, `MAX_ROWS`, and the envelope are unchanged.
  - **`.vercelignore` is load-bearing.** `data/*.sqlite` is git-ignored by design, but must
    still be *uploaded* for `functions.includeFiles` to bundle it.
  - **`outputDirectory: "public"` is a disclosure control, not cosmetics.** Without it,
    Vercel publishes the project root as static assets — which made `lib/*.ts` and the
    SQLite DB itself downloadable at `/data/registry.sqlite`. The store must reach the
    **functions**, never the static surface. For this registry the data is public CC BY 4.0
    metadata so nothing leaked, but the same default applied to a classification-gated store
    (SGPc) would breach the disclosure boundary. **Any future instance of this contract must
    assert that its store is not reachable as a static asset.**
- **Tier 2 — hosted Datasette (optional, opt-in):** the existing VPS + Docker + Caddy stack
  (`docker-compose.yml`, `Caddyfile`, `Dockerfile.mcp`, `deploy/`, independent
  `deploy-api.yml` gated by `AMR_API_DEPLOY_ENABLED`). Retained as working code for the
  cases Tier 1 cannot serve: the faceted public browse UI and arbitrary SQL-over-HTTP at
  Datasette fidelity. It is **a** deployment, not **the** deployment; nothing else may
  depend on its existence.

### D4. Relationship to dataimago (placement)

This repository is **not a dataimago vertical**. It is a standalone, canonical **attribute
registry** — upstream infrastructure with its own governance (ADRs 000–011) — that
dataimago applications consume. The concrete relationships:

- **SGPc-ai (consumer + sibling producer):** consumes registry metadata via `amrr`
  SHA-pinned reads (ADR-011) as an *upstream input*; separately, SGPc analyses produce
  their own large, queryable output store (aggregate-classified bundle artifacts per SGPc
  ADR-009). That store is a **second instance of the D1 contract**, not an extension of
  this database — the two stores stay separate, joined only by shared keys
  (jurisdiction × assessment_system × year) and the shared contract.
- **dataimago L1 (pattern owner):** the D1 contract + D2 explorer graduate into the
  dataimago Level-1 toolkit (data-store pattern, `database` producer driver, zero-config
  explorer target). This registry is instance #1 and the validation case.

  The graduation is a **split, not a move** (rev 2). dataimago's `ProducerDriver` contract is
  `fetch(endpoint, params)`; four of the five tools are named queries with typed params and map
  onto it directly, but `query_registry(sql)` takes arbitrary SQL and never will. So: the
  read-only substrate, the SELECT-only guard, `MAX_ROWS`, the provenance-stamped envelope, and
  schema introspection are **generic** and graduate to L1; `DIMENSIONS`, `get_metadata`,
  `compare_jurisdictions`, and `list_changes` are **domain** and stay in this repo. Raw SQL
  becomes an opt-in capability (default off), because SGPc's `restricted` classification makes
  an always-on SQL surface a footgun. The L1 contract is specified in dataimago-design's wiki
  as `dataimago.store.v1` (pattern `data-store-contract`, ADR `generalized-data-store`).

## Reproducibility posture

The API is **convenience / latest**, and SHA-*stamped* (every instance + response surfaces
`git_sha` from `registry_meta`) — **not** the reproducibility pin. This mirrors ADR-011's
derived-URL mode. The pin remains `github://owner/repo` + SHA (raw canonical sidecars) and
local checkouts. **Per-SHA retention is deferred** (documented follow-on: publish
`registry-<sha>.sqlite` as a Release asset — which also serves Tier 1, whose functions can
pull the exact DB by SHA instead of rebuilding).

## Consequences

- **Honors the bright lines.** Read-only / no write path (immutable Datasette, `:ro` mount,
  `mode=ro` + SELECT-only guard); **no microdata** (the DDL is system-level only); federation
  preserved (a disposable projection, regenerable from `metadata/` alone — never an alternate
  source of truth); **never on the critical path** (analysis runs still use raw-by-SHA
  sidecars / checkouts). Consumption does not re-validate; validation stays the CI/author gate.
- **No VPS on the default path.** The serverless-first re-ranking means the registry's query
  surface can ship (Tier 1) without provisioning, patching, or paying for a box; Tier 2
  remains available behind its opt-in variable with zero cost while disabled.
- **Additive, low-coupling.** `serve/` consumes only the *output* of `build_registry()`;
  no change to `metadata/`, `schemas/`, or the `amrr` R package. Existing `Makefile` targets
  (`serve-native`, `api-render`, `serve-local`, `mcp-local`, …) sit beside the existing loop.
- **Generalization path (dataimago).** Strengthened from the first draft: the D1 contract is
  dataset-agnostic (swap the SQLite file + `metadata.yaml` canned queries +
  `tool_schemas.json`), and D4 names the graduation target (L1 toolkit) and the second
  instance (SGPc-ai's aggregate output store). July scope stays registry-only.
- **Alternatives rejected.** PostgREST/Postgres (adds a DB to provision + load for a
  metadata-sized dataset); a bespoke R/plumber or Node API as the *contract* (most code to
  own; second runtime) — note Tier 1's serverless functions are thin adapters over the D1
  contract, not a bespoke API; baking the DB into a Datasette image via `datasette package`
  (couples image to data, breaks disposability); **static-only CDN as the sole surface**
  (no server-side query/compare — rejected as *sole* surface, but static export remains the
  base layer beneath the tiers); **VPS as the blessed default** (first draft of this ADR —
  reversed by the serverless-first decision; retained as Tier 2).

## Revision history

- **2026-07-09 (rev 3):** **Accepted**, and the deploy loop closed. `.github/workflows/deploy-vercel.yml`
  (opt-in via `AMR_VERCEL_DEPLOY_ENABLED`) rebuilds the DB from the canonical sidecars on every
  push to `main`, deploys, and then *asserts* three things: 22/22 smoke against the live URL;
  `live git_sha == GITHUB_SHA`; and HTTP 404 on `/data/registry.sqlite`.

  The middle assertion is why the workflow exists. `build_registry()` stamps the DB from the
  checked-out HEAD, so provenance is true only if the DB is rebuilt at the commit being deployed.
  A hand-deploy is silently orphaned by the next rebase or squash-merge — which happened **twice**
  on the day Tier 1 shipped, caught both times only because a human looked. Provenance that depends
  on someone remembering is not provenance. The third assertion generalizes the `outputDirectory`
  finding: a store must never be reachable as a static asset, and that is now a gate rather than a
  sentence in an ADR.
- **2026-07-09 (rev 2):** Tier 1 **delivered and verified on-platform** — live at
  `https://assessment-metadata-registry.vercel.app`, 22/22 smoke green against the live URL,
  stateless streamable-http MCP proven with a second independent client. Engine swapped to
  `node:sqlite` (no native addon); `.vercelignore` + `outputDirectory: "public"` recorded as
  load-bearing. Corpus-dependent smoke checks made self-discovering (a hard-coded
  `(content_area, year)` cell held only for the fixture — the real corpus has no IN∩SC year).
  The L1 graduation target now has a concrete shape: the **generic** half of
  `serve/vercel/lib/` (read-only substrate, SELECT-only guard, `MAX_ROWS`, provenance-stamped
  envelope, schema introspection) graduates; the **five tools are domain** and stay here.
  `query_registry(sql)` does not fit dataimago's `fetch(endpoint, params)` producer contract
  and becomes an opt-in capability, default off. No change to the contract, guards, or tiers.
- **2026-07-09 (rev 1):** Reframed from "Datasette on a VPS" to "host-agnostic query
  contract, Datasette-authored, serverless-first deployment." Added D1–D4 structure,
  deployment tiers, and the dataimago placement statement (registry = upstream attribute
  registry; SGPc-ai = consumer + second contract instance; L1 = pattern owner). No change
  to the contract itself, the guards, the reproducibility posture, or the local stack —
  everything verified in M1–M2 carries forward unchanged.
- **2026-07-09 (initial):** Proposed Datasette + FastMCP under `serve/`, self-managed
  VPS + Docker + Caddy, independent opt-in deploy workflow.

Delivered under `serve/` + `.github/workflows/deploy-api.yml`; the reproducible remote of
ADR-011 remains the canonical pinned-read path.
