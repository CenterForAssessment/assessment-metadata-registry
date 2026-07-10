---
title: "Grade Encoding Split — `K` and `0` Both Mean Kindergarten"
type: analysis
created: 2026-07-10
updated: 2026-07-10
status: active
curated: true
sources:
  - schemas/amr.assessment.v2.schema.json
  - metadata/IN/wida-access/wida-access-in-2024.json
  - metadata/IN/in-accountability/in-accountability-2024.json
  - SGPc-rpkg/SGPc/inst/examples/wida-in-sgpc-analysis-spec.json
  - wiki/connections/sgpc-registry-consumption-contract.md
tags: [grades, encoding, schema, sgpc, consumption, drift]
---

# Grade Encoding Split — `K` and `0` Both Mean Kindergarten

One-line summary: the assessment schema's grade pattern admits **both** `"K"` and `"0"`, and
the registry uses one while its own accountability records — and its first consumer — use the
other. Filed, not fixed.

## The observation

`amr.assessment.v2` constrains enrolled-grade tokens with:

```json
"enrolled_grades_tested": { "items": { "type": "string", "pattern": "^(PK|K|[0-9]{1,2})$" } }
```

`"K"` matches the literal alternative. `"0"` matches `[0-9]{1,2}`. **Both validate.** The
schema names `PK` and `K` explicitly, which reads as intent that kindergarten be spelled `K` —
but it never forecloses `0`, and nothing downstream enforces a choice.

Three places in the current corpus disagree:

| Where | Token for kindergarten | Authored by |
|---|---|---|
| `metadata/IN/wida-access/*.json` → `enrollment.enrolled_grades_tested` | `"K"` | this repo (2026-07-10 authoring pass) |
| `metadata/IN/in-accountability/*.json` → `targets[].per_grade_scale_score` | `"0"` | this repo (migration, 2026-07-02) |
| `SGPc` analysis spec `grade_sequence`, and its LONG data `GRADE` column | `"0"` | SGPc |

So a single record family spells kindergarten two ways, and the consumer spells it a third
time the same way as the accountability half.

## Why no validator caught it

The **axis rule** (`.v2_assessment_invariants`) requires that grade keys on `cutscores`,
`scale_bounds`, and `cutscores_source` be members of that content area's
`enrolled_grades_tested`. It is real — introducing `cutscores.READING["13"]` against
`enrolled_grades_tested: ["K","1",…,"12"]` fails validation with
`grade key(s) not in enrollment.enrolled_grades_tested: 13`.

But it constrains **only those three blocks**. It says nothing about
`accountability_target_scale_score.grade`, whose keys come from
`targets[].per_grade_scale_score`. `.accountability_invariants` cross-links a target to a real
assessment record and checks its `content_area` — never its grades. So `"0"` and `"K"` coexist
today without a single error.

The gap was invisible until now for a duller reason: WIDA's `enrolled_grades_tested` was `[]`,
so the axis rule had nothing to check against.

## What it costs

Nothing yet, and something soon.

- **Today**: nothing joins on grade. `find_metadata_cell()` in SGPc keys on
  jurisdiction × system × year. `enrolled_grades_tested` is informational.
- **The moment WIDA cut scores are authored**: they must be keyed by enrolled grade. If they
  are keyed `"K"` (to satisfy the axis rule against `enrolled_grades_tested`) while
  `per_grade_scale_score` keys `"0"`, then a consumer resolving *both* a cut score and an exit
  threshold for the same kindergartener does two lookups with two different keys. One of them
  silently returns `NULL`.

`resolve_achievement_target()` (`SGPc-rpkg/SGPc/R/proficiency.R:372`) reads
`block$per_grade_scale_score[[as.character(grade)]]` and returns `NULL` on a miss. Not an
error. That is the shape of the future bug.

## Options, none taken here

1. **Canonicalize on `"K"`** in the assessment records and rewrite the 9+ accountability
   records' `per_grade_scale_score` keys. Self-describing; touches authored policy data in
   another record family.
2. **Canonicalize on `"0"`** everywhere. Aligns the registry with SGPc and with its own
   accountability half; makes `enrolled_grades_tested` read `["0","1",…]`, which is opaque, and
   leaves the schema's `K`/`PK` alternatives dead.
3. **Tighten the schema** to permit exactly one spelling, and add an invariant covering
   `per_grade_scale_score` grade keys. Correct, and a breaking change to a validated corpus.
4. **Normalize at the consumer boundary** — SGPc's registry translator maps `"K" → "0"` on the
   way in. This is what the SGPc bridge does today (`normalize_enrolled_grade()`), and it is a
   *mitigation*, not a decision: it leaves the registry internally inconsistent and pushes the
   reconciliation onto every future consumer.

## Recommendation

Option 3, as an ADR, once someone decides which spelling wins. Until then the registry is
internally inconsistent in a way that validates cleanly, and that fact should be visible rather
than absorbed by a translator nobody reads.

Per the hub rule — *file an analysis, never silently reconcile* — no data was changed to paper
over this.

## Related Pages

- [[sgpc-registry-consumption-contract]] — the consumer that meets both spellings
- [[schema-crosswalk]] — the field-level mapping that did not surface this, because it compared
  field *names*, not value vocabularies
- [[metadata-taxonomy]] — where a grade-token vocabulary would belong
