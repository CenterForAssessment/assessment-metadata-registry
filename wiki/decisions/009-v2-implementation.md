---
title: "ADR-009: v2 Schema Implementation — Enrollment-Grade Model, Scale Bounds, Extensions, Migration"
type: decision
created: 2026-07-06
updated: 2026-07-06
status: accepted
deciders: Damian Betebenner
curated: true
sources:
  - wiki/decisions/008-unified-metadata-taxonomy.md
  - wiki/analyses/schema-crosswalk.md
  - wiki/patterns/metadata-taxonomy.md
  - schemas/amr.assessment_system.v1.schema.json
  - schemas/amr.accountability_system.v1.schema.json
  - schemas/examples/wida-access-in-2024.v2.example.json
tags: [v2, implementation, schema, enrollment, grade-span, loss-hoss, migration, wida, dogfood]
---

# ADR-009: v2 Schema Implementation

**Status:** Accepted (sign-off Damian Betebenner, 2026-07-06 — binary `fixed|variable` enum
confirmed)
**Date:** 2026-07-06

This is the follow-up implementation ADR required by [[008-unified-metadata-taxonomy]] §8.
ADR-008 fixed the taxonomy and consumption priority; this ADR fixes the concrete v2 field
set, the enrollment-grade model (a refinement identified at ADR-008 sign-off), the
migration policy, and the phased delivery plan.

## Context

ADR-008 was accepted 2026-07-06 with colleague confirmation of API-first consumption.
The near-term proof point is **SGPc sidecar consumption**; the near-term dogfood corpus is
**WIDA-ACCESS Indiana** (nine years already seeded as v1 drafts).

At sign-off the decider identified a subtlety the crosswalk's bare `content_areas[].grades`
field conflates: the relationship between an **assessment instrument** and the **enrolled
grade of the student** taking it. Three motivating cases:

| Assessment | Intended enrollment grade | Enrolled grades tested | Note |
|------------|--------------------------|------------------------|------|
| ILEARN Grade 8 Mathematics | `fixed` | 8 | Grade-level instrument; one per enrolled grade |
| ACT | `variable` | 10, 11, 12 | One high-school instrument; usually 11th grade, but 10th/12th may sit it for graduation-competency purposes |
| WIDA-ACCESS K-2 | `variable` | K, 1, 2 | Grade-span (cluster) instrument |

Today "grade" is doing three jobs: (a) the instrument's target grade or span, (b) the
enrolled grade of the student, and (c) the key on `cutscores`. v2 must disentangle these.

## Decision

### D1 — Enrollment-grade model on every content area

Each `content_areas[]` object gains a required `enrollment` block:

```json
"enrollment": {
  "intended_enrollment_grade": "fixed",
  "enrolled_grades_tested": ["3", "4", "5", "6", "7", "8"],
  "note": "Grade-level instruments; one per enrolled grade."
}
```

- `intended_enrollment_grade` — enum `fixed | variable`. `fixed`: the instrument is built
  for one enrolled grade (ILEARN Grade 8 Math). `variable`: students from multiple
  enrolled grades sit the same instrument (ACT, WIDA grade-span forms).
- `enrolled_grades_tested` — ordered string array; `"K"` permitted; EOC may use `[]` with
  a note.
- `note` — free text for the inevitable edge cases.

**Axis rule (the conflation fix):** `cutscores` and `scale_bounds` (D2) are **always keyed
by enrolled grade** — the score-interpretation axis — never by instrument or form name.
Instrument forms (e.g. WIDA grade clusters) are measurement facts and live in the
extension blocks (`measurement.elp.grade_clusters`). For `fixed` systems the two axes
coincide; for `variable` systems they need not (WIDA: cluster-form K-2, but cuts resolve
per enrolled grade K, 1, 2). For grade-invariant scores (ACT), a cut may be recorded once
per enrolled grade with identical values — explicit beats implicit.

This supersedes the bare `content_areas[].grades` field named in [[schema-crosswalk]] §F
and ADR-008 §5.

### D2 — Scale bounds mirror cutscore keying

New optional top-level `scale_bounds`, exactly parallel to `cutscores`:

```json
"scale_bounds": {
  "MATHEMATICS": { "8": { "loss": 400, "hoss": 590, "source": "official" } }
}
```

`content_area → enrolled grade → {loss, hoss, source?}`. Per-grade because ILEARN-style
scales differ by grade; uniform scales (WIDA composite) simply repeat values. `source` is
the per-value confidence enum `official | derived | provisional` (ADR-008 §5), also
permitted on individual cutscore entries via a parallel optional
`cutscores_source[content_area][grade]` note — *exact mechanism to be settled during
schema authoring; the invariant is that per-value confidence exists somewhere adjacent to
the values.*

**New invariants:** `loss ≤ min(cuts) ≤ max(cuts) ≤ hoss` where both present;
`enrolled_grades_tested ⊇ keys(cutscores[ca]) ∪ keys(scale_bounds[ca])`.

### D3 — Assessment-type discriminator + conditional extensions

`assessment_system.assessment_type` becomes the canonical enum
(`summative | alternate | elp | science | end-of-course`) with legacy strings
(`english-language-proficiency`, `state-summative`) accepted as aliases during migration
and normalized by the migrator. Conditional blocks per [[metadata-taxonomy]]:

- `assessment_type: elp` permits `measurement.elp` (instrument, domains, composites,
  composite_weights, grade_clusters, band_scheme).
- `assessment_type: alternate` permits `measurement.alternate` (instrument,
  achievement_standard, scoring_model, linkage_levels, equating_notes).

### D4 — Governance additions (D5 domain)

- `source_documents[]` — list of `{title, url}` (url nullable), alongside the existing
  single `provenance.source_citation` (which remains, as the primary citation).
- Colleague verification-state map applied at migration
  (`unverified→draft`, `auto_derived→draft+low`, `in_review→reviewed`,
  `human_verified→verified`) — relevant when his WIDA/alternate specs are ingested.

### D5 — Accountability v2 additions

`amr.accountability.v2` adds optional `growth_targets`, `timelines`, and `participation`
blocks per the crosswalk reclassifications (colleague `elp$growth_targets`,
`elp$timelines`, `alternate$participation_criteria`/`federal_cap`). `targets[]` is
unchanged — the SGPc re-merge contract ([[sgpc-registry-consumption-contract]]) is
untouched.

### D6 — Migration policy: dual-version window, whole-corpus flip

- Validator accepts `amr.*.v1`, `amr.*.v2`, and the legacy `sgpc.assessment_metadata.v0.1`
  alias throughout the window.
- `amrr::migrate_registry(".", to = "v2")` restamps and restructures mechanically. New
  fields it cannot derive are **left absent** (they are optional except `enrollment`,
  which the migrator populates from cutscore keys with `intended_enrollment_grade` set
  per-system — WIDA `variable`, ILEARN/demo summatives `fixed`); migration never invents
  facts.
- The whole 24-record corpus migrates in **one reviewed commit**; thereafter the validator
  **warns** on newly authored v1 records.
- v2 is additive over the SGPc projection subset: `get_metadata()` output for existing
  callers is shape-compatible; build-output parity is a phase gate (21 targets, 117 exit
  thresholds, WIDA g5/2024 = 364.4 unchanged).

### D7 — Dogfood-first delivery: WIDA_IN is the riff corpus

A concrete v2 exemplar, `schemas/examples/wida-access-in-2024.v2.example.json`, is the
design artifact to critique **before** JSON Schema authoring hardens anything. Phases
(each gated on `make all` green + wiki update):

| Phase | Deliverable | Verification |
|-------|-------------|--------------|
| **B** | v2 JSON Schemas + extended invariants | v1 corpus still validates; v2 fixtures pass; negative test per new invariant |
| **C** | `migrate_registry()` + corpus migration | 24/24 validate as v2; build parity on SGPc subset |
| **D** | `amrr` v2 accessors (`amrr_enrollment()`, `amrr_scale_bounds()`, `amrr_elp()`, `amrr_alternate()`, `amrr_growth_targets()`, `amrr_timelines()`, `amrr_participation()`) | testthat present/absent/wrong-type cases; `make check` |
| **E** | Build + site v2-aware (index, DDL additions, spec/Display views) | `make site`; CI green; JSON URLs unchanged |
| **F** | `amrr_materialize()` → SHA-stamped `.rda` + colleague demo | round-trip test; walkthrough |
| **G** | SGPc `registry` resolver source (cross-repo) | SGPc-side; consumes stable v2 |

WIDA_IN records get first-pass real authoring (clusters, composites, bounds) during
Phase C — the dogfood loop that stress-tests D1–D4 against a genuinely awkward system
(grade-span forms, composite scores, K grade, policy exit thresholds next door in the
accountability record).

## Alternatives considered

| Alternative | Why not chosen |
|-------------|----------------|
| Three-value enum `grade-level \| grade-span \| grade-variable` | Richer, but the span-ness of forms is already carried by `measurement.elp.grade_clusters` (and analogous extension facts); the binary `fixed|variable` + `note` matches the decider's framing and avoids classifying edge cases twice. **Rejected at sign-off (2026-07-06):** educational-assessment terminology is murky — "grade-span" would not be applied to ACT even though ACT is used across enrolled grades, so a canonical three-way label would misclassify or invite argument; the binary captures the structural fact (instrument targets one enrolled grade or not) and leaves murky vocabulary to `note`. Revisit only if a system's forms become inexpressible. |
| Bare `content_areas[].grades` (crosswalk §F original) | Conflates instrument grade, enrolled grade, and cut keys — the motivating defect |
| `scale_bounds` inline per content area (single loss/hoss) | Fails ILEARN-style per-grade scales; per-grade keying mirrors `cutscores` and the colleague's `<SUBJECT>_<GRADE>` structure |
| Big-bang v2 (drop v1 immediately) | Breaks the SGPc alias contract and the nine seeded systems mid-window |
| Author v2 records by hand, no migrator | 24 records now, more later; mechanical restamp belongs in tooling with tests |

## Consequences

- **Positive:** the instrument/enrolled-grade/cut-key conflation is resolved structurally;
  ACT-like and grade-span systems are expressible without contortion.
- **Positive:** colleague's per-`<SUBJECT>_<GRADE>` loss/hoss/cuts structure has an exact
  canonical home (`scale_bounds` + `cutscores`, enrolled-grade keyed).
- **Neutral:** `enrollment` is required in v2 — one more authored block, but the migrator
  seeds it and the validator catches omissions.
- **Risk:** `fixed|variable` may prove too coarse (see alternatives revisit trigger).
- **Risk:** dual-version window drift — mitigated by whole-corpus migration + v1-authorship
  warning (D6).

## Related

- [[008-unified-metadata-taxonomy]] — accepted parent decision
- [[metadata-taxonomy]] · [[schema-crosswalk]] · [[colleague-assessment-spec-r]]
- [[sgpc-registry-consumption-contract]] — the untouched Tier C contract
- `schemas/examples/wida-access-in-2024.v2.example.json` — the dogfood exemplar
