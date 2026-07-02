#!/usr/bin/env python3
"""Author the demonstration jurisdictions (State C, State D) into the registry.

These mirror the two SGPc `testSGPc()` scenarios (`sgpcData_LONG_StateC`,
`sgpcData_LONG_StateD`), externalized as authored sidecars. Because the data is a
demonstration, we use the freedom to exercise schema features that real states
expose messily:

  State D (SD, sd-summative): a VERTICAL scale with a COVID gap -- no 2020
    administration (recorded as a first-class gap), proficiency_boundary targets.
  State C (SC, sc-summative): a mid-window SCALE TRANSITION -- a legacy scale in
    2013-2014 and a new, non-comparable scale from 2015, so the changelog gets
    real scale-break + cutscore-change signal; explicit scale_score exit targets.

Targets are authored in accountability records (ADR-002); cutscores/levels/scale
in assessment records. Everything lands as status=draft, source_confidence=low
(invented demonstration values). Re-runnable; overwrites the demo sidecars.

Usage:  python3 tools/seed_demo.py [--out metadata]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib

GRADES = [str(g) for g in range(3, 9)]
LEVELS = ["Level 1", "Level 2", "Level 3", "Level 4"]
PROFICIENT = [False, False, True, True]
ENTERED_AT = dt.date.today().isoformat()


def flat(cuts):
    return {g: list(cuts) for g in GRADES}


def flat_ss(value):
    return {g: value for g in GRADES}


def levels_for(content_areas):
    return {ca: {"labels": list(LEVELS), "proficient": list(PROFICIENT)} for ca in content_areas}


# --- State D: vertical scale, COVID gap (no 2020) -----------------------------
SD_YEARS = ["2018", "2019", "2021", "2022", "2023", "2024", "2025"]
SD_CUTS = {"MATHEMATICS": [2400, 2530, 2650], "READING": [2400, 2540, 2650]}


def state_d():
    jur = {"id": "SD", "name": "Demonstration State D", "type": "state"}
    assess, acct = [], []
    for year in SD_YEARS:
        comparability = {"administered": True, "scale_transition": False,
                         "comparable_to_prior_year": True}
        if year == "2021":
            comparability["notes"] = ("2020 not administered (COVID-19); a 2019->2021 "
                                      "growth span crosses the gap.")
        assess.append({
            "schema_version": "amr.assessment_system.v1", "status": "draft",
            "source_confidence": "low",
            "provenance": {"entered_by": "seed:demo", "entered_at": ENTERED_AT,
                           "last_verified_at": None, "changed_from_prior": None},
            "jurisdiction": jur,
            "assessment_system": {"id": "sd-summative",
                                  "name": "Demonstration Summative Assessment (State D)",
                                  "family": "DEMO-SUMMATIVE", "assessment_type": "state-summative"},
            "administration": {"id": f"sd-summative-{year}", "year": year,
                               "vendor": "Demonstration", "window": "annual"},
            "assessment_program": {"assessment_name": "Demonstration Summative Assessment (State D)",
                                   "abbreviation": "DEMO-D"},
            "comparability": comparability,
            "content_areas": [{"id": ca, "label": ca.title(), "vertical_scale": True,
                               "scale_name": "State D Vertical Scale"} for ca in SD_CUTS],
            "achievement_levels": levels_for(SD_CUTS),
            "cutscores": {ca: flat(cuts) for ca, cuts in SD_CUTS.items()},
        })
        acct.append(accountability_record(
            jur, "sd-accountability", "Demonstration State D Accountability System", year,
            [target("sd-summative", ca, "Proficient Cut", "proficiency",
                    "proficiency_boundary", None,
                    "derived from cutscores + proficient mask (demonstration)")
             for ca in SD_CUTS]))
    return assess, acct


# --- State C: scale transition at 2015 ----------------------------------------
SC_OLD_YEARS = ["2013", "2014"]
SC_NEW_YEARS = ["2015", "2016", "2017"]
SC_OLD_CUTS = {"ELA": [400, 470, 540], "MATHEMATICS": [380, 450, 520]}
SC_NEW_CUTS = {"ELA": [600, 700, 770], "MATHEMATICS": [560, 680, 760]}
SC_OLD_EXIT = {"ELA": 500, "MATHEMATICS": 490}
SC_NEW_EXIT = {"ELA": 730, "MATHEMATICS": 720}


def state_c():
    jur = {"id": "SC", "name": "Demonstration State C", "type": "state"}
    assess, acct = [], []
    for year in SC_OLD_YEARS + SC_NEW_YEARS:
        old = year in SC_OLD_YEARS
        cuts = SC_OLD_CUTS if old else SC_NEW_CUTS
        exit_ss = SC_OLD_EXIT if old else SC_NEW_EXIT
        scale_name = "State C Legacy Scale" if old else "State C Scale"
        comparability = {"administered": True, "scale_transition": False,
                         "comparable_to_prior_year": year != "2013"}
        if year == "2015":
            comparability.update({"scale_transition": True, "comparable_to_prior_year": False,
                                  "prior_scale_name": "State C Legacy Scale",
                                  "notes": "New scale adopted in 2015; not comparable to prior-scale scores."})
        assess.append({
            "schema_version": "amr.assessment_system.v1", "status": "draft",
            "source_confidence": "low",
            "provenance": {"entered_by": "seed:demo", "entered_at": ENTERED_AT,
                           "last_verified_at": None,
                           "changed_from_prior": "scale transition" if year == "2015" else None},
            "jurisdiction": jur,
            "assessment_system": {"id": "sc-summative",
                                  "name": "Demonstration Summative Assessment (State C)",
                                  "family": "DEMO-SUMMATIVE", "assessment_type": "state-summative"},
            "administration": {"id": f"sc-summative-{year}", "year": year,
                               "vendor": "Demonstration", "window": "annual"},
            "assessment_program": {"assessment_name": "Demonstration Summative Assessment (State C)",
                                   "abbreviation": "DEMO-C"},
            "comparability": comparability,
            "content_areas": [{"id": ca, "label": ca, "vertical_scale": False,
                               "scale_name": scale_name} for ca in cuts],
            "achievement_levels": levels_for(cuts),
            "cutscores": {ca: flat(c) for ca, c in cuts.items()},
        })
        acct.append(accountability_record(
            jur, "sc-accountability", "Demonstration State C Accountability System", year,
            [target("sc-summative", ca, "Exit Target", "exit", "scale_score",
                    flat_ss(exit_ss[ca]), "explicit per-grade scale (demonstration; ELP-like exit)")
             for ca in cuts]))
    return assess, acct


def target(system_id, content_area, label, semantics, basis, per_grade, provenance):
    t = {"assessment_system_id": system_id, "content_area": content_area, "label": label,
         "semantics": semantics, "basis": basis, "comparison": ">=", "provenance": provenance}
    if per_grade is not None:
        t["per_grade_scale_score"] = per_grade
    return t


def accountability_record(jur, acct_id, acct_name, year, targets):
    return {
        "schema_version": "amr.accountability_system.v1", "status": "draft",
        "source_confidence": "low",
        "provenance": {"entered_by": "seed:demo", "entered_at": ENTERED_AT,
                       "last_verified_at": None, "changed_from_prior": None},
        "jurisdiction": jur,
        "accountability_system": {"id": acct_id, "name": acct_name},
        "administration": {"id": f"{acct_id}-{year}", "year": year},
        "targets": targets,
    }


def write(out: pathlib.Path, rec: dict) -> None:
    jid = rec["jurisdiction"]["id"]
    sid = (rec["assessment_system"]["id"] if "assessment_system" in rec
           else rec["accountability_system"]["id"])
    path = out / jid / sid / f"{rec['administration']['id']}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rec, indent=2, ensure_ascii=False) + "\n")
    return path


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="metadata")
    args = ap.parse_args(argv)
    out = pathlib.Path(args.out)

    n = 0
    for builder in (state_d, state_c):
        assess, acct = builder()
        for rec in assess + acct:
            write(out, rec)
            n += 1
    print(f"Seeded {n} demonstration sidecar(s) for SD + SC.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
