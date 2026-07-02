# HANDOFF — assessment-metadata-registry → CLI (GitHub integration + close the SGPc consumption loop)

**Date:** 2026-07-02
**From:** Cowork session (no R, no authorized GitHub connector, FUSE-mounted filesystem)
**To:** Claude Code CLI (R available, GitHub authorized, native filesystem)
**Repo:** `/Users/conet/GitHub/CenterForAssessment/assessment-metadata-registry` (branch `master`, one commit: `f377faf Initial commit` — everything below is **untracked**)

---

## 1. Why this handoff

Two things need an environment this Cowork session doesn't have:

1. **GitHub integration** — push the work, open a PR, and watch CI (validate + build-publish + R-CMD-check) go green. The connector wasn't authorized here.
2. **Close the consumption loop** — wire SGPc to consume the registry via the `amrr` R package, and prove it with `testSGPc()`. Needs R, which isn't installed here.

Everything else (schema, seed corpus, derivation tooling, the `amrr` package, three ADRs, the wiki) is built and self-consistent. Python-side tooling was verified here; the R package was written but **not executed** — running it is the first CLI task.

---

## 2. Current state (what's in the repo)

Tiers A/B/C are all present for 3 jurisdictions.

```
schemas/            amr.assessment_system.v1 + amr.accountability_system.v1 (+ sql/amr-registry.v1.sql)
metadata/           48 sidecars: IN (ILEARN, WIDA-ACCESS, in-accountability), SC + SD (demo, from testSGPc)
tools/              validate.py, build.py, migrate_sgpc_sidecars.py, split_accountability.py, seed_demo.py, requirements.txt
r-pkg/amrr/         R consumption package: get_metadata() + accessors + testthat + fixture
wiki/               ADR-000..003, patterns (harness, derivation-pipeline), connections (sgpc contract), index, log, schema
.github/workflows/  validate.yml, build-publish.yml, R-CMD-check.yml
AGENTS.md CLAUDE.md purpose.md README.md
```

**Verified in this session (Python):** `python3 tools/validate.py` → 48 files, 0 errors; `python3 tools/build.py` → 48 records across 3 jurisdictions; changelog surfaces SC's 2014→2015 scale break and the ILEARN 2020 gap; proficiency-boundary + target-merge logic parity-checked against the `amrr` fixture.

**NOT verified (needs R):** `amrr` load / `R CMD check` / testthat.

**Key design pins (see ADRs):** JSON sidecars canonical; Git commit SHA is the reproducibility pin; targets live in accountability records and are re-merged onto assessment records at read time (`attach_targets`); `amr.assessment_system.v1` accepts the legacy `sgpc.assessment_metadata.v0.1` string as an alias.

---

## 3. First CLI steps — verify locally before touching GitHub

```bash
cd /Users/conet/GitHub/CenterForAssessment/assessment-metadata-registry

# Python tooling (should reproduce the results above)
python3 -m pip install -r tools/requirements.txt
python3 tools/validate.py            # expect: 48 files, 0 errors
python3 tools/build.py               # writes build/ ; expect: 48 records, 3 jurisdictions
#   NOTE: on the CLI's native filesystem the SQLite build no longer needs the temp-copy
#   workaround, but the workaround is harmless — leave it.

# R package — the part unproven here
cd r-pkg/amrr
Rscript -e 'roxygen2::roxygenise()'        # generate man/ from roxygen comments (NAMESPACE is hand-written; reconcile if roxygen rewrites it)
Rscript -e 'devtools::check()'             # expect: 0 errors, 0 warnings (notes ok)
Rscript -e 'devtools::test()'              # expect: all tests pass (test-get_metadata, test-targets, test-demo)
```

If `devtools::check()` surfaces documentation or NAMESPACE mismatches, let roxygen regenerate `NAMESPACE` and commit the result (the hand-written one is a best-effort mirror). Everything the tests assert was parity-checked in Python, so failures are most likely R-mechanics (roxygen/man/imports), not logic.

---

## 4. GitHub integration

The repo has one commit (`README`); all real work is untracked.

```bash
cd /Users/conet/GitHub/CenterForAssessment/assessment-metadata-registry
git checkout -b phase-1-3-registry-foundation

# Sanity: build/ is git-ignored (derived); confirm it is NOT staged
git status --short

git add -A
git commit -m "Registry foundation: schemas, IN + demo corpus, derivation tooling, amrr package, wiki/ADRs"
git push -u origin phase-1-3-registry-foundation
# open the PR (gh or the GitHub MCP)
gh pr create --fill
```

**CI to watch (all defined in `.github/workflows/`):**

- `validate-metadata` — schema + registry-invariant validation of every sidecar. Must be green.
- `build-publish` — runs on merge to `main`; validates, builds, deploys `build/` to **GitHub Pages** (SHA-stamped). Requires **Pages enabled** for the repo (Settings → Pages → Source: GitHub Actions) and the default `GITHUB_TOKEN` Pages permissions — enable before/at merge.
- `R-CMD-check` — paths-filtered to `r-pkg/**`; runs `roxygen2::roxygenise()` then `rcmdcheck`. First run will exercise the package build in CI.

Consider protecting `main` and requiring these checks. The commit SHA that lands on `main` becomes the first real **reproducibility pin** for consumers.

---

## 5. Close the consumption loop (the core task)

Goal: SGPc consumes the registry through `amrr` instead of embedding/inlining metadata, and `testSGPc()` proves it. SGPc lives at `/Users/conet/GitHub/dataimago/SGPc/SGPc-rpkg/SGPc` (package `SGPc` 0.0.3.0).

The consumption contract is documented in `wiki/connections/sgpc-registry-consumption-contract.md`. Three additive SGPc-side changes:

### 5a. Accept the `amr.*` schema alias (SGPc `R/metadata.R`)

Today SGPc checks `schema_version` with `identical()` in two places:
- line ~39, inside `validate_sgpc_assessment_metadata()`
- line ~351, inside `is_sgpc_metadata_record()`

Introduce an accepted-set and use `%in%`:

```r
sgpc_assessment_metadata_schema_versions <- function() {
  c("amr.assessment_system.v1", sgpc_assessment_metadata_schema_version())  # legacy last
}
# validator:  if (!metadata$schema_version %in% sgpc_assessment_metadata_schema_versions()) stop(...)
# predicate:  is.list(x) && !is.null(x$schema_version) && x$schema_version %in% sgpc_assessment_metadata_schema_versions()
```

Note: SGPc's R validator checks *presence* of known blocks, not `additionalProperties`, so the registry's extra fields (`status`, `provenance`, `source_confidence`, `comparability`) pass through untouched. The merged `achievement_targets` from `amrr` are content-area-keyed with `semantics`/`basis`/`per_grade_scale_score`/`comparison` — the shape SGPc already consumes.

### 5b. Add a `registry` source to the resolver (SGPc `R/metadata.R`)

In `resolve_sgpc_metadata()` the sources list is built at lines ~909–916 (`arg`, `store`, `embedded`). Insert a `registry` source **between `store` and `embedded`**:

```r
if (!is.null(registry)) sources[["registry"]] <- registry   # a path/records from amrr::get_metadata()
# ... existing embedded block last ...
```

Precedence becomes `arg > store > registry > embedded`. The `registry` value can be the list of records returned by `amrr::get_metadata(..., attach_targets = TRUE)` (already `collect_sgpc_metadata_records`-compatible: it's a list of records carrying `schema_version`). Thread a `registry`/`ref` argument through `resolve_run_metadata()` → `run_sgpc_analysis()` as an opt-in, mirroring the existing `metadata=`/`store=` plumbing.

### 5c. Record the pin in outputs (SGPc manifest/output bundle)

Extend the run manifest's metadata block with `registry_ref` (= `amrr::amrr_registry_ref(md)`), `registry_schema_version`, and the per-cell content digest. Additive; keep metadata-unaware runs byte-identical.

### 5d. Prove it with `testSGPc()` (the demo is already in the registry)

`testSGPc()` currently builds demo metadata inline: `sgpc_test_metadata_records(scenario, present_years)` at `R/testSGPc.R:343`, fed at line ~501 and set as `spec$metadata <- list(records = metadata_records)` at ~1592. Replace the inline builder with a registry read:

```r
md <- amrr::get_metadata(scenario$jurisdiction$id,           # "SD" or "SC"
                         system = scenario$assessment_system$id,
                         registry = Sys.getenv("AMRR_REGISTRY"),  # a registry checkout
                         attach_targets = TRUE)
metadata_records <- unclass(md)                              # list of records for spec$metadata$records
```

**Watch the baseline digests.** The demo cutscores/targets match the inline values for the **post-transition** period, but SC's **legacy-scale years (2013–2014)** were *invented* in the registry (different cutscores) to exercise the changelog. testSGPc conditions touch 2013–2016 for SC, so consuming the registry **will change SC proficiency-layer outputs and shift the SC baseline digest**. Options, in order of preference:

1. **Reconcile the registry to match** the inline demo for the years testSGPc uses (drop the SC legacy-scale divergence, or move the invented transition to years testSGPc doesn't touch), keep baselines stable, then `testSGPc(baseline = "update")` only if truly needed. Cleanest for a first proof.
2. **Accept the change**: run `testSGPc(baseline = "update")` to re-baseline SC, and document that the demo now reflects the registry's transition. Fine once the loop is trusted.
3. **Start with State D only** (no invented divergence; the gap is a pure absence) to prove the loop end-to-end, then bring in SC.

Recommended: **State D first** to prove the mechanism with stable baselines, then decide on SC (1 vs 2).

### 5e. Depend on `amrr`

`amrr` is in the registry monorepo (`r-pkg/amrr`). For SGPc to use it: install from the local path (`devtools::install_local("…/assessment-metadata-registry/r-pkg/amrr")`) or add a `Remotes:` entry (`CenterForAssessment/assessment-metadata-registry` with a subdir, once pushed). Keep it a **Suggests** in SGPc if consumption is opt-in, so SGPc doesn't hard-depend on the registry for metadata-unaware runs.

---

## 6. Verification checklist (CLI)

- [ ] `python3 tools/validate.py` → 48 files, 0 errors
- [ ] `python3 tools/build.py` → 48 records, 3 jurisdictions; inspect `build/changelog.json` (SC transition + ILEARN gap)
- [ ] `amrr`: `roxygen2::roxygenise()`, `devtools::check()` clean, `devtools::test()` green
- [ ] Branch pushed; PR open; `validate-metadata` + `R-CMD-check` green on the PR
- [ ] Pages enabled; after merge, `build-publish` deploys and the published `manifest.json` carries a non-dirty `git_sha`
- [ ] SGPc: alias + `registry` source + manifest pin added; `SGPc::testSGPc("1")` (State D) passes consuming `amrr`
- [ ] Decide SC reconciliation (option 1/2/3) and record it in the SGPc-side change + registry `wiki/log.md`

---

## 7. Open decisions & gotchas

- **ADR-000 is still `status: proposed`.** Flip to `accepted` once you (and co-developer) sign off. ADR-001/002/003 are `accepted`.
- **Remote SHA-pinning is unresolved** (see the consumption-contract "Open item"): raw-by-SHA needs the consumed artifact committed, but `build/` is git-ignored. v1 consumes a **local registry checkout** (fully pinnable). Whether to commit per-jurisdiction bundles or publish per-tag release assets is a future ADR — decide when a non-checkout consumer appears.
- **`amrr` NAMESPACE is hand-written**; let roxygen own it once R is available (regenerate + commit).
- **SQLite temp-copy** in `build.py` is a FUSE-mount workaround from this session; harmless on native FS, leave it.
- **ILEARN cutscores are placeholders** (`status: draft`, `source_confidence: low`). Promoting them to `verified` with the official IDOE tables + citations is the natural companion to real use; the schema's conditional then requires `provenance.source_citation`.
- **Changelog target appear/disappear**: the ILEARN 2020 gap shows as targets removed/re-added (from `null`). That's correct signal; if you want to distinguish "added/removed" from "value changed", refine `build_changelog` in `tools/build.py`.

---

## 8. Quick reference

| Thing | Path |
|---|---|
| Architecture | `wiki/decisions/000-registry-architecture.md` |
| Schemas | `schemas/amr.assessment_system.v1.schema.json`, `schemas/amr.accountability_system.v1.schema.json` |
| Consumption contract | `wiki/connections/sgpc-registry-consumption-contract.md` |
| R client | `r-pkg/amrr/R/get_metadata.R`, `R/targets.R`, `R/accessors.R` |
| SGPc resolver | `SGPc-rpkg/SGPc/R/metadata.R` (`resolve_sgpc_metadata` ~909; schema check ~39, ~351) |
| SGPc demo consumer | `SGPc-rpkg/SGPc/R/testSGPc.R` (`sgpc_test_metadata_records` ~343; spec feed ~1592) |
| Re-run seeds | `tools/migrate_sgpc_sidecars.py`, `tools/split_accountability.py`, `tools/seed_demo.py` |

Registry checkout for `amrr`: set `AMRR_REGISTRY` or `options(amrr.registry=)` to the repo root.
