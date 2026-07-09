/**
 * Local harness emulating the Vercel routing for the Tier 1 functions:
 *   npx tsx local-server.ts   (PORT env, default 3000)
 * Routes exactly what vercel.json routes; handlers are the same modules Vercel deploys.
 */
import { createServer } from "node:http";
import changes from "./api/changes.js";
import compare from "./api/compare.js";
import mcp from "./api/mcp.js";
import metadata from "./api/metadata.js";
import query from "./api/query.js";
import schema from "./api/schema.js";

const PORT = Number.parseInt(process.env.PORT ?? "3000", 10);

const routes: Record<string, (req: never, res: never) => unknown> = {
  "/api/schema": schema,
  "/api/query": query,
  "/api/metadata": metadata,
  "/api/compare": compare,
  "/api/changes": changes,
  "/api/mcp": mcp,
  "/mcp": mcp, // the vercel.json rewrite
};

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
