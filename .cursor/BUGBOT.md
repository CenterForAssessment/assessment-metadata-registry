# Bugbot — assessment-metadata-registry

This repo authors **system-level assessment metadata** as JSON sidecars, derives everything
else from them, and serves the result read-only. `AGENTS.md` is the operating manual; this
file names only the things a reviewer gets wrong by default.

## Bright lines (flag any violation, no exceptions)

- **No microdata.** System-level metadata only. Never student- or school-level records,
  credentials, or non-redistributable source data. Flag any PR that adds, reads, or
  references them.
- **Tier A is the only place edits happen.** `metadata/**/*.json` sidecars are authored.
  `build/**`, `registry.sqlite`, indexes, changelogs, and bundles are **derived and
  disposable** — CI regenerates them on every push. A hand-edit to a derived artifact is a
  bug even if the values are right.
- **Every non-draft claim needs a citation.** A record whose `status` is anything other
  than `draft` must carry `provenance.source_citation`. The schema enforces this; a PR that
  promotes `draft → reviewed/verified` without one is wrong, and so is a PR that promotes a
  record whose facts nobody sourced.
- **Never invent a number.** Cut scores, scale bounds, comparability claims, and vendor
  names are sourced or absent. "Absent" is a legitimate, deliberate state — see below.

## Things that look like bugs and are not

- **A record with no `cutscores` is not incomplete.** WIDA ACCESS has no published
  per-grade proficiency-level lookup in hand, so none are authored. Do not suggest adding
  placeholder cut scores, a default, or a `scale_bounds` guess. Growth percentiles need
  scale scores and grades, not cut scores.
- **`comparability` absent** means the psychometric claim was not sourced, not that the
  years are comparable.
- **Grade `"K"` and grade `"0"` both validate.** The pattern `^(PK|K|[0-9]{1,2})$` admits
  both; assessment records use `"K"`, accountability records and SGPc use `"0"`. This split
  is *filed, not fixed* (`wiki/analyses/grade-encoding-split.md`). Do not "correct" one side
  to match the other in a PR that isn't explicitly about reconciling them. **Do** flag any
  new code that compares grade keys across the two families without normalizing.

## Where the real bugs live

**R `$` partial matching.** `record$cutscores` silently returns `cutscores_provenance` on a
record that has the latter and not the former — a prose sentence where a list belongs — and
the next `[[content_area]]` errors on an atomic vector, several frames away. Likewise
`block$proficient` returns v2's `proficient_from` *label* where a boolean mask belongs.
**On any read of a metadata record, require exact `[[`.** This has bitten `amrr` once
already. Flag every new `$` access on a record, block, or sidecar.

**Silent fallbacks.** An accessor that returns `NULL` where it should error, a source that
falls through to a different source when the requested one fails, an argument accepted and
never forwarded. Weight these above style. Concretely:
- `get_metadata(registry = ..., ref = ...)` must fail loudly on an unreachable registry or a
  bad `ref`. Answering from somewhere else is worse than failing.
- `amrr_registry_ref()` returns `NA` when the registry root is not a git checkout. **`NA` is
  the honest answer.** Never synthesize a SHA, and never let `NA` become the string `"NA"`.

**Validation ordering.** Every sidecar validates against its schema *before* any derivation
(`.common_invariants`, `.assessment_invariants`, `.accountability_invariants` in
`r-pkg/amrr/R/validate.R`). An identity conflict is an error, not a warning. A change that
lets a malformed sidecar reach the build is a bug.

**The axis rule.** Grade keys on `cutscores`, `scale_bounds`, and `cutscores_source` must be
members of that content area's `enrolled_grades_tested`. It does **not** constrain
accountability `per_grade_scale_score`. Don't extend it there.

## `serve/vercel` (the read-only API)

- **The DB is never on the static surface.** `public/` is the *entire* published static
  directory and holds exactly one file. Anything that could make `data/registry.sqlite`,
  `lib/*.ts`, or `vercel.json` fetchable is a security bug. `.vercelignore` is load-bearing
  and is not the same file as `.gitignore`.
- **Every SQL-accepting surface passes `assertSelectOnly`.** Read-only connections plus the
  whole-word keyword guard, both. Flag any path that reaches `rowsOf()` without it.
- **Every answer is SHA-stamped.** New endpoints return the `git_sha` envelope.
- **`lib/endpoints.ts` is the single source of truth for what exists.** `GET /api` renders
  from it, `public/index.html` fetches `/api`, `local-server.ts` refuses to boot on a
  route/catalog mismatch, and smoke fetches every advertised path. A hand-maintained
  endpoint list anywhere else is drift waiting to happen.
- **`GET /api` must never 5xx.** When the DB is missing it returns 200 with `git_sha: null`
  and a `provenance_error`. A `null` `git_sha` means "could not read the DB", never "no
  commit". Other endpoints *should* 503 in that case.

## Reviewing data PRs

Sidecar content is gated by `validate-metadata` CI and by human review against source
documents — not by code review. On a PR that only touches `metadata/**`, restrict comments
to schema-shape problems, identity conflicts (filename stem must equal
`administration.id`), cross-record link breakage, and the bright lines above. Do not opine
on whether a cut score or a weight is correct; you cannot know, and a confident guess is
worse than silence.
