---
title: "ADR-013: National and international sample assessments (NAEP, TIMSS, TIMSS-L)"
type: decision
created: 2026-08-30
updated: 2026-08-30
status: accepted
deciders: Damian Betebenner
curated: true
scope:
  - assessment-metadata-registry
  - SGPc-rpkg (consumer, ADR-017/018)
  - SGPc-foundry (NAEP/TIMSS trees)
sources:
  - wiki/decisions/000-registry-architecture.md
  - wiki/decisions/008-unified-metadata-taxonomy.md
  - wiki/decisions/009-v2-implementation.md
  - schemas/amr.assessment.v2.schema.json
  - r-pkg/amrr/R/accessors.R
  - r-pkg/amrr/R/validate.R
  - wiki/connections/sgpc-registry-consumption-contract.md
  - SGPc-rpkg/SGPc/wiki/decisions/017-growth-regime-inference-mode.md
  - SGPc-rpkg/SGPc/wiki/decisions/018-store-v02-marginals-weights-plausible-values.md
  - SGPc-wiki/docs/plans/2026-08-30-00-program-map.md
  - SGPc-wiki/docs/plans/2026-08-30-pa-cross-sectional.md
tags: [schema, v2, naep, timss, sampling-design, plausible-values, international, additive]
---

# ADR-013: National and international sample assessments

**Status:** Accepted — ratified 2026-08-30 by the maintainer (Damian Betebenner), under the planner review `SGPc-wiki/docs/plans/reviews/2026-08-30-pa-contracts-review.md` (B3/B4 applied). Implementation (schema delta, `amrr_design()`, the six validator invariants, two example records) is SGPc P-A task A1.3 / A3.4; until it lands, `amr.assessment.v2` on `main` is unchanged.

The registry learns to describe an assessment that is *sampled*, not administered
to every student, and one that is *international*, not a state's. `amr.assessment.v2`
is widened **additively** — three `jurisdiction.type` values, two `assessment_type`
values, and one optional `design` block — with no `vN` bump, which is what
`AGENTS.md`'s schema-change rule reserves the bump for ("bump the `amr.*.vN` string
only for breaking shape changes"). The unit of record does not move: one sidecar still
describes one `jurisdiction × system × year`, and NAEP or a TIMSS cycle is described
**once**. The states and countries that sit beneath
them are carried by SGPc's store (engine ADR-018), never by the registry.

## Context

SGPc's cross-sectional program (P-A) ingests three deliveries the registry cannot
name today (program map §1, item 4):

- **NAEP** — a U.S. national sample assessment, mathematics, grade 4 (2015) and
  grade 8 (2019), reported as 20 plausible values per student with a full-sample
  weight and 62 jackknife replicate weights; the delivery to SGPc is state-level
  weighted marginal quantile arrays. `jurisdiction.type` has no value for a nation
  and `assessment_type` has no value for a sample design.
- **TIMSS** — an international sample assessment, grades 4 and 8, one cycle per
  delivery, five plausible values, `TOTWGT`, and a JK2 design (`JKZONE`/`JKREP`,
  75 zones). There is no `international` jurisdiction, and no way to say which
  countries participated in a cycle, or that the cycle is what the file describes.
- **TIMSS-L** — a longitudinal follow-up whose waves are linked across years. The
  registry cannot point one administration at another.

What the engine needs from the registry is exactly what a human confirms in Step 0
and nothing an ingest could discover on its own: the sampling design's *semantics*
(how many draws, which weight is the full-sample weight, how replicates are formed),
the achievement levels the marginal is read against, and — for TIMSS-L — which
administration the record is linked to. Everything about *which students* is a
store fact.

## Decision

### D1 — Jurisdiction types and assessment types

Two enums widen; nothing is removed:

```jsonc
"jurisdiction": { "type": { "enum": ["state", "territory", "consortium", "district",
                                      "nation", "international", "benchmarking-entity", "other"] } }
"assessment_system": { "assessment_type": { "enum": ["summative", "alternate", "elp", "science",
                                                      "end-of-course", "national-sample", "international-sample"] } }
```

`nation` is the United States as NAEP's frame (`id: "US"`); `international` is the
IEA frame for a TIMSS cycle (`id: "INTL"`); `benchmarking-entity` is reserved for a
sub-national participant that appears in a TIMSS cycle as its own reporting unit
(e.g. a Canadian province or a U.S. state taking TIMSS off-cycle) *when* it carries an
administration of its own — a benchmarking-only cycle, or a longitudinal follow-up
whose frame is that entity, which is what TIMSS-L may turn out to be (A0.2 decides).
Otherwise it is a store sub-jurisdiction like any other; no record is drafted for it
here.

The two new types are not the design restated. `national-sample` and
`international-sample` gate *consumption semantics*: there is no student-level score
column to read — a score is a set of plausible values, and a marginal is weighted —
so a consumer that reads `assessment_type` knows to route through `design` before
touching a value, and the `measurement.elp` / `measurement.alternate` extension
blocks are excluded for them. `design` says *how* the sample is scored and weighted;
the type says *that* it is.

### D2 — The `design` block (optional, top-level)

One optional block carries the sampling-design semantics the engine reads and an
ingest cannot discover:

```jsonc
"design": {
  "student_sampling": "multistage",                      // census | multistage
  "scoring_model": "scale",                              // scale | profile (default scale)
  "plausible_values": { "count": 20, "variable_prefix": "MRPCM" },   // variable_prefix: a string, or a map keyed by CONTENT AREA then ENROLLED grade
  "weights": {
    "full_sample_variable": "ORIGWT",
    "replicate": { "method": "JK1",                      // JK1 | JK2 | BRR
                   "zones": 62, "replicates": 62,        // required under every method
                   "variance_factor": 1,                 // the multiplier on the sum of squared replicate deviations (NAEP 1; TIMSS 2003-2011 1; TIMSS 2015+ 0.5)
                   "variable_prefix": "SRWT" }           // JK1/BRR: the replicate-weight prefix; JK2: zone_variable + rep_variable instead
  },
  "cycle_years": ["2015"],                               // the calendar years the cycle was administered in; must include administration.year
  "longitudinal_link": { "linked_administration_id": "timss-intl-2023", "span_years": 1, "cohort_label": "TIMSS 2023 G4/G8 -> 2024 G5/G9" },
  "notes": "…"                                           // booklet/matrix design and other facts the engine does not consume
}
```

`student_sampling` names the axis the engine consumes — whether the marginal is a
census or a weighted sample — and nothing else; matrix (booklet) sampling is an
item-design fact that belongs in `notes`, since NAEP and TIMSS are both multistage
*and* matrix and an enum that conflates the two cannot be answered for either.
`cycle_years` exists because a TIMSS cycle can be administered across two calendar
years (southern-hemisphere systems test in the preceding autumn); when it is a single
year it repeats `administration.year` and the validator requires the two to agree.
The replicate block carries the *variance rule*, not just a count, because the rule
changed within one assessment's history: TIMSS 2003–2011 used 75 zones and 75
replicates with factor 1; TIMSS 2015 onward doubles both halves of each zone in turn
— 150 replicates, factor 0.5. The engine reads `variance_factor` (SGPc ADR-017 §5);
the operator verifies each cycle's rule against its user guide in Step 0. The PV prefix
is keyed by content area then grade because the TIMSS deliveries carry science
(`ASSSCI`/`BSSSCI`) beside mathematics; the plain string stays valid for NAEP.

`design` is a measurement fact in the ADR-009 sense — it describes the instrument's
data, not a policy — but it is placed top-level rather than under `measurement`
because it is orthogonal to `assessment_type`: a state census file has a (trivial)
design too, and a future state assessment reported with plausible values would use
the same block without becoming a "sample" assessment.

### D3 — Validator invariants (in `amrr`, not the schema)

1. `assessment_type = international-sample` ⇒ `jurisdiction.type ∈ {international, benchmarking-entity}`.
2. `assessment_type = national-sample` ⇒ `jurisdiction.type = nation`.
3. `design.plausible_values.count ≥ 1` ⇒ `design.scoring_model = "scale"`, and where
   `measurement.alternate.scoring_model` is also present the two must agree (the
   invariant exists so a profile-scored instrument cannot silently claim draws on a
   scale).
4. `design.weights.replicate.{zones, replicates, variance_factor}` are required under
   every method, with `replicates ∈ {zones, 2 × zones}` and `variance_factor ∈ {1, 0.5}`
   matching (`replicates = zones ⇒ 1`; `replicates = 2 × zones ⇒ 0.5`); `JK2` ⇒
   `zone_variable` and `rep_variable` present and `variable_prefix` absent; `JK1` or
   `BRR` ⇒ `variable_prefix` present.
5. `design.cycle_years`, when present, includes `administration.year`.
6. `design.longitudinal_link`, when present, names an administration in the corpus in
   `linked_administration_id` (an identity-conflict-class error if it does not) and
   carries `span_years ≥ 1`.

### D4 — Accessors and the consumption contract

`amrr_design(x)` returns the block (or `NULL`), following the shape of
`amrr_elp()`/`amrr_alternate()`. SGPc's resolver reads it to fill
`snapshot.design_json` at ingest (engine ADR-018 §1) and to choose the within-PV
variance method at run time (engine ADR-017 §5). The consumption contract page gains
a paragraph naming `amrr_design()`; `amrr` also gains the six D3 invariants in
`validate.R`, and nothing else.

### D5 — What is *not* in the registry

- **Sub-jurisdictions.** `US/naep/naep-us-2015.json` describes NAEP once; the 52 NAEP
  reporting jurisdictions in the delivery (states plus DC and DoDEA — the count is a
  delivery fact, see the intake manifest) are `jurisdiction` rows in SGPc's store
  with `parent_jurisdiction_id = "US"`.
  `INTL/timss/timss-intl-2019.json` describes the cycle once; participating
  countries come from the delivery's `IDCNTRY` value labels into the store. A
  registry that listed them would duplicate a store fact and go stale with every
  cycle.
- **Sample sizes, replicate counts per state, `n_eff`.** Those are properties of a
  delivery and live in the intake manifest and `snapshot.design_json`.
- **Kernel or copula policy.** Consumer logic; excluded by ADR-000 D1.

### D6 — Two draft records (the shape, not the truth)

Cut scores below are the public NAEP achievement-level cuts and the TIMSS
international benchmarks as the planner recalls them; they are entered
`status: draft`, `source_confidence: low`, `cutscores_source: provisional`, and a
human verifies them against NCES and IEA before promotion (Step 0; program map §5).

`metadata/US/naep/naep-us-2015.json`

```jsonc
{
  "schema_version": "amr.assessment.v2",
  "status": "draft",
  "source_confidence": "low",
  "provenance": { "entered_by": "ai:sgpc-pa-planner", "entered_at": "2026-08-30",
                  "source_citation": "https://nces.ed.gov/nationsreportcard/mathematics/achieve.aspx",
                  "last_verified_at": null, "verified_by": null, "changed_from_prior": null },
  "jurisdiction": { "id": "US", "name": "United States", "type": "nation" },
  "assessment_system": { "id": "naep", "name": "National Assessment of Educational Progress",
                         "family": "NAEP", "assessment_type": "national-sample" },
  "administration": { "id": "naep-us-2015", "year": "2015", "vendor": "National Center for Education Statistics", "window": "annual" },
  "design": { "student_sampling": "multistage", "scoring_model": "scale",
              "plausible_values": { "count": 20, "variable_prefix": "MRPCM" },
              "weights": { "full_sample_variable": "ORIGWT",
                           "replicate": { "method": "JK1", "zones": 62, "replicates": 62, "variance_factor": 1, "variable_prefix": "SRWT" } },
              "cycle_years": ["2015"],
              "notes": "Matrix (booklet) item sampling. Delivered to SGPc as jurisdiction-level weighted marginal quantile arrays with the national-equivalent percentile; see the intake manifest." },
  "content_areas": [ { "id": "MATHEMATICS", "label": "Mathematics", "vertical_scale": false, "scale_name": "NAEP mathematics scale (0-500)",
                       "enrollment": { "intended_enrollment_grade": "fixed", "enrolled_grades_tested": ["4", "8"],
                                       "note": "NAEP 2015 also assessed grade 12; not in the SGPc delivery." } } ],
  "achievement_levels": { "MATHEMATICS": { "labels": ["Below Basic", "Basic", "Proficient", "Advanced"], "proficient_from": "Proficient" } },
  "cutscores": { "MATHEMATICS": { "4": [214, 249, 282], "8": [262, 299, 333] } },
  "cutscores_source": { "MATHEMATICS": { "4": "provisional", "8": "provisional" } },
  "cutscores_provenance": "PROVISIONAL -- NAEP mathematics achievement-level cut scores as recalled by the planner; verify against NCES before promotion."
}
```

`metadata/INTL/timss/timss-intl-2019.json`

```jsonc
{
  "schema_version": "amr.assessment.v2",
  "status": "draft",
  "source_confidence": "low",
  "provenance": { "entered_by": "ai:sgpc-pa-planner", "entered_at": "2026-08-30",
                  "source_citation": "https://timss2019.org/international-results/",
                  "last_verified_at": null, "verified_by": null, "changed_from_prior": null },
  "jurisdiction": { "id": "INTL", "name": "International (IEA participating systems)", "type": "international" },
  "assessment_system": { "id": "timss", "name": "Trends in International Mathematics and Science Study",
                         "family": "TIMSS", "assessment_type": "international-sample" },
  "administration": { "id": "timss-intl-2019", "year": "2019", "vendor": "IEA / TIMSS & PIRLS International Study Center", "window": "cycle" },
  "design": { "student_sampling": "multistage", "scoring_model": "scale",
              "plausible_values": { "count": 5, "variable_prefix": { "MATHEMATICS": { "4": "ASMMAT", "8": "BSMMAT" }, "SCIENCE": { "4": "ASSSCI", "8": "BSSSCI" } } },
              "weights": { "full_sample_variable": "TOTWGT",
                           "replicate": { "method": "JK2", "zones": 75, "replicates": 150, "variance_factor": 0.5, "zone_variable": "JKZONE", "rep_variable": "JKREP" } },
              "cycle_years": ["2018", "2019"],
              "notes": "Matrix (booklet) item sampling; southern-hemisphere systems tested in late 2018. One sidecar per cycle; participating countries are store sub-jurisdictions from IDCNTRY." },
  "content_areas": [ { "id": "MATHEMATICS", "label": "Mathematics", "vertical_scale": false, "scale_name": "TIMSS mathematics scale (centerpoint 500, SD 100)",
                       "enrollment": { "intended_enrollment_grade": "fixed", "enrolled_grades_tested": ["4", "8"] } },
                     { "id": "SCIENCE", "label": "Science", "vertical_scale": false, "scale_name": "TIMSS science scale (centerpoint 500, SD 100)",
                       "enrollment": { "intended_enrollment_grade": "fixed", "enrolled_grades_tested": ["4", "8"] } } ],
  "achievement_levels": { "MATHEMATICS": { "labels": ["Below Low", "Low", "Intermediate", "High", "Advanced"], "proficient_from": "Intermediate",
                          "notes": "proficient_from is a placeholder choice for SGPc's margins layer, not an IEA designation." } },
  "cutscores": { "MATHEMATICS": { "4": [400, 475, 550, 625], "8": [400, 475, 550, 625] },
                 "SCIENCE":     { "4": [400, 475, 550, 625], "8": [400, 475, 550, 625] } },
  "cutscores_source": { "MATHEMATICS": { "4": "provisional", "8": "provisional" }, "SCIENCE": { "4": "provisional", "8": "provisional" } },
  "cutscores_provenance": "TIMSS international benchmarks (Low 400, Intermediate 475, High 550, Advanced 625); verify the cycle's benchmark definitions before promotion."
}
```

One TIMSS record per cycle in the delivery — 2003, 2007, 2011, 2015, 2019, 2023 —
each with its own replicate rule; TIMSS Numeracy 2015 (`TN15_*` in the delivery) is a
separate `assessment_system` (`timss-numeracy`) if A0.2 puts it in scope.

The TIMSS-L delivery's shape is now known from its manifest: a one-year follow-up of
TIMSS 2023 (grade 4 → 5, grade 8 → 9, tested 2024). It is two administrations — the
2023 base, which *is* the TIMSS 2023 record above, and a follow-up record
`INTL/timss-l/timss-l-intl-2024.json` whose `design` carries
`"longitudinal_link": { "linked_administration_id": "timss-intl-2023", "span_years": 1, "cohort_label": "TIMSS 2023 G4/G8 -> 2024 G5/G9" }`.
Its PV names and the weight that applies to the linked sample are still A0.2 unknowns
(the `Data_R_*.zip` archives were hashed, not opened), so the record is drafted after
the operator answers them.

## Alternatives considered

**A `vN` bump (`amr.assessment.v3`).** Rejected: every change is additive — no
existing sidecar becomes invalid, no key moves — so it is not the breaking shape
change `AGENTS.md` reserves the bump for. A bump would force the migration machinery and the
SGPc alias table for nothing.

**Sub-jurisdictions in the registry** (`sub_jurisdictions[]` on the NAEP record).
Rejected: it duplicates a store fact, goes stale per cycle for TIMSS, and invites
per-state achievement facts that NAEP does not have (the cuts are national).

**A `measurement.sample` extension block instead of top-level `design`.** Rejected:
`measurement.*` blocks are gated on `assessment_type`, and a design is not a type
property — a state summative reported with plausible values should be describable
without re-typing it.

**Registry records per grade** (`timss-intl-2019-g4`). Rejected: the unit of record
is `jurisdiction × system × year` (ADR-000 D2); grade is a content-area enrollment
fact. The *foundry* context may still key administrations per grade for its own
spec generation; that is a store/context identifier, not a registry one.

## Consequences

- Implemented by P-A task A3.5's sibling in the registry (Grok 4.6): the schema
  delta, `amrr_design()`, the six validator invariants, two examples under
  `schemas/examples/`, `make validate && make test` green, the site catalog
  rendering the new records.
- The two draft records above are filed by the `metadata-author` agent as
  `status: draft`; a human promotes them (A3.4). Until then the foundry's
  `metadata/` sidecars are hand-kept projections and say so in `provenance`.
- The consumption contract page gains `amrr_design()`; SGPc's resolver (Phase G,
  A3.5) stamps `registry_ref` and `registry_schema_version` as before.
- What this ADR does not decide: which TIMSS cycles are in scope, which weight
  applies to the TIMSS-L linked sample, or the TIMSS-L cohort semantics — those are
  the operator's Step 0 answers after the intake manifest (A0.2), and the
  `longitudinal_link` block is shaped to receive them.

## Related pages

- [[000-registry-architecture]]
- [[008-unified-metadata-taxonomy]]
- [[009-v2-implementation]]
- [[sgpc-registry-consumption-contract]]
