/**
 * Local harness emulating the Vercel routing for the Tier 1 functions:
 *   npx tsx local-server.ts   (PORT env, default 3000)
 * Routes exactly what vercel.json routes; handlers are the same modules Vercel deploys.
 */
import { createServer } from "node:http";
import changes from "./api/changes.js";
import compare from "./api/compare.js";
import index from "./api/index.js";
import mcp from "./api/mcp.js";
import metadata from "./api/metadata.js";
import query from "./api/query.js";
import schema from "./api/schema.js";
import { ENDPOINT_PATHS } from "./lib/endpoints.js";

const PORT = Number.parseInt(process.env.PORT ?? "3000", 10);

const routes: Record<string, (req: never, res: never) => unknown> = {
  "/api": index,
  "/api/schema": schema,
  "/api/query": query,
  "/api/metadata": metadata,
  "/api/compare": compare,
  "/api/changes": changes,
  "/api/mcp": mcp,
  "/mcp": mcp, // the vercel.json rewrite
};

// `/api` publishes ENDPOINTS as the catalog of what exists. If a path is advertised but
// unrouted, callers are sent to a 404; if it is routed but unadvertised, it is invisible.
// Fail at startup rather than let the two drift. `/api/mcp` is the pre-rewrite alias of
// `/mcp`, so it is routed on purpose without appearing in the catalog.
const ALIASES = new Set(["/api/mcp"]);
const routed = new Set(Object.keys(routes).filter((p) => !ALIASES.has(p)));
const advertised = new Set(ENDPOINT_PATHS);
const missing = [...advertised].filter((p) => !routed.has(p));
const undocumented = [...routed].filter((p) => !advertised.has(p));
if (missing.length > 0 || undocumented.length > 0) {
  throw new Error(
    `route/catalog mismatch — advertised but unrouted: [${missing.join(", ")}]; ` +
      `routed but undocumented: [${undocumented.join(", ")}]`,
  );
}

const server = createServer((req, res) => {
  const pathname = new URL(req.url ?? "/", "http://local").pathname;
  const handler = routes[pathname];
  if (!handler) {
    res.statusCode = 404;
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ error: { code: "no_route", message: `no route for ${pathname}` } }));
    return;
  }
  Promise.resolve(handler(req as never, res as never)).catch((e: unknown) => {
    if (!res.headersSent) {
      res.statusCode = 500;
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify({ error: { code: "internal", message: String(e) } }));
    }
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`amr serve/vercel local harness on http://127.0.0.1:${PORT}`);
});
