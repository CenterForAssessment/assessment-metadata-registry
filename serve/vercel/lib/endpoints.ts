/**
 * The endpoint catalog served by `GET /api` (ADR-012 Tier 1).
 *
 * This is the single source of truth for what the deployment exposes. `local-server.ts`
 * asserts its route table covers exactly these paths at startup, and `scripts/smoke.mjs`
 * asserts every path listed here actually answers. Documentation that drifts from the
 * routes is worse than no documentation, so neither can move without the other.
 */

export interface EndpointParam {
  name: string;
  required: boolean;
  description: string;
}

export interface Endpoint {
  path: string;
  method: "GET" | "POST";
  summary: string;
  params: EndpointParam[];
  /** Illustrative only. Corpus-dependent — not asserted against by the smoke test. */
  example?: string;
}

export const ENDPOINTS: readonly Endpoint[] = [
  {
    path: "/api",
    method: "GET",
    summary: "This index: the endpoint catalog and the registry's build provenance.",
    params: [],
    example: "/api",
  },
  {
    path: "/api/schema",
    method: "GET",
    summary: "Tables and columns of the read-only registry projection. Call first to learn the shape.",
    params: [],
    example: "/api/schema",
  },
  {
    path: "/api/query",
    method: "GET",
    summary:
      "Run one read-only SELECT (or WITH … SELECT) against the registry. Rows come back in a git_sha-stamped envelope.",
    params: [{ name: "sql", required: true, description: "A single SELECT statement." }],
    example: "/api/query?sql=select%20count(*)%20n%20from%20administration",
  },
  {
    path: "/api/metadata",
    method: "GET",
    summary: "The full record for one jurisdiction x assessment system x year.",
    params: [
      { name: "jurisdiction", required: true, description: "Jurisdiction id, e.g. IN." },
      { name: "system", required: true, description: "Assessment system id, e.g. wida-access." },
      { name: "year", required: true, description: "Administration year, e.g. 2024." },
    ],
    example: "/api/metadata?jurisdiction=IN&system=wida-access&year=2024",
  },
  {
    path: "/api/compare",
    method: "GET",
    summary: "Compare one metadata dimension across jurisdictions for a content area and year.",
    params: [
      { name: "content_area", required: true, description: "Content area id, e.g. READING." },
      { name: "year", required: true, description: "Administration year." },
      {
        name: "dimension",
        required: false,
        description: "One of the compare_dimensions listed on this index. Defaults to achievement_levels.",
      },
      {
        name: "jurisdictions",
        required: false,
        description: "Comma-separated jurisdiction ids. Omitted or empty means all.",
      },
    ],
    example: "/api/compare?content_area=ELA&year=2024&dimension=achievement_levels",
  },
  {
    path: "/api/changes",
    method: "GET",
    summary:
      "Scale breaks and non-comparable years — the SQL analogue of the registry changelog.",
    params: [
      { name: "jurisdiction", required: false, description: "Restrict to one jurisdiction id." },
      { name: "system", required: false, description: "Restrict to one assessment system id." },
      { name: "since_year", required: false, description: "Only years >= this." },
    ],
    example: "/api/changes?since_year=2015",
  },
  {
    path: "/mcp",
    method: "POST",
    summary:
      "Stateless streamable-http MCP endpoint exposing the same five read-only tools. Requires Accept: application/json, text/event-stream.",
    params: [],
  },
] as const;

export const ENDPOINT_PATHS: readonly string[] = ENDPOINTS.map((e) => e.path);
