---
title: "Two sources disagree on two ILEARN scale bounds"
type: analysis
created: 2026-09-02
updated: 2026-09-02
status: resolved
curated: true
scope:
  - assessment-metadata-registry
  - SGPc-rpkg (consumer)
sources:
  - metadata/IN/ilearn/ilearn-in-{2019,2021,2022,2023,2024,2025}.json
  - SGP::SGPstateData[["IN"]][["Achievement"]][["Knots_Boundaries"]] (maintainer paste 2026-09-02)
  - wiki/sources/sgpstatedata-operational-provenance.md
  - wiki/decisions/014-source-precedence-and-designated-envelopes.md
tags: [indiana, ilearn, scale-bounds, conflict, filed-not-fixed, resolved]
---

Two cells of the ILEARN scale envelope disagree between the IDOE cut-score PDF the records
cite and `SGPstateData`'s operational `loss.hoss`. Both sources are ones this registry
treats as authoritative, so the disagreement was filed rather than reconciled — and then
decided, on 2026-09-02, in favour of the cited document. The argument below is kept whole:
it is the reason the resolution is a judgement rather than a coin toss, and the reason
[[014-source-precedence-and-designated-envelopes]] states the rule as one of order and not
of truth. **Resolved — see the closing section.**

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

## Resolution

**Decided 2026-09-02 by the maintainer:** the cited PDF stands. Both records keep 5870
and 6080 unchanged, and the whole Indiana envelope — these cells, the other twenty-four
ILEARN cells per year, and the ISTEP-era bounds read off the operational LONG — is
designated the envelope of record for historical copula analysis. The 126 Indiana
`scale_bounds` cells that carried `source: "derived"` now carry `source: "official"`,
each keeping the note that records how the number was obtained.

The reasoning is worth preserving, because it is not "the published number wins." A
cut-score PDF is largely boilerplate carried forward year to year, so a decade of them can
propagate one error while looking like independent confirmation; and a vertical scale's
tails are unreliable about where the bottom is, which makes a 24-point LOSS disagreement
as plausibly an artifact of how the scale was extended below the item pool as a bad
source. Neither source is trusted here. What the decision buys is a deterministic,
auditable answer for a use — rank-based growth over a historical panel — in which no
percentile moves either way.

Two consequences are named rather than assumed. The records stay `status: draft`;
designating a value's confidence is not promoting the record that holds it. And
`SGPstateData` is left untouched, so a plain `SGP` run still uses 5865 and 6104 while an
SGPc run reading the registry uses 5870 and 6080 — a known divergence now, and a separate
decision if it is ever to be closed upstream.

The general rule this case produced lives in
[[014-source-precedence-and-designated-envelopes]]: where a cited agency document is still
retrievable it outranks `SGPstateData`, which reverts to a corroborating witness;
`SGPstateData` is the source of record only where the documentation is gone.

Filed, not fixed — then decided, and the file kept. A contradiction is closed by recording
which way it went and why, never by deleting the evidence that it existed.

## Related pages

- [[sgpstatedata-operational-provenance]] — the attestation this case sits at the edge of
- [[grade-encoding-split]] — the registry's other filed-not-fixed finding
- [[014-source-precedence-and-designated-envelopes]] — the precedence rule this case produced
- [[009-v2-implementation]] — `scale_bounds` keying and the loss ≤ cuts ≤ hoss invariant
