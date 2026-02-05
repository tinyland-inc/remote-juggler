/*
 * Identity.chpl - Identity Management and Switching Module
 *
 * Part of RemoteJuggler v2.0.0
 * Provides high-level identity management operations including:
 *   - Identity lookup and listing
 *   - Identity detection from repository context
 *   - Identity switching with full GPG integration
 *   - Identity validation
 *
 * This module orchestrates the ProviderCLI, GPG, and Remote modules
 * to provide a complete identity switching experience.
 *
 * Copyright (c) 2026 Jess Sullivan <jess@sulliwood.org>
 * License: MIT
 */
prototype module Identity {
  use List;
  use Map;
  use IO;
  use Time;

  // Import core types and dependent modules
  public use super.Core;
  public use super.ProviderCLI;
  public use super.GPG;
  public use super.Remote;
  import super.ProviderCLI;
  import super.GPG;
  import super.Remote;
  import super.GlobalConfig;

  // ============================================================
  // Switch Result Types
  // ============================================================

  /*
   * Complete result of an identity switch operation
   */
  record SwitchResult {
    var success: bool;           // Overall success status
    var identity: GitIdentity;   // The target identity (populated on success)
    var authMode: AuthMode;      // How authentication was achieved
    var gpgConfigured: bool;     // Whether GPG was configured
    var remoteUpdated: bool;     // Whether git remote was updated
    var message: string;         // Human-readable status message

    /*
     * Initialize with default (failure) values
     */
    proc init() {
      this.success = false;
      this.identity = new GitIdentity();
      this.authMode = AuthMode.Failed;
      this.gpgConfigured = false;
      this.remoteUpdated = false;
      this.message = "";
    }

    /*
     * Initialize a successful result
     */
    proc init(identity: GitIdentity, authMode: AuthMode,
              gpgConfigured: bool, remoteUpdated: bool, message: string) {
      this.success = true;
      this.identity = identity;
      this.authMode = authMode;
      this.gpgConfigured = gpgConfigured;
      this.remoteUpdated = remoteUpdated;
      this.message = message;
    }
  }

  /*
   * Result of identity validation
   */
  record IdentityValidationResult {
    var valid: bool;             // Overall validation status
    var sshConnectivity: bool;   // SSH connection test passed
    var credentialAvailable: bool; // Token/credential found
    var gpgKeyFound: bool;       // GPG key exists locally
    var gpgRegistered: bool;     // GPG key registered with provider
    var issues: list(string);    // List of validation issues

    proc init() {
      this.valid = false;
      this.sshConnectivity = false;
      this.credentialAvailable = false;
      this.gpgKeyFound = false;
      this.gpgRegistered = false;
      this.issues = new list(string);
    }
  }

  /*
   * Detection result when identifying repository context
   */
  record DetectionResult {
    var found: bool;             // Whether an identity was detected
    var identity: GitIdentity;   // The detected identity
    var confidence: string;      // "exact", "inferred", "none"
    var reason: string;          // Explanation of how detection was made
  }

  // ============================================================
  // Identity Storage (In-Memory Cache)
  // ============================================================

  // In-memory identity registry (loaded from config file)
  private var identityRegistry: map(string, GitIdentity);
  private var registryLoaded: bool = false;
  // When true, clearIdentities() prevents auto-reload (for testing)
  private var registryCleared: bool = false;

  /*
   * Ensure the identity registry is loaded from config file.
   * This is called automatically by functions that access the registry.
   * If clearIdentities() was called, auto-reload is skipped to allow
   * tests to work with a clean slate.
   */
  proc ensureRegistryLoaded() {
    if registryLoaded then return;
    // If registry was explicitly cleared, don't auto-reload from config
    if registryCleared then return;

    // Load identities from GlobalConfig
    const identities = GlobalConfig.loadIdentities();
    for identity in identities {
      identityRegistry[identity.name] = identity;
    }
    registryLoaded = true;
  }

  /*
   * Register an identity in the in-memory registry
   */
  proc registerIdentity(identity: GitIdentity) {
    ensureRegistryLoaded();
    identityRegistry[identity.name] = identity;
  }

  /*
   * Clear all registered identities.
   * Sets registryCleared flag to prevent auto-reload from config file,
   * enabling test isolation.
   */
  proc clearIdentities() {
    identityRegistry.clear();
    registryLoaded = false;
    registryCleared = true;
  }

  /*
   * Reset the identity registry to initial state.
   * Unlike clearIdentities(), this allows auto-reload from config file.
   * Use this when you want to reload identities from the config file.
   */
  proc resetIdentityRegistry() {
    identityRegistry.clear();
    registryLoaded = false;
    registryCleared = false;
  }

  /*
   * Get the number of registered identities
   */
  proc identityCount(): int {
    ensureRegistryLoaded();
    return identityRegistry.size;
  }

  // ============================================================
  // Identity Lookup Operations
  // ============================================================

  /*
   * Get an identity by name from the registry
   *
   * Args:
   *   name: The identity name to look up
   *
   * Returns:
   *   Tuple of (found, identity)
   */
  proc getIdentity(name: string): (bool, GitIdentity) {
    ensureRegistryLoaded();
    if identityRegistry.contains(name) {
      return (true, identityRegistry[name]);
    }
    return (false, new GitIdentity());
  }

  /*
   * List all registered identities, optionally filtered by provider
   *
   * Args:
   *   provider: Filter by provider (use Provider.Custom for all)
   *
   * Returns:
   *   List of matching identities
   */
  proc listIdentities(provider: Provider = Provider.Custom): list(GitIdentity) {
    ensureRegistryLoaded();
    var result: list(GitIdentity);

    for name in identityRegistry.keys() {
      const identity = identityRegistry[name];
      // Custom means "all providers" as a filter
      if provider == Provider.Custom || identity.provider == provider {
        result.pushBack(identity);
      }
    }

    return result;
  }

  /*
   * List all identity names
   *
   * Returns:
   *   List of identity name strings
   */
  proc listIdentityNames(): list(string) {
    ensureRegistryLoaded();
    var names: list(string);
    for name in identityRegistry.keys() {
      names.pushBack(name);
    }
    return names;
  }

  // ============================================================
  // Identity Detection
  // ============================================================

  /*
   * Detect the appropriate identity for a repository based on its remote URL
   *
   * Detection strategy:
   *   1. Parse origin remote URL
   *   2. Match SSH host alias against registered identities
   *   3. Match organization path against identity organizations
   *   4. Match hostname/provider for general inference
   *
   * Args:
   *   repoPath: Path to the git repository (default: ".")
   *
   * Returns:
   *   Tuple of (found, identity, reason)
   */
  proc detectIdentity(repoPath: string = "."): (bool, GitIdentity, string) {
    ensureRegistryLoaded();

    // Check if path is a git repository
    if !Remote.isGitRepository(repoPath) {
      return (false, new GitIdentity(), "Not a git repository");
    }

    // Get origin URL
    const (hasOrigin, originURL) = Remote.getOriginURL(repoPath);
    if !hasOrigin {
      return (false, new GitIdentity(), "No origin remote configured");
    }

    // Parse the remote URL
    const parsed = Remote.parseRemoteURL(originURL);
    if !parsed.valid {
      return (false, new GitIdentity(), "Could not parse origin URL: " + originURL);
    }

    if verbose {
      writeln("  Detecting identity for remote: ", originURL);
      writeln("    Host: ", parsed.host);
      writeln("    Org: ", parsed.orgPath);
      writeln("    Provider: ", parsed.provider);
    }

    // Strategy 1: Exact SSH host alias match
    for name in identityRegistry.keys() {
      const identity = identityRegistry[name];
      if identity.host == parsed.host {
        return (true, identity,
                "Matched SSH host alias: " + parsed.host);
      }
    }

    // Strategy 2: Organization path match
    for name in identityRegistry.keys() {
      const identity = identityRegistry[name];
      if identity.matchesOrganization(parsed.orgPath) {
        return (true, identity,
                "Matched organization: " + parsed.orgPath);
      }
    }

    // Strategy 3: Provider + hostname match (general inference)
    for name in identityRegistry.keys() {
      const identity = identityRegistry[name];
      if identity.provider == parsed.provider &&
         identity.hostname == parsed.hostname {
        return (true, identity,
                "Inferred from provider/hostname: " +
                providerToString(parsed.provider) + "/" + parsed.hostname);
      }
    }

    // Strategy 4: Just provider match (weak inference)
    for name in identityRegistry.keys() {
      const identity = identityRegistry[name];
      if identity.provider == parsed.provider {
        return (true, identity,
                "Inferred from provider (weak match): " +
                providerToString(parsed.provider));
      }
    }

    return (false, new GitIdentity(),
            "No matching identity for: " + originURL);
  }

  /*
   * Detect identity with detailed result
   */
  proc detectIdentityDetailed(repoPath: string = "."): DetectionResult {
    const (found, identity, reason) = detectIdentity(repoPath);

    var result = new DetectionResult();
    result.found = found;
    result.identity = identity;
    result.reason = reason;

    // Determine confidence level
    if !found {
      result.confidence = "none";
    } else if reason.find("Matched SSH host") != -1 ||
              reason.find("Matched organization") != -1 {
      result.confidence = "exact";
    } else {
      result.confidence = "inferred";
    }

    return result;
  }

  // ============================================================
  // Identity Switching
  // ============================================================

  /*
   * Switch to a different git identity
   *
   * This is the main entry point for identity switching. It:
   *   1. Looks up the target identity
   *   2. Authenticates with the provider (keychain -> env -> CLI -> SSH-only)
   *   3. Updates git remotes (if requested)
   *   4. Configures git user.name and user.email
   *   5. Configures GPG signing (if enabled)
   *   6. Verifies GPG key registration (opportunistic)
   *
   * Args:
   *   targetIdentity: Name of the identity to switch to
   *   updateRemote: Whether to update the git remote URL
   *   repoPath: Path to the repository (default: ".")
   *
   * Returns:
   *   SwitchResult with detailed status
   */
  proc switchIdentity(targetIdentity: string,
                      updateRemote: bool = true,
                      repoPath: string = "."): SwitchResult {
    var result = new SwitchResult();

    // 1. Look up the target identity
    const (found, identity) = getIdentity(targetIdentity);
    if !found {
      result.message = "Identity not found: " + targetIdentity;
      return result;
    }

    if verbose {
      writeln("Switching to identity: ", identity.name);
      writeln("  Provider: ", providerToString(identity.provider));
      writeln("  User: ", identity.user);
      writeln("  Email: ", identity.email);
    }

    // 2. Authenticate with provider
    const authResult = ProviderCLI.authenticateProvider(identity);
    result.authMode = authResult.mode;

    if verbose {
      writeln("  Authentication: ", authResult.message);
    }

    // 3. Update git remotes (if requested and we're in a repo)
    if updateRemote && Remote.isGitRepository(repoPath) {
      const (remoteOk, newURL) = Remote.updateOriginForIdentity(repoPath, identity);
      result.remoteUpdated = remoteOk;

      if verbose {
        if remoteOk {
          writeln("  Remote updated: ", newURL);
        } else {
          writeln("  Remote update: skipped or failed");
        }
      }
    }

    // 4. Configure git user
    if Remote.isGitRepository(repoPath) {
      Remote.setGitUser(repoPath, identity.user, identity.email);

      if verbose {
        writeln("  Git user configured: ", identity.user, " <", identity.email, ">");
      }
    }

    // 5. Configure GPG signing (if enabled)
    if gpgSign && identity.gpg.isConfigured() {
      var gpgKeyId = identity.gpg.keyId;

      // Auto-detect GPG key if set to "auto"
      if identity.gpg.isAutoDetect() {
        const (keyFound, autoKeyId) = GPG.getKeyForEmail(identity.email);
        if keyFound {
          gpgKeyId = autoKeyId;
          if verbose {
            writeln("  GPG key auto-detected: ", gpgKeyId);
          }
        } else {
          if verbose {
            writeln("  Warning: No GPG key found for ", identity.email);
          }
          gpgKeyId = "";
        }
      }

      if gpgKeyId != "" && Remote.isGitRepository(repoPath) {
        const gpgOk = GPG.configureGitGPG(repoPath, gpgKeyId,
                                          identity.gpg.signCommits,
                                          identity.gpg.autoSignoff);
        result.gpgConfigured = gpgOk;

        if verbose {
          writeln("  GPG configured: ", gpgKeyId,
                  " (sign commits: ", identity.gpg.signCommits, ")");
        }

        // 6. Opportunistically verify GPG key registration
        if gpgOk {
          const verifyResult = GPG.verifyKeyWithProvider(identity);
          if !verifyResult.verified && verifyResult.settingsURL != "" {
            writeln("  Note: GPG key may not be registered with ",
                    providerToString(identity.provider));
            writeln("    Add key at: ", verifyResult.settingsURL);
            writeln("    Export command: ", GPG.getExportCommand(gpgKeyId));
          }
        }
      }
    } else if Remote.isGitRepository(repoPath) {
      // Disable GPG signing if not configured for this identity
      GPG.disableGitGPG(repoPath);
    }

    // Build success result
    result.success = true;
    result.identity = identity;
    result.message = "Switched to " + identity.name + " (" +
                     providerToString(identity.provider) + ")";

    return result;
  }

  // ============================================================
  // Identity Validation
  // ============================================================

  /*
   * Validate an identity's configuration and connectivity
   *
   * This performs comprehensive validation:
   *   1. Check SSH connectivity to the host
   *   2. Check credential availability
   *   3. Check GPG key existence (if configured)
   *   4. Check GPG key registration with provider (if requested)
   *
   * Args:
   *   name: Identity name to validate
   *   checkGPG: Also verify GPG key registration with provider
   *
   * Returns:
   *   ValidationResult with detailed status
   */
  proc validateIdentity(name: string, checkGPG: bool = false): IdentityValidationResult {
    var result = new IdentityValidationResult();

    // Look up identity
    const (found, identity) = getIdentity(name);
    if !found {
      result.issues.pushBack("Identity not found: " + name);
      return result;
    }

    if verbose {
      writeln("Validating identity: ", name);
    }

    // 1. SSH connectivity check
    result.sshConnectivity = Remote.validateSSHConnectivity(identity.host);
    if !result.sshConnectivity {
      result.issues.pushBack("SSH connection failed to: " + identity.host);
    } else if verbose {
      writeln("  SSH connectivity: OK");
    }

    // 2. Credential availability check
    const (hasToken, _) = ProviderCLI.resolveCredential(identity);
    result.credentialAvailable = hasToken;
    if !hasToken {
      // This is not necessarily an error - SSH-only is valid
      if verbose {
        writeln("  Credential: None (SSH-only mode)");
      }
    } else if verbose {
      writeln("  Credential: Available");
    }

    // 3. GPG key check (if configured)
    if identity.gpg.isConfigured() {
      var keyId = identity.gpg.keyId;
      if identity.gpg.isAutoDetect() {
        const (keyFound, autoKeyId) = GPG.getKeyForEmail(identity.email);
        result.gpgKeyFound = keyFound;
        if keyFound {
          keyId = autoKeyId;
        }
      } else {
        // Check if the specified key exists
        const allKeys = GPG.listKeys();
        for key in allKeys {
          if key.keyId == keyId || key.fingerprint.endsWith(keyId) {
            result.gpgKeyFound = true;
            break;
          }
        }
      }

      if !result.gpgKeyFound {
        result.issues.pushBack("GPG key not found: " + identity.gpg.keyId);
      } else if verbose {
        writeln("  GPG key: Found (", keyId, ")");
      }

      // 4. GPG provider registration check (if requested)
      if checkGPG && result.gpgKeyFound {
        const verifyResult = GPG.verifyKeyWithProvider(identity);
        result.gpgRegistered = verifyResult.verified;
        if !verifyResult.verified {
          result.issues.pushBack("GPG key not registered with " +
                                 providerToString(identity.provider) +
                                 ": " + verifyResult.message);
        } else if verbose {
          writeln("  GPG registration: Verified");
        }
      }
    } else {
      // GPG not configured - not an issue
      result.gpgKeyFound = true;  // N/A
      result.gpgRegistered = true;  // N/A
    }

    // Determine overall validity
    result.valid = result.sshConnectivity &&
                   result.issues.size == 0;

    return result;
  }

  // ============================================================
  // Status and Diagnostics
  // ============================================================

  /*
   * Get current identity status for a repository
   *
   * Args:
   *   repoPath: Path to the repository
   *
   * Returns:
   *   Formatted status string
   */
  proc getIdentityStatus(repoPath: string = "."): string {
    var status: string = "";

    // Check if we're in a git repo
    if !Remote.isGitRepository(repoPath) {
      return "Not a git repository\n";
    }

    // Get current git user config
    const (hasName, userName) = Remote.getGitConfig(repoPath, "user.name");
    const (hasEmail, userEmail) = Remote.getGitConfig(repoPath, "user.email");

    status += "Git User Configuration:\n";
    status += "  Name: " + (if hasName then userName else "(not set)") + "\n";
    status += "  Email: " + (if hasEmail then userEmail else "(not set)") + "\n";

    // Try to detect identity
    const detection = detectIdentityDetailed(repoPath);
    status += "\nIdentity Detection:\n";
    if detection.found {
      status += "  Detected: " + detection.identity.name + "\n";
      status += "  Confidence: " + detection.confidence + "\n";
      status += "  Reason: " + detection.reason + "\n";
    } else {
      status += "  Not detected\n";
      status += "  Reason: " + detection.reason + "\n";
    }

    // Get origin remote info
    const (hasOrigin, originURL) = Remote.getOriginURL(repoPath);
    if hasOrigin {
      status += "\nOrigin Remote:\n";
      status += "  URL: " + originURL + "\n";
      const parsed = Remote.parseRemoteURL(originURL);
      if parsed.valid {
        status += "  Provider: " + parsed.provider:string + "\n";
        status += "  Host: " + parsed.host + "\n";
        status += "  Repo: " + parsed.repoPath + "\n";
      }
    }

    // GPG status
    const (hasSigningKey, signingKey) = Remote.getGitConfig(repoPath, "user.signingkey");
    const (hasGpgSign, gpgSignValue) = Remote.getGitConfig(repoPath, "commit.gpgsign");
    status += "\nGPG Signing:\n";
    status += "  Key: " + (if hasSigningKey then signingKey else "(not set)") + "\n";
    status += "  Sign Commits: " + (if hasGpgSign then gpgSignValue else "false") + "\n";

    return status;
  }

  /*
   * Print a summary of all registered identities
   */
  proc printIdentitySummary() {
    const identities = listIdentities();

    if identities.size == 0 {
      writeln("No identities registered.");
      return;
    }

    writeln("Registered Identities:");
    writeln("─".repeat(60));

    for identity in identities {
      writeln("  ", identity.name);
      writeln("    Provider: ", providerToString(identity.provider));
      writeln("    User: ", identity.user, " <", identity.email, ">");
      writeln("    SSH Host: ", identity.host);
      if identity.gpg.isConfigured() {
        writeln("    GPG: ", identity.gpg.keyId,
                (if identity.gpg.signCommits then " (signing enabled)" else ""));
      }
      writeln();
    }
  }

  // ============================================================
  // Utility Functions
  // ============================================================

  /*
   * Create a basic identity from minimal parameters
   */
  proc createIdentity(name: string, provider: Provider,
                      host: string, hostname: string,
                      user: string, email: string): GitIdentity {
    var identity = new GitIdentity();
    identity.name = name;
    identity.provider = provider;
    identity.host = host;
    identity.hostname = hostname;
    identity.user = user;
    identity.email = email;
    return identity;
  }

  /*
   * Get ISO 8601 timestamp for current time
   */
  proc nowISO(): string {
    // Simple implementation - Chapel's Time module doesn't have ISO formatting
    // In production, this would use proper date/time formatting
    const t = timeSinceEpoch().totalSeconds();
    return t:string;  // Unix timestamp for now
  }
}
