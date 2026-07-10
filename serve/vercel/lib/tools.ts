/**
 * The five D1-contract tools — TypeScript port of serve/mcp/server.py (ADR-012 Tier 1).
 * Shared by the REST handlers (api/*.ts) and the MCP surface (lib/mcp.ts) so both expose
 * identical shapes. Read-only end to end; every response is git_sha-stamped.
 */
import * as db from "./registry-db.js";
import { MAX_ROWS, RegistryError, type Db } from "./registry-db.js";
import { ENDPOINTS } from "./endpoints.js";

type Result = Record<string, unknown>;

const DIMENSIONS: Record<string, string> = {
  achievement_levels:
    "select jurisdiction_id, assessment_system_id, level_index, label, proficient " +
    "from achievement_level where content_area = :ca and year = :yr {jur} " +
    "order by jurisdiction_id, assessment_system_id, level_index",
  cutscores:
    "select jurisdiction_id, assessment_system_id, grade, level_index, lower_bound " +
    "from cutscore where content_area = :ca and year = :yr {jur} " +
    "order by jurisdiction_id, assessment_system_id, cast(grade as text), level_index",
  vertical_scale:
    "select jurisdiction_id, assessment_system_id, vertical_scale, scale_name " +
    "from vertical_scale where content_area = :ca and year = :yr {jur} " +
    "order by jurisdiction_id, assessment_system_id",
  vendor:
    "select a.jurisdiction_id, a.assessment_system_id, a.vendor " +
    "from administration a join vertical_scale v " +
    "  on a.jurisdiction_id = v.jurisdiction_id " +
    " and a.assessment_system_id = v.assessment_system_id and a.year = v.year " +
    "where v.content_area = :ca and a.year = :yr {jur} " +
    "group by a.jurisdiction_id, a.assessment_system_id, a.vendor " +
    "order by a.jurisdiction_id, a.assessment_system_id",
};

export const DIMENSION_NAMES = Object.keys(DIMENSIONS).sort();

/** Run fn with a fresh read-only connection, mapping failures to error envelopes. */
function withDb(fn: (conn: Db) => Result): Result {
  let conn: Db;
  try {
    conn = db.connect();
  } catch (e) {
    if (e instanceof RegistryError) return db.errorEnvelope(e);
    throw e;
  }
  try {
    return fn(conn);
  } catch (e) {
    if (e instanceof RegistryError) return db.errorEnvelope(e);
    return { error: { code: "sql_error", message: (e as Error).message } };
  } finally {
    conn.close();
  }
}

/**
 * The service index: what this deployment exposes, and which registry build it is serving.
 *
 * Deliberately never fails. Every other surface returns 503 when the bundled DB is missing,
 * which is the right answer for a data endpoint — but the front door has to stay readable
 * during exactly that outage, or a caller who lands here learns nothing about why. So the
 * provenance block degrades to nulls and the underlying error is surfaced beside it, rather
 * than replacing the catalog with an error envelope. It is an index, not a health check.
 */
export function describeService(): Result {
  const provenance = withDb((conn) => {
    const meta = db.provenance(conn);
    return {
      git_sha: meta["git_sha"] ?? null,
      built_at: meta["built_at"] ?? null,
      schema_version: meta["schema_version"] ?? null,
    };
  });
  const failure = provenance["error"] as Result | undefined;

  return {
    service: "assessment-metadata-registry",
    description:
      "Read-only query contract over a disposable SQLite projection of the registry's " +
      "canonical JSON sidecars. Every answer is stamped with the commit SHA it was built from.",
    git_sha: failure ? null : provenance["git_sha"],
    built_at: failure ? null : provenance["built_at"],
    schema_version: failure ? null : provenance["schema_version"],
    // Present only when the registry DB could not be opened. Its absence means provenance
    // is real; do not read a null git_sha as "no commit".
    ...(failure ? { provenance_error: failure } : {}),
    max_rows: MAX_ROWS,
    compare_dimensions: DIMENSION_NAMES,
    endpoints: ENDPOINTS,
    source: "https://github.com/CenterForAssessment/assessment-metadata-registry",
  };
}

/** List tables + columns and build provenance. Call first to learn the shape. */
export function describeSchema(): Result {
  return withDb((conn) => {
    const names = (
      conn
        .prepare(
          "select name from sqlite_master where type='table' " +
            "and name not like 'sqlite_%' order by name",
        )
        .all() as unknown as { name: string }[]
    ).map((r) => r.name);
    const tables: Record<string, string[]> = {};
    for (const t of names) {
      // `t` comes from sqlite_master, not from user input — safe to interpolate.
      // node:sqlite has no .pragma(); a prepared PRAGMA returns rows just the same.
      const cols = conn.prepare(`pragma table_info(${t})`).all() as unknown as { name: string }[];
      tables[t] = cols.map((c) => c.name);
    }
    const meta = db.provenance(conn);
    return {
      git_sha: meta["git_sha"],
      built_at: meta["built_at"],
      schema_version: meta["schema_version"],
      tables,
    };
  });
}

/** Run a single read-only SELECT (or WITH … SELECT); rows in a git_sha-stamped envelope. */
export function queryRegistry(sql: string): Result {
  let core: string;
  try {
    core = db.assertSelectOnly(sql);
  } catch (e) {
    if (e instanceof RegistryError) return db.errorEnvelope(e);
    throw e;
  }
  return withDb((conn) => db.envelope(conn, db.rowsOf(conn, core)));
}

/** Metadata for one jurisdiction × assessment system × year. */
export function getMetadata(jurisdiction: string, system: string, year: number): Result {
  const p = { jur: jurisdiction, sys: system, yr: String(year) };
  return withDb((conn) => {
    const key =
      "where jurisdiction_id = :jur and assessment_system_id = :sys and year = :yr";
    const admin = db.rowsOf(conn, `select * from administration ${key}`, p);
    if (admin.length === 0) {
      return db.errorEnvelope(
        new RegistryError("not_found", `no record for ${jurisdiction}/${system}/${year}`),
      );
    }
    const program = db.rowsOf(conn, `select * from assessment_program ${key}`, p);
    const comparability = db.rowsOf(conn, `select * from comparability ${key}`, p);
    const contentAreas = db.rowsOf(conn, `select * from vertical_scale ${key}`, p);
    const meta = db.provenance(conn);
    return {
      git_sha: meta["git_sha"],
      schema_version: meta["schema_version"],
      jurisdiction,
      system,
      year,
      administration: admin[0],
      program: program[0] ?? null,
      comparability: comparability[0] ?? null,
      content_areas: contentAreas,
    };
  });
}

/** Compare a metadata dimension across jurisdictions for a content area and year. */
export function compareJurisdictions(
  jurisdictions: string[],
  contentArea: string,
  year: number,
  dimension = "achievement_levels",
): Result {
  const template = DIMENSIONS[dimension];
  if (!template) {
    return db.errorEnvelope(
      new RegistryError("bad_dimension", `dimension must be one of ${DIMENSION_NAMES.join(", ")}`),
    );
  }
  const params: db.Row = { ca: contentArea, yr: String(year) };
  let jurClause = "";
  if (jurisdictions.length > 0) {
    const keys = jurisdictions.map((_, i) => `:j${i}`);
    jurClause = `and jurisdiction_id in (${keys.join(", ")})`;
    // 'vendor' aliases the table as a.* — qualify its jurisdiction filter
    if (dimension === "vendor") jurClause = `and a.jurisdiction_id in (${keys.join(", ")})`;
    jurisdictions.forEach((j, i) => {
      params[`j${i}`] = j;
    });
  }
  const sql = template.replace("{jur}", jurClause);
  return withDb((conn) =>
    db.envelope(conn, db.rowsOf(conn, sql, params), {
      dimension,
      content_area: contentArea,
      year,
    }),
  );
}

/** Scale breaks / non-comparable years — the SQL analogue of the registry changelog. */
export function listChanges(
  jurisdiction?: string | null,
  system?: string | null,
  sinceYear?: number | null,
): Result {
  const where = ["(scale_transition = 1 or comparable_to_prior_year = 0)"];
  const params: db.Row = {};
  if (jurisdiction) {
    where.push("jurisdiction_id = :jur");
    params["jur"] = jurisdiction;
  }
  if (system) {
    where.push("assessment_system_id = :sys");
    params["sys"] = system;
  }
  if (sinceYear !== null && sinceYear !== undefined) {
    where.push("year >= :yr");
    params["yr"] = String(sinceYear);
  }
  const sql =
    "select jurisdiction_id, assessment_system_id, year, scale_transition, " +
    "comparable_to_prior_year, prior_scale_name, notes from comparability " +
    `where ${where.join(" and ")} ` +
    "order by jurisdiction_id, assessment_system_id, year";
  return withDb((conn) => db.envelope(conn, db.rowsOf(conn, sql, params)));
}
