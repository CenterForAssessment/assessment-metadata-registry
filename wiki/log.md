# Registry Wiki — Activity Log

Append-only, reverse-chronological. Newest entries on top.

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
