---
title: Assessment Metadata Registry — Wiki Index
type: index
created: 2026-07-02
updated: 2026-07-08
---

# Assessment Metadata Registry — Master Index

Master catalog of the registry's knowledge layer. Read `../AGENTS.md` and `../purpose.md`
first. This wiki follows the **SGPc house style** (the same page-type taxonomy as SGPc's wiki).

**Status:** v2 implemented and migrated (`amrr` 0.2.0), then refined per ADR-010
(`amrr` 0.3.0): `proficient_from` (replacing the legacy `proficient[]` mask, corpus
folded), `verified_by`, the EOC `"eoc"` cut key, and the compact config view
(`as_config`/`read_config`, `build/config/`, site **Config view** page). `amrr` 0.4.0
added a derived-URL remote (latest build); 0.5.0 added a **reproducible remote** —
`get_metadata(registry = "github://…", ref = <SHA>)` reads canonical sidecars raw-by-SHA,
no checkout (ADR-011) — plus **local auto-discovery** (run R anywhere inside a checkout and
no `registry` argument is needed). ADRs 000/004/007/008/009/010/011 accepted 2026-07-06.
Pending: SGPc resolver wiring (Phase G); a `read_config()` sidecar writer; real WIDA_IN /
EOC authoring.
WIDA_IN is the v2 dogfood corpus.

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
| [[010-config-view-reconciliation]] | **accepted** | Reconcile the colleague's `amr.assessment_config.v1`: additive v2 refinements (`proficient_from`, `verified_by`, EOC `"eoc"` cut key) + the compact config shape as an `amrr` projection (`as_config`/`read_config`, `build/config/`, site Config view) — not a canonical re-model |
| [[011-remote-sha-pinning]] | **accepted** | Reproducible remote consumption (`amrr` 0.5.0): `get_metadata(registry = "github://owner/repo", ref = <SHA>)` reads canonical Tier A sidecars raw-by-SHA from GitHub (git-trees + raw content, byte-immutable), no checkout — resolves the deferred remote-pinning open item; derived-URL mode remains for convenience/latest only |
| [[012-query-api-mcp-backend]] | proposed (rev 1) | Read-only **query contract** + MCP backend (Tier C, `serve/`): host-agnostic contract (immutable `registry.sqlite`, SELECT-only guard, SHA-stamped envelope, dual REST+MCP with 5 read-only tools); Datasette as the local/CI authoring–exploration engine; **serverless-first** deployment tiers (bundled read-only SQLite → dataimago `database` driver as Tier 1 default; VPS+Caddy Datasette retained as opt-in Tier 2). Convenience/latest + SHA-stamped, **not** the reproducibility pin; registry = instance #1 of the dataimago data-store pattern, SGPc-ai output store = instance #2 |

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
