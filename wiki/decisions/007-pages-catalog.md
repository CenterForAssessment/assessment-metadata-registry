---
title: "ADR-007: Human-readable Pages catalog (Quarto presentation tier)"
type: decision
created: 2026-07-02
updated: 2026-07-02
status: proposed
deciders: Damian Betebenner
curated: true
sources:
  - site/_quarto.yml
  - site/_common.R
  - .github/workflows/build-publish.yml
  - wiki/decisions/000-registry-architecture.md
  - wiki/patterns/derivation-pipeline.md
tags: [pages, quarto, catalog, presentation, reactable, json-viewer, tier-c]
---

# ADR-007: Human-readable Pages catalog (Quarto presentation tier)

## Status
Proposed.

## Context
GitHub Pages published only the derived `build/**` JSON — machine-readable, not human-readable.
We want an *attractive, read-only* catalog to inspect records (for colleagues reviewing the
spec, and for clients), with a **Display vs Raw** view per record. The house toolchain is R,
and there is an existing Quarto website template to borrow from (`dataimago/HelloWorld`).

## Decision
Add a **Quarto `website`** under `site/` as a **Tier C presentation layer**. It **consumes the
derived `build/**` JSON directly via `jsonlite`** — it does *not* depend on `amrr` — keeping
presentation decoupled from the data pipeline.

- **Catalog browse:** a `reactable` htmlwidget (client-side search/filter/sort), not Quarto
  Listing pages — full styling control, no Listing CSS to fight.
- **Per-record view:** a `::: {.panel-tabset}` with **Display** (R-rendered human-readable
  tables: identity, achievement levels, cutscore grade×boundary matrix, targets, provenance),
  **Explore** (a vendored MIT `@andypf/json-viewer` web component — a JSON-Hero-like tree),
  and **Raw** (a native ```` ```json ```` block). Record pages are generated flat at site root
  (`record-<slug>.qmd`) by a `pre-render` R script so relative asset paths resolve at one depth.
- **Spec viewer:** renders the two JSON Schemas as documentation (field, type, required, enum,
  prose description) — the schemas' `description` strings drive it, so it can't drift.
- **Changelog viewer:** `reactable` over `changelog.json`.

## Additive deploy (non-negotiable)
The published artifact is the Quarto `_site/` **with `build/**` copied in at root**, so every
existing JSON URL (`index.json`, `dist/**`, `manifest.json`, …) — the canonical fetch target
for `amrr` consumers (ADR-000 D7) — keeps resolving. `build-publish` now: validate → build →
`quarto render site` → copy `build/` into `_site/` → deploy `_site/`.

## Dependencies
Site render adds `reactable`, `htmltools`, `knitr`, `rmarkdown`, and the Quarto CLI to CI, plus
one **vendored** JS file (`@andypf/json-viewer`, pinned, MIT, no CDN at runtime). `amrr` and its
consumers are untouched — these are publish-only concerns.

## Consequences
- Emitted HTML is wrapped in Pandoc `{=html}` raw blocks (an `output: asis` chunk is otherwise
  re-parsed as markdown, which mangles values like `>=`); free-text values are `htmlEscape`d.
- The catalog is regenerated on every publish; nothing here is authored or editable.
- Design borrows structure from `dataimago/HelloWorld` but carries a **neutral** identity
  (Public Sans / Fraunces / IBM Plex Mono; warm-paper light + slate dark), not dataimago branding.

## Alternatives considered
- **Quarto Listing pages** for the catalog — rejected: harder to style to spec than `reactable`.
- **Hand-rolled static JS app** — rejected: Quarto fits the R shop and the existing template.
- **`listviewer::jsonedit`** for the tree — kept as a pure-R fallback; `@andypf/json-viewer`
  chosen for the closer JSON-Hero look.
- **jsonhero itself** — not embeddable (a hostable Remix app); inspiration only.
