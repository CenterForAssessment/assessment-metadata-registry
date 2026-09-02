#!/usr/bin/env python3
"""One-time authoring pass: Indiana ISTEP / ISTEP+ / ILEARN draft records.

Numbers come from the maintainer's SGPstateData[['IN']][['Achievement']][['Cutscores']]
paste (2026-09-01) plus the IDOE ILEARN Cut Scores PDF (SBOE 2019-07-25).
All records are status=draft. Do not promote from this script.

Writes:
  assessment-metadata-registry/metadata/IN/{istep,istep-plus,ilearn}/*.json
  SGPc-foundry/Indiana/state-summative/metadata/*.json
"""
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REG_ROOT = HERE.parents[1]
FOUNDRY_META = (
    REG_ROOT.parent / "SGPc-foundry" / "Indiana" / "state-summative" / "metadata"
)

# --- cut tables (SGPstateData + IDOE PDF) -----------------------------------

ISTEP_ELA = {  # commented ELA=list, 2 cuts, 2009-2014
    "3": [417, 521],
    "4": [437, 535],
    "5": [468, 548],
    "6": [478, 579],
    "7": [501, 584],
    "8": [508, 627],
}
ISTEP_MATH = {
    "3": [413, 513],
    "4": [445, 541],
    "5": [463, 556],
    "6": [487, 590],
    "7": [511, 603],
    "8": [537, 641],
}
ISTEP_PLUS_ELA = {  # ELA.2015
    "3": [428, 500],
    "4": [456, 529],
    "5": [486, 546],
    "6": [502, 572],
    "7": [516, 592],
    "8": [537, 617],
    "10": [244, 292],
}
ISTEP_PLUS_MATH = {
    "3": [425, 480],
    "4": [458, 508],
    "5": [480, 536],
    "6": [510, 560],
    "7": [533, 578],
    "8": [554, 595],
    "10": [271, 339],
}
# 2019 operational 3-level collapse (ELA.2019 / MATHEMATICS.2019): At, Above
ILEARN_2019_ELA = {
    "3": [5460, 5515],
    "4": [5493, 5547],
    "5": [5524, 5595],
    "6": [5544, 5604],
    "7": [5568, 5629],
    "8": [5577, 5638],
    "10": [244, 292],  # ISTEP+ Grade 10 scale; intake endpoints [100, 400]
}
ILEARN_2019_MATH = {
    "3": [6425, 6488],
    "4": [6474, 6541],
    "5": [6510, 6566],
    "6": [6545, 6605],
    "7": [6562, 6625],
    "8": [6590, 6651],
    "10": [271, 339],
}
# Official 4-level IDOE 2019-07-25 (= active ELA=/MATHEMATICS= in SGPstateData)
ILEARN_4_ELA = {
    "3": [5416, 5460, 5515],
    "4": [5444, 5493, 5547],
    "5": [5472, 5524, 5595],
    "6": [5492, 5544, 5604],
    "7": [5507, 5568, 5629],
    "8": [5511, 5577, 5638],
}
ILEARN_4_MATH = {
    "3": [6382, 6425, 6488],
    "4": [6429, 6474, 6541],
    "5": [6453, 6510, 6566],
    "6": [6488, 6545, 6605],
    "7": [6493, 6562, 6625],
    "8": [6509, 6590, 6651],
}
# 2026 new standards on the 2019 ILEARN scale (ELA.2026 / MATHEMATICS.2026)
ILEARN_2026_ELA = {
    "3": [5356, 5460, 5547],
    "4": [5395, 5491, 5595],
    "5": [5419, 5521, 5623],
    "6": [5443, 5543, 5640],
    "7": [5458, 5559, 5657],
    "8": [5473, 5574, 5671],
}
ILEARN_2026_MATH = {
    "3": [6356, 6426, 6534],
    "4": [6412, 6469, 6579],
    "5": [6443, 6509, 6603],
    "6": [6471, 6544, 6640],
    "7": [6469, 6562, 6657],
    "8": [6476, 6591, 6694],
}
ILEARN_BOUNDS_ELA = {
    "3": (5060, 5760),
    "4": (5090, 5810),
    "5": (5110, 5850),
    "6": (5130, 5870),
    "7": (5130, 5890),
    "8": (5150, 5920),
}
ILEARN_BOUNDS_MATH = {
    "3": (6080, 6730),
    "4": (6100, 6800),
    "5": (6110, 6850),
    "6": (6110, 6870),
    "7": (6120, 6920),
    "8": (6120, 6950),
}

ISTEP_LABELS = ["Did Not Pass", "Pass", "Pass +"]
ILEARN_3_LABELS = [
    "Below/Approaching Proficiency",
    "At Proficiency",
    "Above Proficiency",
]
ILEARN_4_LABELS = [
    "Below Proficiency",
    "Approaching Proficiency",
    "At Proficiency",
    "Above Proficiency",
]

IDOE = "https://www.in.gov/doe/"
ILEARN_CUTS_PDF = "https://www.in.gov/doe/files/ILEARN-Cut-Scores.pdf"
SGPSTATEDATA = (
    "SGP::SGPstateData[['IN']][['Achievement']][['Cutscores']] "
    "(DBetebenner/SGPstateData; maintainer paste 2026-09-01)"
)
GRADE_NOTE = (
    "ISTEP / ISTEP+ / ILEARN tested grades start at 3. The filed-not-fixed "
    "grade-encoding-split analysis (K vs 0) does not apply."
)

JUR = {"id": "IN", "name": "Indiana", "type": "state"}


def dump(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")
    print(f"  wrote {path}")


def scale_bounds(ela_cuts, math_cuts) -> dict:
    out = {"ELA": {}, "MATHEMATICS": {}}
    for g, (lo, hi) in ILEARN_BOUNDS_ELA.items():
        if g in ela_cuts:
            out["ELA"][g] = {
                "loss": lo,
                "hoss": hi,
                "source": "official",
                "notes": "LOSS/HOSS from IDOE ILEARN Cut Scores PDF (updated 2019-08-26).",
            }
    for g, (lo, hi) in ILEARN_BOUNDS_MATH.items():
        if g in math_cuts:
            out["MATHEMATICS"][g] = {
                "loss": lo,
                "hoss": hi,
                "source": "official",
                "notes": "LOSS/HOSS from IDOE ILEARN Cut Scores PDF (updated 2019-08-26).",
            }
    return out


def cut_source(cuts, value: str) -> dict:
    return {g: value for g in cuts}


def content_areas(scale_ela: str, scale_math: str, grades: list[str], note: str) -> list:
    return [
        {
            "id": "ELA",
            "label": "English/Language Arts",
            "vertical_scale": False,
            "scale_name": scale_ela,
            "enrollment": {
                "intended_enrollment_grade": "fixed",
                "enrolled_grades_tested": grades,
                "note": note,
            },
        },
        {
            "id": "MATHEMATICS",
            "label": "Mathematics",
            "vertical_scale": False,
            "scale_name": scale_math,
            "enrollment": {
                "intended_enrollment_grade": "fixed",
                "enrolled_grades_tested": grades,
                "note": note,
            },
        },
    ]


def levels(labels: list[str], proficient_from: str, notes: str | None = None) -> dict:
    block = {"labels": labels, "proficient_from": proficient_from}
    if notes:
        block["notes"] = notes
    return {"ELA": dict(block), "MATHEMATICS": dict(block)}


def org(name: str, abbr: str) -> dict:
    return {
        "assessment_name": name,
        "abbreviation": abbr,
        "organization": {
            "name": "Indiana Department of Education",
            "abbreviation": "IDOE",
            "url": IDOE,
        },
    }


def foundry_levels(labels: list[str], proficient_from: str) -> dict:
    idx = labels.index(proficient_from)
    mask = [i >= idx for i in range(len(labels))]
    block = {"labels": labels, "proficient": mask}
    return {"ELA": dict(block), "MATHEMATICS": dict(block)}


def foundry_sidecar(
    *,
    admin_id: str,
    year: str,
    system_id: str,
    system_name: str,
    family: str,
    program_name: str,
    abbr: str,
    scale_ela: str,
    scale_math: str,
    labels: list[str],
    proficient_from: str,
    cuts_ela: dict,
    cuts_math: dict,
    provenance: str,
    notes: str,
) -> dict:
    return {
        "schema_version": "sgpc.assessment_metadata.v0.1",
        "jurisdiction": JUR,
        "assessment_system": {
            "id": system_id,
            "name": system_name,
            "family": family,
            "assessment_type": "state-summative",
        },
        "administration": {
            "id": admin_id,
            "year": year,
            "vendor": "Indiana Department of Education",
            "window": "annual",
            "csem_ref": None,
        },
        "assessment_program": org(program_name, abbr),
        "cutscores_provenance": provenance,
        "content_areas": [
            {
                "id": "ELA",
                "label": "English/Language Arts",
                "vertical_scale": False,
                "scale_name": scale_ela,
            },
            {
                "id": "MATHEMATICS",
                "label": "Mathematics",
                "vertical_scale": False,
                "scale_name": scale_math,
            },
        ],
        "achievement_levels": foundry_levels(labels, proficient_from),
        "cutscores": {"ELA": cuts_ela, "MATHEMATICS": cuts_math},
        "notes": notes,
    }


def write_istep() -> None:
    grades = ["3", "4", "5", "6", "7", "8"]
    citation = (
        f"{SGPSTATEDATA}, historical commented ELA= / MATHEMATICS= blocks "
        f"(2 cuts, Did Not Pass / Pass / Pass +). Independent IDOE PDF not "
        f"located this session."
    )
    notes = (
        "ISTEP grades 3–8, three achievement levels. "
        + GRADE_NOTE
        + " Cuts are draft: transcribed from the commented SGPstateData "
        "block; confirm against an IDOE ISTEP cut-score memo before review."
    )
    for year in range(2009, 2015):
        y = str(year)
        admin = f"istep-in-{y}"
        rec = {
            "schema_version": "amr.assessment.v2",
            "status": "draft",
            "source_confidence": "low",
            "provenance": {
                "source_citation": citation,
                "entered_by": "ai:sgpc-harness",
                "entered_at": "2026-09-01",
                "last_verified_at": None,
                "verified_by": None,
                "changed_from_prior": (
                    None
                    if year == 2009
                    else "Same ISTEP cuts and three-level scheme as the prior year."
                ),
            },
            "source_documents": [
                {
                    "title": "SGP::SGPstateData Indiana Achievement$Cutscores (historical commented ISTEP block)",
                    "url": None,
                }
            ],
            "jurisdiction": JUR,
            "assessment_system": {
                "id": "istep",
                "name": "Indiana Statewide Testing for Educational Progress",
                "family": "ISTEP",
                "assessment_type": "summative",
            },
            "administration": {
                "id": admin,
                "year": y,
                "vendor": "Indiana Department of Education",
                "window": "annual",
                "csem_ref": None,
            },
            "assessment_program": org(
                "Indiana Statewide Testing for Educational Progress", "ISTEP"
            ),
            "cutscores_provenance": citation,
            "comparability": {
                "comparable_to_prior_year": year > 2009,
                "scale_transition": False,
                "prior_scale_name": "ISTEP ELA/Mathematics scale" if year > 2009 else None,
                "administered": True,
                "notes": "Continuous ISTEP administration; no scale break inside 2009–2014.",
            },
            "content_areas": content_areas(
                "ISTEP ELA scale", "ISTEP Mathematics scale", grades, GRADE_NOTE
            ),
            "achievement_levels": levels(
                ISTEP_LABELS,
                "Pass",
                "Three-level ISTEP scheme observed in Indiana_Data_LONG$ACHIEVEMENT_LEVEL for 2009–2014.",
            ),
            "cutscores": {"ELA": ISTEP_ELA, "MATHEMATICS": ISTEP_MATH},
            "cutscores_source": {
                "ELA": cut_source(ISTEP_ELA, "provisional"),
                "MATHEMATICS": cut_source(ISTEP_MATH, "provisional"),
            },
            "notes": notes,
        }
        dump(REG_ROOT / "metadata/IN/istep" / f"{admin}.json", rec)
        dump(
            FOUNDRY_META / f"{admin}.json",
            foundry_sidecar(
                admin_id=admin,
                year=y,
                system_id="istep",
                system_name="Indiana Statewide Testing for Educational Progress",
                family="ISTEP",
                program_name="Indiana Statewide Testing for Educational Progress",
                abbr="ISTEP",
                scale_ela="ISTEP ELA scale",
                scale_math="ISTEP Mathematics scale",
                labels=ISTEP_LABELS,
                proficient_from="Pass",
                cuts_ela=ISTEP_ELA,
                cuts_math=ISTEP_MATH,
                provenance=citation,
                notes=notes,
            ),
        )


def write_istep_plus() -> None:
    citation = (
        f"{SGPSTATEDATA}, ELA.2015 / MATHEMATICS.2015 blocks. Indiana State "
        f"Board of Education set the 2015 ISTEP+ pass line on 2015-10-28 "
        f"(IndyStar; Chalkbeat). Independent IDOE numeric PDF not located "
        f"this session."
    )
    for year in range(2015, 2019):
        y = str(year)
        admin = f"istep-plus-in-{y}"
        grades = ["3", "4", "5", "6", "7", "8"]
        ela = dict(ISTEP_PLUS_ELA)
        math = dict(ISTEP_PLUS_MATH)
        if year < 2017:
            ela.pop("10")
            math.pop("10")
        else:
            grades = grades + ["10"]
        notes = (
            "ISTEP+ three-level scheme (Did Not Pass / Pass / Pass +) after "
            "the 2015 college-and-career-ready standards reset. "
            + GRADE_NOTE
            + (
                " Grade 10 ISTEP+ ELA/Mathematics appear in 2017–2018; those "
                "cuts are on a separate hundreds-scale (not the 3–8 scale)."
                if year >= 2017
                else ""
            )
        )
        rec = {
            "schema_version": "amr.assessment.v2",
            "status": "draft",
            "source_confidence": "medium",
            "provenance": {
                "source_citation": citation,
                "entered_by": "ai:sgpc-harness",
                "entered_at": "2026-09-01",
                "last_verified_at": None,
                "verified_by": None,
                "changed_from_prior": (
                    "2015 ISTEP+ new academic standards and cut scores; not comparable to ISTEP 2014."
                    if year == 2015
                    else "Same ISTEP+ 2015 cuts; grade 10 added."
                    if year == 2017
                    else "Same ISTEP+ cuts and three-level scheme as the prior year."
                ),
            },
            "source_documents": [
                {
                    "title": "SGP::SGPstateData Indiana Achievement$Cutscores (ELA.2015 / MATHEMATICS.2015)",
                    "url": None,
                },
                {
                    "title": "State Board of Ed sets pass/fail line for ISTEP (IndyStar, 2015-10-28)",
                    "url": "https://www.indystar.com/story/news/education/2015/10/28/state-board-ed-sets-passfail-line/74747118/",
                },
            ],
            "jurisdiction": JUR,
            "assessment_system": {
                "id": "istep-plus",
                "name": "Indiana Statewide Testing for Educational Progress-Plus",
                "family": "ISTEP+",
                "assessment_type": "summative",
            },
            "administration": {
                "id": admin,
                "year": y,
                "vendor": "Indiana Department of Education",
                "window": "annual",
                "csem_ref": None,
            },
            "assessment_program": org(
                "Indiana Statewide Testing for Educational Progress-Plus", "ISTEP+"
            ),
            "cutscores_provenance": citation,
            "comparability": {
                "comparable_to_prior_year": year > 2015,
                "scale_transition": year == 2015,
                "prior_scale_name": "ISTEP ELA/Mathematics scale" if year == 2015 else "ISTEP+ ELA/Mathematics scale",
                "administered": True,
                "notes": (
                    "2015 ISTEP+ reset to college-and-career-ready Indiana Academic Standards; SBOE set cuts 2015-10-28. Scores are not comparable to ISTEP 2014."
                    if year == 2015
                    else "Continuous ISTEP+ administration on the 2015 scale."
                ),
            },
            "content_areas": content_areas(
                "ISTEP+ ELA scale",
                "ISTEP+ Mathematics scale",
                grades,
                GRADE_NOTE
                + (
                    " Grade 10 uses a separate ISTEP+ Grade 10 scale."
                    if year >= 2017
                    else ""
                ),
            ),
            "achievement_levels": levels(
                ISTEP_LABELS,
                "Pass",
                "Three-level ISTEP+ scheme observed in Indiana_Data_LONG$ACHIEVEMENT_LEVEL for 2015–2018.",
            ),
            "cutscores": {"ELA": ela, "MATHEMATICS": math},
            "cutscores_source": {
                "ELA": cut_source(ela, "provisional"),
                "MATHEMATICS": cut_source(math, "provisional"),
            },
            "notes": notes,
        }
        dump(REG_ROOT / "metadata/IN/istep-plus" / f"{admin}.json", rec)
        dump(
            FOUNDRY_META / f"{admin}.json",
            foundry_sidecar(
                admin_id=admin,
                year=y,
                system_id="istep-plus",
                system_name="Indiana Statewide Testing for Educational Progress-Plus",
                family="ISTEP+",
                program_name="Indiana Statewide Testing for Educational Progress-Plus",
                abbr="ISTEP+",
                scale_ela="ISTEP+ ELA scale",
                scale_math="ISTEP+ Mathematics scale",
                labels=ISTEP_LABELS,
                proficient_from="Pass",
                cuts_ela=ela,
                cuts_math=math,
                provenance=citation,
                notes=notes,
            ),
        )


def write_ilearn_2019() -> None:
    y = "2019"
    admin = "ilearn-in-2019"
    citation = (
        f"IDOE, 'ILEARN Cut Scores (Grades 3-8 and Biology)', SBOE approved "
        f"2019-07-25, PDF updated 2019-08-26: {ILEARN_CUTS_PDF}. This record "
        f"uses the official At Proficiency and Above Proficiency cuts only "
        f"(ELA.2019 / MATHEMATICS.2019 in {SGPSTATEDATA}): the 2019 LONG "
        f"collapses Below Proficiency and Approaching Proficiency into "
        f"'Below/Approaching Proficiency' (SGPstateData note 2019-09-17). "
        f"Grade 10 uses ISTEP+ Grade 10 hundreds-scale cuts "
        f"(ELA 244/292, Math 271/339); intake endpoints [100, 400]."
    )
    notes = (
        "2019 is the first ILEARN administration (program change from ISTEP+). "
        "Official IDOE standard setting produced four levels; the Indiana LONG "
        "and SGPstateData operational SGP-target work report three. At and "
        "Above cuts for grades 3–8 match the IDOE PDF exactly. Grade 10 ELA/"
        "Mathematics in this LONG are on the ISTEP+ Grade 10 scale (100–400); "
        "those two-cut vectors come from SGPstateData GRADE_10. "
        + GRADE_NOTE
        + " Maintainer treats ILEARN as a Smarter Balanced-based CCR "
        "assessment (AIR/Cambium). Confirm against the ILEARN technical "
        "report before promotion — IDOE materials describe ILEARN as an "
        "Indiana Academic Standards CCR assessment, not an SBAC member form."
    )
    bounds = scale_bounds(ILEARN_2019_ELA, ILEARN_2019_MATH)
    g10 = {
        "loss": 100,
        "hoss": 400,
        "source": "derived",
        "notes": "ISTEP+ Grade 10 scale; intake 2019 grade-10 endpoints [100, 400].",
    }
    bounds["ELA"]["10"] = dict(g10)
    bounds["MATHEMATICS"]["10"] = dict(g10)
    rec = {
        "schema_version": "amr.assessment.v2",
        "status": "draft",
        "source_confidence": "medium",
        "provenance": {
            "source_citation": citation,
            "entered_by": "ai:sgpc-harness",
            "entered_at": "2026-09-01",
            "last_verified_at": None,
            "verified_by": None,
            "changed_from_prior": (
                "New assessment system (ILEARN) replacing ISTEP+. Scale "
                "transition. 2019 operational labels are the 3-level collapse "
                "of the official 4-level IDOE scheme."
            ),
        },
        "source_documents": [
            {"title": "IDOE ILEARN Cut Scores (Grades 3-8 and Biology)", "url": ILEARN_CUTS_PDF},
            {
                "title": "IDOE Spring 2019 ILEARN results release (2019-08-27)",
                "url": "https://content.govdelivery.com/attachments/INDOE/2019/08/27/file_attachments/1274135/2019%20ILEARN%20PR%20%28Embargoed%29%202_Final.pdf",
            },
            {
                "title": "SGP::SGPstateData Indiana Achievement$Cutscores (ELA.2019 / MATHEMATICS.2019)",
                "url": None,
            },
        ],
        "jurisdiction": JUR,
        "assessment_system": {
            "id": "ilearn",
            "name": "Indiana Learning Evaluation Assessment Readiness Network",
            "family": "ILEARN",
            "assessment_type": "summative",
        },
        "administration": {
            "id": admin,
            "year": y,
            "vendor": "AIR / Cambium Assessment",
            "window": "annual",
            "csem_ref": None,
        },
        "assessment_program": org(
            "Indiana Learning Evaluation Assessment Readiness Network", "ILEARN"
        ),
        "cutscores_provenance": citation,
        "comparability": {
            "comparable_to_prior_year": False,
            "scale_transition": True,
            "prior_scale_name": "ISTEP+ ELA/Mathematics scale",
            "administered": True,
            "notes": (
                "Program change ISTEP+ → ILEARN. Rank-based copula growth remains "
                "valid across the scale break (Sklar); mark the 2018→2019 cohorts "
                "as a scale_transition on the drift panel (engine ADR-019)."
            ),
        },
        "content_areas": content_areas(
            "ILEARN ELA scale",
            "ILEARN Mathematics scale",
            ["3", "4", "5", "6", "7", "8", "10"],
            GRADE_NOTE
            + " Grade 10 is the ISTEP+ Grade 10 scale (hundreds), not the ILEARN 3–8 scale.",
        ),
        "achievement_levels": levels(
            ILEARN_3_LABELS,
            "At Proficiency",
            "2019 LONG reports three levels (Below/Approaching, At, Above). Official IDOE 4-level Approaching cuts (ELA 5416 / Math 6382 in grade 3, and grade analogues) are in the IDOE PDF but are not the reporting scheme in this file.",
        ),
        "cutscores": {"ELA": ILEARN_2019_ELA, "MATHEMATICS": ILEARN_2019_MATH},
        "cutscores_source": {
            "ELA": {**cut_source(ILEARN_2019_ELA, "official"), "10": "provisional"},
            "MATHEMATICS": {**cut_source(ILEARN_2019_MATH, "official"), "10": "provisional"},
        },
        "scale_bounds": bounds,
        "notes": notes,
    }
    dump(REG_ROOT / "metadata/IN/ilearn" / f"{admin}.json", rec)
    dump(
        FOUNDRY_META / f"{admin}.json",
        foundry_sidecar(
            admin_id=admin,
            year=y,
            system_id="ilearn",
            system_name="Indiana Learning Evaluation Assessment Readiness Network",
            family="ILEARN",
            program_name="Indiana Learning Evaluation Assessment Readiness Network",
            abbr="ILEARN",
            scale_ela="ILEARN ELA scale",
            scale_math="ILEARN Mathematics scale",
            labels=ILEARN_3_LABELS,
            proficient_from="At Proficiency",
            cuts_ela=ILEARN_2019_ELA,
            cuts_math=ILEARN_2019_MATH,
            provenance=citation,
            notes=notes,
        ),
    )


def write_ilearn_2020() -> None:
    admin = "ilearn-in-2020"
    rec = {
        "schema_version": "amr.assessment.v2",
        "status": "draft",
        "source_confidence": "high",
        "provenance": {
            "source_citation": "ILEARN was not administered in 2020 (COVID-19).",
            "entered_by": "ai:sgpc-harness",
            "entered_at": "2026-09-01",
            "last_verified_at": None,
            "verified_by": None,
            "changed_from_prior": "Administration gap; no 2020 ILEARN scores.",
        },
        "source_documents": [
            {
                "title": "IDOE ILEARN Cut Scores (Grades 3-8 and Biology) — 2019 scale unused in 2020",
                "url": ILEARN_CUTS_PDF,
            }
        ],
        "jurisdiction": JUR,
        "assessment_system": {
            "id": "ilearn",
            "name": "Indiana Learning Evaluation Assessment Readiness Network",
            "family": "ILEARN",
            "assessment_type": "summative",
        },
        "administration": {
            "id": admin,
            "year": "2020",
            "vendor": "AIR / Cambium Assessment",
            "window": "annual",
            "csem_ref": None,
        },
        "assessment_program": org(
            "Indiana Learning Evaluation Assessment Readiness Network", "ILEARN"
        ),
        "comparability": {
            "comparable_to_prior_year": False,
            "scale_transition": False,
            "prior_scale_name": "ILEARN ELA/Mathematics scale",
            "administered": False,
            "notes": "COVID-19 administration gap. No scores; no cutscores authored.",
        },
        "content_areas": content_areas(
            "ILEARN ELA scale",
            "ILEARN Mathematics scale",
            ["3", "4", "5", "6", "7", "8"],
            GRADE_NOTE + " Not administered in 2020.",
        ),
        "notes": "Placeholder administration record so the 2019→2021 gap is queryable. No cutscores.",
    }
    dump(REG_ROOT / "metadata/IN/ilearn" / f"{admin}.json", rec)


def write_ilearn_4level(years: list[int]) -> None:
    citation = (
        f"IDOE, 'ILEARN Cut Scores (Grades 3-8 and Biology)', SBOE approved "
        f"2019-07-25: {ILEARN_CUTS_PDF}. Identical to the active "
        f"ELA= / MATHEMATICS= 3-cut vectors in {SGPSTATEDATA}."
    )
    notes = (
        "Four ILEARN levels (Below / Approaching / At / Above Proficiency) "
        "as reported in Indiana_Data_LONG$ACHIEVEMENT_LEVEL for 2021–2025. "
        "Cuts and LOSS/HOSS match the 2019 IDOE PDF. "
        + GRADE_NOTE
    )
    for year in years:
        y = str(year)
        admin = f"ilearn-in-{y}"
        rec = {
            "schema_version": "amr.assessment.v2",
            "status": "draft",
            "source_confidence": "medium",
            "provenance": {
                "source_citation": citation,
                "entered_by": "ai:sgpc-harness",
                "entered_at": "2026-09-01",
                "last_verified_at": None,
                "verified_by": None,
                "changed_from_prior": (
                    "Return after the 2020 COVID gap; four-level ILEARN scheme (the 2019 3-level collapse is not reused)."
                    if year == 2021
                    else "Same official 2019 ILEARN 4-level cuts as the prior year."
                ),
            },
            "source_documents": [
                {"title": "IDOE ILEARN Cut Scores (Grades 3-8 and Biology)", "url": ILEARN_CUTS_PDF},
                {
                    "title": "SGP::SGPstateData Indiana Achievement$Cutscores (active ELA= / MATHEMATICS= 3-cut lists)",
                    "url": None,
                },
            ],
            "jurisdiction": JUR,
            "assessment_system": {
                "id": "ilearn",
                "name": "Indiana Learning Evaluation Assessment Readiness Network",
                "family": "ILEARN",
                "assessment_type": "summative",
            },
            "administration": {
                "id": admin,
                "year": y,
                "vendor": "Cambium Assessment",
                "window": "annual",
                "csem_ref": None,
            },
            "assessment_program": org(
                "Indiana Learning Evaluation Assessment Readiness Network", "ILEARN"
            ),
            "cutscores_provenance": citation,
            "comparability": {
                "comparable_to_prior_year": year > 2021,
                "scale_transition": False,
                "prior_scale_name": "ILEARN ELA/Mathematics scale",
                "administered": True,
                "notes": (
                    "2021 returns after the 2020 COVID gap; scale is the 2019 ILEARN scale, not a new standard setting."
                    if year == 2021
                    else "Continuous ILEARN administration on the 2019 scale."
                ),
            },
            "content_areas": content_areas(
                "ILEARN ELA scale",
                "ILEARN Mathematics scale",
                ["3", "4", "5", "6", "7", "8"],
                GRADE_NOTE,
            ),
            "achievement_levels": levels(ILEARN_4_LABELS, "At Proficiency"),
            "cutscores": {"ELA": ILEARN_4_ELA, "MATHEMATICS": ILEARN_4_MATH},
            "cutscores_source": {
                "ELA": cut_source(ILEARN_4_ELA, "official"),
                "MATHEMATICS": cut_source(ILEARN_4_MATH, "official"),
            },
            "scale_bounds": scale_bounds(ILEARN_4_ELA, ILEARN_4_MATH),
            "notes": notes,
        }
        dump(REG_ROOT / "metadata/IN/ilearn" / f"{admin}.json", rec)
        dump(
            FOUNDRY_META / f"{admin}.json",
            foundry_sidecar(
                admin_id=admin,
                year=y,
                system_id="ilearn",
                system_name="Indiana Learning Evaluation Assessment Readiness Network",
                family="ILEARN",
                program_name="Indiana Learning Evaluation Assessment Readiness Network",
                abbr="ILEARN",
                scale_ela="ILEARN ELA scale",
                scale_math="ILEARN Mathematics scale",
                labels=ILEARN_4_LABELS,
                proficient_from="At Proficiency",
                cuts_ela=ILEARN_4_ELA,
                cuts_math=ILEARN_4_MATH,
                provenance=citation,
                notes=notes,
            ),
        )


def write_ilearn_2026() -> None:
    y = "2026"
    admin = "ilearn-in-2026"
    citation = (
        f"{SGPSTATEDATA}, ELA.2026 / MATHEMATICS.2026: 2026 (new) standards "
        f"expressed on the 2019 ILEARN scale via equipercentile equating "
        f"(SGP_Sandbox/Indiana_2026_ILEARN_Scale_Change). Official new-scale "
        f"cuts (ELA.2026.NEW_SCALE / MATHEMATICS.2026.NEW_SCALE) are commented "
        f"and are for analyses reported on the new scale (>=2027), not this "
        f"transition year. IDOE announced SBOE review of new cut scores on "
        f"2026-08-11 (weekly announcement); a public numeric PDF for the "
        f"equated old-scale cuts was not located this session."
    )
    notes = (
        "2026 transition: scores in the Indiana LONG remain on the 2019 "
        "ILEARN scale (5000s/6100s); cuts are the new standards mapped onto "
        "that scale. Four-level labels match 2021–2025. Grade 10 cuts in "
        "SGPstateData (244/292, 271/339) are ISTEP+ Grade 10 leftovers and "
        "are not applied. Official new-scale cuts are not used here. "
        + GRADE_NOTE
    )
    rec = {
        "schema_version": "amr.assessment.v2",
        "status": "draft",
        "source_confidence": "low",
        "provenance": {
            "source_citation": citation,
            "entered_by": "ai:sgpc-harness",
            "entered_at": "2026-09-01",
            "last_verified_at": None,
            "verified_by": None,
            "changed_from_prior": (
                "New 2026 academic standards expressed on the 2019 ILEARN "
                "scale via equipercentile equating. Score scale is unchanged; "
                "cuts moved."
            ),
        },
        "source_documents": [
            {
                "title": "SGP::SGPstateData Indiana Achievement$Cutscores (ELA.2026 / MATHEMATICS.2026)",
                "url": None,
            },
            {
                "title": "IDOE Knowledge Hub weekly announcement (2026-06-12) — SBOE cut-score review 2026-08-11",
                "url": "https://idoe.atlassian.net/wiki/spaces/IKHTV/pages/2793897985/06+12+2026+Weekly+Announcement",
            },
            {"title": "IDOE ILEARN Cut Scores 2019 (prior scale LOSS/HOSS)", "url": ILEARN_CUTS_PDF},
        ],
        "jurisdiction": JUR,
        "assessment_system": {
            "id": "ilearn",
            "name": "Indiana Learning Evaluation Assessment Readiness Network",
            "family": "ILEARN",
            "assessment_type": "summative",
        },
        "administration": {
            "id": admin,
            "year": y,
            "vendor": "Cambium Assessment",
            "window": "annual",
            "csem_ref": None,
        },
        "assessment_program": org(
            "Indiana Learning Evaluation Assessment Readiness Network", "ILEARN"
        ),
        "cutscores_provenance": citation,
        "comparability": {
            "comparable_to_prior_year": True,
            "scale_transition": False,
            "prior_scale_name": "ILEARN ELA/Mathematics scale",
            "administered": True,
            "notes": (
                "Score scale is still the 2019 ILEARN scale. Cuts are new-standard "
                "locations on that scale. Not a 2018→2019-style program/scale break."
            ),
        },
        "content_areas": content_areas(
            "ILEARN ELA scale (2019; 2026 standards equated onto it)",
            "ILEARN Mathematics scale (2019; 2026 standards equated onto it)",
            ["3", "4", "5", "6", "7", "8"],
            GRADE_NOTE,
        ),
        "achievement_levels": levels(ILEARN_4_LABELS, "At Proficiency"),
        "cutscores": {"ELA": ILEARN_2026_ELA, "MATHEMATICS": ILEARN_2026_MATH},
        "cutscores_source": {
            "ELA": cut_source(ILEARN_2026_ELA, "derived"),
            "MATHEMATICS": cut_source(ILEARN_2026_MATH, "derived"),
        },
        "scale_bounds": scale_bounds(ILEARN_2026_ELA, ILEARN_2026_MATH),
        "notes": notes,
    }
    dump(REG_ROOT / "metadata/IN/ilearn" / f"{admin}.json", rec)
    dump(
        FOUNDRY_META / f"{admin}.json",
        foundry_sidecar(
            admin_id=admin,
            year=y,
            system_id="ilearn",
            system_name="Indiana Learning Evaluation Assessment Readiness Network",
            family="ILEARN",
            program_name="Indiana Learning Evaluation Assessment Readiness Network",
            abbr="ILEARN",
            scale_ela="ILEARN ELA scale (2019; 2026 standards equated onto it)",
            scale_math="ILEARN Mathematics scale (2019; 2026 standards equated onto it)",
            labels=ILEARN_4_LABELS,
            proficient_from="At Proficiency",
            cuts_ela=ILEARN_2026_ELA,
            cuts_math=ILEARN_2026_MATH,
            provenance=citation,
            notes=notes,
        ),
    )


def main() -> None:
    write_istep()
    write_istep_plus()
    write_ilearn_2019()
    write_ilearn_2020()
    write_ilearn_4level([2021, 2022, 2023, 2024, 2025])
    write_ilearn_2026()
    print("done")


if __name__ == "__main__":
    main()
