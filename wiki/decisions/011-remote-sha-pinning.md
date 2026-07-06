---
title: "ADR-011: Reproducible remote consumption — read canonical sidecars from GitHub pinned to a commit SHA"
type: decision
created: 2026-07-06
updated: 2026-07-06
status: accepted
deciders: Damian Betebenner
curated: true
sources:
  - wiki/decisions/000-registry-architecture.md
  - wiki/connections/sgpc-registry-consumption-contract.md
  - r-pkg/amrr/R/remote.R
  - r-pkg/amrr/R/get_metadata.R
tags: [reproducibility, remote, sha-pin, get-metadata, consumption, github, amrr]
---

# ADR-011: Reproducible remote consumption (raw-by-SHA canonical sidecars)

**Status:** Accepted (Damian Betebenner, 2026-07-06)

## Context

ADR-000 D5 makes a **Git commit SHA the sole reproducibility pin**, and D7.3 names
"static JSON **raw at a pinned SHA**" the *canonical* transport for R consumption —
chosen precisely because a SHA pins the exact bytes. Until now `amrr::get_metadata()`
delivered that guarantee only from a **local checkout** (you check out the SHA yourself).
`amrr` 0.4.0 added a *derived-URL* mode (`<base>/dist/<jur>.json`) for convenience, but it
serves the **latest** published build only: the derived `build/`/`dist/` layer is
git-ignored (`.gitignore`), so it is **not** reproducible by tree SHA.

The SGPc consumption contract flagged this exact gap as an **Open item**: *"Remote
(non-checkout) pinning: raw-by-SHA needs the consumed artifact committed… a
published-bundle distribution model is a future ADR."* This ADR resolves it.

## Decision

Add a **reproducible remote** mode to `get_metadata()`: a GitHub repo as the `registry`.

- **Invocation:** `registry = "github://owner/repo"` (also `https://github.com/owner/repo`)
  plus the existing `ref` (SHA | branch | tag | `NULL` → default-branch `HEAD`).
- **What is fetched — canonical Tier A only.** Because only `metadata/` and `schemas/`
  are committed per SHA, reproducibility comes from fetching the **canonical sidecars** at
  the SHA, *not* the git-ignored derived bundle. `get_metadata()` enumerates
  `metadata/<jur>/*.json` via the git-trees API and fetches each blob's raw content — both
  addressed by the commit SHA and therefore **byte-immutable**.
- **Resolve-then-pin.** `ref` is resolved to a concrete 40-hex commit SHA (a full SHA
  short-circuits with no network call; a branch/tag/HEAD is resolved via the commits API).
  That SHA — never a moving branch — is fetched and recorded as `amrr_registry_ref()`, so
  even a "latest" read is pinned to a concrete, reconstructable SHA.
- **Same pipeline.** Fetched records are parsed identically to a local read
  (`jsonlite::fromJSON(…, simplifyVector = FALSE)`) and flow through the unchanged
  system/year filter + accountability `attach_targets` logic.
- **Fail-closed.** A missing jurisdiction, or *any* sidecar that fails to fetch/parse,
  aborts the whole call — a partial jurisdiction would silently break reproducibility.
- **Auth & dependency.** Read-only and unauthenticated by default (public repo). An
  optional token (`AMRR_GITHUB_TOKEN` / `GITHUB_PAT` / `GITHUB_TOKEN`) raises the API rate
  limit. `curl` is a soft dependency (Suggests) used as the HTTP engine when present, with
  a base-R unauthenticated fallback so a public read needs no new hard dependency.
- **Caching seam, store deferred.** All immutable reads flow through two primitives
  (`.gh_get_json` / `.gh_get_raw`); an on-disk cache keyed by owner/repo/SHA/path (safe
  forever since content at a SHA is immutable, enabling offline replay) can wrap them later
  with zero API change. Not shipped in v1.

## Consequences

- **Reproducible remote is now first-class.** A consumer (SGPc included) can pin by SHA
  and read byte-identical metadata with no checkout — the Open item is closed. The
  derived-URL mode remains, explicitly positioned as *convenience/latest*, not reproducible.
- **Three registry kinds** now coexist behind one dispatch (`.registry_kind()`): local
  checkout, GitHub-by-SHA (reproducible), derived-URL (latest). The GitHub classifier must
  intercept before the generic URL matcher (a `https://github.com/...` URL also matches it).
- **Honors the bright lines.** Read-only; system-level metadata only (no microdata);
  federation preserved (the consumer points at the registry, does not fork it); no
  `status` promotion. Consumption does not re-validate — reproducibility is about bytes,
  and validation is the author-time/CI gate.
- **Operational notes.** Unauthenticated API is 60 req/hr (~26 requests per uncached
  jurisdiction read) — a token or the deferred cache removes repeat cost. A truncated
  recursive git-tree (large-repo edge) is handled by a jurisdiction-scoped subtree walk.
  Optional hardening (deferred): verify each fetched blob's git SHA-1 against the tree entry.

Delivered in `amrr` 0.5.0 (`R/remote.R`, dispatch in `R/get_metadata.R`).
