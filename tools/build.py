#!/usr/bin/env python3
"""Derive the registry query layer (Tier B) from the authored sidecars (Tier A).

Handles two authored record types, routed by `schema_version`:
  amr.assessment_system.v1      -> identity, scales, levels, cutscores
  amr.accountability_system.v1  -> achievement TARGETS (state policy), cross-linked to
                                   an assessment system + content area

Emits, under `build/` (git-ignored, regenerated every run):

  build/manifest.json                 provenance: git SHA (reproducibility pin), built_at,
                                      schema versions, counts, per-file sha256
  build/index.json                    flat: one row per jurisdiction x system x year x CA
  build/changelog.json                year-over-year diffs (assessment fields + targets)
  build/targets.json                  flat accountability targets (cross-linked)
  build/dist/<JUR>.json               per-jurisdiction bundle (all records, both types)
  build/dist/<JUR>/<system>.json      per-system bundle (assessment OR accountability)
  build/tables/vendor_by_year.json    derived cross-cutting views
  build/tables/vertical_scale.json
  build/registry.sqlite               self-contained SQLite projection (amr.registry.v1)

Every emitted bundle carries a `_registry` provenance block. DERIVED, never canonical.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile

ASSESSMENT_SCHEMAS = {"amr.assessment_system.v1", "sgpc.assessment_metadata.v0.1"}
ACCT_SCHEMA = "amr.accountability_system.v1"
DDL_PATH_DEFAULT = "schemas/sql/amr-registry.v1.sql"


def is_assessment(rec: dict) -> bool:
    return rec.get("schema_version") in ASSESSMENT_SCHEMAS


def is_accountability(rec: dict) -> bool:
    return rec.get("schema_version") == ACCT_SCHEMA


def system_id(rec: dict) -> str:
    return (rec["assessment_system"]["id"] if is_assessment(rec)
            else rec["accountability_system"]["id"])


# --------------------------------------------------------------------------- provenance
def git_sha(repo: pathlib.Path) -> dict:
    try:
        sha = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                             capture_output=True, text=True, check=True).stdout.strip()
        dirty = bool(subprocess.run(["git", "-C", str(repo), "status", "--porcelain"],
                                    capture_output=True, text=True, check=True).stdout.strip())
        return {"sha": sha, "dirty": dirty}
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {"sha": None, "dirty": None}


def as_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("true", "1", "yes")


# ------------------------------------------------------------------------------- loading
def load_records(metadata_root: pathlib.Path) -> list[dict]:
    records = []
    for path in sorted(metadata_root.rglob("*.json")):
        rec = json.loads(path.read_text())
        rec["_source_path"] = str(path.relative_to(metadata_root.parent))
        records.append(rec)
    return records


# ------------------------------------------------------------------------- derived views
def build_index(records: list[dict]) -> list[dict]:
    rows = []
    for rec in (r for r in records if is_assessment(r)):
        jur, sys_, adm = rec["jurisdiction"], rec["assessment_system"], rec["administration"]
        levels = rec.get("achievement_levels") or {}
        comp = rec.get("comparability") or {}
        for ca in rec.get("content_areas", []):
            ca_id = ca["id"]
            rows.append({
                "jurisdiction_id": jur["id"], "jurisdiction_name": jur["name"],
                "assessment_system_id": sys_["id"], "assessment_system_name": sys_["name"],
                "assessment_type": sys_["assessment_type"], "year": adm["year"],
                "content_area": ca_id, "vertical_scale": bool(ca.get("vertical_scale", False)),
                "scale_name": ca.get("scale_name"), "vendor": adm.get("vendor"),
                "n_levels": len((levels.get(ca_id) or {}).get("labels") or []),
                "has_cutscores": ca_id in (rec.get("cutscores") or {}),
                "scale_transition": comp.get("scale_transition"),
                "comparable_to_prior_year": comp.get("comparable_to_prior_year"),
                "status": rec.get("status"), "source_confidence": rec.get("source_confidence"),
                "source_path": rec["_source_path"],
            })
    return sorted(rows, key=lambda r: (r["jurisdiction_id"], r["assessment_system_id"],
                                       r["year"], r["content_area"]))


def build_targets(records: list[dict]) -> list[dict]:
    """Flat accountability targets, cross-linked to their assessment system."""
    rows = []
    for rec in (r for r in records if is_accountability(r)):
        jur, acct, adm = rec["jurisdiction"], rec["accountability_system"], rec["administration"]
        for t in rec.get("targets", []):
            rows.append({
                "jurisdiction_id": jur["id"],
                "accountability_system_id": acct["id"],
                "assessment_system_id": t["assessment_system_id"],
                "content_area": t["content_area"], "year": adm["year"],
                "semantics": t.get("semantics"), "basis": t.get("basis"),
                "comparison": t.get("comparison"), "label": t.get("label"),
                "has_per_grade_scale_score": bool(t.get("per_grade_scale_score")),
            })
    return sorted(rows, key=lambda r: (r["jurisdiction_id"], r["accountability_system_id"],
                                       r["assessment_system_id"], r["content_area"], r["year"]))


def build_vendor_by_year(records: list[dict]) -> list[dict]:
    rows = [{"jurisdiction_id": r["jurisdiction"]["id"],
             "assessment_system_id": r["assessment_system"]["id"],
             "year": r["administration"]["year"], "vendor": r["administration"].get("vendor")}
            for r in records if is_assessment(r)]
    return sorted(rows, key=lambda r: (r["jurisdiction_id"], r["assessment_system_id"], r["year"]))


def build_vertical_scale(records: list[dict]) -> list[dict]:
    rows = []
    for r in (x for x in records if is_assessment(x)):
        for ca in r.get("content_areas", []):
            rows.append({"jurisdiction_id": r["jurisdiction"]["id"],
                         "assessment_system_id": r["assessment_system"]["id"],
                         "content_area": ca["id"], "year": r["administration"]["year"],
                         "vertical_scale": bool(ca.get("vertical_scale", False)),
                         "scale_name": ca.get("scale_name")})
    return sorted(rows, key=lambda r: (r["jurisdiction_id"], r["assessment_system_id"],
                                       r["content_area"], r["year"]))


def build_changelog(records: list[dict]) -> list[dict]:
    events = []

    # assessment-field diffs per (jurisdiction, assessment_system)
    a_series: dict[tuple, list[dict]] = {}
    for r in (x for x in records if is_assessment(x)):
        a_series.setdefault((r["jurisdiction"]["id"], r["assessment_system"]["id"]), []).append(r)
    for (jid, sid), recs in sorted(a_series.items()):
        recs = sorted(recs, key=lambda r: r["administration"]["year"])
        for prev, cur in zip(recs, recs[1:]):
            base = {"record_type": "assessment", "jurisdiction_id": jid,
                    "assessment_system_id": sid,
                    "year_from": prev["administration"]["year"],
                    "year_to": cur["administration"]["year"]}
            if prev["administration"].get("vendor") != cur["administration"].get("vendor"):
                events.append({**base, "field": "vendor",
                               "from": prev["administration"].get("vendor"),
                               "to": cur["administration"].get("vendor")})
            pv = {c["id"]: bool(c.get("vertical_scale")) for c in prev.get("content_areas", [])}
            cv = {c["id"]: bool(c.get("vertical_scale")) for c in cur.get("content_areas", [])}
            for ca in sorted(set(pv) | set(cv)):
                if pv.get(ca) != cv.get(ca):
                    events.append({**base, "content_area": ca, "field": "vertical_scale",
                                   "from": pv.get(ca), "to": cv.get(ca)})
            pl, cl = prev.get("achievement_levels") or {}, cur.get("achievement_levels") or {}
            for ca in sorted(set(pl) | set(cl)):
                if (pl.get(ca) or {}).get("labels") != (cl.get(ca) or {}).get("labels"):
                    events.append({**base, "content_area": ca, "field": "achievement_levels",
                                   "from": (pl.get(ca) or {}).get("labels"),
                                   "to": (cl.get(ca) or {}).get("labels")})
            pc, cc = prev.get("cutscores") or {}, cur.get("cutscores") or {}
            for ca in sorted(set(pc) | set(cc)):
                if pc.get(ca) != cc.get(ca):
                    events.append({**base, "content_area": ca, "field": "cutscores",
                                   "from": pc.get(ca), "to": cc.get(ca)})

    # target diffs per (jurisdiction, accountability_system, assessment_system, content_area)
    def target_map(rec):
        return {(t["assessment_system_id"], t["content_area"]): t for t in rec.get("targets", [])}

    b_series: dict[tuple, list[dict]] = {}
    for r in (x for x in records if is_accountability(x)):
        b_series.setdefault((r["jurisdiction"]["id"], r["accountability_system"]["id"]), []).append(r)
    for (jid, aid), recs in sorted(b_series.items()):
        recs = sorted(recs, key=lambda r: r["administration"]["year"])
        for prev, cur in zip(recs, recs[1:]):
            pm, cm = target_map(prev), target_map(cur)
            for (sid, ca) in sorted(set(pm) | set(cm)):
                p, c = pm.get((sid, ca), {}), cm.get((sid, ca), {})
                fields = ("semantics", "basis", "comparison", "per_grade_scale_score", "level_value")
                if {k: p.get(k) for k in fields} != {k: c.get(k) for k in fields}:
                    events.append({
                        "record_type": "accountability", "jurisdiction_id": jid,
                        "accountability_system_id": aid, "assessment_system_id": sid,
                        "content_area": ca, "field": "target",
                        "year_from": prev["administration"]["year"],
                        "year_to": cur["administration"]["year"],
                        "from": {k: p.get(k) for k in fields if p.get(k) is not None} or None,
                        "to": {k: c.get(k) for k in fields if c.get(k) is not None} or None})
    return events


# ---------------------------------------------------------------------------- sqlite
def build_sqlite(records, db_path, ddl_path, provenance) -> None:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="amr-build-")) / "registry.sqlite"
    con = sqlite3.connect(tmp)
    try:
        con.executescript(ddl_path.read_text())
        for k, v in (("git_sha", provenance.get("sha")),
                     ("built_at", provenance["built_at"]),
                     ("schema_version", "amr.registry.v1")):
            con.execute("INSERT INTO registry_meta(key, value) VALUES (?, ?)", (k, v))

        seen_jur, seen_sys, seen_acct = set(), set(), set()
        for r in records:
            jur = r["jurisdiction"]
            if jur["id"] not in seen_jur:
                con.execute("INSERT OR REPLACE INTO jurisdiction VALUES (?,?,?,?,?)",
                            (jur["id"], jur["name"], jur["type"], jur.get("nces_id"), jur.get("fips")))
                seen_jur.add(jur["id"])

            if is_assessment(r):
                sys_, adm = r["assessment_system"], r["administration"]
                if sys_["id"] not in seen_sys:
                    con.execute("INSERT OR REPLACE INTO assessment_system VALUES (?,?,?,?)",
                                (sys_["id"], sys_["name"], sys_["family"], sys_["assessment_type"]))
                    seen_sys.add(sys_["id"])
                prov = r.get("provenance") or {}
                con.execute("INSERT OR REPLACE INTO administration VALUES (?,?,?,?,?,?,?,?,?,?)",
                            (jur["id"], sys_["id"], adm["year"], adm.get("id"), adm.get("vendor"),
                             adm.get("window"), adm.get("csem_ref"), r.get("status"),
                             r.get("source_confidence"), prov.get("source_citation")))
                prog = r.get("assessment_program") or {}
                org = prog.get("organization") or {}
                con.execute("INSERT OR REPLACE INTO assessment_program VALUES (?,?,?,?,?,?,?,?)",
                            (jur["id"], sys_["id"], adm["year"], prog.get("assessment_name"),
                             prog.get("abbreviation"), org.get("name"), org.get("abbreviation"),
                             org.get("url")))
                comp = r.get("comparability")
                if comp:
                    tri = lambda v: None if v is None else (1 if v else 0)
                    con.execute("INSERT OR REPLACE INTO comparability VALUES (?,?,?,?,?,?,?,?)",
                                (jur["id"], sys_["id"], adm["year"], tri(comp.get("administered")),
                                 tri(comp.get("scale_transition")),
                                 tri(comp.get("comparable_to_prior_year")),
                                 comp.get("prior_scale_name"), comp.get("notes")))
                for ca in r.get("content_areas", []):
                    con.execute("INSERT OR REPLACE INTO vertical_scale VALUES (?,?,?,?,?,?,?)",
                                (jur["id"], sys_["id"], ca["id"], adm["year"],
                                 1 if ca.get("vertical_scale") else 0, ca.get("scale_name"),
                                 ca.get("label")))
                for ca, block in (r.get("achievement_levels") or {}).items():
                    labels = block.get("labels") or []
                    prof = block.get("proficient") or [None] * len(labels)
                    for i, label in enumerate(labels):
                        p = prof[i] if i < len(prof) else None
                        con.execute("INSERT OR REPLACE INTO achievement_level VALUES (?,?,?,?,?,?,?)",
                                    (jur["id"], sys_["id"], ca, adm["year"], i, label,
                                     None if p is None else (1 if as_bool(p) else 0)))
                for ca, grades in (r.get("cutscores") or {}).items():
                    for grade, cuts in (grades or {}).items():
                        for i, lb in enumerate(cuts, start=1):
                            con.execute("INSERT OR REPLACE INTO cutscore VALUES (?,?,?,?,?,?,?)",
                                        (jur["id"], sys_["id"], ca, adm["year"], str(grade), i, float(lb)))

            elif is_accountability(r):
                acct, adm = r["accountability_system"], r["administration"]
                if acct["id"] not in seen_acct:
                    con.execute("INSERT OR REPLACE INTO accountability_system VALUES (?,?,?)",
                                (acct["id"], acct["name"], acct.get("framework")))
                    seen_acct.add(acct["id"])
                for t in r.get("targets", []):
                    con.execute(
                        "INSERT OR REPLACE INTO accountability_target VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                        (jur["id"], acct["id"], t["assessment_system_id"], t["content_area"],
                         adm["year"], t.get("label"), t.get("semantics"), t.get("basis"),
                         t.get("comparison"), r.get("status"), r.get("source_confidence")))
                    for grade, ss in (t.get("per_grade_scale_score") or {}).items():
                        con.execute(
                            "INSERT OR REPLACE INTO accountability_target_scale_score VALUES (?,?,?,?,?,?,?)",
                            (jur["id"], acct["id"], t["assessment_system_id"], t["content_area"],
                             adm["year"], str(grade), float(ss)))
        con.commit()
    finally:
        con.close()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    db_path.write_bytes(tmp.read_bytes())
    shutil.rmtree(tmp.parent, ignore_errors=True)


# --------------------------------------------------------------------------------- io
def clean_record(rec: dict) -> dict:
    return {k: v for k, v in rec.items() if k != "_source_path"}


def write_json(path: pathlib.Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def sha256_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--metadata", default="metadata")
    ap.add_argument("--out", default="build")
    ap.add_argument("--ddl", default=DDL_PATH_DEFAULT)
    args = ap.parse_args(argv)

    metadata_root = pathlib.Path(args.metadata)
    out = pathlib.Path(args.out)
    repo = metadata_root.parent if metadata_root.name == "metadata" else pathlib.Path(".")

    records = load_records(metadata_root)
    if not records:
        sys.stderr.write(f"No sidecars under {metadata_root}\n")
        return 1

    prov = git_sha(repo)
    prov["built_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    stamp = {"schema_version": "amr.registry.v1", "git_sha": prov.get("sha"),
             "dirty": prov.get("dirty"), "built_at": prov["built_at"]}

    if out.exists():
        for p in sorted(out.rglob("*"), reverse=True):
            try:
                p.unlink() if p.is_file() else p.rmdir()
            except OSError:
                pass

    write_json(out / "index.json", {"_registry": stamp, "records": build_index(records)})
    write_json(out / "targets.json", {"_registry": stamp, "rows": build_targets(records)})
    write_json(out / "changelog.json", {"_registry": stamp, "events": build_changelog(records)})
    write_json(out / "tables" / "vendor_by_year.json",
               {"_registry": stamp, "rows": build_vendor_by_year(records)})
    write_json(out / "tables" / "vertical_scale.json",
               {"_registry": stamp, "rows": build_vertical_scale(records)})

    by_jur: dict[str, list[dict]] = {}
    by_sys: dict[tuple, list[dict]] = {}
    for r in records:
        jid = r["jurisdiction"]["id"]
        by_jur.setdefault(jid, []).append(clean_record(r))
        by_sys.setdefault((jid, system_id(r)), []).append(clean_record(r))
    for jid, recs in by_jur.items():
        write_json(out / "dist" / f"{jid}.json",
                   {"_registry": stamp, "jurisdiction_id": jid, "records": recs})
    for (jid, sid), recs in by_sys.items():
        write_json(out / "dist" / jid / f"{sid}.json",
                   {"_registry": stamp, "jurisdiction_id": jid, "system_id": sid, "records": recs})

    build_sqlite(records, out / "registry.sqlite", pathlib.Path(args.ddl), prov)

    n_assess = sum(is_assessment(r) for r in records)
    n_acct = sum(is_accountability(r) for r in records)
    files = {str(p.relative_to(out)): sha256_file(p)
             for p in sorted(out.rglob("*")) if p.is_file() and p.name != "manifest.json"}
    write_json(out / "manifest.json", {
        "_registry": stamp, "n_records": len(records),
        "n_assessment_records": n_assess, "n_accountability_records": n_acct,
        "n_jurisdictions": len(by_jur), "files": files,
    })

    dirty = " (DIRTY working tree — not publishable)" if prov.get("dirty") else ""
    print(f"Built {len(records)} record(s) [{n_assess} assessment, {n_acct} accountability] "
          f"across {len(by_jur)} jurisdiction(s) @ {prov.get('sha') or 'no-git'}{dirty}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
