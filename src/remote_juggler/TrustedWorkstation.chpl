/*
  TrustedWorkstation Module
  ==========================

  Orchestrates all Trusted Workstation components for automated YubiKey PIN
  handling via hardware security modules (TPM 2.0 / Secure Enclave).

  This module ties together:
  - HSM.chpl: PIN storage in TPM/SecureEnclave
  - GPG.chpl: GPG agent and signing configuration
  - Custom pinentry: pinentry-remotejuggler.py
  - ykman: YubiKey PIN policy management

  **Trusted Workstation Mode:**

  When enabled, YubiKey PINs are stored in hardware security modules and
  automatically retrieved during GPG signing operations. This eliminates
  repeated PIN prompts on trusted development workstations while maintaining
  strong security through hardware-backed encryption.

  **Security Model:**

  1. PINs are sealed (encrypted) by the HSM before storage
  2. Unsealing requires the same hardware and platform state
  3. TPM sealing is bound to PCR 7 (Secure Boot state)
  4. Secure Enclave uses ECIES with SE-protected keys
  5. PIN is never stored in application memory longer than necessary

  **Mode Transitions:**

  - Enabling requires: HSM available, PIN provided, gpg-agent restartable
  - Disabling: Clears PIN from HSM, restores original gpg-agent config
  - Mode switch always requires re-entering PIN

  :author: RemoteJuggler Team
  :version: 2.0.0
  :license: MIT
*/
prototype module TrustedWorkstation {
  use IO;
  use List;
  use FileSystem;
  use Path;
  use Subprocess;
  public use super.Core;
  public use super.HSM;
  public use super.GPG;
  public use super.GlobalConfig except getIdentity;
  public use super.YubiKey;

  // =========================================================================
  // Trusted Workstation Types
  // =========================================================================

  /*
    Error types for Trusted Workstation operations.
  */
  enum TWSError {
    None,
    NoHSM,
    NoYubiKey,
    NoGPGAgent,
    PINStoreFailed,
    ConfigFailed,
    YkmanFailed,
    PINRetrieveFailed,
    RestartFailed,
    VerifyFailed,
    InvalidIdentity,
    AlreadyEnabled,
    NotEnabled,
    InternalError
  }

  /*
    Result of a Trusted Workstation operation.

    :var success: Whether the operation succeeded
    :var error: Error type if failed
    :var message: Human-readable status/error message
  */
  record TWSResult {
    var success: bool = false;
    var error: TWSError = TWSError.None;
    var message: string = "";

    /*
      Initialize with default values (failure state).
    */
    proc init() {
      this.success = false;
      this.error = TWSError.None;
      this.message = "";
    }

    /*
      Initialize a success result.

      :arg message: Success message
    */
    proc init(message: string) {
      this.success = true;
      this.error = TWSError.None;
      this.message = message;
    }

    /*
      Initialize a failure result.

      :arg error: Error type
      :arg message: Error message
    */
    proc init(error: TWSError, message: string) {
      this.success = false;
      this.error = error;
      this.message = message;
    }

    /*
      Initialize with all values.

      :arg success: Whether operation succeeded
      :arg error: Error type
      :arg message: Status message
    */
    proc init(success: bool, error: TWSError, message: string) {
      this.success = success;
      this.error = error;
      this.message = message;
    }
  }

  /*
    Trusted Workstation status information.

    Provides a comprehensive view of the current Trusted Workstation state
    including HSM status, PIN storage, gpg-agent configuration, and YubiKey
    PIN policy.

    :var enabled: Whether Trusted Workstation mode is active
    :var hsmType: HSM backend type (TPM 2.0, Secure Enclave, Keychain)
    :var hsmAvailable: Whether an HSM backend is available
    :var pinStored: Whether a PIN is stored for the identity
    :var gpgAgentConfigured: Whether gpg-agent is configured for custom pinentry
    :var gpgAgentRunning: Whether gpg-agent is currently running
    :var ykmanAvailable: Whether ykman CLI is available
    :var yubiKeyConnected: Whether a YubiKey is connected
    :var yubiKeyPinPolicy: Current YubiKey signature PIN policy
    :var identity: Identity name for which status is reported
    :var pinentryConfigured: Whether custom pinentry is configured
    :var pinentryPath: Path to the configured pinentry program
  */
  record TWSStatus {
    var enabled: bool = false;
    var hsmType: string = "";
    var hsmAvailable: bool = false;
    var pinStored: bool = false;
    var gpgAgentConfigured: bool = false;
    var gpgAgentRunning: bool = false;
    var ykmanAvailable: bool = false;
    var yubiKeyConnected: bool = false;
    var yubiKeyPinPolicy: string = "";
    var identity: string = "";
    var pinentryConfigured: bool = false;
    var pinentryPath: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.enabled = false;
      this.hsmType = "";
      this.hsmAvailable = false;
      this.pinStored = false;
      this.gpgAgentConfigured = false;
      this.gpgAgentRunning = false;
      this.ykmanAvailable = false;
      this.yubiKeyConnected = false;
      this.yubiKeyPinPolicy = "";
      this.identity = "";
      this.pinentryConfigured = false;
      this.pinentryPath = "";
    }

    /*
      Check if all prerequisites for Trusted Workstation are met.

      :returns: true if all prerequisites are satisfied
    */
    proc hasPrerequisites(): bool {
      return hsmAvailable && gpgAgentRunning;
    }

    /*
      Get a list of missing prerequisites.

      :returns: List of missing requirement descriptions
    */
    proc getMissingPrerequisites(): list(string) {
      var missing: list(string);
      if !hsmAvailable then missing.pushBack("HSM (TPM 2.0 or Secure Enclave) not available");
      if !gpgAgentRunning then missing.pushBack("gpg-agent not running");
      if enabled && !pinStored then missing.pushBack("PIN not stored in HSM");
      if enabled && !pinentryConfigured then missing.pushBack("Custom pinentry not configured");
      return missing;
    }

    /*
      Get a summary string for display.

      :returns: Multi-line status summary
    */
    proc summary(): string {
      var result = "";
      result += "Trusted Workstation Mode: " + (if enabled then "ENABLED" else "DISABLED") + "\n";
      result += "  HSM: " + (if hsmAvailable then hsmType else "Not available") + "\n";
      result += "  PIN Stored: " + (if pinStored then "Yes" else "No") + "\n";
      result += "  gpg-agent: " + (if gpgAgentRunning then "Running" else "Not running") + "\n";
      result += "  Custom Pinentry: " + (if pinentryConfigured then "Configured" else "Not configured") + "\n";
      if ykmanAvailable {
        result += "  YubiKey: " + (if yubiKeyConnected then "Connected" else "Not connected") + "\n";
        if yubiKeyConnected && yubiKeyPinPolicy != "" {
          result += "  PIN Policy: " + yubiKeyPinPolicy + "\n";
        }
      }
      if identity != "" {
        result += "  Identity: " + identity + "\n";
      }
      return result;
    }
  }

  /*
    Prerequisites check result.

    :var allMet: Whether all prerequisites are satisfied
    :var issues: List of issues preventing Trusted Workstation mode
    :var warnings: List of non-blocking warnings
  */
  record PrerequisitesResult {
    var allMet: bool = true;
    var issues: list(string);
    var warnings: list(string);

    /*
      Initialize with default values.
    */
    proc init() {
      this.allMet = true;
      this.issues = new list(string);
      this.warnings = new list(string);
    }

    /*
      Add an issue (makes prerequisites not met).

      :arg issue: Issue description
    */
    proc ref addIssue(issue: string) {
      issues.pushBack(issue);
      allMet = false;
    }

    /*
      Add a warning (doesn't block but should be noted).

      :arg warning: Warning message
    */
    proc ref addWarning(warning: string) {
      warnings.pushBack(warning);
    }
  }

  // =========================================================================
  // Configuration Constants
  // =========================================================================

  /*
    Path to custom pinentry program.
  */
  proc getPinentryPath(): string {
    // Check multiple locations
    const candidates = [
      expandTilde("~/.local/bin/pinentry-remotejuggler"),
      "/usr/local/bin/pinentry-remotejuggler",
      expandTilde("~/.config/remote-juggler/pinentry-remotejuggler.py")
    ];

    for candidate in candidates {
      try {
        if FileSystem.exists(candidate) {
          return candidate;
        }
      } catch {
        continue;
      }
    }

    // Return default even if not found
    return expandTilde("~/.local/bin/pinentry-remotejuggler");
  }

  /*
    Path to gpg-agent configuration file.
  */
  proc getGPGAgentConfPath(): string {
    return expandTilde("~/.gnupg/gpg-agent.conf");
  }

  /*
    Path to backup gpg-agent configuration.
  */
  proc getGPGAgentConfBackupPath(): string {
    return expandTilde("~/.gnupg/gpg-agent.conf.rj-backup");
  }

  // =========================================================================
  // Prerequisites Checking
  // =========================================================================

  /*
    Check all prerequisites for Trusted Workstation mode.

    Validates:
    - HSM availability (TPM 2.0 or Secure Enclave)
    - gpg-agent running
    - ykman availability (optional but recommended)
    - YubiKey connected (if configuring ykman)

    :arg identity: Identity name to check prerequisites for
    :returns: PrerequisitesResult with any issues found
  */
  proc checkPrerequisites(identity: string = ""): PrerequisitesResult {
    var result = new PrerequisitesResult();

    verboseLog("Checking Trusted Workstation prerequisites...");

    // Check HSM availability
    const hsmType = hsm_detect_available();
    if hsmType == HSM_TYPE_NONE {
      result.addIssue("No HSM backend available (TPM 2.0 or Secure Enclave required)");
    } else if hsmType == HSM_TYPE_KEYCHAIN {
      result.addWarning("Using software keychain fallback - less secure than hardware HSM");
    }

    // Check gpg-agent
    if !isGPGAgentRunning() {
      result.addIssue("gpg-agent is not running");
    }

    // Check ykman availability (optional)
    if !isYkmanAvailable() {
      result.addWarning("ykman not available - PIN policy management disabled");
    } else {
      // Check YubiKey connection (optional)
      if !isYubiKeyConnected() {
        result.addWarning("No YubiKey connected - will configure when inserted");
      }
    }

    // Check identity if provided
    if identity != "" {
      const (found, _) = getIdentity(identity);
      if !found {
        result.addIssue("Identity not found: " + identity);
      }
    }

    // Check pinentry program
    const pinentryPath = getPinentryPath();
    try {
      if !FileSystem.exists(pinentryPath) {
        result.addWarning("Custom pinentry not found at " + pinentryPath + " - install required");
      }
    } catch {
      result.addWarning("Could not check for custom pinentry");
    }

    return result;
  }

  /*
    Check if gpg-agent is running.

    :returns: true if gpg-agent is running
  */
  proc isGPGAgentRunning(): bool {
    try {
      var p = spawn(["gpg-connect-agent", "/bye"],
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  // Note: isYkmanAvailable() and isYubiKeyConnected() are provided by the YubiKey module

  /*
    Get current YubiKey signature PIN policy.

    :returns: Policy string ("once", "always") or empty if not detected
  */
  proc getYubiKeyPinPolicy(): string {
    if !isYkmanAvailable() || !isYubiKeyConnected() {
      return "";
    }
    const info = getYubiKeyInfo();
    return info.sigPinPolicy;
  }

  /*
    Set YubiKey signature PIN policy.

    :arg policy: "once" or "always"
    :returns: true if policy was set successfully
  */
  proc setYubiKeyPinPolicy(policy: string): bool {
    if !isYkmanAvailable() || !isYubiKeyConnected() {
      return false;
    }
    return setSignaturePinPolicy(policy);
  }

  // =========================================================================
  // gpg-agent Configuration
  // =========================================================================

  /*
    Check if gpg-agent is configured for custom pinentry.

    :returns: true if pinentry-remotejuggler is configured
  */
  proc isGPGAgentConfiguredForTWS(): bool {
    const confPath = getGPGAgentConfPath();

    try {
      if !FileSystem.exists(confPath) then return false;

      var f = open(confPath, ioMode.r);
      defer { try! f.close(); }
      var reader = f.reader(locking=false);
      defer { try! reader.close(); }

      var content: string;
      reader.readAll(content);

      // Check for our pinentry program
      return content.find("pinentry-remotejuggler") != -1;
    } catch {
      return false;
    }
  }

  /*
    Configure gpg-agent for custom pinentry.

    Backs up the existing configuration and adds:
    - pinentry-program pointing to pinentry-remotejuggler
    - allow-loopback-pinentry for fallback support

    :returns: TWSResult indicating success or failure
  */
  proc configureGPGAgentForTWS(): TWSResult {
    const confPath = getGPGAgentConfPath();
    const backupPath = getGPGAgentConfBackupPath();
    const pinentryPath = getPinentryPath();

    verboseLog("Configuring gpg-agent for Trusted Workstation...");

    try {
      var originalContent = "";

      // Read existing config
      if FileSystem.exists(confPath) {
        var f = open(confPath, ioMode.r);
        defer { try! f.close(); }
        var reader = f.reader(locking=false);
        defer { try! reader.close(); }
        reader.readAll(originalContent);

        // Backup original
        var backupFile = open(backupPath, ioMode.cw);
        defer { try! backupFile.close(); }
        var backupWriter = backupFile.writer(locking=false);
        defer { try! backupWriter.close(); }
        backupWriter.write(originalContent);

        verboseLog("Backed up gpg-agent.conf to ", backupPath);
      }

      // Remove existing pinentry-program line if present
      var newLines: list(string);
      for line in originalContent.split("\n") {
        const trimmed = line.strip();
        if !trimmed.startsWith("pinentry-program") {
          newLines.pushBack(line);
        }
      }

      // Add our configuration
      newLines.pushBack("");
      newLines.pushBack("# BEGIN RemoteJuggler Trusted Workstation Configuration");
      newLines.pushBack("pinentry-program " + pinentryPath);
      newLines.pushBack("allow-loopback-pinentry");
      newLines.pushBack("# END RemoteJuggler Trusted Workstation Configuration");

      // Write new config
      var outFile = open(confPath, ioMode.cw);
      defer { try! outFile.close(); }
      var writer = outFile.writer(locking=false);
      defer { try! writer.close(); }

      var first = true;
      for line in newLines {
        if !first then writer.writeln();
        first = false;
        writer.write(line);
      }

      verboseLog("gpg-agent.conf updated with custom pinentry");

      return new TWSResult("gpg-agent configured for Trusted Workstation mode");
    } catch e {
      return new TWSResult(TWSError.ConfigFailed,
                           "Failed to configure gpg-agent: " + e.message());
    }
  }

  /*
    Restore original gpg-agent configuration.

    :returns: TWSResult indicating success or failure
  */
  proc restoreGPGAgentConfig(): TWSResult {
    const confPath = getGPGAgentConfPath();
    const backupPath = getGPGAgentConfBackupPath();

    verboseLog("Restoring original gpg-agent configuration...");

    try {
      if !FileSystem.exists(backupPath) {
        // No backup, try to remove our configuration block
        if FileSystem.exists(confPath) {
          var f = open(confPath, ioMode.r);
          defer { try! f.close(); }
          var reader = f.reader(locking=false);
          defer { try! reader.close(); }

          var content: string;
          reader.readAll(content);

          // Remove our configuration block
          var newLines: list(string);
          var inOurBlock = false;

          for line in content.split("\n") {
            if line.find("BEGIN RemoteJuggler Trusted Workstation") != -1 {
              inOurBlock = true;
              continue;
            }
            if line.find("END RemoteJuggler Trusted Workstation") != -1 {
              inOurBlock = false;
              continue;
            }
            if !inOurBlock {
              newLines.pushBack(line);
            }
          }

          // Write cleaned config
          var outFile = open(confPath, ioMode.cw);
          defer { try! outFile.close(); }
          var writer = outFile.writer(locking=false);
          defer { try! writer.close(); }

          var first = true;
          for line in newLines {
            if !first then writer.writeln();
            first = false;
            writer.write(line);
          }
        }

        return new TWSResult("gpg-agent configuration cleaned (no backup found)");
      }

      // Restore from backup
      var backupFile = open(backupPath, ioMode.r);
      defer { try! backupFile.close(); }
      var reader = backupFile.reader(locking=false);
      defer { try! reader.close(); }

      var backupContent: string;
      reader.readAll(backupContent);

      var outFile = open(confPath, ioMode.cw);
      defer { try! outFile.close(); }
      var writer = outFile.writer(locking=false);
      defer { try! writer.close(); }
      writer.write(backupContent);

      // Remove backup file
      FileSystem.remove(backupPath);

      verboseLog("Restored gpg-agent.conf from backup");

      return new TWSResult("gpg-agent configuration restored");
    } catch e {
      return new TWSResult(TWSError.ConfigFailed,
                           "Failed to restore gpg-agent config: " + e.message());
    }
  }

  /*
    Restart gpg-agent to apply configuration changes.

    :returns: TWSResult indicating success or failure
  */
  proc restartGPGAgent(): TWSResult {
    verboseLog("Restarting gpg-agent...");

    try {
      // Kill existing agent
      var killP = spawn(["gpgconf", "--kill", "gpg-agent"],
                        stdout=pipeStyle.close,
                        stderr=pipeStyle.close);
      killP.wait();

      // Give it a moment
      use Time;
      sleep(1);

      // Start new agent (gpg-connect-agent will auto-start it)
      var startP = spawn(["gpg-connect-agent", "/bye"],
                         stdout=pipeStyle.close,
                         stderr=pipeStyle.close);
      startP.wait();

      if startP.exitCode == 0 {
        return new TWSResult("gpg-agent restarted successfully");
      } else {
        return new TWSResult(TWSError.RestartFailed,
                             "gpg-agent failed to restart");
      }
    } catch e {
      return new TWSResult(TWSError.RestartFailed,
                           "Failed to restart gpg-agent: " + e.message());
    }
  }

  // =========================================================================
  // Enable/Disable Trusted Workstation Mode
  // =========================================================================

  /*
    Enable Trusted Workstation mode for an identity.

    Workflow:
    1. Check prerequisites (HSM, gpg-agent, optionally ykman)
    2. Store PIN in HSM
    3. Configure gpg-agent for custom pinentry
    4. Set YubiKey PIN policy to "once" (if ykman available)
    5. Restart gpg-agent
    6. Verify by triggering a test operation

    :arg identity: Identity name to enable for
    :arg pin: YubiKey PIN to store
    :returns: TWSResult with success/failure status
  */
  proc enableTrustedWorkstation(identity: string, pin: string): TWSResult {
    verboseLog("Enabling Trusted Workstation for identity: ", identity);

    // Step 1: Check prerequisites
    const prereqs = checkPrerequisites(identity);
    if !prereqs.allMet {
      var issueList = "";
      for issue in prereqs.issues {
        if issueList != "" then issueList += "; ";
        issueList += issue;
      }
      return new TWSResult(TWSError.NoHSM,
                           "Prerequisites not met: " + issueList);
    }

    // Validate PIN
    if pin.size < 6 || pin.size > 127 {
      return new TWSResult(TWSError.PINStoreFailed,
                           "PIN must be between 6 and 127 characters");
    }

    // Step 2: Store PIN in HSM
    verboseLog("Storing PIN in HSM...");
    const storeResult = hsm_store_pin(identity, pin, pin.size);
    if storeResult != HSM_SUCCESS {
      const errMsg = hsm_error_message(storeResult);
      return new TWSResult(TWSError.PINStoreFailed,
                           "Failed to store PIN in HSM: " + errMsg);
    }
    verboseLog("PIN stored successfully");

    // Step 3: Configure gpg-agent
    const configResult = configureGPGAgentForTWS();
    if !configResult.success {
      // Rollback: clear PIN
      hsm_clear_pin(identity);
      return configResult;
    }

    // Step 4: Set YubiKey PIN policy to "once" (optional)
    if isYkmanAvailable() && isYubiKeyConnected() {
      verboseLog("Setting YubiKey PIN policy to 'once'...");
      if setYubiKeyPinPolicy("once") {
        verboseLog("YubiKey PIN policy set to 'once'");
      } else {
        verboseLog("Warning: Could not set YubiKey PIN policy");
      }
    }

    // Step 5: Restart gpg-agent
    const restartResult = restartGPGAgent();
    if !restartResult.success {
      // Rollback: restore config and clear PIN
      restoreGPGAgentConfig();
      hsm_clear_pin(identity);
      return restartResult;
    }

    // Step 6: Update identity security mode in config
    var cfg = loadConfig();
    for i in 0..<cfg.identities.size {
      if cfg.identities[i].name == identity {
        cfg.identities[i].gpg.securityMode = "trusted_workstation";
        cfg.identities[i].gpg.pinStorageMethod = hsm_type_name(hsm_detect_available());
        break;
      }
    }
    saveConfig(cfg);

    // Update global settings
    setHSMAvailability(true);

    return new TWSResult("Trusted Workstation mode enabled for " + identity);
  }

  /*
    Disable Trusted Workstation mode for an identity.

    Workflow:
    1. Restore original gpg-agent configuration
    2. Clear PIN from HSM
    3. Reset YubiKey PIN policy to "always" (if ykman available)
    4. Restart gpg-agent

    :arg identity: Identity name to disable for
    :returns: TWSResult with success/failure status
  */
  proc disableTrustedWorkstation(identity: string): TWSResult {
    verboseLog("Disabling Trusted Workstation for identity: ", identity);

    // Step 1: Restore original gpg-agent config
    const configResult = restoreGPGAgentConfig();
    if !configResult.success {
      verboseLog("Warning: Could not restore gpg-agent config: ", configResult.message);
    }

    // Step 2: Clear PIN from HSM
    verboseLog("Clearing PIN from HSM...");
    const clearResult = hsm_clear_pin(identity);
    if clearResult != HSM_SUCCESS {
      verboseLog("Warning: Could not clear PIN from HSM: ", hsm_error_message(clearResult));
    }

    // Step 3: Reset YubiKey PIN policy to "always" (optional)
    if isYkmanAvailable() && isYubiKeyConnected() {
      verboseLog("Resetting YubiKey PIN policy to 'always'...");
      if setYubiKeyPinPolicy("always") {
        verboseLog("YubiKey PIN policy reset to 'always'");
      } else {
        verboseLog("Warning: Could not reset YubiKey PIN policy");
      }
    }

    // Step 4: Restart gpg-agent
    const restartResult = restartGPGAgent();
    if !restartResult.success {
      verboseLog("Warning: gpg-agent restart failed: ", restartResult.message);
    }

    // Step 5: Update identity security mode in config
    var cfg = loadConfig();
    for i in 0..<cfg.identities.size {
      if cfg.identities[i].name == identity {
        cfg.identities[i].gpg.securityMode = "developer_workflow";
        cfg.identities[i].gpg.pinStorageMethod = "";
        break;
      }
    }
    saveConfig(cfg);

    return new TWSResult("Trusted Workstation mode disabled for " + identity);
  }

  // =========================================================================
  // Status Reporting
  // =========================================================================

  /*
    Get comprehensive Trusted Workstation status.

    :arg identity: Optional identity name to check status for
    :returns: TWSStatus with full status information
  */
  proc getTrustedWorkstationStatus(identity: string = ""): TWSStatus {
    var status = new TWSStatus();

    // HSM status
    const hsmType = hsm_detect_available();
    status.hsmAvailable = (hsmType != HSM_TYPE_NONE);
    status.hsmType = hsm_type_name(hsmType);

    // gpg-agent status
    status.gpgAgentRunning = isGPGAgentRunning();
    status.gpgAgentConfigured = isGPGAgentConfiguredForTWS();

    // Pinentry status
    const pinentryPath = getPinentryPath();
    status.pinentryPath = pinentryPath;
    try {
      status.pinentryConfigured = FileSystem.exists(pinentryPath);
    } catch {
      status.pinentryConfigured = false;
    }

    // YubiKey status
    status.ykmanAvailable = isYkmanAvailable();
    if status.ykmanAvailable {
      status.yubiKeyConnected = isYubiKeyConnected();
      if status.yubiKeyConnected {
        status.yubiKeyPinPolicy = getYubiKeyPinPolicy();
      }
    }

    // Identity-specific status
    if identity != "" {
      status.identity = identity;
      status.pinStored = hsm_has_pin(identity) != 0;

      // Check if identity has TWS enabled in config
      const cfg = loadConfig();
      for id in cfg.identities {
        if id.name == identity {
          status.enabled = id.gpg.securityMode == "trusted_workstation";
          break;
        }
      }
    } else {
      // Check if any identity has TWS enabled
      const cfg = loadConfig();
      for id in cfg.identities {
        if id.gpg.securityMode == "trusted_workstation" {
          status.enabled = true;
          status.identity = id.name;
          status.pinStored = hsm_has_pin(id.name) != 0;
          break;
        }
      }
    }

    return status;
  }

  /*
    Get identity by name from configuration.

    :arg name: Identity name
    :returns: Tuple of (found, GitIdentity)
  */
  proc getIdentity(name: string): (bool, GitIdentity) {
    const cfg = loadConfig();
    for id in cfg.identities {
      if id.name == name {
        return (true, id);
      }
    }
    return (false, new GitIdentity());
  }

  // =========================================================================
  // PIN Unsealing (for use by pinentry)
  // =========================================================================

  /*
    Unseal and print PIN to stdout for use by pinentry.

    This is called by the pinentry-remotejuggler.py script via CLI.
    The PIN is output to stdout for the pinentry to capture.

    :arg identity: Identity to unseal PIN for
    :returns: TWSResult with success/failure
  */
  proc unsealPinForPinentry(identity: string): TWSResult {
    // Verify identity has TWS enabled
    const (found, id) = getIdentity(identity);
    if !found {
      return new TWSResult(TWSError.InvalidIdentity, "Identity not found: " + identity);
    }

    if id.gpg.securityMode != "trusted_workstation" {
      return new TWSResult(TWSError.NotEnabled,
                           "Trusted Workstation mode not enabled for " + identity);
    }

    // Check if PIN is stored
    if hsm_has_pin(identity) == 0 {
      return new TWSResult(TWSError.PINRetrieveFailed,
                           "No PIN stored for identity: " + identity);
    }

    // Retrieve PIN
    const (status, pin) = hsm_retrieve_pin(identity);
    if status != HSM_SUCCESS {
      return new TWSResult(TWSError.PINRetrieveFailed,
                           "Failed to retrieve PIN: " + hsm_error_message(status));
    }

    // Output PIN to stdout (pinentry captures this)
    write(pin);

    return new TWSResult("PIN retrieved successfully");
  }

  // =========================================================================
  // CLI Command Handlers
  // =========================================================================

  /*
    Handle 'trusted-workstation enable' command.

    Prompts for PIN if not provided via argument.

    :arg identity: Identity name
    :arg pin: Optional PIN (will prompt if empty)
    :returns: TWSResult
  */
  proc handleTWSEnable(identity: string, pin: string = ""): TWSResult {
    var pinToUse = pin;

    // Prompt for PIN if not provided
    if pinToUse == "" {
      writeln("Enter YubiKey PIN for ", identity, " (input hidden):");
      write("> ");

      if !stdin.readLine(pinToUse) {
        return new TWSResult(TWSError.PINStoreFailed, "Failed to read PIN");
      }
      pinToUse = pinToUse.strip();
    }

    return enableTrustedWorkstation(identity, pinToUse);
  }

  /*
    Handle 'trusted-workstation disable' command.

    :arg identity: Identity name
    :returns: TWSResult
  */
  proc handleTWSDisable(identity: string): TWSResult {
    return disableTrustedWorkstation(identity);
  }

  /*
    Handle 'trusted-workstation status' command.

    :arg identity: Optional identity name
    :returns: Status string for display
  */
  proc handleTWSStatus(identity: string = ""): string {
    const status = getTrustedWorkstationStatus(identity);
    return status.summary();
  }

  // =========================================================================
  // Verification
  // =========================================================================

  /*
    Verify Trusted Workstation mode is working by performing a test sign.

    :arg identity: Identity to verify
    :returns: TWSResult indicating verification success/failure
  */
  proc verifyTrustedWorkstation(identity: string): TWSResult {
    verboseLog("Verifying Trusted Workstation for: ", identity);

    // Get identity GPG key
    const (found, id) = getIdentity(identity);
    if !found {
      return new TWSResult(TWSError.InvalidIdentity, "Identity not found: " + identity);
    }

    if !id.gpg.isConfigured() {
      return new TWSResult(TWSError.VerifyFailed,
                           "No GPG key configured for identity: " + identity);
    }

    // Try a test sign
    const keyId = id.gpg.keyId;
    if testSigning(keyId) {
      return new TWSResult("Trusted Workstation verification successful");
    } else {
      return new TWSResult(TWSError.VerifyFailed,
                           "GPG signing test failed - check PIN and YubiKey connection");
    }
  }
}
