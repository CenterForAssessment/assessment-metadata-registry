/**
 * Read-only SQLite access + SELECT-only guard — TypeScript port of serve/mcp/registry_db.py
 * (ADR-012 Tier 1). The registry DB is a disposable projection of the canonical JSON
 * sidecars; it is opened read-only and every SQL-accepting surface passes the SELECT-only
 * guard as defense-in-depth. A fresh connection per call picks up a swapped DB file.
 *
 * Backed by `node:sqlite` (Node >= 22.5, stable and flag-free on 24) rather than
 * better-sqlite3: no native build step, so nothing to compile in the Vercel build image.
 * `year` columns are TEXT, so every year parameter is bound as a string — see rowsOf callers.
 */
import { DatabaseSync } from "node:sqlite";
import { existsSync } from "node:fs";
import path from "node:path";

/** The single SQLite handle type the rest of the surface passes around. */
export type Db = DatabaseSync;

export const MAX_ROWS = 5000; // hard cap on rows returned to an agent

export class RegistryError extends Error {
  constructor(
    public code: string,
    message: string,
  ) {
    super(message);
    this.name = "RegistryError";
  }
}

export function dbPath(): string {
  const p =
    process.env.AMRR_REGISTRY_DB ?? path.join(process.cwd(), "data", "registry.sqlite");
  if (!existsSync(p)) {
    throw new RegistryError(
      "db_not_found",
      `registry DB not found at '${p}' (set AMRR_REGISTRY_DB, or run \`make build\` and copy build/registry.sqlite to serve/vercel/data/)`,
    );
  }
  return p;
}

/** A read-only connection. `readOnly: true` makes every write fail at the SQLite layer
 *  (and implies the file must already exist). */
export function connect(): Db {
  return new DatabaseSync(dbPath(), { readOnly: true });
}

// Whole-word write / DDL / transaction keywords. readonly already blocks writes; this
// gives a clear up-front rejection. \b won't fire inside identifiers like `created_at`
// (underscore is a word char), so schema columns are safe. Mirrors registry_db.py.
const FORBIDDEN =
  /\b(attach|detach|insert|update|delete|drop|alter|create|replace|vacuum|reindex|pragma|analyze|begin|commit|rollback|savepoint)\b/i;
const LEADING = /^\s*(--[^\n]*\n|\/\*[\s\S]*?\*\/|\s)+/;

/** Return the single-statement SQL if it is a read-only SELECT/WITH, else throw. */
export function assertSelectOnly(sql: string): string {
  const s = (sql ?? "").trim();
  if (!s) throw new RegistryError("empty_sql", "SQL is empty");
  const core = s.endsWith(";") ? s.slice(0, -1).trimEnd() : s;
  if (core.includes(";")) {
    throw new RegistryError("multiple_statements", "only a single SELECT statement is allowed");
  }
  // strip leading comments/whitespace and any opening parens before the keyword
  let prev: string | null = null;
  let head = core;
  while (prev !== head) {
    prev = head;
    head = head.replace(LEADING, "");
  }
  head = head.replace(/^\(+/, "").toLowerCase();
  if (!(head.startsWith("select") || head.startsWith("with"))) {
    throw new RegistryError("not_select", "only SELECT (or WITH … SELECT) queries are allowed");
  }
  if (FORBIDDEN.test(core)) {
    throw new RegistryError("forbidden_keyword", "query contains a non-read-only keyword");
  }
  return core;
}

export type Row = Record<string, unknown>;

export function provenance(db: Db): Record<string, string> {
  const rows = db.prepare("select key, value from registry_meta").all() as unknown as {
    key: string;
    value: string;
  }[];
  return Object.fromEntries(rows.map((r) => [r.key, r.value]));
}

export function rowsOf(db: Db, sql: string, params: Row = {}): Row[] {
  const stmt = db.prepare(sql);
  // node:sqlite rejects an empty named-parameter object for a statement with no
  // placeholders, so only bind when there is something to bind.
  const iter = (
    Object.keys(params).length > 0 ? stmt.iterate(params as never) : stmt.iterate()
  ) as Iterable<Row>;
  const out: Row[] = [];
  for (const row of iter) {
    if (out.length >= MAX_ROWS) break;
    out.push(row);
  }
  return out;
}

export interface Envelope extends Row {
  git_sha: string | undefined;
  schema_version: string | undefined;
  row_count: number;
  truncated: boolean;
  rows: Row[];
}

/** Wrap rows with registry provenance so every answer is SHA-stamped. */
export function envelope(db: Db, rows: Row[], extra: Row = {}): Envelope {
  const meta = provenance(db);
  return {
    git_sha: meta["git_sha"],
    schema_version: meta["schema_version"],
    row_count: rows.length,
    truncated: rows.length >= MAX_ROWS,
    rows,
    ...extra,
  };
}

export function errorEnvelope(e: RegistryError): { error: { code: string; message: string } } {
  return { error: { code: e.code, message: e.message } };
}
