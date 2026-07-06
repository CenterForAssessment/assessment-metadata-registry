# amrr 0.3.0 (2026-07-06)

v2 refinements reconciling the colleague's `amr.assessment_config.v1` feedback
(ADR-010) -- additive, no canonical re-modeling.

* `achievement_levels[ca]` gains `proficient_from` (the lowest proficient
  label), the canonical proficiency benchmark. It replaces the fragile
  positional `proficient[]` boolean mask (still accepted, now deprecated;
  the validator checks the two agree). `.proficient_mask()` derives the mask
  for consumers; `proficiency_boundary` target resolution and the
  `achievement_level` projection route through it. The corpus was folded to
  `proficient_from`; `migrate_registry()` now emits it directly.
* `provenance.verified_by` (string|null): who performed the last verification.
* End-of-course assessments may key `cutscores` / `scale_bounds` once under the
  instrument-level `"eoc"` sentinel instead of copying across enrolled grades;
  the validator permits it only when `assessment_type = "end-of-course"`.
* New `as_config()` / `read_config()`: project registry records into the compact
  "assessment config" authoring/export view (reusable `level_schemes`, `tests`,
  a `content_area x grade` `map`, unified `cuts`) and back. A lens on canonical
  v2, not a second source of truth (ADR-008 tier-3); a round-trip preserves the
  core facts (extension/provenance blocks are dropped).

# amrr 0.2.0 (2026-07-06)

v2 schema surface (ADR-008 / ADR-009).

* `validate_registry()` routes records to v1 or v2 schemas (dual-version
  window) and enforces the new v2 invariants: the enrollment **axis rule**
  (cutscore / scale-bound / cutscores-source grade keys must be enrolled
  grades within `enrollment.enrolled_grades_tested`) and the scale envelope
  (`loss <= min(cuts) <= max(cuts) <= hoss`). Once any v2 record exists,
  remaining v1 records raise a migration warning.
* New `migrate_registry()`: mechanical v1 -> v2 restamp (schema_version,
  canonical `assessment_type` enum, `enrollment` block seeded from cutscore
  grade keys). Never invents facts; dry-run with `write = FALSE`.
* New v2 accessors: `amrr_enrollment()`, `amrr_scale_bounds()`, `amrr_elp()`,
  `amrr_alternate()`, `amrr_source_documents()`, and (accountability)
  `amrr_growth_targets()`, `amrr_timelines()`, `amrr_participation()`.
* New `amrr_materialize()`: persist a pinned `get_metadata()` response to
  `.rds`/`.rda` for package embedding (SGPstateData-style); the artifact
  carries the registry SHA and a `materialized_at` stamp.
* `build_registry()` index rows carry `intended_enrollment_grade`,
  `enrolled_grades_tested`, and `has_scale_bounds` (null on v1 rows).
* Fixture registry gains the v2 schemas and a v2 record
  (`wida-access-in-2025.json`).

# amrr 0.1.0

Initial release: `get_metadata()` (+ target re-merge), accessors,
`validate_registry()`, `build_registry()` (ADR-004 single-language tooling).
