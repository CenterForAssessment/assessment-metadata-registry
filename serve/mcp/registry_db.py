"""Read-only SQLite access + SELECT-only guard for the registry MCP server (ADR-012).

The registry DB (`build/registry.sqlite`) is a disposable projection of the canonical
JSON sidecars. This module opens it `mode=ro` — SQLite rejects every write at the driver
level — and adds a SELECT-only guard on top as defense-in-depth with friendly errors. A
fresh connection per call picks up an atomically-swapped DB on the next request, so a
deploy never serves a half-written file.
"""
from __future__ import annotations

import os
import re
import sqlite3

MAX_ROWS = 5000  # hard cap on rows returned to an agent


class RegistryError(Exception):
    """A read-only-guard or DB-access failure, surfaced as a machine-readable envelope."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def db_path() -> str:
    path = os.environ.get("AMRR_REGISTRY_DB", "build/registry.sqlite")
    if not os.path.exists(path):
        raise RegistryError(
            "db_not_found",
            f"registry DB not found at '{path}' (set AMRR_REGISTRY_DB or run `make build`)",
        )
    return path


def connect() -> sqlite3.Connection:
    """A read-only connection. mode=ro makes every write fail at the SQLite layer."""
    uri = f"file:{os.path.abspath(db_path())}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5.0)
    conn.row_factory = sqlite3.Row
    return conn


# Whole-word write / DDL / transaction keywords. mode=ro already blocks writes; this
# gives a clear up-front rejection. \b won't fire inside identifiers like
# `created_at` (underscore is a word char), so schema columns are safe.
_FORBIDDEN = re.compile(
    r"\b(attach|detach|insert|update|delete|drop|alter|create|replace|"
    r"vacuum|reindex|pragma|analyze|begin|commit|rollback|savepoint)\b",
    re.IGNORECASE,
)
_LEADING = re.compile(r"^\s*(--[^\n]*\n|/\*.*?\*/|\s)+", re.DOTALL)


def assert_select_only(sql: str) -> str:
    """Return the single-statement SQL if it is a read-only SELECT/WITH, else raise."""
    s = (sql or "").strip()
    if not s:
        raise RegistryError("empty_sql", "SQL is empty")
    core = s[:-1].rstrip() if s.endswith(";") else s
    if ";" in core:
        raise RegistryError("multiple_statements", "only a single SELECT statement is allowed")
    # strip leading comments/whitespace and any opening parens before the keyword
    prev = None
    head = core
    while prev != head:
        prev = head
        head = _LEADING.sub("", head, count=1)
    head = head.lstrip("(").lower()
    if not (head.startswith("select") or head.startswith("with")):
        raise RegistryError("not_select", "only SELECT (or WITH … SELECT) queries are allowed")
    if _FORBIDDEN.search(core):
        raise RegistryError("forbidden_keyword", "query contains a non-read-only keyword")
    return core


def provenance(conn: sqlite3.Connection) -> dict:
    rows = conn.execute("select key, value from registry_meta").fetchall()
    return {r["key"]: r["value"] for r in rows}


def rows_of(conn: sqlite3.Connection, sql: str, params: dict | None = None) -> list[dict]:
    cur = conn.execute(sql, params or {})
    out: list[dict] = []
    for i, row in enumerate(cur):
        if i >= MAX_ROWS:
            break
        out.append(dict(row))
    return out


def envelope(conn: sqlite3.Connection, rows: list[dict], **extra) -> dict:
    """Wrap rows with registry provenance so every answer is SHA-stamped."""
    meta = provenance(conn)
    env = {
        "git_sha": meta.get("git_sha"),
        "schema_version": meta.get("schema_version"),
        "row_count": len(rows),
        "truncated": len(rows) >= MAX_ROWS,
        "rows": rows,
    }
    env.update(extra)
    return env


def error(e: RegistryError) -> dict:
    return {"error": {"code": e.code, "message": e.message}}
