---
title: Assessment Metadata Registry — Purpose
type: overview
created: 2026-07-02
updated: 2026-07-02
---

# Purpose

## Thesis

State assessment metadata — what assessment a jurisdiction used, in what year, for which
grades and content areas, on what scale, with which vendor, achievement levels, cutscores,
comparability caveats, and accountability rules — is a **durable public data product**,
not project-specific helper code. This repository is the canonical, versioned home for
that metadata, framed as a **general registry** with SGPc as its first consumer.

## The problem it solves

Assessment metadata used to live as a single embedded R object (`SGPstateData`) that could
not be queried across jurisdictions and lost history whenever a state re-established
performance levels. SGPc took the first step by moving to self-contained annual JSON
sidecars. This registry takes the next step: lifting those sidecars into a standalone,
version-controlled product that many tools can consume, with Git as the history axis and a
commit SHA as the reproducibility pin.

## Scope

**In scope:** system-level assessment metadata (`amr.assessment_system.v1`) and
accountability-system metadata (`amr.accountability_system.v1`) — identity, administration,
content areas, scales, achievement levels, cutscores, vendors, comparability, Ed-Fi
descriptors, accountability rules; the derived query layer; the `amrr` R consumption
package; the AI-assisted authoring harness.

**Out of scope:** student- or school-level microdata (hard boundary); SGP-specific
configuration (knots/boundaries, copula policy) — those stay in SGPc.

## Key questions the registry answers

- What was true for `jurisdiction × system × year` — and what was true *as used by a
  specific past analysis* (via its recorded commit SHA)?
- Which jurisdictions used a vertical scale in grade 3–8 math? Which used WIDA-ACCESS in
  2025? When did a vendor change? When did cutscores or level names change?
- How do a state's multiple programs (general summative + ELP + science + alternate)
  relate under one accountability system?

## Primary audience

SGPc and other internal analyses first; state partners and public researchers over time.
The design keeps the core general so it stays valuable beyond any one analysis.

See `wiki/decisions/000-registry-architecture.md` for the founding architecture.
