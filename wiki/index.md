---
title: Assessment Metadata Registry — Wiki Index
type: index
created: 2026-07-02
updated: 2026-07-02
---

# Assessment Metadata Registry — Master Index

Master catalog of the registry's knowledge layer. Read `../AGENTS.md` and `../purpose.md`
first. This wiki follows the **SGPc house style** (the same page-type taxonomy as SGPc's wiki).

**Status:** Phase 3. `amrr` R package (`get_metadata()` + target re-merge + accessors)
landed with tests and R-CMD-check CI. Tiers A/B complete; accountability record type in
place. Founding ADR proposed pending sign-off.

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
| [[000-registry-architecture]] | **proposed** | Founding architecture: JSON canonical, Git-SHA versioning, monorepo `amrr`, static-first consumption, separate accountability records, AI authoring harness |
| [[001-assessment-system-schema]] | **accepted** | `amr.assessment_system.v1` schema: ported SGPc surface + governance fields + legacy alias |
| [[002-accountability-system-record]] | **accepted** | `amr.accountability_system.v1`; relocated achievement targets (ELP exit) out of the assessment record — the worked "what goes where" example |
| [[003-demo-jurisdictions]] | **accepted** | Demo jurisdictions SD + SC from testSGPc; `comparability` schema extension (scale transitions, COVID gap); changelog fix |
| ADR-003 | planned | AI-assisted authoring / scraping pipeline |
| ADR-004 | planned | Governance: authorship, review, promotion to `verified` |

---

## Patterns

- [[development-harness]] — the iterative development harness (ported SGPc wisdom)
- [[derivation-pipeline]] — Tier B build: sidecars → index, changelog, bundles, SQLite, manifest

---

## Connections (cross-repo contracts)

- [[sgpc-registry-consumption-contract]] — the Tier C boundary with SGPc's
  `resolve_sgpc_metadata()` resolver (adds a `registry` source; re-merges targets;
  records the commit SHA in SGPc outputs).

---

## Sources

*Upstream documents that inform the registry (state technical reports, vendor manuals,
Ed-Fi descriptors). Seeded as authoring begins.*

---

## Analyses

*Gap analyses, cross-state comparisons, and open questions. Seeded as the corpus grows.*
