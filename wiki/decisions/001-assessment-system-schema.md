---
title: "ADR-001: amr.assessment_system.v1 Schema"
type: decision
created: 2026-07-02
updated: 2026-07-02
status: accepted
deciders: Damian Betebenner
curated: true
sources:
  - schemas/amr.assessment_system.v1.schema.json
  - SGPc-rpkg/SGPc/inst/schemas/sgpc-assessment-metadata.schema.json
  - wiki/decisions/000-registry-architecture.md
tags: [schema, metadata, governance, migration]
---

# ADR-001: `amr.assessment_system.v1` Schema

**Status:** Accepted
**Date:** 2026-07-02

## Context

ADR-000 (D3) called for a registry-neutral schema, ported from SGPc's
`sgpc.assessment_metadata.v0.1`, with governance fields added and the legacy string
accepted as an alias. This ADR fixes the concrete schema.

## Decision

Adopt `schemas/amr.assessment_system.v1.schema.json` (JSON Schema draft 2020-12). It
retains the full SGPc sidecar surface — `jurisdiction`, `assessment_system`,
`administration`, `assessment_program`, `content_areas`, `achievement_levels`,
`cutscores`, `achievement_targets`, `aliases`, `edfi` — and adds:

- **`schema_version`** as an `enum` of `["amr.assessment_system.v1",
  "sgpc.assessment_metadata.v0.1"]` so legacy SGPc sidecars validate during migration.
- **Governance block:** `status` (required; draft/reviewed/verified/deprecated),
  `source_confidence` (low/medium/high), and `provenance`
  (`source_citation`, `entered_by`, `entered_at`, `last_verified_at`,
  `changed_from_prior`).
- A conditional (`allOf`/`if`/`then`): any `status` other than `draft` **requires**
  `provenance.source_citation`.
- Minor additive identity fields (`jurisdiction.nces_id`, `jurisdiction.fips`) and
  retention of `cutscores_provenance` as an allowed free-text note (present in the SGPc
  seed files).
- `achievement_levels.*.proficient` accepts booleans **or** strings (the SGPc files use
  booleans; the R layer coerces).

Registry invariants a schema cannot express (filename == `administration.id`, path ==
identity, cut count == levels − 1, cutscore monotonicity, one year per file) are enforced
by `tools/validate.py` and run in CI alongside schema validation.

## Consequences

- SGPc's resolver can consume registry records unchanged except for accepting the new
  `schema_version` string (a two-line change in `sgpc_assessment_metadata_schema_version`
  handling and `is_sgpc_metadata_record`).
- Seed corpus migrated as `status: draft` — placeholder ILEARN cutscores and preliminary
  WIDA exit targets are explicitly low/medium confidence until reviewed.
- `status` is required, so every new record makes a governance claim by construction.

## Related

- [[000-registry-architecture]]
- Planned: ADR-002 (`amr.accountability_system.v1`).
