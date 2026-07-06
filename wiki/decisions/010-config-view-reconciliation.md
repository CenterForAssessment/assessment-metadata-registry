---
title: "ADR-010: Reconciling the colleague's assessment_config spec — additive v2 refinements + a config view"
type: decision
created: 2026-07-06
updated: 2026-07-06
status: accepted
deciders: Damian Betebenner
curated: true
sources:
  - wiki/decisions/008-unified-metadata-taxonomy.md
  - wiki/decisions/009-v2-implementation.md
  - wiki/decisions/002-accountability-system-record.md
  - schemas/amr.assessment.v2.schema.json
  - schemas/examples/algebra-i-eoc.v2.example.json
tags: [v2, reconciliation, config-view, proficient-from, eoc, level-schemes, colleague-spec]
---

# ADR-010: Reconciling the colleague's `amr.assessment_config.v1`

**Status:** Accepted (framing approved, Damian Betebenner, 2026-07-06)
**Date:** 2026-07-06

## Context

Right after v2 shipped ([[009-v2-implementation]], `amrr` 0.2.0) and the 48-record corpus
was migrated, a colleague sent an alternative assessment schema
(`amr.assessment_config.v1`) as feedback. It is a **compact, DRY authoring shape**: one
file per program, reusable named `level_schemes` referenced by `tests`, a `content_area ×
grade → test` `map`, and unified per-grade `cuts` (`{loss, hoss, values}`).

[[008-unified-metadata-taxonomy]] already set the governing principle: the colleague's spec
is a **naming/structural input and SGPstateData analog — not a co-equal canonical format**.
Reviewed against v2, ~90% of the spec is the *same facts in a different arrangement*: v2
already stores the level content, cutscores, scale bounds, enrollment, and (via
`assessment_type = end-of-course`) EOC typing. His spec optimizes for *compact authoring*;
v2 optimizes for *normalized, queryable, Git-versioned storage*. They are different layers,
not competing schemas.

Two genuine contributions, one modeling smell, and one ergonomics gap emerged.

## Decision

**Refine v2 in place (additive, non-breaking) and offer the compact shape as an `amrr`
projection — do not re-model canonical.** Concretely:

### Adopted (additive to `amr.assessment.v2`)

- **`achievement_levels[ca].proficient_from`** — the canonical proficiency benchmark: the
  label of the *lowest proficient level*. Replaces the fragile positional `proficient[]`
  boolean mask (still accepted, now deprecated; the validator checks the two agree). This
  fixes a smell the colleague's spec shared with v2: a parallel boolean array is
  positionally coupled to `labels`, encodes one bit of information in N booleans, permits
  non-monotonic nonsense, and bundles a **policy** judgment (where proficiency begins) into
  a **measurement** structure ([[002-accountability-system-record]] draws exactly this
  line; ADR-008 §5 already said the benchmark should be *derived*). `proficient_from` is one
  value, robust to label edits, and cleanly separable. `.proficient_mask()` derives the
  boolean mask for consumers; `proficiency_boundary` target resolution and the SQLite
  `achievement_level` projection route through it. The corpus was folded to `proficient_from`
  and `migrate_registry()` now emits it directly.
- **End-of-course instrument-level cut key (`"eoc"`)** — an EOC standard is instrument-level,
  not grade-specific. Records with `assessment_type = end-of-course` may key `cutscores` /
  `scale_bounds` / `cutscores_source` once under the sentinel `"eoc"` instead of copying the
  cut across every enrolled grade. This is a scoped exception to the axis rule ([[009-v2-implementation]] D2),
  gated by the validator to EOC only; any other type keying by `"eoc"` still fails the axis
  rule. `schemas/examples/algebra-i-eoc.v2.example.json` demonstrates the shape.
- **`provenance.verified_by`** — the one provenance field v2 lacked (it already had
  `entered_by`/`entered_at`/`last_verified_at`/`changed_from_prior`).

### Adopted (as a projection, not canonical)

- **The compact config shape** is offered as an `amrr` **authoring/export view**
  (ADR-008 tier-3), not a second source of truth: `as_config()` projects one
  `jurisdiction × system` into `amr.assessment_config.v1` (deduped named `level_schemes`,
  `tests`, a `map`, unified `cuts`); `read_config()` expands it back into a v2 record.
  `build_registry()` emits the projection under `build/config/`, and the site's **Config
  view** page renders it. The projection must carry v2's **`intended_enrollment_grade`**
  (`fixed|variable`) explicitly on each test — the colleague's `intended_grades` list alone
  cannot express it (ILEARN tests grades 3–8 yet is `fixed`), so a bare grade list would
  lose the enrollment axis.

### Rejected (recorded rationale)

| Colleague construct | Verdict | Rationale |
|---|---|---|
| `tests` + `map` as the **canonical** enrollment model | Rejected as canonical | Conflicts with the signed-off enrollment model ([[009-v2-implementation]]); `enrolled_grades_tested` is the single axis-rule authority. The map's only extra expressiveness (different grades → different instruments in one content area) is better served by separate content areas / records. Available as the config *view*. |
| Unified `cuts {loss, hoss, values}` in canonical | Rejected | v2 deliberately separates always-present `cutscores` from often-provisional `scale_bounds` (independent `source`/confidence, envelope invariant). The config view unifies them for display; canonical keeps them separate. |
| Single-file multi-test `program` container as canonical | Rejected as canonical | v2 is normalized annual sidecars (Git history axis, per `jurisdiction × system × year`). The container is an authoring convenience — the `amrr` config view, per ADR-008 tier-3. |
| `level_schemes` as a **canonical** top-level construct | Deferred | The DRY win is real but belongs to the *authoring* layer; canonical keeps levels inline per content area (with `proficient_from`). The config view materializes reusable named schemes on export. Revisit if inline repetition becomes a maintenance burden. |

## Consequences

- **Non-breaking.** The migrated corpus stayed valid throughout; `proficient[]` is still
  accepted. `amrr` 0.3.0.
- **The `proficient` smell is fixed in canonical** — the 27 assessment records now carry
  `proficient_from`; build parity held (ILEARN ELA proficient `[0,0,1,1]`, ELA g3
  proficiency_boundary = 497, WIDA g5/2024 = 364.4, all unchanged).
- **The colleague gets his ergonomics** without a canonical rewrite: author/review in the
  compact shape via `read_config()`/`as_config()`, browse it on the Config view page.
- **Follow-ups:** a `read_config()` → sidecar *writer* (authoring CLI) is deferred (the
  current inverse returns in-memory records); real EOC authoring for a jurisdiction remains
  future Tier A work.

## Alternatives considered

- **Pivot canonical to the colleague's `tests`/`map` shape.** Rejected: re-migrates a
  just-shipped corpus, discards the signed-off enrollment model, and inverts the
  storage-vs-authoring layering ADR-008 established.
- **Decision memo only (no code).** Rejected in favor of shipping the additive refinements
  now, since they are non-breaking and the `proficient_from` fix improves canonical
  independently of the colleague conversation.
