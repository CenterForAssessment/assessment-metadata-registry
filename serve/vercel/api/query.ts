import type { IncomingMessage, ServerResponse } from "node:http";
import { badRequest, queryOf, send } from "../lib/http.js";
import { queryRegistry } from "../lib/tools.js";

/** GET /api/query?sql=<single SELECT> — guarded read-only SQL. */
export default function handler(req: IncomingMessage, res: ServerResponse): void {
  const sql = queryOf(req).get("sql");
  if (!sql) return badRequest(res, "missing required query parameter: sql");
  send(res, queryRegistry(sql));
}
