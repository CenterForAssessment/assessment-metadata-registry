#!/usr/bin/env python3
"""Migrate SGPc foundry assessment-metadata sidecars into the registry.

One-time (re-runnable) Tier A migration: reads self-contained per-annual sidecars
authored in SGPc (schema_version sgpc.assessment_metadata.v0.1) and writes registry
copies stamped to amr.assessment_system.v1 with governance fields (status /
source_confidence / provenance).

Faithful by design: substantive facts (identity, cutscores, levels, targets) are copied
verbatim. Only the schema_version is restamped and the governance block is added. Records
land as `status: draft` because the SGPc seed values are scaffold/preliminary; a human
promotes them to reviewed/verified in a later commit (with a source_citation).

Usage:
    python3 tools/migrate_sgpc_sidecars.py <SOURCE_DIR>... --out metadata

Destination layout: metadata/<JURISDICTION_ID>/<ASSESSMENT_SYSTEM_ID>/<administration.id>.json
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import sys

AMR_SCHEMA = "amr.assessment_system.v1"
LEGACY_SCHEMA = "sgpc.assessment_metadata.v0.1"
ENTERED_BY = "migration:sgpc-foundry"


def infer_confidence(record: dict) -> str:
    """Low if any block advertises placeholder/scaffold/preliminary values, else medium.

    Nothing here is `high`; promotion to high confidence is a reviewed human decision
    backed by an authoritative citation.
    """
    blob = json.dumps(record).lower()
    if any(flag in blob for flag in ("placeholder", "scaffold", "preliminary")):
        return "low"
    return "medium"


def migrate_record(record: dict, entered_at: str) -> dict:
    if record.get("schema_version") not in (LEGACY_SCHEMA, AMR_SCHEMA):
        raise ValueError(f"unexpected schema_version: {record.get('schema_version')!r}")

    out: dict = {"schema_version": AMR_SCHEMA}
    # status/governance sit right after schema_version for readability.
    out["status"] = "draft"
    out["source_confidence"] = infer_confidence(record)
    out["provenance"] = {
        "entered_by": ENTERED_BY,
        "entered_at": entered_at,
        "last_verified_at": None,
        "changed_from_prior": None,
    }
    # Copy every remaining field verbatim, preserving order, minus the old schema_version.
    for key, value in record.items():
        if key == "schema_version":
            continue
        out[key] = value
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs="+", help="Source directories of sidecar JSON.")
    parser.add_argument("--out", default="metadata", help="Registry metadata root.")
    args = parser.parse_args(argv)

    entered_at = dt.date.today().isoformat()
    out_root = pathlib.Path(args.out)
    written = 0

    for source in args.sources:
        for path in sorted(pathlib.Path(source).glob("*.json")):
            record = json.loads(path.read_text())
            migrated = migrate_record(record, entered_at)
            jid = migrated["jurisdiction"]["id"]
            sid = migrated["assessment_system"]["id"]
            name = f"{migrated['administration']['id']}.json"
            dest_dir = out_root / jid / sid
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / name
            dest.write_text(json.dumps(migrated, indent=2, ensure_ascii=False) + "\n")
            print(f"  {path.name} -> {dest}")
            written += 1

    print(f"Migrated {written} sidecar(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
