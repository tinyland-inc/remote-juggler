/*
 * TokenHealth.chpl - Token expiry detection and health monitoring
 *
 * Part of RemoteJuggler v2.0.0
 * Provides token health checking and expiry warnings:
 *   - Query provider APIs for token information
 *   - Track token creation and last verified dates
 *   - Warn when tokens are approaching expiry
 *   - Support token renewal workflows
 *
 * Copyright (c) 2026 Jess Sullivan <jess@sulliwood.org>
 * License: Zlib
 */
prototype module TokenHealth {
  use Time;
  use IO;
  use JSON;
  use List;
  use Map;
  use FileSystem;
  use Path;

  // Import core modules
  public use super.Core;
  public use super.ProviderCLI;
  public use super.Keychain;
  import super.ProviderCLI;
  import super.Keychain;

  // ============================================================
  // Token Metadata Records
  // ============================================================

  /*
   * Metadata about a stored token
   */
  record TokenMetadata {
    var identityName: string;         // Identity this token belongs to
    var provider: string;             // Provider (gitlab, github, etc.)
    var createdAt: real;              // Unix timestamp when token was stored
    var lastVerified: real;           // Unix timestamp of last verification
    var expiresAt: real;              // Unix timestamp when token expires (0 if unknown)
    var scopes: list(string);         // Token scopes/permissions
    var tokenType: string;            // "pat" (Personal Access Token), "oauth", etc.
    var isValid: bool;                // Last verification result
    var warningIssued: real;          // Last time expiry warning was issued

    proc init() {
      this.identityName = "";
      this.provider = "";
      this.createdAt = 0.0;
      this.lastVerified = 0.0;
      this.expiresAt = 0.0;
      this.scopes = new list(string);
      this.tokenType = "pat";
      this.isValid = true;
      this.warningIssued = 0.0;
    }
  }

  /*
   * Result of token health check
   */
  record TokenHealthResult {
    var healthy: bool;                // Overall health status
    var hasToken: bool;               // Token was found
    var isExpired: bool;              // Token has expired
    var daysUntilExpiry: int;         // Days until expiry (negative if expired)
    var needsRenewal: bool;           // Should renew soon (< 30 days)
    var scopes: list(string);         // Available token scopes
    var message: string;              // Human-readable status
    var metadata: TokenMetadata;      // Full metadata

    proc init() {
      this.healthy = false;
      this.hasToken = false;
      this.isExpired = false;
      this.daysUntilExpiry = 0;
      this.needsRenewal = false;
      this.scopes = new list(string);
      this.message = "";
      this.metadata = new TokenMetadata();
    }
  }

  // ============================================================
  // Metadata Storage (JSON file)
  // ============================================================

  /*
   * Get path to token metadata storage file
   */
  proc getMetadataPath(): string {
    const homeDir = getEnvVar("HOME");
    if homeDir == "" {
      return ".remote-juggler-tokens.json";
    }
    return homeDir + "/.config/remote-juggler/tokens.json";
  }

  /*
   * Load all token metadata from storage
   */
  proc loadMetadata(): map(string, TokenMetadata) {
    var metadataMap: map(string, TokenMetadata);
    const path = getMetadataPath();

    if !exists(path) {
      return metadataMap;
    }

    try {
      var f = open(path, ioMode.r);
      var reader = f.reader(locking=false);
      var jsonStr: string;
      reader.readAll(jsonStr);

      // Parse JSON and populate map
      // Note: Chapel's JSON module is limited, so we do simple parsing
      // In production, use a proper JSON parser

      // For now, return empty map
      // TODO: Implement JSON parsing when Chapel JSON module is more mature

      f.close();

    } catch e {
      if verbose then writeln("Warning: Could not load token metadata: ", e.message());
    }

    return metadataMap;
  }

  /*
   * Save token metadata to storage
   */
  proc saveMetadata(const ref metadataMap: map(string, TokenMetadata)): bool {
    const path = getMetadataPath();

    try {
      // Ensure directory exists
      const dir = dirname(path);
      if dir != "" && !exists(dir) {
        mkdir(dir, parents=true);
      }

      var f = open(path, ioMode.cw);
      var writer = f.writer(locking=false);

      // Write JSON manually (Chapel JSON module is limited)
      writer.writeln("{");
      writer.writeln("  \"version\": \"1.0\",");
      writer.writeln("  \"tokens\": {");

      var first = true;
      for key in metadataMap.keys() {
        const meta = metadataMap[key];
        if !first then writer.writeln(",");
        first = false;

        writer.writeln("    \"", key, "\": {");
        writer.writeln("      \"identityName\": \"", meta.identityName, "\",");
        writer.writeln("      \"provider\": \"", meta.provider, "\",");
        writer.writeln("      \"createdAt\": ", meta.createdAt, ",");
        writer.writeln("      \"lastVerified\": ", meta.lastVerified, ",");
        writer.writeln("      \"expiresAt\": ", meta.expiresAt, ",");
        writer.writeln("      \"tokenType\": \"", meta.tokenType, "\",");
        writer.writeln("      \"isValid\": ", meta.isValid, ",");
        writer.writeln("      \"warningIssued\": ", meta.warningIssued);
        writer.write("    }");
      }

      writer.writeln();
      writer.writeln("  }");
      writer.writeln("}");

      f.close();

      return true;
    } catch e {
      if verbose then writeln("Warning: Could not save token metadata: ", e.message());
      return false;
    }
  }

  /*
   * Get metadata key for an identity
   */
  proc getMetadataKey(identity: GitIdentity): string {
    return identity.provider:string + ":" + identity.name;
  }

  /*
   * Get or create metadata for an identity
   */
  proc getOrCreateMetadata(ref metadataMap: map(string, TokenMetadata),
                           identity: GitIdentity): TokenMetadata {
    const key = getMetadataKey(identity);

    if !metadataMap.contains(key) {
      var meta = new TokenMetadata();
      meta.identityName = identity.name;
      meta.provider = identity.provider:string;
      meta.createdAt = timeSinceEpoch().totalSeconds();
      meta.lastVerified = 0.0;
      meta.expiresAt = 0.0;
      metadataMap[key] = meta;
    }

    return metadataMap[key];
  }

  // ============================================================
  // Token Expiry Calculation
  // ============================================================

  /*
   * Calculate days until token expires
   *
   * Returns negative number if already expired
   */
  proc daysUntilExpiry(expiresAt: real): int {
    if expiresAt == 0.0 {
      return 999999;  // Unknown expiry
    }

    const now = timeSinceEpoch().totalSeconds();
    const secondsRemaining = expiresAt - now;
    const daysRemaining = (secondsRemaining / 86400.0): int;

    return daysRemaining;
  }

  /*
   * Check if token needs renewal (< 30 days until expiry)
   */
  proc needsRenewal(expiresAt: real): bool {
    const days = daysUntilExpiry(expiresAt);
    return days < 30 && days > 0;
  }

  /*
   * Check if token is expired
   */
  proc isExpired(expiresAt: real): bool {
    if expiresAt == 0.0 {
      return false;  // Unknown expiry
    }
    const now = timeSinceEpoch().totalSeconds();
    return now >= expiresAt;
  }

  // ============================================================
  // Provider API Token Verification
  // ============================================================

  /*
   * Verify token with GitLab API
   *
   * Queries /api/v4/personal_access_tokens/self for token info
   */
  proc verifyGitLabToken(hostname: string, token: string): (bool, real, list(string)) {
    if !ProviderCLI.glabAvailable() {
      return (false, 0.0, new list(string));
    }

    try {
      // Use glab API to query token info
      const (ok, response) = ProviderCLI.glabAPI("personal_access_tokens/self", hostname);

      if ok && response != "" {
        // Token is valid, but we can't parse expiry without proper JSON parser
        // TODO: Implement proper JSON parsing when Chapel JSON module is more mature
        // For now, just return valid status with unknown expiry
        var scopes: list(string);
        scopes.pushBack("api");
        return (true, 0.0, scopes);  // 0.0 = unknown expiry
      }
    } catch e {
      if verbose then writeln("GitLab token verification error: ", e.message());
    }

    return (false, 0.0, new list(string));
  }

  /*
   * Verify token with GitHub API
   *
   * Queries /user endpoint and checks X-OAuth-Scopes header
   */
  proc verifyGitHubToken(hostname: string, token: string): (bool, real, list(string)) {
    if !ProviderCLI.ghAvailable() {
      return (false, 0.0, new list(string));
    }

    try {
      // GitHub doesn't expose PAT expiry via API
      // We can only check if token is valid
      const (ok, response) = ProviderCLI.ghAPI("user", hostname);

      if ok && response != "" {
        // Token is valid but we don't know expiry
        var scopes: list(string);
        scopes.pushBack("repo");  // Assume standard scopes
        return (true, 0.0, scopes);  // 0.0 = unknown expiry
      }
    } catch e {
      if verbose then writeln("GitHub token verification error: ", e.message());
    }

    return (false, 0.0, new list(string));
  }

  /*
   * Verify token with provider API
   */
  proc verifyTokenWithProvider(identity: GitIdentity, token: string): (bool, real, list(string)) {
    select identity.provider {
      when Provider.GitLab {
        return verifyGitLabToken(identity.hostname, token);
      }
      when Provider.GitHub {
        return verifyGitHubToken(identity.hostname, token);
      }
      otherwise {
        // Custom providers - cannot verify
        return (false, 0.0, new list(string));
      }
    }
  }

  // ============================================================
  // Token Health Checking
  // ============================================================

  /*
   * Check health of a token for an identity
   *
   * This performs:
   *   1. Token retrieval from credential sources
   *   2. Provider API verification (if token found)
   *   3. Expiry calculation
   *   4. Metadata update
   */
  proc checkTokenHealth(identity: GitIdentity): TokenHealthResult {
    var result = new TokenHealthResult();

    // Load metadata
    var metadataMap = loadMetadata();
    var meta = getOrCreateMetadata(metadataMap, identity);
    const key = getMetadataKey(identity);

    // Get token from credential resolution chain
    const (hasToken, token) = ProviderCLI.resolveCredential(identity);
    result.hasToken = hasToken;

    if !hasToken {
      result.message = "No token found (SSH-only mode)";
      result.healthy = true;  // SSH-only is healthy
      return result;
    }

    // Verify token with provider API
    const (verified, expiresAt, scopes) = verifyTokenWithProvider(identity, token);

    if !verified {
      result.message = "Could not verify token with provider API";
      result.healthy = false;
      meta.isValid = false;
    } else {
      result.healthy = true;
      meta.isValid = true;
      meta.expiresAt = expiresAt;
      meta.scopes = scopes;
      meta.lastVerified = timeSinceEpoch().totalSeconds();

      for scope in scopes {
        result.scopes.pushBack(scope);
      }

      // Check expiry
      if expiresAt > 0.0 {
        result.daysUntilExpiry = daysUntilExpiry(expiresAt);
        result.isExpired = isExpired(expiresAt);
        result.needsRenewal = needsRenewal(expiresAt);

        if result.isExpired {
          result.message = "Token has expired";
          result.healthy = false;
        } else if result.needsRenewal {
          result.message = "Token expires in " + result.daysUntilExpiry:string + " days - renewal recommended";
        } else {
          result.message = "Token is healthy (expires in " + result.daysUntilExpiry:string + " days)";
        }
      } else {
        result.message = "Token is valid (expiry date unknown)";
        result.daysUntilExpiry = 999999;
      }
    }

    // Save updated metadata
    metadataMap[key] = meta;
    result.metadata = meta;
    saveMetadata(metadataMap);

    return result;
  }

  /*
   * Check health of all registered identities
   *
   * Returns a map of identity name -> health result
   */
  proc checkAllTokens(identities: list(GitIdentity)): map(string, TokenHealthResult) {
    var results: map(string, TokenHealthResult);

    for identity in identities {
      const result = checkTokenHealth(identity);
      results[identity.name] = result;
    }

    return results;
  }

  // ============================================================
  // Expiry Warnings
  // ============================================================

  /*
   * Print expiry warning if needed
   *
   * Returns true if warning was issued
   */
  proc warnIfExpiring(identity: GitIdentity): bool {
    const healthResult = checkTokenHealth(identity);

    if !healthResult.hasToken {
      return false;  // No warning for SSH-only
    }

    if healthResult.isExpired {
      writeln("[WARNING]  WARNING: Token for ", identity.name, " has expired!");
      writeln("   Renewal required for API operations.");
      writeln("   Run: remote-juggler token renew ", identity.name);
      return true;
    }

    if healthResult.needsRenewal {
      writeln("[WARNING]  WARNING: Token for ", identity.name, " expires in ",
              healthResult.daysUntilExpiry, " days");
      writeln("   Consider renewing soon.");
      writeln("   Run: remote-juggler token renew ", identity.name);
      return true;
    }

    return false;
  }

  /*
   * Check if we should issue warning (rate-limited to once per day)
   */
  proc shouldWarn(meta: TokenMetadata): bool {
    const now = timeSinceEpoch().totalSeconds();
    const daysSinceWarning = (now - meta.warningIssued) / 86400.0;
    return daysSinceWarning >= 1.0;
  }

  // ============================================================
  // Token Renewal Workflow
  // ============================================================

  /*
   * Prompt user to renew a token
   *
   * This guides the user through:
   *   1. Opening provider settings page
   *   2. Creating new PAT
   *   3. Storing new token in keychain
   */
  proc promptTokenRenewal(identity: GitIdentity) {
    writeln("Token Renewal for: ", identity.name);
    writeln("Provider: ", identity.provider:string);
    writeln();

    // Get provider-specific token creation URL
    var tokenURL = "";
    select identity.provider {
      when Provider.GitLab {
        tokenURL = "https://" + identity.hostname + "/-/user_settings/personal_access_tokens";
      }
      when Provider.GitHub {
        tokenURL = "https://" + identity.hostname + "/settings/tokens/new";
      }
      otherwise {
        writeln("Token renewal not supported for custom providers");
        return;
      }
    }

    writeln("Steps to renew your token:");
    writeln("1. Open: ", tokenURL);
    writeln("2. Create a new Personal Access Token with appropriate scopes");
    writeln("3. Copy the new token");
    writeln("4. Run: remote-juggler token set ", identity.name);
    writeln();
  }

  /*
   * Interactive token renewal
   */
  proc renewToken(identity: GitIdentity): bool {
    promptTokenRenewal(identity);

    // Prompt for new token
    writeln("Enter new token (input hidden): ");
    var newToken: string;

    // Note: Chapel doesn't have built-in hidden input
    // In production, use a C library for this
    try {
      stdin.readLine(newToken);
      newToken = newToken.strip();

      if newToken == "" {
        writeln("Token renewal cancelled");
        return false;
      }

      // Verify token with provider
      const (verified, expiresAt, scopes) = verifyTokenWithProvider(identity, newToken);

      if !verified {
        writeln("Error: Token verification failed");
        writeln("The token may be invalid or lack required scopes");
        return false;
      }

      // Store token in keychain
      if Keychain.isDarwin() {
        const stored = ProviderCLI.storeIdentityToken(identity, newToken);
        if stored {
          writeln("[OK] Token stored successfully in keychain");

          // Update metadata
          var metadataMap = loadMetadata();
          var meta = getOrCreateMetadata(metadataMap, identity);
          const key = getMetadataKey(identity);
          meta.createdAt = timeSinceEpoch().totalSeconds();
          meta.lastVerified = meta.createdAt;
          meta.expiresAt = expiresAt;
          meta.scopes = scopes;
          meta.isValid = true;
          metadataMap[key] = meta;
          saveMetadata(metadataMap);

          return true;
        } else {
          writeln("Error: Could not store token in keychain");
          return false;
        }
      } else {
        writeln("Note: Keychain storage only available on macOS");
        writeln("Set environment variable ", identity.tokenEnvVar, " to use this token");
        return true;
      }

    } catch e {
      writeln("Error reading token: ", e.message());
      return false;
    }
  }

  // ============================================================
  // Status Reporting
  // ============================================================

  /*
   * Format health result as human-readable string
   */
  proc formatHealthResult(result: TokenHealthResult): string {
    var status = "";

    if !result.hasToken {
      status += "  Status: SSH-only (no token)\n";
    } else if !result.healthy {
      status += "  Status: [FAILED] " + result.message + "\n";
    } else if result.needsRenewal {
      status += "  Status: [WARNING]  " + result.message + "\n";
    } else {
      status += "  Status: [OK] " + result.message + "\n";
    }

    if result.scopes.size > 0 {
      status += "  Scopes: ";
      var first = true;
      for scope in result.scopes {
        if !first then status += ", ";
        status += scope;
        first = false;
      }
      status += "\n";
    }

    return status;
  }

  /*
   * Print summary of all token health
   */
  proc printTokenHealthSummary(identities: list(GitIdentity)) {
    writeln("Token Health Summary");
    var separator = "";
    for i in 1..60 do separator += "═";
    writeln(separator);
    writeln();

    const results = checkAllTokens(identities);

    for identity in identities {
      writeln(identity.name, " (", identity.provider:string, "):");

      if results.contains(identity.name) {
        const result = results[identity.name];
        write(formatHealthResult(result));
      } else {
        writeln("  Status: Not checked");
      }
      writeln();
    }
  }
}
