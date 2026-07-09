/**
 * POST /mcp (rewritten from /api/mcp) — STATELESS streamable-http MCP endpoint.
 *
 * The serverless constraint (ADR-012 Tier 1): no session affinity, no long-lived
 * process. So every request builds a fresh McpServer + StreamableHTTPServerTransport
 * with `sessionIdGenerator: undefined` (stateless mode) and `enableJsonResponse: true`
 * (plain JSON responses instead of a held-open SSE stream — required on a platform
 * that bills by function duration).
 */
import type { IncomingMessage, ServerResponse } from "node:http";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { buildServer } from "../lib/mcp.js";

export default async function handler(
  req: IncomingMessage & { body?: unknown },
  res: ServerResponse,
): Promise<void> {
  const server = buildServer();
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // stateless: no session tracking
    enableJsonResponse: true, // JSON body responses, no held-open SSE
  });
  res.on("close", () => {
    void transport.close();
    void server.close();
  });
  await server.connect(transport);
  // Vercel pre-parses JSON bodies into req.body; locally the SDK reads the stream.
  await transport.handleRequest(req, res, req.body);
}
