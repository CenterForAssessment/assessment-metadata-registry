/** Tiny helpers shared by the Vercel function handlers and the local harness. */
import type { IncomingMessage, ServerResponse } from "node:http";

/** Parse the request URL without depending on Vercel's req.query augmentation. */
export function queryOf(req: IncomingMessage): URLSearchParams {
  return new URL(req.url ?? "/", "http://local").searchParams;
}

const ERROR_STATUS: Record<string, number> = {
  empty_sql: 400,
  multiple_statements: 400,
  not_select: 400,
  forbidden_keyword: 400,
  bad_dimension: 400,
  bad_request: 400,
  not_found: 404,
  db_not_found: 503,
  sql_error: 400,
};

/** Send a tool result as JSON, mapping error envelopes to HTTP statuses. */
export function send(res: ServerResponse, result: Record<string, unknown>): void {
  const err = result["error"] as { code?: string } | undefined;
  const status = err ? (ERROR_STATUS[err.code ?? ""] ?? 500) : 200;
  const body = JSON.stringify(result);
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.setHeader("access-control-allow-origin", "*");
  res.end(body);
}

export function badRequest(res: ServerResponse, message: string): void {
  send(res, { error: { code: "bad_request", message } });
}
