---
title: "ADR-014: Source precedence, and designating a scale envelope of record"
type: decision
created: 2026-09-02
updated: 2026-09-02
status: accepted
deciders: Damian Betebenner
curated: true
scope:
  - assessment-metadata-registry
  - SGPc-rpkg (consumer — margins layer, ADR-014 crosswalk)
  - SGPc-foundry (Indiana state-summative pipeline)
sources:
  - wiki/sources/sgpstatedata-operational-provenance.md
  - wiki/analyses/indiana-ilearn-scale-bound-conflict.md
  - wiki/decisions/008-unified-metadata-taxonomy.md
  - wiki/decisions/009-v2-implementation.md
  - metadata/IN/istep/*.json, metadata/IN/istep-plus/*.json, metadata/IN/ilearn/*.json
tags: [governance, provenance, precedence, scale-bounds, indiana, sgpstatedata]
---

# ADR-014: Source precedence, and designating a scale envelope of record

**Status:** Accepted — decided 2026-09-02 by the maintainer (Damian Betebenner), on the
two-cell ILEARN conflict filed as [[indiana-ilearn-scale-bound-conflict]]: *"Where these
discrepancies occur, it would probably be best to just go with the PDF record if it
exists. … Given what we want to use these for (historical copula analyses), I'm inclined
to designate as official the loss/hoss values we have just established."*

The registry now has two sources it treats as authoritative for the same numbers — the
state agency's published cut-score document, and `SGPstateData`, whose operational
standing ADR-scoped page [[sgpstatedata-operational-provenance]] establishes. That page
answered the case where the agency document has vanished. It did not answer the harder
case, which Indiana produced within a day: both sources present, both authoritative, and
disagreeing. This ADR supplies the ordering, and — separately, because it is a different
kind of act — the designation that closes the Indiana envelope for use.

## Context: a tie the attestation could not break

Six ILEARN records on the 2019 scale disagree with `SGPstateData` in exactly two cells,
identically in every year, while twenty-four other cells per year match: ELA grade 6 HOSS
(record 5870, `SGPstateData` 5865) and MATHEMATICS grade 3 LOSS (record 6080,
`SGPstateData` 6104). The analysis page sets out why neither value can be dismissed as a
transcription slip. Both candidates for grade 6 sit inside the published HOSS
progression; for grade 3, the record's value is monotone with the neighbouring grades and
`SGPstateData`'s is not, which is weak evidence and weak for a principled reason — a
lowest obtainable score is a property of each grade's form, not of a sequence.

## Decision

**D1 — A retrievable, cited agency document outranks `SGPstateData`.** Where a record
cites a state-agency source that can still be read, its values stand and `SGPstateData`
becomes a corroborating witness, not an authority. `SGPstateData` is the source of record
only where the agency documentation is no longer retrievable, which is the case
[[sgpstatedata-operational-provenance]] was written for. Precedence is by *retrievability
of the primary document*, not by recency and not by which source an authoring agent
happened to reach first.

**D2 — D1 is a rule of order, not a claim of truth.** Two things weaken any published
figure enough that D1 must not be read as adjudicating fact. Cut-score PDFs are largely
boilerplate carried forward from year to year, so an error in one propagates silently
through a decade of documents that look like independent confirmations. And a vertical
scale's tails are notoriously unreliable about where the bottom actually is: a disagreement
at a LOSS is as likely an artifact of how the scale was extended below the item pool as it
is a bad transcription. D1 buys a deterministic, auditable answer. It does not buy the
right answer, and a record that follows it should not be read as asserting one.

**D3 — The Indiana ISTEP / ISTEP+ / ILEARN envelope is designated of record.** The
loss/hoss values established across 2009–2026 — ILEARN's from the cited IDOE cut-score PDF,
the ISTEP-era's from the observed endpoints of the operational LONG, confirmed by the
maintainer — are the values Indiana historical copula analyses use. All 126 Indiana
state-summative `scale_bounds` cells that carried `source: "derived"` are set to
`source: "official"`, and each keeps the note recording how the number was actually
obtained. `source` is the per-value **confidence** enum of ADR-008 §5, not a provenance
type; raising it is the act of designation, and the note is what keeps derivation legible
underneath it.

## What this does not establish

Three boundaries, because each has already been mistaken for something larger in this
registry's short history.

**It does not promote a record.** Every Indiana ISTEP/ISTEP+/ILEARN record stays
`status: draft`. Promotion to `reviewed` remains the separate human act that
[[sgpstatedata-operational-provenance]] and ADR-000 make it, gated on checking citations
and the 2019 three-level collapse. A cell may be `source: official` inside a `draft`
record; the two axes are independent by design (ADR-008 §5).

**It does not assert that these are the true obtainable extrema.** D3 designates fitness
for a purpose — rank-based growth analysis over a historical panel, where the envelope
serves the margins crosswalk and the reported scale range, and where no percentile moves
if a HOSS is off by five points. A different purpose, a scale-score report or a
standard-setting audit, is entitled to reopen the question and should cite this ADR when
it does.

**It does not change `SGPstateData`.** The two divergent cells persist upstream, so a
plain `SGP` run reading `Knots_Boundaries` still uses 5865 and 6104 while an SGPc run
reading the registry uses 5870 and 6080. That divergence is now a known, named quantity
rather than a surprise; correcting it upstream is a separate decision the maintainer may
take at any time, and would be implemented here as a re-derivation, not as a silent edit.

## Consequences

The conflict page moves from `open` to `resolved` and keeps its whole argument: a filed
contradiction is closed by recording which way it was decided and why, never by deleting
the evidence that it existed. Future jurisdictions inherit D1 as the default tie-break, so
the second state to hit this cites this ADR instead of re-litigating it. Authoring agents
gain a rule they can apply without a maintainer round-trip in the common case, and a
standing instruction for the uncommon one: where D1 decides a cell against a source the
registry also calls authoritative, file the disagreement before applying it.

Precedence buys a decision, not a fact — the ordering says which number the registry
publishes, and the note beneath it says what that number actually is.

## Related pages

- [[sgpstatedata-operational-provenance]] — the attestation this ADR orders against
- [[indiana-ilearn-scale-bound-conflict]] — the case that forced the rule
- [[008-unified-metadata-taxonomy]] — per-value confidence (`official`/`derived`/`provisional`)
- [[009-v2-implementation]] — `scale_bounds` keying and the loss ≤ cuts ≤ hoss invariant
- [[sgpc-registry-consumption-contract]] — what SGPc reads from these records
