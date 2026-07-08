# HANDOFF — assessment-metadata-registry

**Date:** 2026-07-08
**Repo:** `CenterForAssessment/assessment-metadata-registry` (branch `main`, clean; this is
the canonical remote)
**State:** All remote-consumption + local-ergonomics work is **shipped and merged**
(`amrr` 0.5.0). `main` is the only branch. No open PRs. Nothing in flight.

This file hands the project to the next AI agent. Read `AGENTS.md` first (session-start
protocol), then `purpose.md`, then `wiki/index.md`, then the top few entries of
`wiki/log.md` — those are always the freshest truth. This file is the orientation layer.

---

## 1. What this repo is (30-second version)

A **general U.S. state assessment-metadata registry**. Version-controlled annual JSON
sidecars are the canonical source of truth; everything else is derived. Three tiers:

```
Tier A  Authored JSON sidecars   metadata/<jur>/<system>/*.json   (CANONICAL, gated by schemas/)
Tier B  Derived layer            amrr::build_registry() -> build/  (index, changelog, dist/ bundles, SQLite, manifest) — GIT-IGNORED, rebuilt by CI
Tier C  Consumed                 r-pkg/amrr (get_metadata + accessors) + site/ Quarto catalog
```

Founding architecture: `wiki/decisions/000-registry-architecture.md` (read it). The pin for
reproducibility is a **Git commit SHA** — consumers record it, and any past state is
reconstructable from it.

## 2. Where things stand

- **Corpus:** 48 sidecars, all **v2** (`amr.assessment.v2` / `amr.accountability.v2`), 3
  jurisdictions — **IN** (Indiana: ILEARN, WIDA-ACCESS, accountability) is the real one; **SC**
  and **SD** are demonstration jurisdictions. All records are `status: draft` (scaffold
  values) pending human review — **never self-promote toward `verified`.**
- **Schemas:** v2 is primary; the v1 schemas remain accepted during the migration window.
  Key v2 ideas: the **enrollment-grade model** (`intended_enrollment_grade: fixed|variable`
  + `enrolled_grades_tested[]`) and the **axis rule** (cutscores / scale_bounds keyed by
  *enrolled grade*, never instrument/form name). `proficient_from` (a single label) is the
  canonical proficiency benchmark, replacing the legacy positional `proficient[]` mask; EOC
  assessments may use the instrument-level `"eoc"` cut key. Design exemplars live in
  `schemas/examples/` (not Tier A — the validator ignores them).
- **`amrr` R package (0.5.0)** — `r-pkg/amrr/R/`: `get_metadata.R` + `accessors.R` +
  `targets.R` (consume), `remote.R` (remote registries), `config.R` (`as_config`/`read_config`
  view), `validate.R` + `build.R` + `migrate.R` + `materialize.R` (tooling),
  `registry.R` + `tooling-internal.R` (internals).
- **ADRs accepted (000-011):** all accepted except **005** (AI authoring pipeline) and **006**
  (governance / promotion policy), which are `planned`. `wiki/index.md` has the full table.

### The one thing most likely to be new to you: how consumers reach the registry

`get_metadata(jurisdiction, system, year, registry, ref, attach_targets)` resolves the
`registry` argument three ways (`.registry_kind()` in `R/remote.R` dispatches):

1. **Local checkout** — a directory with `metadata/`. If `registry` is omitted, resolution is
   `option("amrr.registry")` → `AMRR_REGISTRY` env → **auto-discovery** (walk up from the
   working directory to the nearest checkout: a dir with both `metadata/` and `schemas/`).
   So running R anywhere inside a clone just works with no argument. Pin = git `HEAD`.
2. **Reproducible remote** — `registry = "github://owner/repo"` (or `https://github.com/...`)
   + `ref` (SHA | branch | tag | default HEAD). Reads the **canonical sidecars** straight
   from GitHub, pinned to an exact commit SHA (git-trees enumeration + raw content, both
   immutable) — no checkout, byte-for-byte reproducible (ADR-011).
3. **Derived-URL** — a base URL (e.g. GitHub Pages root) serving `dist/<jur>.json`.
   **Convenience only — serves the latest build, not reproducible.**

The github classifier must intercept before the generic URL matcher (a `https://github.com/`
URL also matches `.is_url_registry()`). `ref` resolves-and-fetches for `github://` (no
mismatch warning) and asserts-and-warns for local/derived.

## 3. Ground rules (from AGENTS.md — non-negotiable)

- **Tier A is the only place edits happen.** `metadata/`, `schemas/` are authored. The
  `build/` layer is derived, disposable, git-ignored — never hand-edit it; regenerate it.
- **No microdata, ever.** System-level metadata only. Never add/read student- or
  school-level records. If a task implies microdata, stop and flag it.
- **Every non-draft claim needs a citation** (`provenance.source_citation`). Machine-drafted
  records stay `status: draft` + low confidence until a human promotes them.
- **Validate before you project.** A malformed / identity-conflicting sidecar fails the build.
- **Federation, not duplication.** A fact lives in one place; consumers point at the
  registry, they don't fork it.
- **Keep the wiki current** — append a `wiki/log.md` entry after substantive work; update
  `wiki/index.md` when the state or ADR set changes.

## 4. Working the repo

Local loop (all R behind a Makefile — same gates as CI; prefer it over ad-hoc commands):

```bash
make setup      # once: install R tooling + site packages
make validate   # Tier A gate (schema + registry invariants)
make build      # validate, then derive Tier B into build/
make test       # full testthat suite
make check      # R CMD check (roxygenise regenerates man/ + NAMESPACE)
make site       # render the Quarto catalog into site/_site/
make all        # validate -> build -> test
```

- **CI (required on PRs):** `validate` (path-filtered to `metadata/`/`schemas/`),
  `R-CMD-check` (path-filtered to `r-pkg/**`), and `build-publish` (Pages deploy on merge to
  `main`, SHA-stamped). `main` is **branch-protected — a PR is required.** Do not merge
  without green CI.
- **Auto-validate hook:** `.claude/hooks/validate-metadata.sh` runs on edits to
  `metadata/`/`schemas/` — silence = success; a failure is fed back. Degrades to a no-op
  without the R toolchain.
- **Subagents** (`.claude/agents/`): `metadata-author` (draft-only authoring from a cited
  source), `registry-librarian` (regenerate + diff the derived layer, read-only on Tier A),
  `consumption-lint` (verify the SGPc consumption contract still holds — run before merging
  any Tier A schema or `amrr` change).

> **⚠ Local toolchain caveat (2026-07-08):** the dev machine's R was upgraded to **4.6.1**
> and its package library is currently **bare** (no `testthat`/`devtools`/`withr`/…), so
> `make test` / `make check` will not run locally until you `make setup` (or
> `install.packages(c("devtools","testthat","withr","jsonvalidate","DBI","RSQLite","digest","curl"))`).
> Until then, **CI R-CMD-check is the authoritative full-suite gate.** You can still
> parse-check and functionally smoke-test dependency-free R with base `Rscript`.

## 5. Open work (pick up here — none started; do not start unbidden without confirming)

Roughly in priority order:

1. **Phase G — SGPc resolver wiring.** Wire SGPc's metadata resolver to consume this
   registry as a `registry` source — ideally the new `github://` reproducible remote (pin by
   SHA, no submodule). Contract + open questions: `wiki/connections/sgpc-registry-consumption-contract.md`
   (its former "remote pinning" open item is now **resolved** by ADR-011). Verify SGPc output
   stays byte-identical for metadata-unaware runs; run the `consumption-lint` subagent.
   *Note:* any SGPc path reading raw `proficient[]` directly from sidecar JSON must migrate to
   `proficient_from` / `amrr_achievement_levels()` (the raw mask is deprecated).
2. **Real WIDA_IN authoring.** Fill the nine WIDA-ACCESS records with real enrolled grades,
   official proficiency-level lookups, scale bounds, and `measurement.elp` — replacing the
   migration scaffold. Exemplar: `schemas/examples/wida-access-in-2024.v2.example.json`. Use
   the `metadata-author` subagent (draft-only, cited).
3. **On-disk cache store for the `github://` remote.** The immutable-read *seam* exists
   (`.gh_get_json` / `.gh_get_raw` in `R/remote.R`); add a store keyed by owner/repo/SHA/path
   under `tools::R_user_dir("amrr","cache")` (safe forever — content at a SHA is immutable —
   enabling offline replay). Optional hardening: verify each fetched blob's git SHA-1 against
   the tree entry.
4. **ADR-006 — governance / promotion policy** (`draft`→`reviewed`→`verified`). Draftable
   independently; gates real authoring.
5. **`read_config()` sidecar writer.** Currently the config view round-trips in memory; a
   writer that emits authored sidecars from the compact shape would close the authoring loop.
6. **ADR-005 — AI authoring/scraping pipeline.** Deferred until the v2 corpus is stable.

## 6. Known sharp edges

- **Squash-merges delete the branch and rewrite SHAs.** After a merge, `git cherry` shows the
  original commits as "unmerged" (patch-id mismatch) even though their content is on `main` —
  don't be fooled. Branch off fresh `origin/main` for new work; don't reuse a squash-merged
  branch.
- **Reproducibility only holds for Tier A over a SHA.** The derived `dist/` bundles are
  git-ignored, so the derived-URL mode is latest-only. For a reproducible remote read, use
  `github://` + `ref`, or a checkout at a SHA.
- **Auto-discovery finds *any* registry-shaped ancestor.** A test that asserts "no registry →
  error" must `setwd()` to a tmpdir outside any checkout (see `test-get_metadata.R`).
- **`jsonvalidate` needs V8; the remote path prefers `curl`** (both `Suggests`). CI installs
  them; `make setup` covers them.
- **R `$` partial matching bit us once:** `block$proficient` silently matched `proficient_from`.
  Use exact `[[ ]]` on records with overlapping key prefixes (see `.proficient_mask()`).
- **`schemas/examples/` is documentation, not Tier A** — the validator ignores it.
