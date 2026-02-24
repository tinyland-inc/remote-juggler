/*
 * ACP.chpl - Agent Client Protocol Server for RemoteJuggler
 *
 * This module implements the ACP (Agent Client Protocol) server for JetBrains
 * IntelliJ integration. ACP is a session-based protocol that extends JSON-RPC 2.0
 * with streaming updates and content blocks for agentic coding assistants.
 *
 * Key differences from MCP:
 * - Session-based: maintains conversation state via session IDs
 * - Streaming: uses session/update notifications for real-time progress
 * - Content blocks: structured output with text, tool calls, diffs, etc.
 * - Prompt turns: client sends session/prompt, agent streams back updates
 *
 * Protocol Version: 1 (ACP initial)
 * Transport: STDIO (stdin/stdout with newline-delimited JSON)
 *
 * Part of RemoteJuggler v2.0.0
 * Chapel 2.8
 *
 * Protocol reference: https://agentclientprotocol.com/
 *
 * Sources:
 * - https://agentclientprotocol.com/protocol/overview
 * - https://github.com/agentclientprotocol/agent-client-protocol
 */
prototype module ACP {
  use IO;
  use List;
  use Map;
  use Time;
  use Random;
  public use super.Protocol;
  public use super.Tools;
  import super.Protocol;
  import super.Tools;

  // ============================================================
  // ACP Protocol Constants
  // ============================================================

  // ACP protocol version (single integer per spec)
  param ACP_PROTOCOL_VERSION: int = 1;
  param ACP_SERVER_NAME = "RemoteJuggler";
  param ACP_SERVER_VERSION = "2.2.0";

  // ACP-specific error codes
  param ACP_ERROR_AUTH_REQUIRED = -32000;
  param ACP_ERROR_SESSION_NOT_FOUND = -32001;
  param ACP_ERROR_RESOURCE_NOT_FOUND = -32002;

  // ============================================================
  // ACP State Enums
  // ============================================================

  /*
   * ACPState - Server lifecycle state
   */
  enum ACPState {
    Uninitialized,   // Before initialize request
    Initialized,     // After initialize, ready for sessions
    InSession,       // Active session exists
    Shutdown         // Server shutting down
  }

  /*
   * ContentBlockType - Types of content in ACP responses
   */
  enum ContentBlockType {
    TextBlock,       // Plain text content
    ToolCallBlock,   // Tool invocation status
    ToolResultBlock, // Tool execution result
    CodeDiffBlock,   // File diff representation
    ErrorBlock       // Error information
  }

  /*
   * ToolCallStatus - Progress state of a tool call
   */
  enum ToolCallStatus {
    Pending,         // Tool call queued
    Running,         // Tool currently executing
    Completed,       // Tool finished successfully
    Failed           // Tool execution failed
  }

  /*
   * StopReason - Why a prompt turn ended
   */
  enum StopReason {
    Completed,       // Normal completion
    Cancelled,       // User cancelled
    Error,           // Error occurred
    ToolLimit,       // Too many tool calls
    MaxTokens        // Token limit reached
  }

  // ============================================================
  // ACP Session State
  // ============================================================

  /*
   * ACPSession - Active conversation session
   *
   * Sessions maintain state across multiple prompt turns.
   */
  record ACPSession {
    var sessionId: string = "";
    var createdAt: string = "";
    var lastActivity: string = "";
    var cwd: string = "";
    var promptCount: int = 0;
    var isActive: bool = false;
  }

  /*
   * ACPServer - Main server state
   */
  record ACPServer {
    var state: ACPState = ACPState.Uninitialized;
    var protocolVersion: int = ACP_PROTOCOL_VERSION;
    var clientName: string = "";
    var clientVersion: string = "";
    var sessions: map(string, ACPSession);
    var currentSessionId: string = "";
  }

  /*
   * ContentBlock - A single content block in responses
   */
  record ContentBlock {
    var blockType: ContentBlockType;
    var text: string = "";
    var toolName: string = "";
    var toolStatus: ToolCallStatus = ToolCallStatus.Pending;
    var isError: bool = false;
  }

  // Module-level server state
  private var _server: ACPServer;

  // ============================================================
  // ACP Server Main Loop
  // ============================================================

  /*
   * Run the ACP STDIO server
   *
   * Starts the main server loop, reading JSON-RPC messages from stdin
   * and writing responses to stdout. The server continues until:
   *   - A "shutdown" request is received
   *   - stdin is closed
   *   - An unrecoverable error occurs
   */
  proc runACPServer() {
    stderr.writeln("ACP: RemoteJuggler ACP Server starting...");
    stderr.writeln("ACP: Protocol version ", ACP_PROTOCOL_VERSION);

    // Initialize server state
    _server = new ACPServer();

    // Main message processing loop
    while true {
      var line: string;
      try {
        if !stdin.readLine(line) {
          stderr.writeln("ACP: EOF received, shutting down");
          break;
        }
      } catch {
        stderr.writeln("ACP: Error reading from stdin, shutting down");
        break;
      }

      const trimmedLine = line.strip();
      if trimmedLine == "" {
        continue;  // Skip empty lines
      }

      stderr.writeln("ACP: Received: ", trimmedLine);

      // Process the message and get response
      const response = handleACPMessage(trimmedLine);

      // Send response if non-empty
      if response != "" {
        stderr.writeln("ACP: Sending: ", response);
        try {
          stdout.writeln(response);
          stdout.flush();
        } catch {
          stderr.writeln("ACP: Error writing to stdout");
          break;
        }
      }

      // Check for shutdown
      if _server.state == ACPState.Shutdown {
        stderr.writeln("ACP: Shutdown requested, exiting");
        break;
      }
    }

    stderr.writeln("ACP: Server stopped");
  }

  // ============================================================
  // Message Processing
  // ============================================================

  /*
   * Route an incoming ACP message to the appropriate handler
   *
   * @param line: Raw JSON message
   * @return: JSON response string (empty for notifications)
   */
  proc handleACPMessage(line: string): string {
    // Parse the JSON-RPC message
    const (parseOk, req) = Protocol.parseRequest(line);

    if !parseOk {
      stderr.writeln("ACP: Failed to parse request");
      return Protocol.makeErrorResponse(-1, Protocol.PARSE_ERROR,
                                         "Failed to parse JSON-RPC request");
    }

    stderr.writeln("ACP: Method: ", req.method, ", ID: ", req.id);

    // Route based on method
    select req.method {
      // Connection lifecycle
      when "initialize" {
        return handleInitialize(req);
      }
      when "initialized" {
        // Notification - no response needed
        handleInitializedNotification();
        return "";
      }
      when "shutdown" {
        return handleShutdown(req);
      }

      // Session management (ACP-specific)
      when "session/new" {
        return handleSessionNew(req);
      }
      when "session/load" {
        return handleSessionLoad(req);
      }
      when "session/prompt" {
        return handleSessionPrompt(req);
      }
      when "session/cancel" {
        return handleSessionCancel(req);
      }

      // MCP-compatible tool operations (for compatibility)
      when "tools/list" {
        return handleToolsList(req);
      }
      when "tools/call" {
        return handleToolsCall(req);
      }

      // Utility methods
      when "ping" {
        return handlePing(req);
      }

      otherwise {
        stderr.writeln("ACP: Unknown method: ", req.method);
        return Protocol.makeErrorResponse(req.id, Protocol.METHOD_NOT_FOUND,
                                           "Method not found: " + req.method);
      }
    }
  }

  /*
   * Handle initialized notification
   */
  proc handleInitializedNotification() {
    stderr.writeln("ACP: Client sent initialized notification");
    // The client has acknowledged the initialize response
  }

  // ============================================================
  // Connection Lifecycle Handlers
  // ============================================================

  /*
   * Handle initialize request
   *
   * The client sends this as the first message to negotiate protocol version
   * and exchange capabilities.
   *
   * Request params:
   *   - protocolVersion: int (required)
   *   - clientCapabilities: object (optional)
   *   - clientInfo: { name: string, version: string } (optional)
   *
   * Response result:
   *   - protocolVersion: int
   *   - agentCapabilities: object
   *   - agentInfo: { name: string, version: string }
   *   - authMethods: array (empty - no auth required)
   */
  proc handleInitialize(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleInitialize");

    if _server.state != ACPState.Uninitialized {
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_REQUEST,
                                         "Server already initialized");
    }

    // Parse client protocol version
    const (hasVersion, clientVersion) = Protocol.extractJsonInt(req.params, "protocolVersion");

    if !hasVersion {
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_PARAMS,
                                         "Missing required parameter: protocolVersion");
    }

    // Check version compatibility
    if clientVersion != ACP_PROTOCOL_VERSION {
      stderr.writeln("ACP: Client version ", clientVersion,
                     " differs from server version ", ACP_PROTOCOL_VERSION);
    }

    // Extract client info for logging
    const (hasClientInfo, clientInfo) = Protocol.extractJsonObject(req.params, "clientInfo");
    if hasClientInfo {
      const (hasName, clientName) = Protocol.extractJsonString(clientInfo, "name");
      const (hasVer, clientVer) = Protocol.extractJsonString(clientInfo, "version");
      if hasName {
        _server.clientName = clientName;
        stderr.writeln("ACP: Client: ", clientName);
      }
      if hasVer {
        _server.clientVersion = clientVer;
      }
    }

    // Update server state
    _server.state = ACPState.Initialized;

    // Build response per ACP spec
    var result = "{";

    // Protocol version (integer per spec)
    result += "\"protocolVersion\":" + ACP_PROTOCOL_VERSION:string;

    // Agent capabilities
    result += ",\"agentCapabilities\":{";
    result += "\"sessions\":{\"new\":true,\"load\":false}";
    result += ",\"prompts\":{\"text\":true,\"image\":false,\"audio\":false}";
    result += ",\"mcp\":{\"stdio\":true,\"http\":false,\"sse\":false}";
    result += "}";

    // Agent info (meta in ACP spec)
    result += ",\"agentInfo\":{";
    result += "\"name\":\"" + Protocol.escapeJsonString(ACP_SERVER_NAME) + "\"";
    result += ",\"version\":\"" + Protocol.escapeJsonString(ACP_SERVER_VERSION) + "\"";
    result += "}";

    // Auth methods (empty - no auth required)
    result += ",\"authMethods\":[]";

    result += "}";

    return Protocol.makeResponse(req.id, result);
  }

  /*
   * Handle shutdown request
   */
  proc handleShutdown(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleShutdown");
    _server.state = ACPState.Shutdown;
    return Protocol.makeResponse(req.id, "null");
  }

  /*
   * Handle ping request
   */
  proc handlePing(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handlePing");
    return Protocol.makeResponse(req.id, "{}");
  }

  // ============================================================
  // Session Management Handlers
  // ============================================================

  /*
   * Handle session/new request
   *
   * Creates a new conversation session.
   *
   * Request params:
   *   - cwd: string (required) - absolute path to working directory
   *   - mcpServers: array (optional) - MCP servers to connect
   *
   * Response result:
   *   - sessionId: string
   */
  proc handleSessionNew(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleSessionNew");

    if _server.state != ACPState.Initialized && _server.state != ACPState.InSession {
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_REQUEST,
                                         "Server not initialized");
    }

    // Extract working directory
    const (hasCwd, cwd) = Protocol.extractJsonString(req.params, "cwd");
    const workDir = if hasCwd then cwd else ".";

    // Generate unique session ID
    const sessionId = generateSessionId();

    // Create session
    var session = new ACPSession(
      sessionId = sessionId,
      createdAt = isoTimestamp(),
      lastActivity = isoTimestamp(),
      cwd = workDir,
      promptCount = 0,
      isActive = true
    );

    // Store session
    _server.sessions.add(sessionId, session);
    _server.currentSessionId = sessionId;
    _server.state = ACPState.InSession;

    stderr.writeln("ACP: Created session ", sessionId, " with cwd ", workDir);

    // Build response
    var result = "{";
    result += "\"sessionId\":\"" + Protocol.escapeJsonString(sessionId) + "\"";
    result += "}";

    return Protocol.makeResponse(req.id, result);
  }

  /*
   * Handle session/load request - not supported
   */
  proc handleSessionLoad(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleSessionLoad - not supported");
    return Protocol.makeErrorResponse(req.id, ACP_ERROR_SESSION_NOT_FOUND,
                                       "Session loading not supported. Use session/new instead.");
  }

  /*
   * Handle session/prompt request
   *
   * Process a user prompt within a session. This is the main interaction point.
   *
   * Request params:
   *   - sessionId: string (required)
   *   - prompt: array of ContentBlock (required)
   *
   * Response result:
   *   - stopReason: string
   *
   * During processing, the server sends session/update notifications.
   */
  proc handleSessionPrompt(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleSessionPrompt");

    // Extract session ID
    const (hasSessionId, sessionId) = Protocol.extractJsonString(req.params, "sessionId");

    if !hasSessionId || sessionId == "" {
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_PARAMS,
                                         "Missing required parameter: sessionId");
    }

    // Validate session exists
    if !_server.sessions.contains(sessionId) {
      return Protocol.makeErrorResponse(req.id, ACP_ERROR_SESSION_NOT_FOUND,
                                         "Session not found: " + sessionId);
    }

    // Get session and update activity
    var session = _server.sessions[sessionId];
    session.lastActivity = isoTimestamp();
    session.promptCount += 1;

    // Extract prompt content
    var promptText = "";
    const (hasPrompt, promptArray) = Protocol.extractJsonObject(req.params, "prompt");
    if hasPrompt {
      const (hasText, text) = Protocol.extractJsonString(promptArray, "text");
      if hasText {
        promptText = text;
      }
    }

    // Fallback: try raw prompt string
    if promptText == "" {
      const (hasRaw, raw) = Protocol.extractJsonString(req.params, "prompt");
      if hasRaw {
        promptText = raw;
      }
    }

    stderr.writeln("ACP: Session ", sessionId, " prompt #", session.promptCount, ": ", promptText);

    // Process the prompt and send streaming updates
    const stopReason = processPrompt(sessionId, promptText, session.cwd);

    // Update session
    _server.sessions[sessionId] = session;

    // Build response
    var result = "{";
    result += "\"stopReason\":\"" + stopReasonToString(stopReason) + "\"";
    result += "}";

    return Protocol.makeResponse(req.id, result);
  }

  /*
   * Handle session/cancel request
   */
  proc handleSessionCancel(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleSessionCancel");

    const (hasSessionId, sessionId) = Protocol.extractJsonString(req.params, "sessionId");

    if !hasSessionId || sessionId == "" {
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_PARAMS,
                                         "Missing required parameter: sessionId");
    }

    if !_server.sessions.contains(sessionId) {
      return Protocol.makeErrorResponse(req.id, ACP_ERROR_SESSION_NOT_FOUND,
                                         "Session not found: " + sessionId);
    }

    stderr.writeln("ACP: Session ", sessionId, " cancel requested");
    return Protocol.makeResponse(req.id, "{}");
  }

  // ============================================================
  // Tool Handlers (MCP-compatible)
  // ============================================================

  /*
   * Handle tools/list request
   */
  proc handleToolsList(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleToolsList");

    const tools = Tools.getToolDefinitions();
    var toolsJson = "[";
    var first = true;

    for tool in tools {
      if !first then toolsJson += ",";
      first = false;

      toolsJson += "{";
      toolsJson += "\"name\":\"" + Protocol.escapeJsonString(tool.name) + "\"";
      toolsJson += ",\"description\":\"" + Protocol.escapeJsonString(tool.description) + "\"";
      toolsJson += ",\"inputSchema\":" + tool.inputSchema;
      toolsJson += "}";
    }

    toolsJson += "]";

    return Protocol.makeResponse(req.id, "{\"tools\":" + toolsJson + "}");
  }

  /*
   * Handle tools/call request
   */
  proc handleToolsCall(req: Protocol.JsonRpcRequest): string {
    stderr.writeln("ACP: handleToolsCall");

    // Extract tool name
    const (hasName, toolName) = Protocol.extractJsonString(req.params, "name");
    if !hasName || toolName == "" {
      return Protocol.makeErrorResponse(req.id, Protocol.INVALID_PARAMS,
                                         "Missing required parameter: name");
    }

    // Extract arguments
    const (hasArgs, toolArgs) = Protocol.extractJsonObject(req.params, "arguments");
    const args = if hasArgs then toolArgs else "{}";

    stderr.writeln("ACP: Calling tool: ", toolName);

    // Execute the tool
    const (success, resultText) = Tools.executeTool(toolName, args);

    // Format response
    var content = "{\"content\":[{";
    content += "\"type\":\"text\"";
    content += ",\"text\":\"" + Protocol.escapeJsonString(resultText) + "\"";
    content += "}]";
    content += ",\"isError\":" + (if success then "false" else "true");
    content += "}";

    return Protocol.makeResponse(req.id, content);
  }

  // ============================================================
  // Prompt Processing
  // ============================================================

  /*
   * Process a user prompt and send streaming updates
   *
   * This parses user intent and executes appropriate tools,
   * streaming updates as work progresses.
   */
  proc processPrompt(sessionId: string, prompt: string, cwd: string): StopReason {
    stderr.writeln("ACP: processPrompt for session ", sessionId);

    // Send initial acknowledgment
    sendTextUpdate(sessionId, "Processing your request...");

    // Parse intent from prompt
    const intent = parseIntent(prompt);
    stderr.writeln("ACP: Detected intent: ", intent);

    // Handle based on intent
    select intent {
      when "list" {
        sendTextUpdate(sessionId, "Listing git identities...");
        sendToolCallUpdate(sessionId, "juggler_list_identities", ToolCallStatus.Running);

        const (success, result) = Tools.executeTool("juggler_list_identities", "{}");

        sendToolCallUpdate(sessionId, "juggler_list_identities",
                           if success then ToolCallStatus.Completed else ToolCallStatus.Failed);
        sendTextUpdate(sessionId, result);
      }

      when "detect" {
        sendTextUpdate(sessionId, "Detecting repository identity...");
        sendToolCallUpdate(sessionId, "juggler_detect_identity", ToolCallStatus.Running);

        const params = "{\"repoPath\":\"" + Protocol.escapeJsonString(cwd) + "\"}";
        const (success, result) = Tools.executeTool("juggler_detect_identity", params);

        sendToolCallUpdate(sessionId, "juggler_detect_identity",
                           if success then ToolCallStatus.Completed else ToolCallStatus.Failed);
        sendTextUpdate(sessionId, result);
      }

      when "switch" {
        const identity = extractIdentityFromPrompt(prompt);

        if identity == "" {
          sendTextUpdate(sessionId, "Please specify which identity to switch to (e.g., 'personal', 'work', 'github-personal')");
          return StopReason.Completed;
        }

        sendTextUpdate(sessionId, "Switching to identity: " + identity + "...");
        sendToolCallUpdate(sessionId, "juggler_switch", ToolCallStatus.Running);

        const params = "{\"identity\":\"" + Protocol.escapeJsonString(identity) +
                       "\",\"repoPath\":\"" + Protocol.escapeJsonString(cwd) + "\"}";
        const (success, result) = Tools.executeTool("juggler_switch", params);

        sendToolCallUpdate(sessionId, "juggler_switch",
                           if success then ToolCallStatus.Completed else ToolCallStatus.Failed);
        sendTextUpdate(sessionId, result);
      }

      when "validate" {
        const identity = extractIdentityFromPrompt(prompt);

        if identity == "" {
          sendTextUpdate(sessionId, "Please specify which identity to validate.");
          return StopReason.Completed;
        }

        sendTextUpdate(sessionId, "Validating identity: " + identity + "...");
        sendToolCallUpdate(sessionId, "juggler_validate", ToolCallStatus.Running);

        const params = "{\"identity\":\"" + Protocol.escapeJsonString(identity) + "\"}";
        const (success, result) = Tools.executeTool("juggler_validate", params);

        sendToolCallUpdate(sessionId, "juggler_validate",
                           if success then ToolCallStatus.Completed else ToolCallStatus.Failed);
        sendTextUpdate(sessionId, result);
      }

      when "status" {
        sendTextUpdate(sessionId, "Getting current status...");
        sendToolCallUpdate(sessionId, "juggler_status", ToolCallStatus.Running);

        const params = "{\"repoPath\":\"" + Protocol.escapeJsonString(cwd) + "\"}";
        const (success, result) = Tools.executeTool("juggler_status", params);

        sendToolCallUpdate(sessionId, "juggler_status",
                           if success then ToolCallStatus.Completed else ToolCallStatus.Failed);
        sendTextUpdate(sessionId, result);
      }

      when "sync" {
        sendTextUpdate(sessionId, "Synchronizing configuration...");
        sendToolCallUpdate(sessionId, "juggler_sync_config", ToolCallStatus.Running);

        const (success, result) = Tools.executeTool("juggler_sync_config", "{}");

        sendToolCallUpdate(sessionId, "juggler_sync_config",
                           if success then ToolCallStatus.Completed else ToolCallStatus.Failed);
        sendTextUpdate(sessionId, result);
      }

      when "help" {
        sendHelpText(sessionId);
      }

      otherwise {
        sendTextUpdate(sessionId, "I didn't understand that request.\n\n");
        sendHelpText(sessionId);
      }
    }

    return StopReason.Completed;
  }

  /*
   * Parse user intent from prompt text
   */
  proc parseIntent(prompt: string): string {
    const lowerPrompt = prompt.toLower();

    if lowerPrompt.find("list") != -1 && lowerPrompt.find("identit") != -1 {
      return "list";
    }
    if lowerPrompt.find("show") != -1 && lowerPrompt.find("identit") != -1 {
      return "list";
    }
    if lowerPrompt.find("detect") != -1 {
      return "detect";
    }
    if lowerPrompt.find("which") != -1 && lowerPrompt.find("identity") != -1 {
      return "detect";
    }
    if lowerPrompt.find("switch") != -1 {
      return "switch";
    }
    if lowerPrompt.find("change") != -1 && lowerPrompt.find("identity") != -1 {
      return "switch";
    }
    if lowerPrompt.find("use") != -1 && (lowerPrompt.find("personal") != -1 ||
       lowerPrompt.find("work") != -1 || lowerPrompt.find("github") != -1) {
      return "switch";
    }
    if lowerPrompt.find("validate") != -1 || lowerPrompt.find("test") != -1 {
      return "validate";
    }
    if lowerPrompt.find("check") != -1 && lowerPrompt.find("connect") != -1 {
      return "validate";
    }
    if lowerPrompt.find("status") != -1 || lowerPrompt.find("current") != -1 {
      return "status";
    }
    if lowerPrompt.find("sync") != -1 {
      return "sync";
    }
    if lowerPrompt.find("help") != -1 || lowerPrompt == "?" {
      return "help";
    }

    return "unknown";
  }

  /*
   * Extract identity name from prompt
   */
  proc extractIdentityFromPrompt(prompt: string): string {
    const lowerPrompt = prompt.toLower();

    // Check for known identity names
    if lowerPrompt.find("github-personal") != -1 ||
       lowerPrompt.find("github personal") != -1 ||
       (lowerPrompt.find("github") != -1 && lowerPrompt.find("personal") != -1) {
      return "github-personal";
    }
    if lowerPrompt.find("personal") != -1 {
      return "personal";
    }
    if lowerPrompt.find("work") != -1 {
      return "work";
    }
    if lowerPrompt.find("github") != -1 {
      return "github-personal";
    }

    return "";
  }

  /*
   * Send help text
   */
  proc sendHelpText(sessionId: string) {
    var help = "RemoteJuggler - Git Identity Management\n";
    help += "========================================\n\n";
    help += "Available commands:\n\n";
    help += "- 'list identities' - Show all configured git identities\n";
    help += "- 'detect identity' - Detect identity for current repository\n";
    help += "- 'switch to [personal|work|github-personal]' - Switch identity\n";
    help += "- 'validate [identity]' - Test SSH and API connectivity\n";
    help += "- 'status' - Show current identity and auth status\n";
    help += "- 'sync config' - Synchronize SSH/git config\n";
    help += "- 'help' - Show this help message\n";

    sendTextUpdate(sessionId, help);
  }

  // ============================================================
  // Streaming Updates
  // ============================================================

  /*
   * Send a session/update notification with a text block
   */
  proc sendTextUpdate(sessionId: string, text: string) {
    var params = "{";
    params += "\"sessionId\":\"" + Protocol.escapeJsonString(sessionId) + "\"";
    params += ",\"update\":{";
    params += "\"type\":\"content_chunk\"";
    params += ",\"content\":[{";
    params += "\"type\":\"text\"";
    params += ",\"text\":\"" + Protocol.escapeJsonString(text) + "\"";
    params += "}]";
    params += "}}";

    const notification = Protocol.makeNotification("session/update", params);
    sendNotification(notification);
  }

  /*
   * Send a session/update notification with tool call status
   */
  proc sendToolCallUpdate(sessionId: string, toolName: string, status: ToolCallStatus) {
    var params = "{";
    params += "\"sessionId\":\"" + Protocol.escapeJsonString(sessionId) + "\"";
    params += ",\"update\":{";
    params += "\"type\":\"tool_call\"";
    params += ",\"tool\":\"" + Protocol.escapeJsonString(toolName) + "\"";
    params += ",\"status\":\"" + toolCallStatusToString(status) + "\"";
    params += "}}";

    const notification = Protocol.makeNotification("session/update", params);
    sendNotification(notification);
  }

  /*
   * Send a notification to stdout
   */
  proc sendNotification(notification: string) {
    stderr.writeln("ACP: Sending notification: ", notification);
    try {
      stdout.writeln(notification);
      stdout.flush();
    } catch {
      stderr.writeln("ACP: Error sending notification");
    }
  }

  // ============================================================
  // Helper Functions
  // ============================================================

  /*
   * Generate a unique session ID
   */
  proc generateSessionId(): string {
    var rng = new randomStream(uint(8));
    var id = "sess-";

    const hexChars = "0123456789abcdef";
    for i in 0..<16 {
      const idx = (rng.next() % 16):int;
      id += hexChars[idx..idx];
    }

    return id;
  }

  /*
   * Get ISO 8601 timestamp
   */
  proc isoTimestamp(): string {
    try {
      const now = dateTime.now();
      // Manual ISO 8601 formatting since isoFormat() may not be available
      return "%04i-%02i-%02iT%02i:%02i:%02iZ".format(
        now.year, now.month:int, now.day,
        now.hour, now.minute, now.second
      );
    } catch {
      return "1970-01-01T00:00:00Z";
    }
  }

  /*
   * Convert StopReason to string
   */
  proc stopReasonToString(reason: StopReason): string {
    select reason {
      when StopReason.Completed do return "completed";
      when StopReason.Cancelled do return "cancelled";
      when StopReason.Error do return "error";
      when StopReason.ToolLimit do return "tool_limit";
      when StopReason.MaxTokens do return "max_tokens";
      otherwise do return "unknown";
    }
  }

  /*
   * Convert ToolCallStatus to string
   */
  proc toolCallStatusToString(status: ToolCallStatus): string {
    select status {
      when ToolCallStatus.Pending do return "pending";
      when ToolCallStatus.Running do return "running";
      when ToolCallStatus.Completed do return "completed";
      when ToolCallStatus.Failed do return "failed";
      otherwise do return "unknown";
    }
  }

  // ============================================================
  // Session Helpers
  // ============================================================

  /*
   * Create a new session
   */
  proc createSession(cwd: string = "."): string {
    const sessionId = generateSessionId();

    var session = new ACPSession(
      sessionId = sessionId,
      createdAt = isoTimestamp(),
      lastActivity = isoTimestamp(),
      cwd = cwd,
      isActive = true
    );

    _server.sessions.add(sessionId, session);
    _server.currentSessionId = sessionId;

    return sessionId;
  }

  /*
   * Get a session by ID
   */
  proc getSession(sessionId: string): (bool, ACPSession) {
    if _server.sessions.contains(sessionId) {
      return (true, _server.sessions[sessionId]);
    }
    return (false, new ACPSession());
  }

  /*
   * Check if a session exists
   */
  proc hasSession(sessionId: string): bool {
    return _server.sessions.contains(sessionId);
  }

  /*
   * Delete a session
   */
  proc deleteSession(sessionId: string): bool {
    if _server.sessions.contains(sessionId) {
      _server.sessions.remove(sessionId);
      if _server.currentSessionId == sessionId {
        _server.currentSessionId = "";
      }
      return true;
    }
    return false;
  }

  // ============================================================
  // Content Block Helpers
  // ============================================================

  /*
   * Create a text content block
   */
  proc makeTextBlock(text: string): ContentBlock {
    return new ContentBlock(
      blockType = ContentBlockType.TextBlock,
      text = text
    );
  }

  /*
   * Create a tool call content block
   */
  proc makeToolCallBlock(toolName: string, status: ToolCallStatus): ContentBlock {
    return new ContentBlock(
      blockType = ContentBlockType.ToolCallBlock,
      toolName = toolName,
      toolStatus = status
    );
  }

  /*
   * Convert a content block to JSON
   */
  proc contentBlockToJson(block: ContentBlock): string {
    select block.blockType {
      when ContentBlockType.TextBlock {
        return "{\"type\":\"text\",\"text\":\"" +
               Protocol.escapeJsonString(block.text) + "\"}";
      }
      when ContentBlockType.ToolCallBlock {
        var json = "{\"type\":\"tool_call\"";
        json += ",\"tool\":\"" + Protocol.escapeJsonString(block.toolName) + "\"";
        json += ",\"status\":\"" + toolCallStatusToString(block.toolStatus) + "\"";
        json += "}";
        return json;
      }
      when ContentBlockType.ErrorBlock {
        return "{\"type\":\"error\",\"message\":\"" +
               Protocol.escapeJsonString(block.text) + "\"}";
      }
      otherwise {
        return "{\"type\":\"unknown\"}";
      }
    }
  }

  /*
   * Send a session update with multiple content blocks
   */
  proc sendSessionUpdate(sessionId: string, updates: list(ContentBlock)) {
    var blocksJson = "[";
    var first = true;

    for block in updates {
      if !first then blocksJson += ",";
      first = false;
      blocksJson += contentBlockToJson(block);
    }

    blocksJson += "]";

    var params = "{";
    params += "\"sessionId\":\"" + Protocol.escapeJsonString(sessionId) + "\"";
    params += ",\"update\":{";
    params += "\"type\":\"content_chunk\"";
    params += ",\"content\":" + blocksJson;
    params += "}}";

    const notification = Protocol.makeNotification("session/update", params);
    sendNotification(notification);
  }
}
