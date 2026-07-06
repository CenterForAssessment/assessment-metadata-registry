---
title: Assessment Metadata Registry — Wiki Index
type: index
created: 2026-07-02
updated: 2026-07-03
---

# Assessment Metadata Registry — Master Index

Master catalog of the registry's knowledge layer. Read `../AGENTS.md` and `../purpose.md`
first. This wiki follows the **SGPc house style** (the same page-type taxonomy as SGPc's wiki).

**Status:** v2 implemented (ADR-009 accepted; Phases B–F landed in `amrr` 0.2.0: v2
schemas + invariants, `migrate_registry()`, v2 accessors, `amrr_materialize()`,
build/site v2-aware). ADRs 000/004/007/008/009 accepted 2026-07-06. Pending: local
`make all` + corpus migration commit (needs R toolchain), then SGPc resolver wiring
(Phase G). WIDA_IN is the v2 dogfood corpus.

---

## Infrastructure

| Page | Summary |
|------|---------|
| `../AGENTS.md` | Canonical operating manual (harness root) |
| `../purpose.md` | Registry thesis, scope, key questions |
| [[log]] | Chronological record of wiki/registry activity |
| [[schema]] | Wiki page-type taxonomy and conventions |

---

## Decisions (ADRs)

| ADR | Status | Summary |
|-----|--------|---------|
| [[000-registry-architecture]] | **accepted** | Founding architecture: JSON canonical, Git-SHA versioning, monorepo `amrr`, static-first consumption, separate accountability records, AI authoring harness |
| [[001-assessment-system-schema]] | **accepted** | `amr.assessment_system.v1` schema: ported SGPc surface + governance fields + legacy alias |
| [[002-accountability-system-record]] | **accepted** | `amr.accountability_system.v1`; relocated achievement targets (ELP exit) out of the assessment record — the worked "what goes where" example |
| [[003-demo-jurisdictions]] | **accepted** | Demo jurisdictions SD + SC from testSGPc; `comparability` schema extension (scale transitions, COVID gap); changelog fix |
| [[004-tooling-language]] | **accepted** | Single-language R tooling: `validate`/`build` become `amrr::validate_registry()`/`build_registry()` (build deps in Suggests), drop Python, semantic parity verified |
| ADR-005 | planned | AI-assisted authoring / scraping pipeline |
| ADR-006 | planned | Governance: authorship, review, promotion to `verified` |
| [[007-pages-catalog]] | **accepted** | Human-readable Pages catalog: a Quarto site (`site/`) renders the derived JSON — `reactable` browse, per-record Display/Explore/Raw, spec + changelog viewers; additive to the published JSON |
| [[008-unified-metadata-taxonomy]] | **accepted** | Greenfield five-domain taxonomy; naming alignment first; registry API via `amrr` as primary consumption (SGPc function-argument pattern); optional `.rda` materialization secondary; colleague spec as SGPstateData analog |
| [[009-v2-implementation]] | **accepted** | v2 implementation: enrollment-grade model (`fixed`/`variable` + `enrolled_grades_tested`), enrolled-grade-keyed `scale_bounds`, type-discriminated extensions, dual-version migration, WIDA_IN dogfood-first delivery |

---

## Patterns

- [[development-harness]] — the iterative development harness (ported SGPc wisdom)
- [[derivation-pipeline]] — Tier B build: sidecars → index, changelog, bundles, SQLite, manifest
- [[metadata-taxonomy]] — five metadata domains, canonical naming, projection layers (canonical → SGPc / R spec)

---

## Connections (cross-repo contracts)

- [[sgpc-registry-consumption-contract]] — the Tier C boundary with SGPc's
  `resolve_sgpc_metadata()` resolver (adds a `registry` source; re-merges targets;
  records the commit SHA in SGPc outputs).

---

## Sources

| Page | Summary |
|------|---------|
| [[colleague-assessment-spec-r]] | Colleague's unified `assessment_spec.R`: typed general/alternate/ELP list schema, verification workflow, separated demographics |

---

## Analyses

| Page | Summary |
|------|---------|
| [[schema-crosswalk]] | Field-level mapping of `amr.*`, SGPc sidecar, and `assessment_spec.R` onto the five-domain taxonomy — conflicts, gaps, reclassifications |
