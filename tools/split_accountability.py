#!/usr/bin/env python3
"""Relocate achievement_targets from assessment sidecars into accountability records.

The worked "what goes where" example (ADR-002): an achievement target (ELP exit, summative
proficiency goal) is *state policy* about how to use an assessment, not a property of the
assessment. This one-time migration:

  1. reads every amr.assessment_system.v1 sidecar under metadata/,
  2. pops its `achievement_targets` map,
  3. rewrites the assessment sidecar without that block,
  4. aggregates the popped targets by (jurisdiction, year) into a single
     amr.accountability_system.v1 record per year, each target cross-linked to its
     assessment_system_id + content_area.

Accountability records land at metadata/<JUR>/<accountability_system_id>/<id>-<year>.json.
Re-runnable: it reads the current assessment sidecars, so running twice (after step 3 has
stripped them) simply produces no new targets.

Usage:  python3 tools/split_accountability.py [--metadata metadata]
        [--acct-id in-accountability] [--acct-name "Indiana Accountability System"]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import sys

ASSESSMENT_SCHEMA = "amr.assessment_system.v1"
ACCT_SCHEMA = "amr.accountability_system.v1"


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text())


def dump(path: pathlib.Path, rec: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rec, indent=2, ensure_ascii=False) + "\n")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--metadata", default="metadata")
    ap.add_argument("--acct-id", default="in-accountability")
    ap.add_argument("--acct-name", default="Indiana Accountability System")
    args = ap.parse_args(argv)

    root = pathlib.Path(args.metadata)
    entered_at = dt.date.today().isoformat()

    # (jurisdiction_id, year) -> {"jurisdiction": {...}, "targets": [...]}
    buckets: dict[tuple, dict] = {}

    assessment_files = [
        p for p in sorted(root.rglob("*.json"))
        if load(p).get("schema_version") == ASSESSMENT_SCHEMA
    ]

    for path in assessment_files:
        rec = load(path)
        targets = rec.pop("achievement_targets", None)
        if not targets:
            continue
        jid = rec["jurisdiction"]["id"]
        year = rec["administration"]["year"]
        sid = rec["assessment_system"]["id"]
        key = (jid, year)
        bucket = buckets.setdefault(key, {"jurisdiction": rec["jurisdiction"], "targets": []})
        for content_area, tgt in targets.items():
            bucket["targets"].append({
                "assessment_system_id": sid,
                "content_area": content_area,
                "label": tgt.get("label"),
                "semantics": tgt.get("semantics"),
                "basis": tgt.get("basis"),
                "comparison": tgt.get("comparison"),
                **({"per_grade_scale_score": tgt["per_grade_scale_score"]}
                   if tgt.get("per_grade_scale_score") is not None else {}),
                **({"level_value": tgt["level_value"]}
                   if tgt.get("level_value") is not None else {}),
                **({"provenance": tgt["provenance"]}
                   if tgt.get("provenance") is not None else {}),
            })
        # rewrite assessment sidecar without achievement_targets
        dump(path, rec)
        print(f"  stripped targets from {path.relative_to(root.parent)}")

    written = 0
    for (jid, year), bucket in sorted(buckets.items()):
        # drop null-valued optional keys for cleanliness
        clean_targets = [{k: v for k, v in t.items() if v is not None} for t in bucket["targets"]]
        # low confidence if any target advertises preliminary/placeholder provenance
        blob = json.dumps(clean_targets).lower()
        confidence = "low" if any(f in blob for f in ("preliminary", "placeholder", "scaffold")) else "medium"
        acct = {
            "schema_version": ACCT_SCHEMA,
            "status": "draft",
            "source_confidence": confidence,
            "provenance": {
                "entered_by": "migration:sgpc-foundry-accountability",
                "entered_at": entered_at,
                "last_verified_at": None,
                "changed_from_prior": None,
            },
            "jurisdiction": bucket["jurisdiction"],
            "accountability_system": {"id": args.acct_id, "name": args.acct_name},
            "administration": {"id": f"{args.acct_id}-{year}", "year": year},
            "targets": sorted(clean_targets, key=lambda t: (t["assessment_system_id"], t["content_area"])),
        }
        dest = root / jid / args.acct_id / f"{args.acct_id}-{year}.json"
        dump(dest, acct)
        print(f"  wrote {dest.relative_to(root.parent)}  ({len(clean_targets)} target(s))")
        written += 1

    print(f"Relocated targets into {written} accountability record(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
