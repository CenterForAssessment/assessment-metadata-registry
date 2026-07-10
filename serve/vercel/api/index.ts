import type { IncomingMessage, ServerResponse } from "node:http";
import { send } from "../lib/http.js";
import { describeService } from "../lib/tools.js";

/** GET /api — endpoint catalog + the registry build this deployment serves. */
export default function handler(_req: IncomingMessage, res: ServerResponse): void {
  send(res, describeService());
}
