---
title: "SGPstateData as operational provenance"
type: source
created: 2026-09-02
updated: 2026-09-02
status: active
curated: true
sources:
  - SGP::SGPstateData (DBetebenner/SGPstateData)
  - metadata/IN/istep/*.json, metadata/IN/istep-plus/*.json, metadata/IN/ilearn/*.json
tags: [provenance, cutscores, sgpstatedata, governance, indiana]
---

`SGP::SGPstateData` is an authoritative source for state cut scores in this registry,
not a convenience fallback. Where a record cites it, the absence of a retrievable
state-agency URL is a documentation gap and does not by itself lower the record's
trustworthiness.

## The determination

**Maintainer attestation, Damian Betebenner, 2026-09-02:** the Indiana values in
`SGPstateData[['IN']][['Achievement']][['Cutscores']]` were derived from IDOE documents
and used operationally in production SGP analyses. Much of that source documentation is
no longer retrievable on the public web. The attestation is recorded verbatim in the
`cutscores_provenance` of each affected record so a reader of the JSON alone reaches the
same conclusion without finding this page.

## Why this is a source page and not an exception

Registry ADR-000 makes every authored number carry provenance, and the authoring agents
are instructed to cite a primary document. Left unqualified, that instruction would
push an agent to mark decades-old state cut scores `source_confidence: low` — or worse,
to go looking for a substitute number on the open web — precisely where the most reliable
record is a package the maintainer built from the agency's own documents and then ran in
production for years. Operational use is itself evidence: a cut score that produced
reported results for a state is not a value someone guessed.

The boundary matters as much as the permission. This page licenses *SGPstateData* as a
citation of record. It does not license an agent to fill a gap from memory, from a
secondary summary, or from another package; and it does not convert a `draft` record into
a `reviewed` one. Promotion remains the human act it was (ADR-000; ADR-006 planned).

## How to cite it in a record

Name the exact accessor, the delivery, and the date, then state the attestation:

```jsonc
"cutscores_provenance":
  "SGP::SGPstateData[['IN']][['Achievement']][['Cutscores']] (DBetebenner/SGPstateData; maintainer paste 2026-09-01), ELA.2015 / MATHEMATICS.2015 blocks. … MAINTAINER ATTESTATION (Damian Betebenner, 2026-09-02): SGPstateData is AUTHORITATIVE for these cut scores. … A missing URL is therefore a documentation gap, not a provenance defect. See wiki/sources/sgpstatedata-operational-provenance.md."
```

Keep any independent corroboration that *was* found alongside it — the 2015 ISTEP+ records
cite contemporaneous press coverage of the State Board's pass-line vote, and that
corroboration stays. An attestation supplements evidence; it does not replace it.

## Where this recurs

Indiana is the first jurisdiction to need this, and it will not be the last: the same
package carries cut scores for every state whose SGP analyses the maintainer has run.
When the second state arrives, cite this page rather than restating the argument, and add
the jurisdiction to the tags. If a future ADR-006 (governance) formalizes promotion
criteria, this determination is one of its inputs — recorded here so it is not
rediscovered.

## Related pages

- [[000-registry-architecture]] — provenance on every authored number
- [[013-national-international-assessments]] — the sibling case where primary sources *were* retrievable (NCES, IEA)
- [[sgpc-registry-consumption-contract]] — what SGPc reads from these records
