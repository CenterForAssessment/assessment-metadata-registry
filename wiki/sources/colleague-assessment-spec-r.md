---
title: "Source: colleague assessment_spec.R"
type: source
created: 2026-07-03
updated: 2026-07-03
status: active
curated: true
sources:
  - colleague assessment_spec.R (shared 2026-07-03; not yet in this repo)
tags: [assessment-spec, el-spec, r-list, state-summative, elp, alternate, verification]
---

# Source: colleague `assessment_spec.R`

One-line summary: a unified, verifiable R-list schema for state summative / alternate / ELP
assessments — one spec per `STATE × YEAR × TYPE`, designed to seed a GitHub repo of
git-diff-friendly `.R` sidecars with validation, accessors, and manifest tooling.

## Origin and intent

Shared by a colleague (2026-07-03) as feedback on the registry / SGPc metadata alignment
discussion. The file generalizes two prior patterns — a general summative `assessment_spec`
and an EL-package `el_spec` — into a single typed schema with a type discriminator. It
resembles the historical **SGPstateData** embedding model (one R object per state-year
program) but adds explicit validation, provenance, and repo layout conventions.

**Primary audience:** state accountability / summative analysis workflows that need
cutscores, achievement levels, and data-column mappings in one sourced object.

**Not the same as:** the registry's JSON sidecars (federated, Git-SHA-pinned, multi-consumer)
or SGPc's narrow analysis projection. This source informs the **typed authoring view** in
[[008-unified-metadata-taxonomy]].

## Structural design

### Type discriminator

`program$assessment_type` is one of `"general"`, `"alternate"`, or `"elp"`. Each type shares
a common base; ELP and Alternate add conditional extension blocks:

| Type | Extension block | Purpose |
|------|-----------------|---------|
| `general` | *(none)* | State summative / EOC |
| `alternate` | `alternate` | DLM / MSAA / state alt programs |
| `elp` | `elp` | WIDA ACCESS and similar ELP instruments |

### Base blocks (all types)

| Block | Role |
|-------|------|
| `schema_version` | Semver string (`"1.0.0"`) for safe repo evolution |
| `program` | Identity: name, short_name, state, department, assessment_type, administration_year, vendor |
| `subjects` | Named list: each subject = `list(label, grades)`; EOC uses `grades = NULL` |
| `achievement_levels` | `labels` (ordered low→high), `policy_benchmark` (one label = proficient cut), `data_column` |
| `scale_scores` | Named list keyed `<SUBJECT>_<GRADE>` (span) or `<SUBJECT>` (EOC); each = `loss`, `hoss`, `cuts`, optional `source` |
| `years` | `tested_years`, `cohort_anchor_grade` |
| `data` | Column name mappings for assessment fields + `demographics_spec` path (separate file) |
| `verification` | Human review workflow: status, verified_by, verified_date, method, notes |
| `source_documents` | List of `{title, url}`; `url` may be `NA_character_` when not yet located |

### ELP extension (`elp` block)

Instrument, domains, composites, composite_weights, grade_clusters, band_scheme,
exit_criteria, growth_targets, timelines. **Note:** exit/growth/timeline are state *policy*
facts in the registry model — see [[schema-crosswalk]] for reclassification into
accountability metadata.

### Alternate extension (`alternate` block)

Instrument, achievement_standard, scoring_model (`"scale"` | `"profile"`), linkage_levels,
participation_criteria, federal_cap, equating_notes. Participation criteria and federal cap
are policy facts; scoring_model and linkage_levels are measurement facts.

## Key design choices (relevant to alignment)

1. **Demographics removed from the spec.** `data$demographics_spec` points to a separate
   demographics file so demographic coding can change independently of assessment metadata.
2. **Verification as a first-class block** with states:
   `unverified → auto_derived → in_review → human_verified`. Cut entries carry per-value
   `source` (`official` / `derived` / `provisional`); validator warns if
   `human_verified` coexists with derived/provisional cuts.
3. **Back-compatibility preserved:** `get_score_spec()`, `assign_level()` using
   `sum(score > cuts) + 1`, and `<SUBJECT>_<GRADE>` keying match existing analysis code.
4. **Repo layout:** `specs/<STATE>/<YEAR>/<STATE>_<type>_<year>.R` plus
   `demographics/<STATE>/<YEAR>/...`; `build_manifest()` scans and validates on source.
5. **Serialization path:** plain named lists today; YAML/JSON export noted for non-R
   consumers later.

## Machinery (R API surface)

| Function | Purpose |
|----------|---------|
| `validate_assessment_spec()` | Structural validation (cuts, monotonicity, extension presence) |
| `as_assessment_spec()` | Validate + S3 class `assessment_spec` |
| `get_score_spec()` / `assign_level()` | Score → level using cut convention |
| `spec_id()` / `spec_summary()` / `build_manifest()` | Repo indexing and status table |

## Gaps vs registry / SGPc

| Present in assessment_spec.R | Absent or different elsewhere |
|------------------------------|-------------------------------|
| `loss` / `hoss` per scale key | Registry/SGPc cutscores only; no explicit bounds |
| `subjects` + per-subject `grades` | Registry `content_areas` array without grades |
| `policy_benchmark` (single label) | Registry `proficient` boolean mask |
| `verification` + per-cut `source` | Registry `status` + `provenance` + `source_confidence` |
| `source_documents[]` (list) | Registry single `provenance.source_citation` |
| `data$columns` mappings | Not in registry (consumer plumbing) |
| `years$tested_years` / cohort anchor | Not in registry (analysis config) |
| ELP/alternate extension blocks | Not in v1 registry schemas |
| `comparability` / scale transitions | Registry only (ADR-003) |
| `edfi` crosswalk | Registry + SGPc only |
| Accountability targets (exit) in `elp$exit_criteria` | Registry accountability record (ADR-002) |

## Related pages

- [[schema-crosswalk]] — field-level mapping onto the five-domain taxonomy
- [[metadata-taxonomy]] — canonical domain definitions
- [[008-unified-metadata-taxonomy]] — greenfield target model ADR
- [[002-accountability-system-record]] — why exit targets belong in accountability
