/*
 * ProviderCLI.chpl - glab and gh CLI abstraction layer
 *
 * Part of RemoteJuggler - Backend-agnostic git identity management
 * Provides wrapper functions for GitLab CLI (glab) and GitHub CLI (gh)
 * with graceful fallback when CLIs are not available.
 *
 * Credential resolution chain:
 *   1. Darwin Keychain (macOS)
 *   2. Environment variable
 *   3. CLI stored auth (glab/gh)
 *   4. SSH-only fallback
 */
prototype module ProviderCLI {
  use Subprocess;
  use IO;
  use List;
  use CTypes;
  use OS.POSIX only getenv;
  public use super.Core;
  public use super.Keychain;
  import super.Keychain;

  // ============================================================
  // CLI Availability Detection
  // ============================================================

  /*
   * Check if glab CLI is available in PATH
   */
  proc glabAvailable(): bool {
    try {
      var p = spawn(["which", "glab"], stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Check if gh CLI is available in PATH
   */
  proc ghAvailable(): bool {
    try {
      var p = spawn(["which", "gh"], stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  // ============================================================
  // Token Retrieval from CLI Stored Auth
  // ============================================================

  /*
   * Get token from glab CLI for a specific hostname
   *
   * Args:
   *   hostname: The GitLab hostname (e.g., "gitlab.com")
   *
   * Returns:
   *   Tuple of (success, token) where token is empty string on failure
   */
  proc getGlabToken(hostname: string): (bool, string) {
    if !glabAvailable() then return (false, "");

    try {
      var p = spawn(["glab", "auth", "token", "-h", hostname],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var token: string;
        p.stdout.readAll(token);
        return (true, token.strip());
      }
    } catch {
      // Fall through to return false
    }
    return (false, "");
  }

  /*
   * Get token from gh CLI for a specific hostname
   *
   * Args:
   *   hostname: The GitHub hostname (default: "github.com")
   *
   * Returns:
   *   Tuple of (success, token) where token is empty string on failure
   */
  proc getGhToken(hostname: string = "github.com"): (bool, string) {
    if !ghAvailable() then return (false, "");

    try {
      var args: [0..2] string = ["gh", "auth", "token"];
      var argList: list(string);
      for a in args do argList.pushBack(a);

      // Add hostname flag for non-default hosts
      if hostname != "github.com" {
        argList.pushBack("-h");
        argList.pushBack(hostname);
      }

      var p = spawn(argList.toArray(),
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var token: string;
        p.stdout.readAll(token);
        return (true, token.strip());
      }
    } catch {
      // Fall through to return false
    }
    return (false, "");
  }

  // ============================================================
  // Authentication Operations
  // ============================================================

  /*
   * Authenticate with GitLab using glab CLI
   *
   * Args:
   *   hostname: The GitLab hostname
   *   token: The authentication token
   *
   * Returns:
   *   true if authentication succeeded, false otherwise
   */
  proc glabAuth(hostname: string, token: string): bool {
    if !glabAvailable() then return false;

    try {
      var p = spawn(["glab", "auth", "login", "-h", hostname, "--stdin"],
                    stdin=pipeStyle.pipe,
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);

      p.stdin.write(token);
      p.stdin.close();
      p.wait();

      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Authenticate with GitHub using gh CLI
   *
   * Args:
   *   hostname: The GitHub hostname
   *   token: The authentication token
   *
   * Returns:
   *   true if authentication succeeded, false otherwise
   */
  proc ghAuth(hostname: string, token: string): bool {
    if !ghAvailable() then return false;

    try {
      var p = spawn(["gh", "auth", "login", "-h", hostname, "--with-token"],
                    stdin=pipeStyle.pipe,
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);

      p.stdin.write(token);
      p.stdin.close();
      p.wait();

      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Logout from GitLab using glab CLI
   *
   * Args:
   *   hostname: The GitLab hostname
   *
   * Returns:
   *   true if logout succeeded, false otherwise
   */
  proc glabLogout(hostname: string): bool {
    if !glabAvailable() then return false;

    try {
      var p = spawn(["glab", "auth", "logout", "-h", hostname],
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Logout from GitHub using gh CLI
   *
   * Args:
   *   hostname: The GitHub hostname (default: "github.com")
   *
   * Returns:
   *   true if logout succeeded, false otherwise
   */
  proc ghLogout(hostname: string = "github.com"): bool {
    if !ghAvailable() then return false;

    try {
      // Use -y flag to skip confirmation prompt
      var p = spawn(["gh", "auth", "logout", "-h", hostname, "-y"],
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  // ============================================================
  // Credential Resolution Chain
  // ============================================================

  /*
   * Get environment variable value
   *
   * Args:
   *   name: Environment variable name
   *
   * Returns:
   *   The value or empty string if not set
   */
  proc getEnvVar(name: string): string {
    try {
      var cstr = getenv(name.c_str());
      if cstr != nil {
        return string.createCopyingBuffer(cstr);
      }
    } catch {
      // Fall through
    }
    return "";
  }

  /*
   * Resolve credential for an identity using the resolution chain:
   *   1. Darwin Keychain (macOS only)
   *   2. Environment variable (if tokenEnvVar is set)
   *   3. CLI stored auth (glab/gh)
   *   4. Return empty (SSH-only fallback)
   *
   * Args:
   *   identity: The GitIdentity to resolve credentials for
   *
   * Returns:
   *   Tuple of (hasToken, token) where token is empty string if not found
   */
  proc resolveCredential(identity: GitIdentity): (bool, string) {
    // 1. Try Keychain first (Darwin only)
    if useKeychain && Keychain.isDarwin() {
      const providerStr = providerToString(identity.provider);
      const (found, token) = Keychain.retrieveToken(providerStr, identity.name, identity.user);
      if found {
        if verbose then writeln("  Credential source: Keychain");
        return (true, token);
      }
    }

    // 2. Try environment variable
    if identity.tokenEnvVar != "" {
      const token = getEnvVar(identity.tokenEnvVar);
      if token != "" {
        if verbose then writeln("  Credential source: Environment ($", identity.tokenEnvVar, ")");
        return (true, token);
      }
    }

    // 3. Try provider CLI stored auth
    select identity.provider {
      when Provider.GitLab {
        const (ok, token) = getGlabToken(identity.hostname);
        if ok {
          if verbose then writeln("  Credential source: glab CLI");
          return (true, token);
        }
      }
      when Provider.GitHub {
        const (ok, token) = getGhToken(identity.hostname);
        if ok {
          if verbose then writeln("  Credential source: gh CLI");
          return (true, token);
        }
      }
      otherwise {
        // Custom providers - try environment variable only
      }
    }

    // 4. No token found - SSH-only fallback
    if verbose then writeln("  Credential source: None (SSH-only mode)");
    return (false, "");
  }

  /*
   * Authenticate with the provider for a given identity
   *
   * This performs the full authentication flow:
   *   1. Resolve credential via the resolution chain
   *   2. If token found, authenticate with provider CLI
   *   3. Return appropriate AuthResult
   *
   * Args:
   *   identity: The GitIdentity to authenticate
   *
   * Returns:
   *   AuthResult indicating success/failure and authentication mode
   */
  proc authenticateProvider(identity: GitIdentity): AuthResult {
    // Get token from any available source
    const (hasToken, token) = resolveCredential(identity);

    if !hasToken {
      // SSH-only mode - still functional for git operations
      return new AuthResult(
        success = true,
        mode = AuthMode.SSHOnly,
        message = "No token found - using SSH-only mode"
      );
    }

    // Try provider CLI authentication
    var cliSuccess = false;
    select identity.provider {
      when Provider.GitLab {
        if glabAvailable() {
          cliSuccess = glabAuth(identity.hostname, token);
        }
      }
      when Provider.GitHub {
        if ghAvailable() {
          cliSuccess = ghAuth(identity.hostname, token);
        }
      }
      otherwise {
        // Custom providers don't have CLI support
      }
    }

    if cliSuccess {
      return new AuthResult(
        success = true,
        mode = AuthMode.CLIAuthenticated,
        message = "Authenticated via " + providerToString(identity.provider) + " CLI"
      );
    }

    // CLI not available but token exists - can still use for API calls
    return new AuthResult(
      success = true,
      mode = AuthMode.TokenOnly,
      message = "Token available, CLI not installed or authentication failed"
    );
  }

  // ============================================================
  // API Operations via CLI
  // ============================================================

  /*
   * Execute a glab API call and return the response
   *
   * Args:
   *   endpoint: The API endpoint (e.g., "user/gpg_keys")
   *   hostname: The GitLab hostname
   *
   * Returns:
   *   Tuple of (success, responseBody)
   */
  proc glabAPI(endpoint: string, hostname: string): (bool, string) {
    if !glabAvailable() then return (false, "");

    try {
      var p = spawn(["glab", "api", endpoint, "-h", hostname],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var response: string;
        p.stdout.readAll(response);
        return (true, response.strip());
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  /*
   * Execute a gh API call and return the response
   *
   * Args:
   *   endpoint: The API endpoint (e.g., "user/gpg_keys")
   *   hostname: The GitHub hostname (default: "github.com")
   *
   * Returns:
   *   Tuple of (success, responseBody)
   */
  proc ghAPI(endpoint: string, hostname: string = "github.com"): (bool, string) {
    if !ghAvailable() then return (false, "");

    try {
      var argList: list(string);
      argList.pushBack("gh");
      argList.pushBack("api");
      argList.pushBack(endpoint);

      if hostname != "github.com" {
        argList.pushBack("--hostname");
        argList.pushBack(hostname);
      }

      var p = spawn(argList.toArray(),
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var response: string;
        p.stdout.readAll(response);
        return (true, response.strip());
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  // ============================================================
  // Status and Diagnostic Functions
  // ============================================================

  /*
   * Get the current glab authentication status for a hostname
   *
   * Args:
   *   hostname: The GitLab hostname
   *
   * Returns:
   *   Tuple of (isAuthenticated, username)
   */
  proc getGlabAuthStatus(hostname: string): (bool, string) {
    if !glabAvailable() then return (false, "");

    try {
      var p = spawn(["glab", "auth", "status", "-h", hostname],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.pipe);
      p.wait();

      if p.exitCode == 0 {
        var output: string;
        p.stdout.readAll(output);
        // Parse output for username (format varies)
        // Typically: "Logged in to gitlab.com as username"
        const marker = "Logged in to";
        if output.find(marker) != -1 {
          // Extract username from the output
          const asIdx = output.find(" as ");
          if asIdx != -1 {
            var username = output[asIdx+4..].strip();
            // Remove any trailing info
            const spaceIdx = username.find(" ");
            if spaceIdx != -1 {
              username = username[..spaceIdx-1];
            }
            return (true, username);
          }
        }
        return (true, "");
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  /*
   * Get the current gh authentication status for a hostname
   *
   * Args:
   *   hostname: The GitHub hostname
   *
   * Returns:
   *   Tuple of (isAuthenticated, username)
   */
  proc getGhAuthStatus(hostname: string = "github.com"): (bool, string) {
    if !ghAvailable() then return (false, "");

    try {
      var argList: list(string);
      argList.pushBack("gh");
      argList.pushBack("auth");
      argList.pushBack("status");
      argList.pushBack("-h");
      argList.pushBack(hostname);

      var p = spawn(argList.toArray(),
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.pipe);
      p.wait();

      if p.exitCode == 0 {
        var output: string;
        p.stdout.readAll(output);
        // Parse output for username
        // Typically: "Logged in to github.com as username"
        const asIdx = output.find(" as ");
        if asIdx != -1 {
          var username = output[asIdx+4..].strip();
          // Remove parenthetical info if present
          const parenIdx = username.find(" (");
          if parenIdx != -1 {
            username = username[..parenIdx-1];
          }
          return (true, username);
        }
        return (true, "");
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  /*
   * Generate a summary of CLI availability and auth status
   *
   * Returns:
   *   A formatted string with CLI status information
   */
  proc getCLIStatusSummary(): string {
    var summary: string = "";

    // glab status
    summary += "glab CLI: ";
    if glabAvailable() {
      summary += "Available\n";
    } else {
      summary += "Not installed\n";
    }

    // gh status
    summary += "gh CLI: ";
    if ghAvailable() {
      summary += "Available\n";
    } else {
      summary += "Not installed\n";
    }

    return summary;
  }

  // ============================================================
  // Token Storage Operations
  // ============================================================

  /*
   * Store a token in the keychain for an identity
   *
   * Args:
   *   identity: The GitIdentity
   *   token: The token to store
   *
   * Returns:
   *   true if storage succeeded, false otherwise
   */
  proc storeIdentityToken(identity: GitIdentity, token: string): bool {
    if !Keychain.isDarwin() {
      if verbose then writeln("Warning: Keychain storage only available on macOS");
      return false;
    }

    const providerStr = providerToString(identity.provider);
    return Keychain.storeToken(providerStr, identity.name, identity.user, token);
  }

  /*
   * Clear a token from the keychain for an identity
   *
   * Args:
   *   identity: The GitIdentity
   *
   * Returns:
   *   true if deletion succeeded, false otherwise
   */
  proc clearIdentityToken(identity: GitIdentity): bool {
    if !Keychain.isDarwin() {
      return false;
    }

    const providerStr = providerToString(identity.provider);
    return Keychain.deleteToken(providerStr, identity.name, identity.user);
  }
}
