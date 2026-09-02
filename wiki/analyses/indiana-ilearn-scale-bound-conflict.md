---
title: "Two sources disagree on two ILEARN scale bounds"
type: analysis
created: 2026-09-02
updated: 2026-09-02
status: open
curated: true
scope:
  - assessment-metadata-registry
  - SGPc-rpkg (consumer)
sources:
  - metadata/IN/ilearn/ilearn-in-{2019,2021,2022,2023,2024,2025}.json
  - SGP::SGPstateData[["IN"]][["Achievement"]][["Knots_Boundaries"]] (maintainer paste 2026-09-02)
  - wiki/sources/sgpstatedata-operational-provenance.md
tags: [indiana, ilearn, scale-bounds, conflict, filed-not-fixed]
---

Two cells of the ILEARN scale envelope disagree between the IDOE cut-score PDF the records
cite and `SGPstateData`'s operational `loss.hoss`. Both sources are ones this registry
treats as authoritative, so the disagreement is filed rather than reconciled.

## The disagreement

Across all six ILEARN records on the 2019 scale (2019, 2021–2025) — the same two cells,
identically, in every year:

| Cell | Record (`source: official`) | `SGPstateData` `loss.hoss` |
|---|---|---|
| ELA grade 6 HOSS | **5870** | **5865** |
| MATHEMATICS grade 3 LOSS | **6080** | **6104** |

Every other cell in every ILEARN year matches exactly (ELA 3–8 and 10, MATHEMATICS 3–8
and 10 — 24 further cells per year), which is what makes these two worth a page: this is
not two sources built independently, it is one source with two cells that drifted.

The record cites "IDOE ILEARN Cut Scores PDF (updated 2019-08-26)". The `SGPstateData`
values are the bounds used operationally in Indiana's production SGP analyses, which
`sgpstatedata-operational-provenance` records as authoritative for cut scores.

## Why it is not obvious which wins

The 2026-09-02 attestation makes `SGPstateData` authoritative *where the agency
documentation is no longer retrievable*. Here it is retrievable and cited — so the
attestation does not settle it, and neither value can be dismissed as a transcription
slip:

- **ELA grade 6.** The published HOSS series runs 5760, 5810, 5850, **?**, 5890, 5920. Both
  5865 and 5870 sit inside that progression; neither breaks it.
- **MATHEMATICS grade 3.** The LOSS series runs **?**, 6100, 6110, 6110, 6120, 6120. Here
  6080 is monotone with the rest and 6104 is not — grade 3's LOSS would exceed grade 4's.
  That is weak evidence for the record's 6080, and it is weak because a lowest-obtainable
  score is a property of each grade's form, not of a monotone sequence. `SGPstateData`'s
  own `boundaries_3` for mathematics is 6041.4, below both candidates, so the spline
  boundary does not adjudicate either.

## What is at stake

Very little for growth, and something real for reporting. SGPc's copula methods are
rank-based, so a 5-point HOSS or a 24-point LOSS shift does not move a percentile.
`scale_bounds` is consumed by the proficiency (margins) layer — the cut/scale/percentile
crosswalk of engine ADR-014 — and by any report that describes the scale's range. A
24-point LOSS error at mathematics grade 3 would misstate the floor of the reported scale
in every Indiana ILEARN year.

## Resolution path

The maintainer decides, one of three ways: read the cited IDOE PDF and let it stand;
correct `SGPstateData` upstream and re-derive these records from it; or record that the
two serve different purposes (published scale range vs analysis bound) and keep both, with
the record's `notes` naming which is which. Until then the records keep their cited PDF
values, unchanged, and this page is the reason the mismatch is not a silent one.

Filed, not fixed — the house rule for a contradiction between two sources of record.

## Related pages

- [[sgpstatedata-operational-provenance]] — the attestation this case sits at the edge of
- [[grade-encoding-split]] — the registry's other filed-not-fixed finding
- [[009-v2-implementation]] — `scale_bounds` keying and the loss ≤ cuts ≤ hoss invariant
