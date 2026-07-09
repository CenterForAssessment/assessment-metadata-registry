"""Read-only MCP server for the Assessment Metadata Registry (Tier C, ADR-012).

Exposes query/compare tools over the derived, immutable `registry.sqlite` so Claude and
other agents can explore U.S. state assessment metadata. Read-only end to end: the DB is
opened mode=ro and every tool issues a SELECT. Each response carries the registry
`git_sha`, so an answer is provenance-stamped — but this is the LATEST build, not a
reproducibility pin (pin with `amrr::get_metadata(registry="github://…", ref=<SHA>)`).

Transports (set MCP_TRANSPORT):
  stdio (default)   local Claude Code:   python server.py
  streamable-http   VPS behind Caddy:    MCP_TRANSPORT=streamable-http python server.py
                    (streamable_http_path defaults to /mcp, matching the Caddy route)
"""
from __future__ import annotations

import os
import sqlite3
from typing import Optional

from mcp.server.fastmcp import FastMCP

import registry_db as db

TRANSPORT = os.environ.get("MCP_TRANSPORT", "stdio")
HOST = os.environ.get("MCP_HOST", "127.0.0.1")
PORT = int(os.environ.get("MCP_PORT", "8010"))

mcp = FastMCP(
    "assessment-metadata-registry",
    instructions=(
        "Read-only query tools over the U.S. state Assessment Metadata Registry "
        "(system-level metadata only: assessment systems, achievement levels, cutscores, "
        "vendors, vertical scales, accountability targets — no student/school microdata). "
        "Everything is year-keyed; content areas are UPPER-CASE (ELA, MATHEMATICS, "
        "READING, ELP_COMPOSITE); jurisdiction ids are upper-case (IN, SC, SD) and system "
        "ids lower-case (ilearn, wida-access). Call describe_schema() first. Every result "
        "is stamped with the registry git_sha and reflects the latest build, not a pin."
    ),
    host=HOST,
    port=PORT,
    stateless_http=True,
)

DIMENSIONS = {
    "achievement_levels": (
        "select jurisdiction_id, assessment_system_id, level_index, label, proficient "
        "from achievement_level where content_area = :ca and year = :yr {jur} "
        "order by jurisdiction_id, assessment_system_id, level_index"
    ),
    "cutscores": (
        "select jurisdiction_id, assessment_system_id, grade, level_index, lower_bound "
        "from cutscore where content_area = :ca and year = :yr {jur} "
        "order by jurisdiction_id, assessment_system_id, cast(grade as text), level_index"
    ),
    "vertical_scale": (
        "select jurisdiction_id, assessment_system_id, vertical_scale, scale_name "
        "from vertical_scale where content_area = :ca and year = :yr {jur} "
        "order by jurisdiction_id, assessment_system_id"
    ),
    "vendor": (
        "select a.jurisdiction_id, a.assessment_system_id, a.vendor "
        "from administration a join vertical_scale v "
        "  on a.jurisdiction_id = v.jurisdiction_id "
        " and a.assessment_system_id = v.assessment_system_id and a.year = v.year "
        "where v.content_area = :ca and a.year = :yr {jur} "
        "group by a.jurisdiction_id, a.assessment_system_id, a.vendor "
        "order by a.jurisdiction_id, a.assessment_system_id"
    ),
}


@mcp.tool()
def describe_schema() -> dict:
    """List the registry tables and their columns, plus build provenance (git_sha,
    built_at, schema_version). Call this first to learn the shape before querying."""
    try:
        conn = db.connect()
    except db.RegistryError as e:
        return db.error(e)
    with conn:
        names = [
            r["name"]
            for r in conn.execute(
                "select name from sqlite_master where type='table' "
                "and name not like 'sqlite_%' order by name"
            )
        ]
        tables = {t: [r["name"] for r in conn.execute(f"pragma table_info({t})")] for t in names}
        meta = db.provenance(conn)
    return {
        "git_sha": meta.get("git_sha"),
        "built_at": meta.get("built_at"),
        "schema_version": meta.get("schema_version"),
        "tables": tables,
    }


@mcp.tool()
def query_registry(sql: str) -> dict:
    """Run a single read-only SELECT (or WITH … SELECT) against the registry SQLite
    projection and return the rows in a git_sha-stamped envelope. Writes/DDL are rejected.
    Use describe_schema() first; content areas are UPPER-CASE. Results are capped."""
    try:
        core = db.assert_select_only(sql)
        conn = db.connect()
    except db.RegistryError as e:
        return db.error(e)
    try:
        with conn:
            return db.envelope(conn, db.rows_of(conn, core))
    except sqlite3.Error as e:
        return {"error": {"code": "sql_error", "message": str(e)}}


@mcp.tool()
def get_metadata(jurisdiction: str, system: str, year: int) -> dict:
    """Return metadata for one jurisdiction × assessment system × year: administration
    (vendor/window/status/citation), program names, comparability, and per-content-area
    vertical-scale facts. jurisdiction is upper-case (e.g. 'IN'); system lower-case
    (e.g. 'ilearn'); year an integer (e.g. 2024)."""
    p = {"jur": jurisdiction, "sys": system, "yr": str(year)}
    try:
        conn = db.connect()
    except db.RegistryError as e:
        return db.error(e)
    with conn:
        key = "where jurisdiction_id = :jur and assessment_system_id = :sys and year = :yr"
        admin = db.rows_of(conn, f"select * from administration {key}", p)
        if not admin:
            return db.error(
                db.RegistryError(
                    "not_found",
                    f"no record for {jurisdiction}/{system}/{year}",
                )
            )
        program = db.rows_of(conn, f"select * from assessment_program {key}", p)
        comparability = db.rows_of(conn, f"select * from comparability {key}", p)
        content_areas = db.rows_of(conn, f"select * from vertical_scale {key}", p)
        meta = db.provenance(conn)
    return {
        "git_sha": meta.get("git_sha"),
        "schema_version": meta.get("schema_version"),
        "jurisdiction": jurisdiction,
        "system": system,
        "year": year,
        "administration": admin[0],
        "program": program[0] if program else None,
        "comparability": comparability[0] if comparability else None,
        "content_areas": content_areas,
    }


@mcp.tool()
def compare_jurisdictions(
    jurisdictions: list[str],
    content_area: str,
    year: int,
    dimension: str = "achievement_levels",
) -> dict:
    """Compare a metadata dimension across jurisdictions for a content area and year.
    dimension ∈ {achievement_levels, cutscores, vendor, vertical_scale}. content_area is
    UPPER-CASE (ELA, MATHEMATICS, READING, ELP_COMPOSITE); year an integer. An empty
    jurisdictions list compares all."""
    if dimension not in DIMENSIONS:
        return db.error(
            db.RegistryError(
                "bad_dimension",
                f"dimension must be one of {sorted(DIMENSIONS)}",
            )
        )
    params: dict = {"ca": content_area, "yr": str(year)}
    jur_clause = ""
    if jurisdictions:
        keys = [f":j{i}" for i in range(len(jurisdictions))]
        jur_clause = f"and jurisdiction_id in ({', '.join(keys)})"
        # 'vendor' aliases the table as a.* — qualify its jurisdiction filter
        if dimension == "vendor":
            jur_clause = f"and a.jurisdiction_id in ({', '.join(keys)})"
        params.update({f"j{i}": j for i, j in enumerate(jurisdictions)})
    sql = DIMENSIONS[dimension].format(jur=jur_clause)
    try:
        conn = db.connect()
    except db.RegistryError as e:
        return db.error(e)
    with conn:
        return db.envelope(
            conn,
            db.rows_of(conn, sql, params),
            dimension=dimension,
            content_area=content_area,
            year=year,
        )


@mcp.tool()
def list_changes(
    jurisdiction: Optional[str] = None,
    system: Optional[str] = None,
    since_year: Optional[int] = None,
) -> dict:
    """List scale breaks / non-comparable years (comparability.scale_transition = 1 or
    comparable_to_prior_year = 0), optionally filtered by jurisdiction, system, and a
    minimum year. This is the SQL analogue of the registry changelog."""
    where = ["(scale_transition = 1 or comparable_to_prior_year = 0)"]
    params: dict = {}
    if jurisdiction:
        where.append("jurisdiction_id = :jur")
        params["jur"] = jurisdiction
    if system:
        where.append("assessment_system_id = :sys")
        params["sys"] = system
    if since_year is not None:
        where.append("year >= :yr")
        params["yr"] = str(since_year)
    sql = (
        "select jurisdiction_id, assessment_system_id, year, scale_transition, "
        "comparable_to_prior_year, prior_scale_name, notes from comparability "
        f"where {' and '.join(where)} "
        "order by jurisdiction_id, assessment_system_id, year"
    )
    try:
        conn = db.connect()
    except db.RegistryError as e:
        return db.error(e)
    with conn:
        return db.envelope(conn, db.rows_of(conn, sql, params))


if __name__ == "__main__":
    mcp.run(transport=TRANSPORT)
