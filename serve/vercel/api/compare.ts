import type { IncomingMessage, ServerResponse } from "node:http";
import { badRequest, queryOf, send } from "../lib/http.js";
import { compareJurisdictions } from "../lib/tools.js";

/**
 * GET /api/compare?content_area=ELA&year=2024&dimension=achievement_levels&jurisdictions=IN,SC
 * jurisdictions is comma-separated; empty/omitted = all.
 */
export default function handler(req: IncomingMessage, res: ServerResponse): void {
  const q = queryOf(req);
  const contentArea = q.get("content_area");
  const year = Number.parseInt(q.get("year") ?? "", 10);
  if (!contentArea || Number.isNaN(year)) {
    return badRequest(res, "required query parameters: content_area, year (integer)");
  }
  const jurisdictions = (q.get("jurisdictions") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const dimension = q.get("dimension") ?? "achievement_levels";
  send(res, compareJurisdictions(jurisdictions, contentArea, year, dimension));
}
