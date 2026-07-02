---
title: "ADR-002: Accountability System Record + Achievement-Target Relocation"
type: decision
created: 2026-07-02
updated: 2026-07-02
status: accepted
deciders: Damian Betebenner
curated: true
sources:
  - schemas/amr.accountability_system.v1.schema.json
  - schemas/amr.assessment_system.v1.schema.json
  - tools/split_accountability.py
  - SGPc-rpkg/SGPc/wiki/decisions/015-achievement-target-criterion-referenced.md
  - wiki/decisions/000-registry-architecture.md
tags: [accountability, achievement-target, exit, cross-link, what-goes-where]
---

# ADR-002: Accountability System Record + Achievement-Target Relocation

**Status:** Accepted
**Date:** 2026-07-02

## Context

ADR-000 (D4) reserved a separate, cross-linked accountability record type. The first
concrete case that forced the boundary: the **WIDA-ACCESS ELP exit target**. In the SGPc
sidecars the exit target lived in the assessment record's `achievement_targets` block —
placed there because SGPc needed it downstream, not because it belongs to the assessment.

An achievement target is the **policy goal a score is measured against**. SGPc ADR-015
already says so explicitly: "the target is a property of *state policy*, year-resolved."
A student with WIDA Overall 4.3 exits in a state whose target is 4.2 but not one whose
target is 5.0 — same assessment, different accountability policy. The assessment system
(WIDA / the vendor / standard-setting) defines the scale, the six proficiency levels, and
the cutscores; the **state accountability system** decides the exit threshold.

## Decision

**1. New record type `amr.accountability_system.v1`.** Keyed
`jurisdiction × accountability_system × year`; a state-wide object that *uses* one or more
assessment systems. v1 carries a `targets[]` array (extensible later with participation
rules, N-size, indicator weights). Each target **cross-links** an `assessment_system_id`
+ `content_area` and declares `semantics` (`exit` | `proficiency`) and `basis`
(`proficiency_boundary` | `scale_score` | `level`). `scale_score` targets carry explicit
`per_grade_scale_score`; `proficiency_boundary` targets resolve against the linked
assessment's cutscores + `proficient` mask at consumption time.

**2. Relocate all `achievement_targets` out of the assessment schema.** `tools/split_accountability.py`
extracts them from the 15 assessment sidecars into 9 per-year accountability records
(one per `jurisdiction × year`, aggregating targets across assessments) and strips them
from the assessment sidecars. `achievement_targets` is removed from
`amr.assessment_system.v1`.

**3. Cross-link integrity is a build gate.** `tools/validate.py` verifies every target's
`(assessment_system_id, content_area, year)` resolves to an existing assessment record
declaring that content area. A dangling target fails the build.

**4. Consumption re-merges (Phase 3).** Authoring is *separated* (correct), but
`amrr::get_metadata(..., attach_targets = TRUE)` will merge resolved targets back onto the
assessment record under `achievement_targets` — the shape SGPc already expects — so SGPc
consumes the correct model without a structural rewrite. `proficiency_boundary` targets
are resolved to per-grade scale scores from the assessment cutscores at merge time.

## What goes where (the general rule this establishes)

| Belongs to the **assessment system** | Belongs to the **accountability system** |
|---|---|
| Scales, content areas, vertical-scale flags | Achievement targets (exit, accountability proficiency) |
| Achievement levels + labels + `proficient` mask | Participation rules, N-size (future) |
| Cutscores (scale-score level boundaries) | Indicator weights, business rules (future) |
| Vendor, administration window | Which assessments feed accountability (the cross-links) |

Heuristic: if a fact comes from **standard-setting / the vendor**, it is the assessment.
If it is a **state decision about how to use** scores, it is accountability.

## Consequences

- The registry now models two record types; tooling routes by `schema_version`.
- SGPc's consumption contract changes: targets come from accountability, re-merged by the
  R package. SGPc methodology is unaffected (it still sees `achievement_targets`).
- The changelog gains a `target` field so a state re-choosing its exit cut (WIDA's July
  2026 scale reset will force this) is an explicit, queryable event.
- Seed accountability records are `status: draft` (exit targets preliminary) pending review.

## Related

- [[000-registry-architecture]] · [[001-assessment-system-schema]]
- [[derivation-pipeline]]
- SGPc: [[instantiation:SGPc-rpkg/SGPc/wiki/decisions/015-achievement-target-criterion-referenced]]
