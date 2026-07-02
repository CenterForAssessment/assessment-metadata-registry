#!/usr/bin/env python3
"""Validate every registry sidecar (assessment + accountability).

Routing is by `schema_version`:
  amr.assessment_system.v1     -> assessment schema  + assessment invariants
  sgpc.assessment_metadata.v0.1 (legacy alias)       -> assessment schema
  amr.accountability_system.v1 -> accountability schema + accountability invariants

Two layers of checks per file:

1. JSON Schema (shape + governance).
2. Registry invariants a schema cannot express:
   Assessment:
     - filename == administration.id; path == metadata/<jurisdiction>/<system>/
     - cutscore count per grade == (achievement_levels labels - 1), when both present
     - cutscores monotonic non-decreasing
   Accountability:
     - filename == administration.id; path == metadata/<jurisdiction>/<accountability_system>/
     - CROSS-LINK: every target (assessment_system_id, content_area) resolves to an
       assessment record for the same jurisdiction + year, and that record declares the
       content_area
   Both:
     - non-draft records carry provenance.source_citation

Exit non-zero on any failure. Deterministic; no network.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.stderr.write("jsonschema is required: pip install jsonschema\n")
    raise

ASSESSMENT_SCHEMAS = {"amr.assessment_system.v1", "sgpc.assessment_metadata.v0.1"}
ACCT_SCHEMA = "amr.accountability_system.v1"


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text())


def build_assessment_index(records: list[tuple[pathlib.Path, dict]]) -> dict:
    """(jurisdiction_id, assessment_system_id, year) -> set of content_area ids."""
    index: dict[tuple, set] = {}
    for _, rec in records:
        if rec.get("schema_version") in ASSESSMENT_SCHEMAS:
            key = (rec["jurisdiction"]["id"], rec["assessment_system"]["id"],
                   rec["administration"]["year"])
            index[key] = {ca["id"] for ca in rec.get("content_areas", [])}
    return index


def common_invariants(path, rec, metadata_root, system_key) -> list[str]:
    errors = []
    admin = rec.get("administration", {})
    jid = rec.get("jurisdiction", {}).get("id")
    sysseg = rec.get(system_key, {}).get("id")
    admin_id = admin.get("id")
    if admin_id and path.stem != admin_id:
        errors.append(f"filename '{path.stem}' != administration.id '{admin_id}'")
    expected = metadata_root / str(jid) / str(sysseg)
    if path.parent.resolve() != expected.resolve():
        errors.append(f"path {path.parent} != identity path {expected}")
    year = admin.get("year")
    if year and admin_id and not admin_id.endswith(str(year)):
        errors.append(f"administration.id '{admin_id}' does not end with year '{year}'")
    if rec.get("status") in ("reviewed", "verified", "deprecated"):
        if not (rec.get("provenance") or {}).get("source_citation"):
            errors.append(f"status '{rec.get('status')}' requires provenance.source_citation")
    return errors


def assessment_invariants(path, rec, metadata_root) -> list[str]:
    errors = common_invariants(path, rec, metadata_root, "assessment_system")
    levels = rec.get("achievement_levels") or {}
    for ca, grades in (rec.get("cutscores") or {}).items():
        n_labels = len(((levels.get(ca) or {}).get("labels")) or [])
        expected_cuts = n_labels - 1 if n_labels else None
        for grade, cuts in (grades or {}).items():
            if expected_cuts is not None and len(cuts) != expected_cuts:
                errors.append(f"cutscores[{ca}][{grade}] has {len(cuts)} cut(s); "
                              f"achievement_levels implies {expected_cuts}")
            if any(cuts[i] > cuts[i + 1] for i in range(len(cuts) - 1)):
                errors.append(f"cutscores[{ca}][{grade}] not monotonic: {cuts}")
    return errors


def accountability_invariants(path, rec, metadata_root, assessment_index) -> list[str]:
    errors = common_invariants(path, rec, metadata_root, "accountability_system")
    jid = rec.get("jurisdiction", {}).get("id")
    year = rec.get("administration", {}).get("year")
    for i, tgt in enumerate(rec.get("targets", [])):
        sid = tgt.get("assessment_system_id")
        ca = tgt.get("content_area")
        key = (jid, sid, year)
        if key not in assessment_index:
            errors.append(f"targets[{i}] cross-link ({sid}, {year}) has no assessment record")
        elif ca not in assessment_index[key]:
            errors.append(f"targets[{i}] content_area '{ca}' not in assessment {sid} {year} "
                          f"(has: {sorted(assessment_index[key])})")
    return errors


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--metadata", default="metadata")
    ap.add_argument("--schema-dir", default="schemas")
    args = ap.parse_args(argv)

    schema_dir = pathlib.Path(args.schema_dir)
    assess_validator = Draft202012Validator(
        json.loads((schema_dir / "amr.assessment_system.v1.schema.json").read_text()))
    acct_validator = Draft202012Validator(
        json.loads((schema_dir / "amr.accountability_system.v1.schema.json").read_text()))

    metadata_root = pathlib.Path(args.metadata)
    files = sorted(metadata_root.rglob("*.json"))
    if not files:
        sys.stderr.write(f"No sidecars under {metadata_root}\n")
        return 1

    records = []
    for path in files:
        try:
            records.append((path, load(path)))
        except json.JSONDecodeError as exc:
            print(f"FAIL {path}: invalid JSON: {exc}")
            return 1

    assessment_index = build_assessment_index(records)
    total_errors = 0

    for path, rec in records:
        sv = rec.get("schema_version")
        if sv in ASSESSMENT_SCHEMAS:
            errors = [f"schema: {e.message} (at {'/'.join(map(str, e.path)) or '<root>'})"
                      for e in assess_validator.iter_errors(rec)]
            errors += assessment_invariants(path, rec, metadata_root)
        elif sv == ACCT_SCHEMA:
            errors = [f"schema: {e.message} (at {'/'.join(map(str, e.path)) or '<root>'})"
                      for e in acct_validator.iter_errors(rec)]
            errors += accountability_invariants(path, rec, metadata_root, assessment_index)
        else:
            errors = [f"unknown schema_version: {sv!r}"]

        if errors:
            print(f"FAIL {path}")
            for e in errors:
                print(f"     - {e}")
            total_errors += len(errors)
        else:
            print(f"ok   {path}")

    print(f"\n{len(files)} file(s) checked, {total_errors} error(s).")
    return 1 if total_errors else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
