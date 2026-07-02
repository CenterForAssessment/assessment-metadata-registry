# Wiki Schema — Assessment Metadata Registry

This wiki follows the **SGPc house style** — the same page-type taxonomy used by the SGPc
wiki — so one operating manual (`AGENTS.md` / `CLAUDE.md`) applies throughout.

## Page Types

| Type | Directory | Purpose |
|------|-----------|---------|
| source | `wiki/sources/` | Summary of an upstream document (state technical report, vendor manual, Ed-Fi spec) that informs registry metadata |
| principle | `wiki/principles/` | A value the registry upholds |
| pattern | `wiki/patterns/` | An implementation pattern (build pipeline, harness, consumption flow) |
| decision | `wiki/decisions/` | An ADR (`NNN-short-title.md`) |
| connection | `wiki/connections/` | An integration boundary with a consumer (e.g. SGPc) |
| analysis | `wiki/analyses/` | Gap analysis, cross-state comparison, open questions |
| overview | `wiki/overview.md` / `purpose.md` | High-level synthesis |

## Naming

- Files: `kebab-case.md`. Decisions: `NNN-short-title.md` (zero-padded).
- Match each page's `title:` frontmatter to its filename.

## Frontmatter

```yaml
---
title: <page title>
type: source | principle | pattern | decision | connection | analysis | overview | index
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: draft | active            # decisions use: proposed | accepted | superseded | deprecated
curated: false                    # false = safe to regenerate; flip true once meaningfully edited
sources: []                       # upstream files / pages that informed this page
tags: []
---
```

## Index, Log, Cross-referencing

- `wiki/index.md` — master catalog grouped by type.
- `wiki/log.md` — append-only, reverse-chronological.
- Internal links use `[[page-slug]]`; add back-links, avoid orphans.
- Cross-repo pointers into a consumer's wiki use the federation-URI form,
  e.g. `[[instantiation:SGPc-rpkg/SGPc/wiki/decisions/011-assessment-metadata-layer]]`.

## Single-fact-per-page

A fact lives in exactly one place. The registry owns assessment-metadata facts; consumer
repos point to them. Do not duplicate consumer-specific logic here.
