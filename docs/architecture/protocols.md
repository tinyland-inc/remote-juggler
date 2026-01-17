---
title: "Protocol Specifications"
description: "JSON-RPC 2.0 protocol details for MCP and ACP including message formats, error codes, and transport layer implementation."
category: "reference"
llm_priority: 4
keywords:
  - protocol
  - json-rpc
  - mcp
  - acp
  - transport
---

# Protocol Specifications

RemoteJuggler implements two agent communication protocols: MCP and ACP.

## JSON-RPC 2.0 Base

Both protocols use JSON-RPC 2.0 as the transport layer.

### Request Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "method_name",
  "params": {}
}
```

### Response Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {}
}
```

### Error Format

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32600,
    "message": "Invalid Request"
  }
}
```

## Model Context Protocol (MCP)

MCP is the primary protocol for AI assistant integration.

### Protocol Version

RemoteJuggler implements MCP version `2025-11-25`.

### Initialization

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": {
      "name": "client-name",
      "version": "1.0.0"
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-11-25",
    "capabilities": {
      "tools": {}
    },
    "serverInfo": {
      "name": "remote-juggler",
      "version": "2.0.0"
    }
  }
}
```

### Tools List

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "juggler_list_identities",
        "description": "List all configured git identities...",
        "inputSchema": {
          "type": "object",
          "properties": {
            "provider": {
              "type": "string",
              "enum": ["gitlab", "github", "bitbucket", "all"]
            }
          }
        }
      }
    ]
  }
}
```

### Tool Call

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "juggler_switch",
    "arguments": {
      "identity": "work",
      "setRemote": true
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Switched to identity: work\n..."
      }
    ]
  }
}
```

### Error Response

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Error: Identity not found"
      }
    ],
    "isError": true
  }
}
```

## Agent Communication Protocol (ACP)

ACP is used by JetBrains IDEs.

### Server Registration

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "acp/initialize",
  "params": {
    "clientInfo": {
      "name": "intellij",
      "version": "2024.3"
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "serverInfo": {
      "name": "RemoteJuggler",
      "version": "2.0.0",
      "description": "Git identity management"
    },
    "tools": [...]
  }
}
```

### Execute Action

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "acp/executeAction",
  "params": {
    "tool": "juggler_switch",
    "arguments": {
      "identity": "work"
    },
    "context": {
      "projectPath": "/path/to/project"
    }
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "success": true,
    "output": "Switched to identity: work\n..."
  }
}
```

## Transport

Both protocols use STDIO transport:

- Server reads JSON-RPC messages from stdin (one per line)
- Server writes JSON-RPC responses to stdout (one per line)
- Diagnostic output goes to stderr

### Message Framing

Each message is a single line of JSON, terminated by newline:

```
{"jsonrpc":"2.0","id":1,"method":"initialize",...}\n
```

### Parsing Implementation

**Location:** `src/remote_juggler/Protocol.chpl`

```chapel
proc parseJsonRpcRequest(line: string): (bool, int, string, string) {
  // Extract id, method, params from JSON-RPC request
  const (hasId, idStr) = extractJsonString(line, "id");
  const (hasMethod, method) = extractJsonString(line, "method");
  const (hasParams, params) = extractJsonObject(line, "params");

  if !hasId || !hasMethod {
    return (false, 0, "", "");
  }

  const id = idStr:int;
  return (true, id, method, params);
}
```

## Error Codes

### JSON-RPC Standard Errors

| Code | Message | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid Request | Missing required fields |
| -32601 | Method not found | Unknown method |
| -32602 | Invalid params | Invalid parameters |
| -32603 | Internal error | Server error |

### RemoteJuggler Errors

| Code | Message | Description |
|------|---------|-------------|
| -32001 | Identity not found | Requested identity doesn't exist |
| -32002 | Validation failed | SSH/API connectivity failed |
| -32003 | Keychain error | Token storage failed |
| -32004 | Config error | Configuration file issue |

## Debugging

Enable protocol debugging:

```bash
REMOTE_JUGGLER_VERBOSE=1 remote-juggler --mode=mcp 2>protocol.log
```

The log shows:
- Incoming requests
- Parsed parameters
- Tool execution results
- Response formatting

## Protocol Comparison

| Feature | MCP | ACP |
|---------|-----|-----|
| Base Protocol | JSON-RPC 2.0 | JSON-RPC 2.0 |
| Init Method | `initialize` | `acp/initialize` |
| Tool List | `tools/list` | Included in init |
| Tool Call | `tools/call` | `acp/executeAction` |
| Context | Minimal | Project context |
| Result Format | `content` array | `output` string |
