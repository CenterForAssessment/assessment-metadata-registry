# HANDOFF — assessment-metadata-registry → CLI (v2 implementation: verify, migrate, ship)

**Date:** 2026-07-06
**From:** Cowork session (no R toolchain; all R code written but **not executed**)
**To:** Claude Code CLI (R available, GitHub authorized, native filesystem)
**Repo:** `/Users/conet/GitHub/CenterForAssessment/assessment-metadata-registry` (branch `main`;
everything below is **uncommitted** — a mix of untracked files and modifications)

Read `AGENTS.md` first (session-start protocol), then this file. The wiki is current:
`wiki/log.md` top two entries describe exactly what landed today.

---

## 1. What happened today (context)

All open ADRs were signed off by Damian (2026-07-06) and the **v2 schema implementation
(ADR-009)** was built end-to-end — `amrr` 0.2.0:

- **ADRs 000, 004, 007, 008, 009 → accepted.** ADR-009 (`wiki/decisions/009-v2-implementation.md`)
  is the spec for everything below. Key design: the **enrollment-grade model** — every v2
  content area carries `enrollment` (`intended_enrollment_grade: fixed|variable` +
  `enrolled_grades_tested[]` + `note`), and the **axis rule**: `cutscores`, `scale_bounds`,
  `cutscores_source` are always keyed by *enrolled grade*, never instrument/form names.
- **Phase B** — `schemas/amr.assessment.v2.schema.json` + `schemas/amr.accountability.v2.schema.json`;
  `validate_registry()` routes v1/v2 (dual-version window), adds v2 invariants (axis rule;
  `loss <= min(cuts) <= max(cuts) <= hoss`), warns on v1 stragglers once any v2 record exists.
- **Phase C** — `amrr::migrate_registry()` (`r-pkg/amrr/R/migrate.R`): mechanical v1→v2
  restamp; `assessment_type` normalization (`state-summative→summative`,
  `english-language-proficiency→elp`); enrollment seeded from cutscore grade keys
  (`elp→variable`, else `fixed`). Never invents facts. **The corpus (48 records under
  `metadata/`) has NOT been migrated — that is your job (Task 3).**
- **Phase D** — v2 accessors: `amrr_enrollment()`, `amrr_scale_bounds()`, `amrr_elp()`,
  `amrr_alternate()`, `amrr_source_documents()`, `amrr_growth_targets()`, `amrr_timelines()`,
  `amrr_participation()`.
- **Phase E** — `build_registry()` index rows carry the enrollment fields + `has_scale_bounds`;
  `site/spec.qmd` renders all four schemas; `site/_common.R` renders v2 blocks (and fixes a
  latent bug: `amr_is_accountability` matched only the v1 string).
- **Phase F** — `amrr_materialize()` → SHA-stamped `.rds`/`.rda` (the colleague-bridge).
- **Tests** — fixture registry gained the v2 schemas + a v2 record
  (`inst/extdata/registry/metadata/IN/wida-access/wida-access-in-2025.json`); new
  `tests/testthat/test-v2.R`; `test-tooling.R` updated (fixture is now **6** records and its
  v1/v2 mix intentionally raises the dual-window warning); shared `helper-registry.R`.
- **Sandbox verification already done** (Python jsonschema, throwaway — not in repo): all 54
  corpus+fixture records validate under routing; 7 negative cases reject; a shadow of the
  migration transform over all 48 corpus records validates as v2. **The R test suite is the
  real gate and has not run.**

## 2. Ground rules (from AGENTS.md — non-negotiable)

- Tier A (`metadata/`, `schemas/`) is canonical; never hand-edit `build/`.
- Migration must never invent facts; new v2 fields stay absent until authored.
- Never promote a record's `status` toward `verified` — human-reviewed commits only.
- Update `wiki/log.md` (and `wiki/index.md` if pages change) after substantive steps.
- Small commits, each gated on a green loop (`make validate` / `make all`).

## 3. Task list (in order; stop and report if any gate fails)

**Task 0 — Baseline.** `make validate` must pass on the still-v1 corpus with **no**
dual-window warning. If R packages are missing: `make setup`.

**Task 1 — Commit the 2026-07-03 taxonomy work** (predates today; untracked):
`wiki/decisions/008-unified-metadata-taxonomy.md`, `wiki/patterns/metadata-taxonomy.md`,
`wiki/analyses/schema-crosswalk.md`, `wiki/sources/colleague-assessment-spec-r.md`.
Suggested: `docs(wiki): ADR-008 unified metadata taxonomy + crosswalk + colleague-spec source`.
(The status flips inside ADR files are part of today's work — fine if they ride along here
or in Task 2; keep the split sensible, not fussy.)

**Task 2 — Commit the v2 implementation** (everything except the not-yet-run corpus
migration): schemas (+ `schemas/examples/`), all `r-pkg/amrr` changes, `site/` changes,
ADR-009 + wiki updates, remaining ADR status flips. Before committing:
1. `make validate` (still green, still no warning — corpus untouched).
2. `make test` — the full testthat suite including `test-v2.R`. **This is the first
   execution of today's R code.** Fix surgically if anything fails; the tests encode the
   intended behavior, so prefer fixing code to weakening tests.
3. `make check` — roxygenise regenerates `NAMESPACE` (should match the hand-written one)
   and generates `man/*.Rd` for the ~10 new exports; **commit the generated man pages**.
   R CMD check must be clean (NOTEs acceptable if pre-existing).
Suggested: `feat(v2): ADR-009 schemas, validator invariants, migrate_registry, accessors, materialize (amrr 0.2.0)`.

**Task 3 — Migrate the corpus (one reviewed commit, ADR-009 D6).**
```r
pkgload::load_all("r-pkg/amrr")
amrr::migrate_registry(".", write = FALSE)  # dry run: expect 48 would-migrate, 0 skipped
amrr::migrate_registry(".")                 # write
```
Review the diff before committing — expect per-file: `schema_version` restamp,
`assessment_type` normalized, `enrollment` block added per content area. jsonlite's
2-space serialization may reformat lines beyond the semantic change; use
`git diff --word-diff` (or `jq -S` on before/after) to confirm nothing semantic drifted.
Spot-check: `metadata/IN/ilearn/ilearn-in-2024.json` (fixed, grades 3–8, `summative`) and
`metadata/IN/wida-access/wida-access-in-2024.json` (variable, **empty**
`enrolled_grades_tested` — correct: the v1 record has no per-grade facts; authoring fills it).
Then `make all` — validation must be green with **no** dual-window warning (all-v2 corpus),
and build parity must hold: **21 targets, 117 per-grade exit thresholds, WIDA grade-5 2024
exit = 364.4** (check `build/targets.json` / the SQLite projection).
Suggested: `feat(metadata): migrate corpus v1 -> v2 (mechanical, ADR-009 D6)`.

**Task 4 — Site.** `make site`; open `site/_site/index.html`. Check: the spec page shows
four tabs (v2 primary, v1 marked "migration window"); a migrated assessment record page
shows the enrollment columns; the v1 JSON fetch URLs still exist under `_site/` (additive
deploy, ADR-007). Headless screenshots are the house pattern if available.

**Task 5 — PR + CI.** Push a feature branch (e.g. `v2-implementation`), open a PR to
`main`, watch `validate`, `R-CMD-check`, and `build-publish` (on merge) go green. Do not
merge without green CI. Wiki: append a short `wiki/log.md` entry recording the local
verification results + PR link.

## 4. Follow-ups (after this handoff ships — do not start unbidden)

1. **WIDA_IN real authoring**: fill enrolled grades, official proficiency-level lookups,
   scale bounds, `measurement.elp` for the nine WIDA records (exemplar to riff on:
   `schemas/examples/wida-access-in-2024.v2.example.json`).
2. **Phase G**: SGPc-side `registry` resolver source (SGPc repo; see
   `wiki/connections/sgpc-registry-consumption-contract.md`).
3. **ADR-006** (governance / promotion policy) — draftable in parallel.
4. **ADR-005** (AI authoring pipeline) — deferred until after v2 corpus is stable.

## 5. Known sharp edges

- `test-v2.R` uses `expect_no_warning` (needs testthat >= 3.1.5) and `withr`.
- The dual-window warning is a `warning()`, not an error, and fires whenever v1 and v2
  records coexist — the fixture triggers it by design; the live corpus should only
  trigger it between Task 2 and Task 3 (never in a committed state).
- `jsonvalidate` needs `V8`; CI installs it, local `make setup` covers it.
- The PostToolUse hook (`.claude/hooks/validate-metadata.sh`) auto-validates on edits to
  `metadata/`/`schemas/` — silence is success; exit 2 shows validator errors to fix.
- `schemas/examples/` is design documentation, not Tier A — the validator ignores it.
