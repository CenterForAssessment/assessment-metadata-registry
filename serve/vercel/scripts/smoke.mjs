/**
 * Smoke test for the Tier 1 surface (ADR-012). Run against the local harness or a
 * deployed URL:
 *   node scripts/smoke.mjs                     # http://127.0.0.1:3000
 *   node scripts/smoke.mjs https://<app>.vercel.app
 *
 * Validates: REST endpoints, SELECT-only guard rejections, SHA-stamped envelopes, and a
 * real STATELESS streamable-http MCP round-trip (initialize → list_tools → call all 5).
 * Exit code 0 = all green.
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const BASE = (process.argv[2] ?? "http://127.0.0.1:3000").replace(/\/$/, "");
const results = [];

function check(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? `  — ${detail}` : ""}`);
}

async function getJson(pathname) {
  const res = await fetch(`${BASE}${pathname}`);
  let body = null;
  try {
    body = await res.json();
  } catch {
    /* non-JSON body */
  }
  return { status: res.status, body };
}

// ---------- static root ----------
async function rootTests() {
  const res = await fetch(`${BASE}/`);
  const html = res.status === 200 ? await res.text() : "";
  check(
    "GET / serves the landing page",
    res.status === 200 && (res.headers.get("content-type") ?? "").includes("text/html"),
    `status=${res.status} type=${res.headers.get("content-type")}`,
  );
  check("GET / renders from /api", html.includes('fetch("/api"'));

  // The page must NOT hard-code the catalog: it fetches /api and renders whatever it says.
  // A literal endpoint path in the markup is the first symptom of a list that will rot.
  const hardCoded = ["/api/schema", "/api/query", "/api/metadata", "/api/compare", "/api/changes"].filter(
    (p) => html.includes(`>${p}<`) || html.includes(`href="${p}"`),
  );
  check(
    "GET / hard-codes no endpoint list",
    hardCoded.length === 0,
    hardCoded.length ? `found ${hardCoded.join(", ")}` : "rendered from /api",
  );

  // The static surface is exactly one file. The DB must never be reachable there.
  const db = await fetch(`${BASE}/data/registry.sqlite`);
  check("GET /data/registry.sqlite is not served", db.status === 404, `status=${db.status}`);
}

// ---------- REST ----------
async function restTests() {
  const index = await getJson("/api");
  check(
    "REST /api index",
    index.status === 200 &&
      !!index.body?.git_sha &&
      index.body?.provenance_error === undefined &&
      Array.isArray(index.body?.endpoints) &&
      index.body.endpoints.length > 0,
    `git_sha=${index.body?.git_sha?.slice(0, 8)} endpoints=${index.body?.endpoints?.length}`,
  );

  check(
    "REST /api index agrees with /api/schema on git_sha",
    index.body?.git_sha === (await getJson("/api/schema")).body?.git_sha,
  );

  // The index advertises a catalog. Every path in it must answer. A 404 here means the
  // catalog is lying — which is worse than having no catalog, because a caller trusts it.
  for (const ep of index.body?.endpoints ?? []) {
    const r = await fetch(`${BASE}${ep.path}`);
    check(
      `advertised ${ep.method} ${ep.path} is routed`,
      r.status !== 404,
      `status=${r.status}`,
    );
  }

  const schema = await getJson("/api/schema");
  check(
    "REST /api/schema",
    schema.status === 200 && !!schema.body?.git_sha && !!schema.body?.tables?.administration,
    `git_sha=${schema.body?.git_sha?.slice(0, 8)}`,
  );

  const q = await getJson(
    `/api/query?sql=${encodeURIComponent("select jurisdiction_id, count(*) n from administration group by 1 order by 1")}`,
  );
  check(
    "REST /api/query envelope",
    q.status === 200 &&
      !!q.body?.git_sha &&
      typeof q.body?.row_count === "number" &&
      q.body?.truncated === false &&
      Array.isArray(q.body?.rows) &&
      q.body.rows.length > 0,
    `rows=${q.body?.row_count}`,
  );

  // Guard rejections — the delete/multi/pragma trio verified on the Python stack.
  for (const [label, sql, code] of [
    ["delete", "delete from administration", "not_select"],
    ["multi-statement", "select 1; select 2", "multiple_statements"],
    ["pragma statement", "pragma table_info(administration)", "not_select"],
    ["insert-via-with", "with x as (select 1) insert into administration values (1)", "forbidden_keyword"],
  ]) {
    const r = await getJson(`/api/query?sql=${encodeURIComponent(sql)}`);
    check(
      `guard rejects ${label}`,
      r.status === 400 && r.body?.error?.code === code,
      `code=${r.body?.error?.code}`,
    );
  }

  // Positive control: keyword-substring identifiers must NOT trip the whole-word guard.
  const ident = await getJson(
    `/api/query?sql=${encodeURIComponent("select jurisdiction_id as delete_me from jurisdiction limit 1")}`,
  );
  check("guard allows keyword-substring identifier", ident.status === 200 && ident.body?.rows?.length === 1);

  const meta = await getJson("/api/metadata?jurisdiction=IN&system=ilearn&year=2024");
  check(
    "REST /api/metadata IN/ilearn/2024",
    meta.status === 200 &&
      meta.body?.administration?.vendor != null &&
      Array.isArray(meta.body?.content_areas),
    `vendor=${meta.body?.administration?.vendor}`,
  );

  const missing = await getJson("/api/metadata?jurisdiction=ZZ&system=nope&year=1999");
  check("REST /api/metadata 404 on missing", missing.status === 404 && missing.body?.error?.code === "not_found");

  // Corpus-agnostic: ask the DB which cell actually spans >= 2 jurisdictions, then compare
  // on it. Hard-coding a cell (e.g. ELA/2024/IN,SC) only holds for whichever corpus the
  // check was written against — the fixture has that overlap; the real registry does not.
  // Omitting `jurisdictions` means "all" (see api/compare.ts).
  const pick = await getJson(
    "/api/query?sql=" +
      encodeURIComponent(
        "select content_area, year from achievement_level " +
          "group by 1, 2 having count(distinct jurisdiction_id) >= 2 " +
          "order by year desc limit 1",
      ),
  );
  const cell = pick.body?.rows?.[0];
  check("REST /api/query finds a multi-jurisdiction cell", pick.status === 200 && !!cell, `cell=${
    cell ? `${cell.content_area}/${cell.year}` : "none"
  }`);

  const cmp = await getJson(
    `/api/compare?content_area=${encodeURIComponent(cell?.content_area ?? "")}` +
      `&year=${cell?.year ?? 0}&dimension=achievement_levels`,
  );
  const jurs = new Set((cmp.body?.rows ?? []).map((r) => r.jurisdiction_id));
  check(
    "REST /api/compare spans >= 2 jurisdictions",
    cmp.status === 200 && jurs.size >= 2 && cmp.body?.dimension === "achievement_levels",
    `${cell?.content_area}/${cell?.year} jurs=${[...jurs].join(",")} rows=${cmp.body?.row_count}`,
  );

  const badDim = await getJson("/api/compare?content_area=ELA&year=2024&dimension=bogus");
  check("REST /api/compare bad dimension", badDim.status === 400 && badDim.body?.error?.code === "bad_dimension");

  const chg = await getJson("/api/changes?since_year=2015");
  check(
    "REST /api/changes finds scale break",
    chg.status === 200 && (chg.body?.rows ?? []).some((r) => r.scale_transition === 1),
    `rows=${chg.body?.row_count}`,
  );
}

// ---------- MCP (stateless streamable-http) ----------
const EXPECTED_TOOLS = [
  "compare_jurisdictions",
  "describe_schema",
  "get_metadata",
  "list_changes",
  "query_registry",
];

function parseTool(result) {
  const text = result?.content?.find((c) => c.type === "text")?.text;
  return text ? JSON.parse(text) : null;
}

async function mcpTests() {
  const client = new Client({ name: "amr-smoke", version: "0.1.0" });
  const transport = new StreamableHTTPClientTransport(new URL(`${BASE}/mcp`));
  await client.connect(transport); // initialize round-trip
  check("MCP initialize (stateless streamable-http)", true);

  const tools = await client.listTools();
  const names = tools.tools.map((t) => t.name).sort();
  check(
    "MCP list_tools = 5 expected",
    JSON.stringify(names) === JSON.stringify(EXPECTED_TOOLS),
    names.join(","),
  );

  const ds = parseTool(await client.callTool({ name: "describe_schema", arguments: {} }));
  check("MCP describe_schema", !!ds?.git_sha && !!ds?.tables?.cutscore, `git_sha=${ds?.git_sha?.slice(0, 8)}`);

  const qr = parseTool(
    await client.callTool({
      name: "query_registry",
      arguments: { sql: "select count(*) n from achievement_level" },
    }),
  );
  check("MCP query_registry envelope", !!qr?.git_sha && qr?.rows?.[0]?.n > 0, `n=${qr?.rows?.[0]?.n}`);

  const guard = parseTool(
    await client.callTool({ name: "query_registry", arguments: { sql: "drop table cutscore" } }),
  );
  check("MCP guard rejects drop", guard?.error?.code === "not_select", `code=${guard?.error?.code}`);

  const gm = parseTool(
    await client.callTool({
      name: "get_metadata",
      arguments: { jurisdiction: "IN", system: "ilearn", year: 2024 },
    }),
  );
  check("MCP get_metadata", gm?.administration?.status != null && Array.isArray(gm?.content_areas));

  const cj = parseTool(
    await client.callTool({
      name: "compare_jurisdictions",
      arguments: { jurisdictions: [], content_area: "ELA", year: 2024, dimension: "cutscores" },
    }),
  );
  check("MCP compare_jurisdictions (all, cutscores)", !!cj?.git_sha && cj?.rows?.length > 0, `rows=${cj?.row_count}`);

  const lc = parseTool(await client.callTool({ name: "list_changes", arguments: { since_year: 2015 } }));
  check("MCP list_changes", !!lc?.git_sha && lc?.rows?.some((r) => r.comparable_to_prior_year === 0));

  // Statelessness: a SECOND independent client must work with no session carryover.
  const client2 = new Client({ name: "amr-smoke-2", version: "0.1.0" });
  await client2.connect(new StreamableHTTPClientTransport(new URL(`${BASE}/mcp`)));
  const ds2 = parseTool(await client2.callTool({ name: "describe_schema", arguments: {} }));
  check("MCP second independent client (stateless)", !!ds2?.git_sha);
  await client2.close();
  await client.close();
}

try {
  await rootTests();
  await restTests();
  await mcpTests();
} catch (e) {
  check("unhandled error", false, String(e));
}

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed against ${BASE}`);
process.exit(failed.length === 0 ? 0 : 1);
