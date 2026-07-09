import type { IncomingMessage, ServerResponse } from "node:http";
import { send } from "../lib/http.js";
import { describeSchema } from "../lib/tools.js";

/** GET /api/schema — tables + columns + build provenance. */
export default function handler(_req: IncomingMessage, res: ServerResponse): void {
  send(res, describeSchema());
}
