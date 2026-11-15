#!/usr/bin/env node
/**
 * Minimal MCP-like JSON-RPC stdio fixture for integration tests.
 * Not a full MCP SDK server — enough to exercise lifecycle + tools/list + tools/call.
 */
const readline = require("readline");

const tools = [
  {
    name: "echo",
    description: "Echo arguments",
    inputSchema: {
      type: "object",
      properties: { message: { type: "string" } },
      required: ["message"]
    }
  }
];

const rl = readline.createInterface({ input: process.stdin, terminal: false });

rl.on("line", (line) => {
  let req;
  try {
    req = JSON.parse(line);
  } catch (e) {
    respond({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
    return;
  }
  const id = req.id;
  switch (req.method) {
    case "initialize":
      respond({
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: "fixture-echo", version: "1.0.0" }
        }
      });
      break;
    case "notifications/initialized":
      // no response required for notifications; reply for our simplified client
      if (id !== undefined && id !== null) {
        respond({ jsonrpc: "2.0", id, result: {} });
      }
      break;
    case "tools/list":
      respond({ jsonrpc: "2.0", id, result: { tools } });
      break;
    case "tools/call": {
      const name = req.params && req.params.name;
      const args = (req.params && req.params.arguments) || {};
      if (name !== "echo") {
        respond({ jsonrpc: "2.0", id, error: { code: -32602, message: "Unknown tool" } });
        break;
      }
      respond({
        jsonrpc: "2.0",
        id,
        result: { content: [{ type: "text", text: String(args.message || "") }] }
      });
      break;
    }
    default:
      respond({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } });
  }
});

function respond(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}
