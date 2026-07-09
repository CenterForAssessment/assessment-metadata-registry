import type { IncomingMessage, ServerResponse } from "node:http";
import { queryOf, send } from "../lib/http.js";
import { listChanges } from "../lib/tools.js";

/** GET /api/changes?jurisdiction=IN&system=ilearn&since_year=2015 (all filters optional) */
export default function handler(req: IncomingMessage, res: ServerResponse): void {
  const q = queryOf(req);
  const sinceRaw = q.get("since_year");
  const sinceYear = sinceRaw === null ? null : Number.parseInt(sinceRaw, 10);
  send(res, listChanges(q.get("jurisdiction"), q.get("system"), Number.isNaN(sinceYear as number) ? null : sinceYear));
}
