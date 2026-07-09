/**
 * MCP surface (ADR-012 Tier 1): the same five tools as serve/mcp/server.py, served
 * STATELESS over streamable-http — a fresh McpServer + transport per request, no session
 * state, which is what a serverless function requires. Tool shapes mirror
 * serve/mcp/tool_schemas.json (the dual REST+MCP contract's single source of truth).
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  compareJurisdictions,
  describeSchema,
  getMetadata,
  listChanges,
  queryRegistry,
} from "./tools.js";

const INSTRUCTIONS =
  "Read-only query tools over the U.S. state Assessment Metadata Registry " +
  "(system-level metadata only: assessment systems, achievement levels, cutscores, " +
  "vendors, vertical scales, accountability targets — no student/school microdata). " +
  "Everything is year-keyed; content areas are UPPER-CASE (ELA, MATHEMATICS, READING, " +
  "ELP_COMPOSITE); jurisdiction ids are upper-case (IN, SC, SD) and system ids " +
  "lower-case (ilearn, wida-access). Call describe_schema() first. Every result is " +
  "stamped with the registry git_sha and reflects the latest build, not a pin.";

function asContent(result: Record<string, unknown>) {
  return { content: [{ type: "text" as const, text: JSON.stringify(result) }] };
}

/** Build a fresh server instance (stateless: one per request). */
export function buildServer(): McpServer {
  const server = new McpServer(
    { name: "assessment-metadata-registry", version: "0.1.0" },
    { instructions: INSTRUCTIONS },
  );

  server.tool(
    "describe_schema",
    "List the registry tables and their columns, plus build provenance (git_sha, " +
      "built_at, schema_version). Call this first to learn the shape before querying.",
    {},
    async () => asContent(describeSchema()),
  );

  server.tool(
    "query_registry",
    "Run a single read-only SELECT (or WITH … SELECT) against the registry SQLite " +
      "projection and return the rows in a git_sha-stamped envelope. Writes/DDL are " +
      "rejected. Use describe_schema() first; content areas are UPPER-CASE. Results are capped.",
    { sql: z.string().describe("a single SELECT statement") },
    async ({ sql }) => asContent(queryRegistry(sql)),
  );

  server.tool(
    "get_metadata",
    "Return metadata for one jurisdiction × assessment system × year: administration " +
      "(vendor/window/status/citation), program names, comparability, and per-content-area " +
      "vertical-scale facts. jurisdiction is upper-case (e.g. 'IN'); system lower-case " +
      "(e.g. 'ilearn'); year an integer (e.g. 2024).",
    {
      jurisdiction: z.string().describe("upper-case id, e.g. IN"),
      system: z.string().describe("lower-case id, e.g. ilearn"),
      year: z.number().int().describe("e.g. 2024"),
    },
    async ({ jurisdiction, system, year }) => asContent(getMetadata(jurisdiction, system, year)),
  );

  server.tool(
    "compare_jurisdictions",
    "Compare a metadata dimension across jurisdictions for a content area and year. " +
      "dimension ∈ {achievement_levels, cutscores, vendor, vertical_scale}. content_area " +
      "is UPPER-CASE (ELA, MATHEMATICS, READING, ELP_COMPOSITE); year an integer. An " +
      "empty jurisdictions list compares all.",
    {
      jurisdictions: z.array(z.string()).describe("upper-case ids; empty = all"),
      content_area: z.string().describe("UPPER-CASE, e.g. ELA"),
      year: z.number().int(),
      dimension: z
        .enum(["achievement_levels", "cutscores", "vendor", "vertical_scale"])
        .default("achievement_levels"),
    },
    async ({ jurisdictions, content_area, year, dimension }) =>
      asContent(compareJurisdictions(jurisdictions, content_area, year, dimension)),
  );

  server.tool(
    "list_changes",
    "List scale breaks / non-comparable years (comparability.scale_transition = 1 or " +
      "comparable_to_prior_year = 0), optionally filtered by jurisdiction, system, and a " +
      "minimum year. This is the SQL analogue of the registry changelog.",
    {
      jurisdiction: z.string().nullable().optional(),
      system: z.string().nullable().optional(),
      since_year: z.number().int().nullable().optional(),
    },
    async ({ jurisdiction, system, since_year }) =>
      asContent(listChanges(jurisdiction ?? null, system ?? null, since_year ?? null)),
  );

  return server;
}
