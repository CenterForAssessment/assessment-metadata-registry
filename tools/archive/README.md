# tools/archive — historical, one-time bootstrap scripts

These Python scripts seeded the Tier A corpus during the registry's initial build-out.
They are **not part of the ongoing toolchain** (which is R — see
`wiki/decisions/004-tooling-language.md`), are **not run by CI**, and are kept here only
for provenance and reproducibility of how the seed corpus was authored.

| Script | What it did (one-time) |
|--------|------------------------|
| `migrate_sgpc_sidecars.py` | Migrated the Indiana SGPc sidecars (ILEARN, WIDA-ACCESS) into `metadata/IN/`. |
| `split_accountability.py`  | ADR-002 relocation: extracted `achievement_targets` from assessment sidecars into per-year `*-accountability` records. |
| `seed_demo.py`             | ADR-003: authored the demonstration jurisdictions (State C, State D). |

Re-running them requires Python 3 (stdlib only) and overwrites the sidecars they
generate. Prefer authoring new sidecars directly (or via the `metadata-author` subagent)
and validating with `make validate`.
