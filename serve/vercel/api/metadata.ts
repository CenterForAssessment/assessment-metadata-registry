import type { IncomingMessage, ServerResponse } from "node:http";
import { badRequest, queryOf, send } from "../lib/http.js";
import { getMetadata } from "../lib/tools.js";

/** GET /api/metadata?jurisdiction=IN&system=ilearn&year=2024 */
export default function handler(req: IncomingMessage, res: ServerResponse): void {
  const q = queryOf(req);
  const jurisdiction = q.get("jurisdiction");
  const system = q.get("system");
  const year = Number.parseInt(q.get("year") ?? "", 10);
  if (!jurisdiction || !system || Number.isNaN(year)) {
    return badRequest(res, "required query parameters: jurisdiction, system, year (integer)");
  }
  send(res, getMetadata(jurisdiction, system, year));
}
