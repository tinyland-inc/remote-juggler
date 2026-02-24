/*
 * MCP.chpl - Model Context Protocol Server Implementation for RemoteJuggler
 *
 * This module implements the MCP (Model Context Protocol) STDIO server,
 * enabling integration with Claude Code and other MCP-compatible clients.
 *
 * Protocol Version: 2025-11-25
 * Transport: STDIO (stdin/stdout for JSON-RPC, stderr for logging)
 *
 * MCP Specification: https://modelcontextprotocol.io/specification/2025-11-25
 */
prototype module MCP {
  use super.Protocol;
  use super.Tools;
  use IO;
  use List;

  // ============================================================================
  // MCP Server State
  // ============================================================================

  /*
   * MCPState - Server lifecycle states
   *
   * Uninitialized: Server has started but not received initialize request
   * Ready: Server has completed initialization handshake and is ready for requests
   * ShuttingDown: Server is in the process of shutting down
   */
  enum MCPState {
    Uninitialized,
    Ready,
    ShuttingDown
  }

  /*
   * MCPServer - Main server state container
   *
   * Tracks the server's current state and configuration.
   */
  record MCPServer {
    var state: MCPState = MCPState.Uninitialized;
    var protocolVersion: string = "2025-11-25";
    var serverName: string = "remote-juggler";
    var serverVersion: string = "2.2.0";
    var clientName: string = "";
    var clientVersion: string = "";
  }

  // ============================================================================
  // MCP Capability Structures
  // ============================================================================

  /*
   * ToolsCapability - Describes tool-related capabilities
   */
  record ToolsCapability {
    var listChanged: bool = true;  // Server can notify when tools list changes
  }

  /*
   * ServerCapabilities - All server capabilities
   */
  record ServerCapabilities {
    var tools: ToolsCapability;
  }

  /*
   * ServerInfo - Server identification
   */
  record ServerInfo {
    var name: string;
    var version: string;
  }

  // ============================================================================
  // MCP Protocol Messages
  // ============================================================================

  /*
   * Build the initialize response payload.
   * This is the server's response to the initialize request.
   */
  proc buildInitializeResult(server: MCPServer): string {
    // Protocol version
    const protocolVersionJson = Protocol.jsonString(server.protocolVersion);

    // Server capabilities
    const toolsCapJson = '{"listChanged":true}';
    const capabilitiesJson = '{"tools":' + toolsCapJson + '}';

    // Server info
    const serverInfoJson = '{"name":' + Protocol.jsonString(server.serverName) +
                          ',"version":' + Protocol.jsonString(server.serverVersion) + '}';

    // Complete result
    return '{"protocolVersion":' + protocolVersionJson +
           ',"capabilities":' + capabilitiesJson +
           ',"serverInfo":' + serverInfoJson + '}';
  }

  /*
   * Build the tools/list response payload.
   * Returns all available tools with their schemas.
   */
  proc buildToolsListResult(): string {
    const tools = Tools.getToolDefinitions();

    var toolsJson: list(string);
    for tool in tools {
      const toolJson = '{"name":' + Protocol.jsonString(tool.name) +
                      ',"description":' + Protocol.jsonString(tool.description) +
                      ',"inputSchema":' + tool.inputSchema + '}';
      toolsJson.pushBack(toolJson);
    }

    return '{"tools":' + Protocol.buildJsonArray(toolsJson) + '}';
  }

  /*
   * Build a tool call result (success case).
   */
  proc buildToolCallResult(content: string, isError: bool = false): string {
    // MCP tool results use content blocks
    const contentBlock = '{"type":"text","text":' + Protocol.jsonString(content) + '}';
    return '{"content":[' + contentBlock + '],"isError":' + Protocol.jsonBool(isError) + '}';
  }

  /*
   * Build a ping response.
   */
  proc buildPingResult(): string {
    return "{}";
  }

  // ============================================================================
  // Message Handlers
  // ============================================================================

  /*
   * Handle the initialize request from client.
   *
   * This is the first message in the MCP protocol handshake.
   * The server responds with its capabilities and version info.
   *
   * NOTE: We auto-transition to Ready state after initialize because some
   * MCP clients (like Claude Code) may not send the initialized notification.
   * This is safe because initialize is always the first request.
   */
  proc handleInitialize(ref server: MCPServer, req: JsonRpcRequest): string {
    stderr.writeln("MCP: Handling initialize request");

    // Extract client info from params (optional)
    const params = req.params;
    const (hasClientName, clientName) = Protocol.extractJsonString(params, "clientInfo");
    if hasClientName {
      server.clientName = clientName;
    }

    // Extract protocol version requested by client
    const (hasProtoVer, requestedVersion) = Protocol.extractJsonString(params, "protocolVersion");
    if hasProtoVer {
      stderr.writeln("MCP: Client requested protocol version: ", requestedVersion);
      // We support 2025-11-25, which is backwards compatible
    }

    // Auto-transition to Ready state after initialize
    // Some clients don't send the initialized notification
    server.state = MCPState.Ready;
    stderr.writeln("MCP: Server is now ready (auto-transition after initialize)");

    // Build and return response
    const result = buildInitializeResult(server);
    return Protocol.makeResponse(req.id, result);
  }

  /*
   * Handle the initialized notification from client.
   *
   * This notification signals that the client has processed the initialize
   * response and is ready to proceed. No response is sent.
   */
  proc handleInitialized(ref server: MCPServer, req: JsonRpcRequest): string {
    stderr.writeln("MCP: Received initialized notification");
    server.state = MCPState.Ready;
    stderr.writeln("MCP: Server is now ready");
    return "";  // Notifications don't get responses
  }

  /*
   * Handle the tools/list request.
   *
   * Returns the list of all available tools with their input schemas.
   */
  proc handleToolsList(server: MCPServer, req: JsonRpcRequest): string {
    stderr.writeln("MCP: Handling tools/list request");

    if server.state != MCPState.Ready && server.state != MCPState.Uninitialized {
      // Allow tools/list even before initialized for some clients
      stderr.writeln("MCP: Warning - tools/list called in state: ", server.state:string);
    }

    const result = buildToolsListResult();
    return Protocol.makeResponse(req.id, result);
  }

  /*
   * Handle the tools/call request.
   *
   * Executes a specific tool and returns the result.
   */
  proc handleToolsCall(server: MCPServer, req: JsonRpcRequest): string {
    stderr.writeln("MCP: Handling tools/call request");

    if server.state != MCPState.Ready {
      stderr.writeln("MCP: Error - tools/call before server ready");
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_REQUEST,
                                        "Server not initialized");
    }

    // Extract tool name from params
    const params = req.params;
    const (hasName, toolName) = Protocol.extractJsonString(params, "name");

    if !hasName || toolName == "" {
      stderr.writeln("MCP: Error - missing tool name in tools/call");
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_PARAMS,
                                        "Missing required parameter: name");
    }

    stderr.writeln("MCP: Calling tool: ", toolName);

    // Extract arguments for the tool
    const (hasArgs, toolArgs) = Protocol.extractJsonObject(params, "arguments");
    const argsJson = if hasArgs then toolArgs else "{}";

    // Execute the tool
    const (success, resultContent) = Tools.executeTool(toolName, argsJson);

    // Build result
    const result = buildToolCallResult(resultContent, !success);
    return Protocol.makeResponse(req.id, result);
  }

  /*
   * Handle the ping request.
   *
   * Simple keepalive mechanism.
   */
  proc handlePing(req: JsonRpcRequest): string {
    stderr.writeln("MCP: Handling ping request");
    const result = buildPingResult();
    return Protocol.makeResponse(req.id, result);
  }

  /*
   * Handle the shutdown request.
   *
   * Prepares the server for termination.
   */
  proc handleShutdown(ref server: MCPServer, req: JsonRpcRequest): string {
    stderr.writeln("MCP: Handling shutdown request");
    server.state = MCPState.ShuttingDown;
    return Protocol.makeResponse(req.id, "null");
  }

  /*
   * Handle the exit notification.
   *
   * Terminates the server process.
   */
  proc handleExit(ref server: MCPServer, req: JsonRpcRequest): string {
    stderr.writeln("MCP: Received exit notification, terminating");
    // Return empty string - the main loop will handle exit
    return "";
  }

  // ============================================================================
  // Message Router
  // ============================================================================

  /*
   * Route an incoming message to the appropriate handler.
   *
   * @param server: Mutable reference to server state
   * @param line: Raw JSON-RPC message string
   * @return: Response string (empty for notifications)
   */
  proc handleMessage(ref server: MCPServer, line: string): string {
    // Parse the request
    const (parseOk, req) = Protocol.parseRequest(line);

    if !parseOk {
      stderr.writeln("MCP: Failed to parse request");
      // Can't determine ID, use 0
      return Protocol.makeErrorResponse(0, Protocol.PARSE_ERROR,
                                        "Failed to parse JSON-RPC request");
    }

    stderr.writeln("MCP: Received method: ", req.method);

    // Route based on method
    select req.method {

      // Lifecycle methods
      when "initialize" {
        return handleInitialize(server, req);
      }
      when "initialized" {
        return handleInitialized(server, req);
      }
      when "shutdown" {
        return handleShutdown(server, req);
      }
      when "exit" {
        return handleExit(server, req);
      }

      // Utility methods
      when "ping" {
        return handlePing(req);
      }

      // Tools methods
      when "tools/list" {
        return handleToolsList(server, req);
      }
      when "tools/call" {
        return handleToolsCall(server, req);
      }

      // MCP 2025-11-25 additional methods
      when "notifications/cancelled" {
        // Client cancelled a request - log and ignore
        stderr.writeln("MCP: Request cancelled by client");
        return "";
      }
      when "notifications/progress" {
        // Progress notification - log and ignore
        stderr.writeln("MCP: Progress notification received");
        return "";
      }

      // Resources (not implemented in this version)
      when "resources/list" {
        return Protocol.makeResponse(req.id, '{"resources":[]}');
      }
      when "resources/read" {
        return Protocol.makeErrorResponse(req.id, Protocol.METHOD_NOT_FOUND,
                                          "Resources not supported in this version");
      }

      // Prompts (not implemented in this version)
      when "prompts/list" {
        return Protocol.makeResponse(req.id, '{"prompts":[]}');
      }
      when "prompts/get" {
        return Protocol.makeErrorResponse(req.id, Protocol.METHOD_NOT_FOUND,
                                          "Prompts not supported in this version");
      }

      // Unknown method
      otherwise {
        stderr.writeln("MCP: Unknown method: ", req.method);
        return Protocol.makeErrorResponse(req.id, Protocol.METHOD_NOT_FOUND,
                                          "Method not found: " + req.method);
      }
    }
  }

  // ============================================================================
  // Main Server Loop
  // ============================================================================

  /*
   * Run the MCP server.
   *
   * Reads JSON-RPC messages from stdin (one per line), processes them,
   * and writes responses to stdout. Logging goes to stderr.
   *
   * CRITICAL STDIO rules:
   * - All logging goes to stderr
   * - Only JSON-RPC messages go to stdout
   * - Messages are newline-delimited
   * - No embedded newlines in JSON output
   */
  proc runMCPServer() {
    stderr.writeln("MCP: RemoteJuggler MCP Server starting...");
    stderr.writeln("MCP: Protocol version: 2025-11-25");
    stderr.writeln("MCP: Server version: 2.2.0");
    stderr.writeln("MCP: Waiting for input on stdin...");

    var server = new MCPServer();
    var shouldExit = false;

    // Main message loop
    while !shouldExit {
      var line: string;

      // Read a line from stdin
      // readLine returns false on EOF
      try {
        const readOk = stdin.readLine(line);
        if !readOk {
          stderr.writeln("MCP: EOF received, exiting");
          break;
        }
      } catch e {
        stderr.writeln("MCP: Error reading from stdin: ", e.message());
        break;
      }

      // Skip empty lines
      const trimmedLine = line.strip();
      if trimmedLine.size == 0 {
        continue;
      }

      stderr.writeln("MCP: Processing message (", trimmedLine.size, " bytes)");

      // Handle the message
      const response = handleMessage(server, trimmedLine);

      // Send response if not empty (notifications don't get responses)
      if response != "" {
        stdout.writeln(response);
        stdout.flush();
        stderr.writeln("MCP: Response sent (", response.size, " bytes)");
      }

      // Check for exit condition
      if server.state == MCPState.ShuttingDown {
        // After shutdown, expect exit notification
        // But also exit if we don't receive it
        stderr.writeln("MCP: Server shutting down...");
      }

      // Handle exit method
      if trimmedLine.find('"exit"') != -1 && trimmedLine.find('"method"') != -1 {
        shouldExit = true;
      }
    }

    stderr.writeln("MCP: Server terminated");
  }

  // ============================================================================
  // Server Status Helpers
  // ============================================================================

  /*
   * Check if the server is in a ready state.
   */
  proc isServerReady(server: MCPServer): bool {
    return server.state == MCPState.Ready;
  }

  /*
   * Get server state as a string for logging.
   */
  proc getServerState(server: MCPServer): string {
    select server.state {
      when MCPState.Uninitialized do return "uninitialized";
      when MCPState.Ready do return "ready";
      when MCPState.ShuttingDown do return "shutting_down";
      otherwise do return "unknown";
    }
  }

  // ============================================================================
  // Notification Senders (Server -> Client)
  // ============================================================================

  /*
   * Send a tools/list_changed notification to the client.
   *
   * This notifies the client that the tool list has changed and should be
   * refreshed. Used when tools are dynamically added/removed.
   */
  proc sendToolsListChangedNotification() {
    const notification = Protocol.makeNotification("notifications/tools/list_changed", "{}");
    stdout.writeln(notification);
    stdout.flush();
    stderr.writeln("MCP: Sent tools/list_changed notification");
  }

  /*
   * Send a progress notification to the client.
   *
   * Used for long-running tool executions to provide feedback.
   */
  proc sendProgressNotification(progressToken: string, progress: int, total: int) {
    const params = '{"progressToken":' + Protocol.jsonString(progressToken) +
                  ',"progress":' + Protocol.jsonInt(progress) +
                  ',"total":' + Protocol.jsonInt(total) + '}';
    const notification = Protocol.makeNotification("notifications/progress", params);
    stdout.writeln(notification);
    stdout.flush();
    stderr.writeln("MCP: Sent progress notification: ", progress, "/", total);
  }

  /*
   * Send a log message notification to the client.
   *
   * Allows the server to send log messages that the client can display.
   */
  proc sendLogNotification(level: string, message: string, logger: string = "remote-juggler") {
    const params = '{"level":' + Protocol.jsonString(level) +
                  ',"logger":' + Protocol.jsonString(logger) +
                  ',"data":' + Protocol.jsonString(message) + '}';
    const notification = Protocol.makeNotification("notifications/message", params);
    stdout.writeln(notification);
    stdout.flush();
  }
}
