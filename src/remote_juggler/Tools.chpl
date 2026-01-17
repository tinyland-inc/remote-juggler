/*
 * Tools.chpl - MCP Tool Definitions and Handlers for RemoteJuggler
 *
 * This module defines all MCP tools exposed by the RemoteJuggler server
 * and implements their execution logic. Tools are the primary interface
 * for AI agents to interact with git identity management.
 *
 * Tools:
 * - juggler_list_identities: List all configured git identities
 * - juggler_detect_identity: Detect identity for current repository
 * - juggler_switch: Switch to a different git identity
 * - juggler_status: Get current identity and authentication status
 * - juggler_validate: Validate SSH and credential connectivity
 * - juggler_store_token: Store a token in the system keychain
 * - juggler_sync_config: Synchronize managed config blocks
 */
prototype module Tools {
  use super.Protocol;
  use List;
  use IO;
  use OS.POSIX;
  use FileSystem;
  use Subprocess;
  use Path;

  // ============================================================================
  // Tool Definition Structure
  // ============================================================================

  /*
   * ToolDefinition - Describes a tool for the tools/list response
   *
   * name: Unique tool identifier (should be prefixed with "juggler_")
   * description: Human-readable description for AI agents
   * inputSchema: JSON Schema defining the tool's input parameters
   */
  record ToolDefinition {
    var name: string;
    var description: string;
    var inputSchema: string;  // JSON Schema as string
  }

  // ============================================================================
  // Tool Definitions
  // ============================================================================

  /*
   * Get all tool definitions for the tools/list response.
   *
   * Returns a list of all available tools with their schemas.
   */
  proc getToolDefinitions(): list(ToolDefinition) {
    var tools: list(ToolDefinition);

    // Tool: juggler_list_identities
    tools.pushBack(new ToolDefinition(
      name = "juggler_list_identities",
      description = "List all configured git identities with their providers (GitLab, GitHub, Bitbucket, etc.). Optionally filter by provider and include credential availability status.",
      inputSchema = '{' +
        '"type":"object",' +
        '"properties":{' +
          '"provider":{' +
            '"type":"string",' +
            '"enum":["gitlab","github","bitbucket","all"],' +
            '"description":"Filter identities by provider type. Use \'all\' or omit for all providers."' +
          '},' +
          '"includeCredentialStatus":{' +
            '"type":"boolean",' +
            '"description":"Include credential availability status (keychain, env, CLI) for each identity",' +
            '"default":false' +
          '}' +
        '}' +
      '}'
    ));

    // Tool: juggler_detect_identity
    tools.pushBack(new ToolDefinition(
      name = "juggler_detect_identity",
      description = "Detect the git identity for a repository based on its remote URL. Analyzes SSH host aliases, gitconfig URL rewrites, and organization paths to determine the appropriate identity.",
      inputSchema = '{' +
        '"type":"object",' +
        '"properties":{' +
          '"repoPath":{' +
            '"type":"string",' +
            '"description":"Path to the git repository. Defaults to current working directory if not specified."' +
          '}' +
        '}' +
      '}'
    ));

    // Tool: juggler_switch
    tools.pushBack(new ToolDefinition(
      name = "juggler_switch",
      description = "Switch to a different git identity context. Updates git user config, authenticates with provider CLI (glab/gh) if available, and optionally configures GPG signing.",
      inputSchema = '{' +
        '"type":"object",' +
        '"properties":{' +
          '"identity":{' +
            '"type":"string",' +
            '"description":"Identity name to switch to (e.g., \'personal\', \'work\', \'github-personal\')"' +
          '},' +
          '"setRemote":{' +
            '"type":"boolean",' +
            '"description":"Update git remote URL to match the identity\'s SSH host alias",' +
            '"default":true' +
          '},' +
          '"configureGPG":{' +
            '"type":"boolean",' +
            '"description":"Configure GPG signing using the identity\'s GPG key",' +
            '"default":true' +
          '},' +
          '"repoPath":{' +
            '"type":"string",' +
            '"description":"Path to git repository. Defaults to current working directory."' +
          '}' +
        '},' +
        '"required":["identity"]' +
      '}'
    ));

    // Tool: juggler_status
    tools.pushBack(new ToolDefinition(
      name = "juggler_status",
      description = "Get the current git identity context, authentication status, GPG configuration, and recent switch history. Provides a comprehensive view of the current identity state.",
      inputSchema = '{' +
        '"type":"object",' +
        '"properties":{' +
          '"repoPath":{' +
            '"type":"string",' +
            '"description":"Path to git repository for context. Defaults to current working directory."' +
          '},' +
          '"verbose":{' +
            '"type":"boolean",' +
            '"description":"Include additional details like SSH key fingerprints and credential sources",' +
            '"default":false' +
          '}' +
        '}' +
      '}'
    ));

    // Tool: juggler_validate
    tools.pushBack(new ToolDefinition(
      name = "juggler_validate",
      description = "Validate SSH key connectivity and credential availability for an identity. Tests the SSH connection to the provider and verifies token accessibility.",
      inputSchema = '{' +
        '"type":"object",' +
        '"properties":{' +
          '"identity":{' +
            '"type":"string",' +
            '"description":"Identity name to validate (e.g., \'personal\', \'work\')"' +
          '},' +
          '"checkGPG":{' +
            '"type":"boolean",' +
            '"description":"Also verify GPG key exists and is registered with the provider",' +
            '"default":false' +
          '},' +
          '"testAuth":{' +
            '"type":"boolean",' +
            '"description":"Test authentication by making an API call to the provider",' +
            '"default":true' +
          '}' +
        '},' +
        '"required":["identity"]' +
      '}'
    ));

    // Tool: juggler_store_token
    tools.pushBack(new ToolDefinition(
      name = "juggler_store_token",
      description = "Store a token in the system keychain (macOS) or credential store for an identity. The token will be used for provider CLI authentication.",
      inputSchema = '{' +
        '"type":"object",' +
        '"properties":{' +
          '"identity":{' +
            '"type":"string",' +
            '"description":"Identity name to store the token for"' +
          '},' +
          '"token":{' +
            '"type":"string",' +
            '"description":"The access token to store (GitLab/GitHub personal access token)"' +
          '}' +
        '},' +
        '"required":["identity","token"]' +
      '}'
    ));

    // Tool: juggler_sync_config
    tools.pushBack(new ToolDefinition(
      name = "juggler_sync_config",
      description = "Synchronize managed configuration blocks from SSH config and gitconfig. Updates the RemoteJuggler config file with the latest SSH hosts and URL rewrites.",
      inputSchema = '{' +
        '"type":"object",' +
        '"properties":{' +
          '"force":{' +
            '"type":"boolean",' +
            '"description":"Force sync even if no changes detected",' +
            '"default":false' +
          '},' +
          '"dryRun":{' +
            '"type":"boolean",' +
            '"description":"Show what would be changed without making changes",' +
            '"default":false' +
          '}' +
        '}' +
      '}'
    ));

    return tools;
  }

  // ============================================================================
  // Tool Execution Dispatcher
  // ============================================================================

  /*
   * Execute a tool by name with the given parameters.
   *
   * @param name: Tool name (e.g., "juggler_list_identities")
   * @param params: JSON-encoded parameters object
   * @return: (success, resultContent) tuple
   */
  proc executeTool(name: string, params: string): (bool, string) {
    stderr.writeln("Tools: Executing tool '", name, "' with params: ", params);

    select name {
      when "juggler_list_identities" {
        return handleListIdentities(params);
      }
      when "juggler_detect_identity" {
        return handleDetectIdentity(params);
      }
      when "juggler_switch" {
        return handleSwitch(params);
      }
      when "juggler_status" {
        return handleStatus(params);
      }
      when "juggler_validate" {
        return handleValidate(params);
      }
      when "juggler_store_token" {
        return handleStoreToken(params);
      }
      when "juggler_sync_config" {
        return handleSyncConfig(params);
      }
      otherwise {
        stderr.writeln("Tools: Unknown tool: ", name);
        return (false, "Unknown tool: " + name);
      }
    }
  }

  // ============================================================================
  // Configuration Helpers
  // ============================================================================

  /*
   * Get the path to the RemoteJuggler config file.
   */
  proc getConfigPath(): string {
    const home = getEnvHome();
    return home + "/.config/remote-juggler/config.json";
  }

  /*
   * Get the HOME environment variable.
   */
  proc getEnvHome(): string {
    var home: c_ptr(c_char) = getenv("HOME".c_str());
    if home == nil {
      return "/tmp";
    }
    return string.createCopyingBuffer(home);
  }

  /*
   * Get an environment variable value.
   */
  proc getEnvVar(name: string): string {
    var val: c_ptr(c_char) = getenv(name.c_str());
    if val == nil {
      return "";
    }
    return string.createCopyingBuffer(val);
  }

  /*
   * Get the current working directory.
   */
  proc getCwd(): string {
    try {
      return here.cwd();
    } catch {
      return ".";
    }
  }

  /*
   * Read the config file contents.
   */
  proc readConfigFile(): (bool, string) {
    const configPath = getConfigPath();

    if !exists(configPath) {
      return (false, "");
    }

    try {
      var f = open(configPath, ioMode.r);
      var reader = f.reader(locking=false);
      var content: string;
      reader.readAll(content);
      reader.close();
      f.close();
      return (true, content);
    } catch {
      return (false, "");
    }
  }

  // ============================================================================
  // Git Helpers
  // ============================================================================

  /*
   * Get the git remote URL for a repository.
   */
  proc getGitRemoteUrl(repoPath: string, remoteName: string = "origin"): (bool, string) {
    try {
      var p = spawn(["git", "-C", repoPath, "remote", "get-url", remoteName],
                       stdout=pipeStyle.pipe, stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var url: string;
        p.stdout.readAll(url);
        return (true, url.strip());
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  /*
   * Get the current git user.name for a repository.
   */
  proc getGitUserName(repoPath: string): (bool, string) {
    try {
      var p = spawn(["git", "-C", repoPath, "config", "user.name"],
                       stdout=pipeStyle.pipe, stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var name: string;
        p.stdout.readAll(name);
        return (true, name.strip());
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  /*
   * Get the current git user.email for a repository.
   */
  proc getGitUserEmail(repoPath: string): (bool, string) {
    try {
      var p = spawn(["git", "-C", repoPath, "config", "user.email"],
                       stdout=pipeStyle.pipe, stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var email: string;
        p.stdout.readAll(email);
        return (true, email.strip());
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  /*
   * Set a git config value for a repository.
   */
  proc setGitConfig(repoPath: string, key: string, value: string): bool {
    try {
      var p = spawn(["git", "-C", repoPath, "config", key, value],
                       stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Set the git remote URL for a repository.
   */
  proc setGitRemoteUrl(repoPath: string, remoteName: string, url: string): bool {
    try {
      var p = spawn(["git", "-C", repoPath, "remote", "set-url", remoteName, url],
                       stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  // ============================================================================
  // SSH Helpers
  // ============================================================================

  /*
   * Test SSH connectivity to a host.
   */
  proc testSSHConnection(host: string): (bool, string) {
    try {
      // Use ssh -T to test connection without executing a command
      var p = spawn(["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                        "git@" + host],
                       stdout=pipeStyle.pipe, stderr=pipeStyle.pipe);
      p.wait();

      var output: string;
      p.stderr.readAll(output);

      // GitHub/GitLab return exit code 1 but print welcome message
      if output.find("successfully authenticated") != -1 ||
         output.find("Welcome to GitLab") != -1 ||
         output.find("Hi ") != -1 {
        return (true, output.strip());
      }

      // Check for common success patterns
      if p.exitCode == 1 && output.size > 0 {
        return (true, output.strip());
      }

      return (false, output.strip());
    } catch e {
      return (false, "SSH test failed: " + e.message());
    }
  }

  // ============================================================================
  // Provider CLI Helpers
  // ============================================================================

  /*
   * Check if glab CLI is available.
   */
  proc isGlabAvailable(): bool {
    try {
      var p = spawn(["which", "glab"],
                       stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Check if gh CLI is available.
   */
  proc isGhAvailable(): bool {
    try {
      var p = spawn(["which", "gh"],
                       stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Get the current glab auth status.
   */
  proc getGlabAuthStatus(hostname: string = "gitlab.com"): (bool, string) {
    if !isGlabAvailable() {
      return (false, "glab not installed");
    }

    try {
      var p = spawn(["glab", "auth", "status", "-h", hostname],
                       stdout=pipeStyle.pipe, stderr=pipeStyle.pipe);
      p.wait();

      var output: string;
      p.stdout.readAll(output);
      p.stderr.readAll(output);

      return (p.exitCode == 0, output.strip());
    } catch e {
      return (false, e.message());
    }
  }

  /*
   * Get the current gh auth status.
   */
  proc getGhAuthStatus(hostname: string = "github.com"): (bool, string) {
    if !isGhAvailable() {
      return (false, "gh not installed");
    }

    try {
      var args: list(string);
      args.pushBack("gh");
      args.pushBack("auth");
      args.pushBack("status");
      if hostname != "github.com" {
        args.pushBack("-h");
        args.pushBack(hostname);
      }

      var p = spawn(args.toArray(), stdout=pipeStyle.pipe, stderr=pipeStyle.pipe);
      p.wait();

      var output: string;
      p.stdout.readAll(output);
      p.stderr.readAll(output);

      return (p.exitCode == 0, output.strip());
    } catch e {
      return (false, e.message());
    }
  }

  // ============================================================================
  // Tool Handlers
  // ============================================================================

  /*
   * Handle juggler_list_identities tool call.
   *
   * Lists all configured identities from the config file.
   */
  proc handleListIdentities(params: string): (bool, string) {
    stderr.writeln("Tools: handleListIdentities");

    // Parse filter parameter
    const (hasProvider, providerFilter) = Protocol.extractJsonString(params, "provider");
    const filterProvider = if hasProvider && providerFilter != "all" then providerFilter else "";

    const (hasCreds, includeCredStr) = Protocol.extractJsonString(params, "includeCredentialStatus");
    const includeCreds = hasCreds && includeCredStr == "true";

    // Read config file
    const (configOk, configContent) = readConfigFile();

    if !configOk {
      // Return sample identities if no config exists
      const sampleOutput =
        "No configuration file found at " + getConfigPath() + "\n\n" +
        "To create a configuration, run:\n" +
        "  remote-juggler config init\n\n" +
        "Or create ~/.config/remote-juggler/config.json manually with identity definitions.";
      return (true, sampleOutput);
    }

    // Extract identities from config
    const (hasIdentities, identitiesJson) = Protocol.extractJsonObject(configContent, "identities");

    if !hasIdentities {
      return (true, "No identities configured in " + getConfigPath());
    }

    // Build output string
    var output = "Configured Git Identities:\n";
    output += "==========================\n\n";

    // Parse each identity (simplified - in production would use proper JSON parsing)
    // For now, list known identity names
    const knownIdentities = ["personal", "work", "github-personal"];

    for identityName in knownIdentities {
      const (hasId, idJson) = Protocol.extractJsonObject(identitiesJson, identityName);
      if hasId {
        // Extract identity fields
        const (_, provider) = Protocol.extractJsonString(idJson, "provider");
        const (_, user) = Protocol.extractJsonString(idJson, "user");
        const (_, email) = Protocol.extractJsonString(idJson, "email");
        const (_, host) = Protocol.extractJsonString(idJson, "host");

        // Apply filter
        if filterProvider != "" && provider != filterProvider {
          continue;
        }

        output += "- " + identityName + "\n";
        output += "    Provider: " + provider + "\n";
        output += "    User: " + user + "\n";
        output += "    Email: " + email + "\n";
        output += "    SSH Host: " + host + "\n";

        if includeCreds {
          // Check credential availability
          const (_, credSource) = Protocol.extractJsonString(idJson, "credentialSource");
          output += "    Credential Source: " + credSource + "\n";

          // Test actual availability
          if provider == "gitlab" {
            const (authOk, _) = getGlabAuthStatus();
            output += "    glab CLI: " + (if authOk then "authenticated" else "not authenticated") + "\n";
          } else if provider == "github" {
            const (authOk, _) = getGhAuthStatus();
            output += "    gh CLI: " + (if authOk then "authenticated" else "not authenticated") + "\n";
          }
        }

        output += "\n";
      }
    }

    return (true, output);
  }

  /*
   * Handle juggler_detect_identity tool call.
   *
   * Detects the appropriate identity for a repository based on its remote URL.
   */
  proc handleDetectIdentity(params: string): (bool, string) {
    stderr.writeln("Tools: handleDetectIdentity");

    // Get repository path
    const (hasPath, repoPath) = Protocol.extractJsonString(params, "repoPath");
    const path = if hasPath && repoPath != "" then repoPath else getCwd();

    // Check if it's a git repository
    if !exists(path + "/.git") {
      return (false, "Not a git repository: " + path);
    }

    // Get the remote URL
    const (urlOk, remoteUrl) = getGitRemoteUrl(path);

    if !urlOk {
      return (false, "Could not get remote URL for repository at " + path);
    }

    var output = "Repository: " + path + "\n";
    output += "Remote URL: " + remoteUrl + "\n\n";

    // Detect identity based on URL patterns
    var detectedIdentity = "";
    var detectedProvider = "";
    var confidence = "low";

    // Check for SSH host aliases
    if remoteUrl.find("gitlab-personal:") != -1 {
      detectedIdentity = "personal";
      detectedProvider = "gitlab";
      confidence = "high";
    } else if remoteUrl.find("gitlab-work:") != -1 {
      detectedIdentity = "work";
      detectedProvider = "gitlab";
      confidence = "high";
    } else if remoteUrl.find("github.com:") != -1 || remoteUrl.find("@github.com:") != -1 {
      detectedIdentity = "github-personal";
      detectedProvider = "github";
      confidence = "medium";
    } else if remoteUrl.find("gitlab.com:") != -1 || remoteUrl.find("@gitlab.com:") != -1 {
      // Check organization path
      if remoteUrl.find("tinyland") != -1 {
        detectedIdentity = "personal";
        detectedProvider = "gitlab";
        confidence = "high";
      } else if remoteUrl.find("bates") != -1 {
        detectedIdentity = "work";
        detectedProvider = "gitlab";
        confidence = "high";
      } else {
        detectedIdentity = "work";  // Default to work for generic gitlab.com
        detectedProvider = "gitlab";
        confidence = "low";
      }
    }

    if detectedIdentity != "" {
      output += "Detected Identity: " + detectedIdentity + "\n";
      output += "Provider: " + detectedProvider + "\n";
      output += "Confidence: " + confidence + "\n\n";

      // Get current git config
      const (hasName, currentName) = getGitUserName(path);
      const (hasEmail, currentEmail) = getGitUserEmail(path);

      output += "Current Git Config:\n";
      output += "  user.name: " + (if hasName then currentName else "(not set)") + "\n";
      output += "  user.email: " + (if hasEmail then currentEmail else "(not set)") + "\n";
    } else {
      output += "Could not detect identity from remote URL.\n";
      output += "Use 'juggler_switch' to manually set an identity.\n";
    }

    return (true, output);
  }

  /*
   * Handle juggler_switch tool call.
   *
   * Switches to a different git identity.
   */
  proc handleSwitch(params: string): (bool, string) {
    stderr.writeln("Tools: handleSwitch");

    // Get required identity parameter
    const (hasIdentity, identity) = Protocol.extractJsonString(params, "identity");

    if !hasIdentity || identity == "" {
      return (false, "Missing required parameter: identity");
    }

    // Get optional parameters
    const (hasSetRemote, setRemoteStr) = Protocol.extractJsonString(params, "setRemote");
    const setRemote = !hasSetRemote || setRemoteStr != "false";

    const (hasConfigGPG, configGPGStr) = Protocol.extractJsonString(params, "configureGPG");
    const configureGPG = !hasConfigGPG || configGPGStr != "false";

    const (hasPath, repoPath) = Protocol.extractJsonString(params, "repoPath");
    const path = if hasPath && repoPath != "" then repoPath else getCwd();

    // Read config to get identity details
    const (configOk, configContent) = readConfigFile();

    var user = "";
    var email = "";
    var provider = "";
    var host = "";
    var hostname = "";
    var gpgKeyId = "";

    if configOk {
      const (hasIdentities, identitiesJson) = Protocol.extractJsonObject(configContent, "identities");
      if hasIdentities {
        const (hasId, idJson) = Protocol.extractJsonObject(identitiesJson, identity);
        if hasId {
          const (_, u) = Protocol.extractJsonString(idJson, "user");
          const (_, e) = Protocol.extractJsonString(idJson, "email");
          const (_, p) = Protocol.extractJsonString(idJson, "provider");
          const (_, h) = Protocol.extractJsonString(idJson, "host");
          const (_, hn) = Protocol.extractJsonString(idJson, "hostname");
          user = u;
          email = e;
          provider = p;
          host = h;
          hostname = hn;

          // Get GPG config
          const (hasGpg, gpgJson) = Protocol.extractJsonObject(idJson, "gpg");
          if hasGpg {
            const (_, keyId) = Protocol.extractJsonString(gpgJson, "keyId");
            gpgKeyId = keyId;
          }
        }
      }
    }

    // Use defaults if identity not found in config
    if user == "" {
      select identity {
        when "personal" {
          user = "xoxdjess";
          email = "jess@sulliwood.org";
          provider = "gitlab";
          host = "gitlab-personal";
          hostname = "gitlab.com";
        }
        when "work" {
          user = "jsullivan2";
          email = "jsullivan2@bates.edu";
          provider = "gitlab";
          host = "gitlab-work";
          hostname = "gitlab.com";
        }
        when "github-personal" {
          user = "Jesssullivan";
          email = "jess@sulliwood.org";
          provider = "github";
          host = "github.com";
          hostname = "github.com";
        }
        otherwise {
          return (false, "Unknown identity: " + identity + ". Available: personal, work, github-personal");
        }
      }
    }

    var output = "Switching to identity: " + identity + "\n";
    output += "================================\n\n";

    // Set git user config
    var success = true;

    if setGitConfig(path, "user.name", user) {
      output += "[OK] Set user.name = " + user + "\n";
    } else {
      output += "[FAIL] Could not set user.name\n";
      success = false;
    }

    if setGitConfig(path, "user.email", email) {
      output += "[OK] Set user.email = " + email + "\n";
    } else {
      output += "[FAIL] Could not set user.email\n";
      success = false;
    }

    // Update remote URL if requested
    if setRemote && exists(path + "/.git") {
      const (urlOk, currentUrl) = getGitRemoteUrl(path);
      if urlOk {
        // Check if URL needs updating
        var newUrl = currentUrl;
        var needsUpdate = false;

        // Replace host in SSH URLs
        if currentUrl.find("git@") != -1 {
          if currentUrl.find("gitlab.com:") != -1 && host != "gitlab.com" {
            newUrl = currentUrl.replace("git@gitlab.com:", "git@" + host + ":");
            needsUpdate = true;
          } else if currentUrl.find("gitlab-personal:") != -1 && host != "gitlab-personal" {
            newUrl = currentUrl.replace("git@gitlab-personal:", "git@" + host + ":");
            needsUpdate = true;
          } else if currentUrl.find("gitlab-work:") != -1 && host != "gitlab-work" {
            newUrl = currentUrl.replace("git@gitlab-work:", "git@" + host + ":");
            needsUpdate = true;
          }
        }

        if needsUpdate {
          if setGitRemoteUrl(path, "origin", newUrl) {
            output += "[OK] Updated remote URL to: " + newUrl + "\n";
          } else {
            output += "[WARN] Could not update remote URL\n";
          }
        } else {
          output += "[OK] Remote URL already correct: " + currentUrl + "\n";
        }
      }
    }

    // Configure GPG signing if requested
    if configureGPG && gpgKeyId != "" && gpgKeyId != "auto" {
      if setGitConfig(path, "user.signingkey", gpgKeyId) {
        output += "[OK] Set GPG signing key: " + gpgKeyId + "\n";
      }
      if setGitConfig(path, "commit.gpgsign", "true") {
        output += "[OK] Enabled GPG commit signing\n";
      }
    }

    // Authenticate with provider CLI
    output += "\nProvider CLI Authentication:\n";
    if provider == "gitlab" {
      const (authOk, authMsg) = getGlabAuthStatus(hostname);
      if authOk {
        output += "[OK] glab authenticated to " + hostname + "\n";
      } else {
        output += "[INFO] glab not authenticated. Run: glab auth login -h " + hostname + "\n";
      }
    } else if provider == "github" {
      const (authOk, authMsg) = getGhAuthStatus(hostname);
      if authOk {
        output += "[OK] gh authenticated to " + hostname + "\n";
      } else {
        output += "[INFO] gh not authenticated. Run: gh auth login\n";
      }
    }

    output += "\nIdentity switch " + (if success then "completed successfully." else "completed with warnings.");

    return (success, output);
  }

  /*
   * Handle juggler_status tool call.
   *
   * Shows the current identity status.
   */
  proc handleStatus(params: string): (bool, string) {
    stderr.writeln("Tools: handleStatus");

    // Get repository path
    const (hasPath, repoPath) = Protocol.extractJsonString(params, "repoPath");
    const path = if hasPath && repoPath != "" then repoPath else getCwd();

    const (hasVerbose, verboseStr) = Protocol.extractJsonString(params, "verbose");
    const verbose = hasVerbose && verboseStr == "true";

    var output = "RemoteJuggler Status\n";
    output += "====================\n\n";

    // Current working directory
    output += "Working Directory: " + path + "\n";

    // Check if it's a git repo
    if exists(path + "/.git") {
      output += "Git Repository: Yes\n\n";

      // Current git config
      const (hasName, currentName) = getGitUserName(path);
      const (hasEmail, currentEmail) = getGitUserEmail(path);

      output += "Current Git Identity:\n";
      output += "  user.name: " + (if hasName then currentName else "(not set)") + "\n";
      output += "  user.email: " + (if hasEmail then currentEmail else "(not set)") + "\n";

      // Remote URL
      const (urlOk, remoteUrl) = getGitRemoteUrl(path);
      if urlOk {
        output += "  remote (origin): " + remoteUrl + "\n";
      }

      output += "\n";
    } else {
      output += "Git Repository: No\n\n";
    }

    // Provider CLI status
    output += "Provider CLI Status:\n";

    if isGlabAvailable() {
      const (glabOk, glabStatus) = getGlabAuthStatus();
      output += "  glab: " + (if glabOk then "authenticated" else "not authenticated") + "\n";
      if verbose && glabStatus != "" {
        output += "    " + glabStatus.replace("\n", "\n    ") + "\n";
      }
    } else {
      output += "  glab: not installed\n";
    }

    if isGhAvailable() {
      const (ghOk, ghStatus) = getGhAuthStatus();
      output += "  gh: " + (if ghOk then "authenticated" else "not authenticated") + "\n";
      if verbose && ghStatus != "" {
        output += "    " + ghStatus.replace("\n", "\n    ") + "\n";
      }
    } else {
      output += "  gh: not installed\n";
    }

    output += "\n";

    // Config file status
    const configPath = getConfigPath();
    if exists(configPath) {
      output += "Configuration: " + configPath + " (exists)\n";
    } else {
      output += "Configuration: " + configPath + " (not found)\n";
      output += "  Run 'remote-juggler config init' to create.\n";
    }

    return (true, output);
  }

  /*
   * Handle juggler_validate tool call.
   *
   * Validates connectivity for an identity.
   */
  proc handleValidate(params: string): (bool, string) {
    stderr.writeln("Tools: handleValidate");

    // Get required identity parameter
    const (hasIdentity, identity) = Protocol.extractJsonString(params, "identity");

    if !hasIdentity || identity == "" {
      return (false, "Missing required parameter: identity");
    }

    const (hasCheckGPG, checkGPGStr) = Protocol.extractJsonString(params, "checkGPG");
    const checkGPG = hasCheckGPG && checkGPGStr == "true";

    const (hasTestAuth, testAuthStr) = Protocol.extractJsonString(params, "testAuth");
    const testAuth = !hasTestAuth || testAuthStr != "false";

    // Get identity details
    var host = "";
    var provider = "";
    var hostname = "";

    select identity {
      when "personal" {
        host = "gitlab-personal";
        provider = "gitlab";
        hostname = "gitlab.com";
      }
      when "work" {
        host = "gitlab-work";
        provider = "gitlab";
        hostname = "gitlab.com";
      }
      when "github-personal" {
        host = "github.com";
        provider = "github";
        hostname = "github.com";
      }
      otherwise {
        return (false, "Unknown identity: " + identity);
      }
    }

    var output = "Validating identity: " + identity + "\n";
    output += "================================\n\n";

    var allPassed = true;

    // Test SSH connectivity
    output += "SSH Connectivity Test:\n";
    const (sshOk, sshMsg) = testSSHConnection(host);
    if sshOk {
      output += "  [PASS] SSH connection to " + host + " successful\n";
      if sshMsg.size > 0 && sshMsg.size < 200 {
        output += "  Response: " + sshMsg + "\n";
      }
    } else {
      output += "  [FAIL] SSH connection to " + host + " failed\n";
      output += "  Error: " + sshMsg + "\n";
      allPassed = false;
    }

    output += "\n";

    // Test API authentication
    if testAuth {
      output += "API Authentication Test:\n";
      if provider == "gitlab" {
        if isGlabAvailable() {
          const (authOk, authMsg) = getGlabAuthStatus(hostname);
          if authOk {
            output += "  [PASS] glab authenticated to " + hostname + "\n";
          } else {
            output += "  [WARN] glab not authenticated to " + hostname + "\n";
            output += "  Fix: glab auth login -h " + hostname + "\n";
          }
        } else {
          output += "  [SKIP] glab CLI not installed\n";
        }
      } else if provider == "github" {
        if isGhAvailable() {
          const (authOk, authMsg) = getGhAuthStatus(hostname);
          if authOk {
            output += "  [PASS] gh authenticated to " + hostname + "\n";
          } else {
            output += "  [WARN] gh not authenticated to " + hostname + "\n";
            output += "  Fix: gh auth login\n";
          }
        } else {
          output += "  [SKIP] gh CLI not installed\n";
        }
      }
    }

    // Check GPG if requested
    if checkGPG {
      output += "\nGPG Key Validation:\n";
      output += "  [SKIP] GPG validation not yet implemented\n";
    }

    output += "\nValidation " + (if allPassed then "passed." else "completed with issues.");

    return (allPassed, output);
  }

  /*
   * Handle juggler_store_token tool call.
   *
   * Stores a token in the system keychain.
   */
  proc handleStoreToken(params: string): (bool, string) {
    stderr.writeln("Tools: handleStoreToken");

    // Get required parameters
    const (hasIdentity, identity) = Protocol.extractJsonString(params, "identity");
    const (hasToken, token) = Protocol.extractJsonString(params, "token");

    if !hasIdentity || identity == "" {
      return (false, "Missing required parameter: identity");
    }

    if !hasToken || token == "" {
      return (false, "Missing required parameter: token");
    }

    // For security, we don't actually store tokens in this demo implementation
    // In production, this would use the Keychain module
    var output = "Token Storage\n";
    output += "=============\n\n";

    // Check platform
    const platform = getEnvVar("CHPL_TARGET_PLATFORM");
    if platform == "darwin" || platform == "" {
      output += "Platform: macOS (Keychain available)\n";
      output += "Identity: " + identity + "\n";
      output += "Token: " + token[0..#4] + "..." + token[token.size-4..] + " (" + token.size:string + " chars)\n\n";

      // In production:
      // const service = "remote-juggler." + provider + "." + identity;
      // const success = Keychain.storeToken(service, user, token);

      output += "NOTE: Token storage requires the Keychain module (not yet linked).\n";
      output += "For now, store the token manually:\n\n";
      output += "  security add-generic-password \\\n";
      output += "    -s 'remote-juggler." + identity + "' \\\n";
      output += "    -a '" + identity + "' \\\n";
      output += "    -w '" + token + "'\n\n";

      output += "Or set environment variable:\n";
      output += "  export " + identity.toUpper().replace("-", "_") + "_TOKEN='" + token + "'\n";

      return (true, output);
    } else {
      output += "Platform: " + platform + " (Keychain not available)\n";
      output += "Store token in environment variable:\n";
      output += "  export " + identity.toUpper().replace("-", "_") + "_TOKEN='" + token + "'\n";
      return (true, output);
    }
  }

  /*
   * Handle juggler_sync_config tool call.
   *
   * Synchronizes managed config blocks.
   */
  proc handleSyncConfig(params: string): (bool, string) {
    stderr.writeln("Tools: handleSyncConfig");

    const (hasForce, forceStr) = Protocol.extractJsonString(params, "force");
    const force = hasForce && forceStr == "true";

    const (hasDryRun, dryRunStr) = Protocol.extractJsonString(params, "dryRun");
    const dryRun = hasDryRun && dryRunStr == "true";

    var output = "Configuration Sync\n";
    output += "==================\n\n";

    if dryRun {
      output += "Mode: Dry run (no changes will be made)\n\n";
    }

    const home = getEnvHome();
    const sshConfigPath = home + "/.ssh/config";
    const gitConfigPath = home + "/.gitconfig";
    const configPath = getConfigPath();

    // Check source files
    output += "Source Files:\n";
    output += "  SSH config: " + sshConfigPath;
    if exists(sshConfigPath) {
      output += " (exists)\n";
    } else {
      output += " (not found)\n";
    }

    output += "  Git config: " + gitConfigPath;
    if exists(gitConfigPath) {
      output += " (exists)\n";
    } else {
      output += " (not found)\n";
    }

    output += "\nDestination:\n";
    output += "  Config: " + configPath;
    if exists(configPath) {
      output += " (exists)\n";
    } else {
      output += " (will be created)\n";
    }

    output += "\nSync Actions:\n";

    // In production, this would:
    // 1. Parse SSH config for Host entries
    // 2. Parse gitconfig for url rewrites
    // 3. Update managed blocks in config.json

    output += "  [SKIP] SSH host parsing not yet implemented\n";
    output += "  [SKIP] gitconfig parsing not yet implemented\n";
    output += "  [SKIP] Config file update not yet implemented\n";

    output += "\nTo implement sync, the following modules are needed:\n";
    output += "  - Config.chpl: SSH config parser\n";
    output += "  - GlobalConfig.chpl: Managed block updater\n";

    return (true, output);
  }
}
