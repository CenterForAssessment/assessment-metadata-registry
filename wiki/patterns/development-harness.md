---
title: "Pattern: Registry Development Harness"
type: pattern
created: 2026-07-02
updated: 2026-07-02
status: active
curated: true
sources:
  - AGENTS.md
  - SGPc-wiki/wiki/patterns/vertical-development-harness.md
tags: [harness, subagents, skills, gates, hooks, provenance]
---

# Pattern: Registry Development Harness

The operational half of the registry: the engineered circumstances around the agents that
make high-quality, reproducible metadata work repeatable. The wiki is the knowledge half;
this is the machinery. Ported from the SGPc vertical harness and adapted to a
single-repo, data-product context.

## Principle

Most development quality is **circumstantial** — it comes from the harness, not the model.
For a metadata registry the environment is: a shared operating manual, a JSON Schema that
is the contract, deterministic build/validation gates, provenance/status on every record,
and orientation hooks. Investing here is what makes AI-assisted authoring (ADR-003) safe
rather than reckless.

## Components

### 1. Operating manual (highest-ROI lever)
`AGENTS.md` (canonical) + `CLAUDE.md` (import shim). One tool-neutral manual; agents
inherit the role and the bright lines rather than re-deriving them.

### 2. The schema as contract
The `amr.*.vN` JSON Schema is the enforceable contract for Tier A. Validation is a
**deterministic gate**: a malformed or identity-conflicting sidecar fails the build.
This is the registry analogue of SGPc's `on_conflict = "error"` — turning "the metadata
is wrong" into a caught error rather than a silent bad row.

### 3. Deterministic gates (fast loop)
- **Validate** every sidecar against its schema on every push.
- **Regenerate** the derived layer (DB, indexes, changelogs, bundles) and assert the diff
  is explainable by the input change (no hand edits to derived artifacts).
- **Changelog** surfaces year-over-year changes so re-establishments and corrections are
  explicit, reviewable signals.
- **One local entry point:** `Makefile` (`make validate | build | check | test | all`) runs
  the same R gates humans and CI run (`amrr::validate_registry()`, `amrr::build_registry()`; ADR-004).
  `main` is branch-protected (PR required; `validate` a required status check), so the gates
  are enforced, not optional.
- **Proposed next increment (needs human review — self-modifying):** a checked-in
  `.claude/settings.json` allow-list for the safe, repeated loop commands, plus a
  `PostToolUse` hook that runs `amrr::validate_registry(".")` the instant a `metadata/`/`schemas/`
  file is edited (tightest authoring feedback). Behavior-changing, so it lands only on explicit sign-off.

### 4. Subagents (throughput lever — fan out)
`.claude/agents/` (present):
- `metadata-author` — drafts/validates a single sidecar from a cited source; writes only
  `draft` status; never promotes.
- `registry-librarian` — regenerates and diffs the derived layer; read-only on Tier A.
- `consumption-lint` — checks the SGPc consumption contract still holds (resolver source,
  schema alias, manifest fields).

#### Agent role conventions (inherited)
- **Operational, not flattering.** A role is a scoped action space plus hard boundaries,
  not adjectives.
- **One tight opening `**Role:**` line** per agent: identity + the single hardest
  constraint.
- **State the boundary as a prohibition** (never edit derived artifacts; never promote to
  `verified`; never touch microdata; never fetch outside allowed sources).

### 5. Provenance & status as a safety rail
`status` + `source_confidence` + `source_citation` on every record are what let an AI
harness participate safely: machine drafts are visibly `draft`/`low` with a citation, and
promotion to `verified` is a human-reviewed commit. The harness can *propose* at scale;
humans *dispose*.

### 6. Reproducibility by SHA
Because Git is the content version store, the harness never needs to snapshot a database
for reproducibility — a recorded commit SHA reconstructs any past state exactly. This is
simpler and more trustworthy than versioned binary artifacts.

## Templatization

When this harness stabilizes it becomes a reusable pattern, the same way the SGPc harness
did — so the next data-product repo inherits it rather than re-deriving it.
