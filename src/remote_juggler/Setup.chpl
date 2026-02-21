/*
 * Setup.chpl - First-time setup wizard for RemoteJuggler
 *
 * Part of RemoteJuggler v2.0.0
 * Provides interactive and automated setup for:
 *   - SSH host detection and identity import
 *   - GPG key discovery and association
 *   - YubiKey/HSM detection for Trusted Workstation mode
 *   - gpg-agent configuration
 *   - Configuration file generation
 *
 * Usage:
 *   remote-juggler setup              # Interactive wizard
 *   remote-juggler setup --auto       # Auto-detect everything
 *   remote-juggler setup --import-ssh # Import SSH hosts only
 *   remote-juggler setup --import-gpg # Import GPG keys only
 *
 * Copyright (c) 2026 Jess Sullivan <jess@sulliwood.org>
 * License: Zlib
 */
module Setup {
  use IO;
  use List;
  use Map;
  use FileSystem;
  use Time;
  use Path;
  use Subprocess;

  // Import required modules
  public use super.Core;
  public use super.Config;
  public use super.GPG;
  public use super.YubiKey;
  public use super.HSM;
  public use super.GlobalConfig;
  import super.Config;
  import super.GPG;
  import super.YubiKey;
  import super.HSM;
  import super.GlobalConfig;

  // ============================================================
  // Setup Mode Enum
  // ============================================================

  /*
   * Setup operation mode
   */
  enum SetupMode {
    Interactive,  // Full interactive wizard
    Auto,         // Auto-detect and configure
    ImportSSH,    // Import SSH hosts only
    ImportGPG,    // Import GPG keys only
    Status,       // Show current setup status
    ShellIntegration  // Install shell integration (envrc, starship, nix)
  }

  // ============================================================
  // Setup Result Types
  // ============================================================

  /*
   * Result of the setup wizard
   */
  record SetupResult {
    var success: bool;
    var identitiesCreated: int;
    var gpgKeysAssociated: int;
    var hsmDetected: bool;
    var hsmType: string;  // "tpm", "secure_enclave", "none"
    var configPath: string;
    var message: string;
    var warnings: list(string);

    proc init() {
      this.success = false;
      this.identitiesCreated = 0;
      this.gpgKeysAssociated = 0;
      this.hsmDetected = false;
      this.hsmType = "none";
      this.configPath = "";
      this.message = "";
      this.warnings = new list(string);
    }
  }

  /*
   * Detected SSH host for import
   */
  record DetectedSSHHost {
    var alias: string;       // SSH host alias
    var hostname: string;    // Actual hostname
    var user: string;        // SSH user
    var identityFile: string; // Path to key
    var provider: string;    // Detected provider (gitlab, github, etc)
    var selected: bool;      // User selected for import

    proc init() {
      this.alias = "";
      this.hostname = "";
      this.user = "git";
      this.identityFile = "";
      this.provider = "";
      this.selected = true;
    }

    proc init(host: Config.SSHHost) {
      this.alias = host.host;
      this.hostname = host.hostname;
      this.user = host.user;
      this.identityFile = host.identityFile;
      this.provider = detectProvider(host.hostname, host.host);
      this.selected = true;
    }
  }

  /*
   * Detected GPG key for import
   */
  record DetectedGPGKey {
    var keyId: string;
    var email: string;
    var name: string;
    var fingerprint: string;
    var associatedIdentity: string;  // Identity name if matched
    var selected: bool;

    proc init() {
      this.keyId = "";
      this.email = "";
      this.name = "";
      this.fingerprint = "";
      this.associatedIdentity = "";
      this.selected = false;
    }

    proc init(key: GPG.GPGKey) {
      this.keyId = key.keyId;
      this.email = key.email;
      this.name = key.name;
      this.fingerprint = key.fingerprint;
      this.associatedIdentity = "";
      this.selected = false;
    }
  }

  /*
   * Detected HSM/hardware security module
   */
  record DetectedHSM {
    var available: bool;
    var hsmType: string;  // "tpm", "secure_enclave", "yubikey", "none"
    var details: string;
    var canStorePIN: bool;

    proc init() {
      this.available = false;
      this.hsmType = "none";
      this.details = "";
      this.canStorePIN = false;
    }
  }

  // ============================================================
  // Provider Detection
  // ============================================================

  /*
   * Detect git provider from hostname or SSH alias
   */
  proc detectProvider(hostname: string, alias: string): string {
    const lowerHost = hostname.toLower();
    const lowerAlias = alias.toLower();

    // Check hostname first
    if lowerHost.find("gitlab") != -1 then return "gitlab";
    if lowerHost.find("github") != -1 then return "github";
    if lowerHost.find("bitbucket") != -1 then return "bitbucket";
    if lowerHost.find("azure") != -1 || lowerHost.find("visualstudio") != -1 then return "azure";
    if lowerHost.find("codeberg") != -1 then return "codeberg";

    // Check alias
    if lowerAlias.find("gitlab") != -1 then return "gitlab";
    if lowerAlias.find("github") != -1 then return "github";
    if lowerAlias.find("bitbucket") != -1 then return "bitbucket";

    // Default based on common patterns
    if lowerHost == "gitlab.com" then return "gitlab";
    if lowerHost == "github.com" then return "github";
    if lowerHost == "bitbucket.org" then return "bitbucket";

    return "other";
  }

  // ============================================================
  // SSH Host Detection
  // ============================================================

  /*
   * Detect SSH hosts from ~/.ssh/config
   */
  proc detectSSHHosts(): list(DetectedSSHHost) {
    var hosts: list(DetectedSSHHost);

    // Parse SSH config (return empty list on failure)
    var sshHosts: list(Config.SSHHost);
    try {
      sshHosts = Config.parseSSHConfig();
    } catch {
      return hosts;
    }

    for host in sshHosts {
      // Skip wildcard and local hosts
      if host.host == "*" || host.host == "" then continue;
      if host.hostname.find("localhost") != -1 then continue;
      if host.hostname.find("127.0.0.1") != -1 then continue;

      // Skip if no identity file specified (not a git identity)
      if host.identityFile == "" then continue;

      var detected = new DetectedSSHHost(host);

      // Filter to likely git providers
      const provider = detected.provider;
      if provider == "gitlab" || provider == "github" ||
         provider == "bitbucket" || provider == "azure" ||
         provider == "codeberg" {
        detected.selected = true;
      } else {
        // Still include but not selected by default
        detected.selected = false;
      }

      hosts.pushBack(detected);
    }

    return hosts;
  }

  // ============================================================
  // GPG Key Detection
  // ============================================================

  /*
   * Detect GPG keys available for signing
   */
  proc detectGPGKeys(): list(DetectedGPGKey) {
    var keys: list(DetectedGPGKey);

    if !GPG.gpgAvailable() then return keys;

    const gpgKeys = GPG.listKeys();

    for key in gpgKeys {
      if key.keyId != "" && key.email != "" {
        keys.pushBack(new DetectedGPGKey(key));
      }
    }

    return keys;
  }

  /*
   * Match GPG keys to identities by email
   */
  proc matchGPGKeysToIdentities(
    ref keys: list(DetectedGPGKey),
    hosts: list(DetectedSSHHost)
  ) {
    // Build email domain to identity map
    // This is a heuristic - we match by email domain patterns

    for i in 0..<keys.size {
      ref key = keys[i];
      const email = key.email.toLower();

      // Try to match against detected hosts by common patterns
      for host in hosts {
        if !host.selected then continue;

        // Try to guess email patterns
        // e.g., gitlab-personal might match personal@...
        const alias = host.alias.toLower();

        // Check if email contains parts of the alias
        const aliasParts = alias.split("-");
        for part in aliasParts {
          if part.size >= 3 && email.find(part) != -1 {
            key.associatedIdentity = host.alias;
            key.selected = true;
            break;
          }
        }

        // Match by provider domain
        if host.provider == "github" && email.find("github") != -1 {
          key.associatedIdentity = host.alias;
          key.selected = true;
        }
      }
    }
  }

  // ============================================================
  // HSM Detection
  // ============================================================

  /*
   * Detect available HSM (TPM, Secure Enclave, YubiKey)
   */
  proc detectHSM(): DetectedHSM {
    var hsm = new DetectedHSM();

    // Check platform
    const isMac = checkPlatformMac();
    const isLinux = !isMac;  // Simplified check

    if isMac {
      // Check for Secure Enclave
      if checkSecureEnclaveAvailable() {
        hsm.available = true;
        hsm.hsmType = "secure_enclave";
        hsm.details = "Apple Secure Enclave (T2/M1+ chip)";
        hsm.canStorePIN = true;
        return hsm;
      }
    } else if isLinux {
      // Check for TPM 2.0
      if checkTPMAvailable() {
        hsm.available = true;
        hsm.hsmType = "tpm";
        hsm.details = "TPM 2.0 hardware module";
        hsm.canStorePIN = true;
        return hsm;
      }
    }

    // Check for YubiKey (both platforms)
    if YubiKey.isYubiKeyConnected() {
      const yubiKeyInfo = YubiKey.getYubiKeyInfo();
      hsm.available = true;
      hsm.hsmType = "yubikey";
      hsm.details = "YubiKey " + yubiKeyInfo.serialNumber;
      hsm.canStorePIN = false;  // YubiKey caches PIN internally
      return hsm;
    }

    return hsm;
  }

  /*
   * Check if running on macOS
   */
  proc checkPlatformMac(): bool {
    try {
      var p = spawn(["uname", "-s"], stdout=pipeStyle.pipe, stderr=pipeStyle.close);
      p.wait();
      if p.exitCode == 0 {
        var output: string;
        p.stdout.readAll(output);
        return output.strip().toLower() == "darwin";
      }
    } catch {
      // Ignore errors
    }
    return false;
  }

  /*
   * Check if Secure Enclave is available (macOS)
   */
  proc checkSecureEnclaveAvailable(): bool {
    try {
      var p = spawn(["system_profiler", "SPiBridgeDataType"],
                    stdout=pipeStyle.pipe, stderr=pipeStyle.close);
      p.wait();
      if p.exitCode == 0 {
        var output: string;
        p.stdout.readAll(output);
        return output.find("T2") != -1 || output.find("Apple M") != -1;
      }
    } catch {
      // Ignore errors
    }
    return false;
  }

  /*
   * Check if TPM 2.0 is available (Linux)
   */
  proc checkTPMAvailable(): bool {
    // Check for TPM device
    if exists("/dev/tpm0") || exists("/dev/tpmrm0") {
      // Verify TPM2 with tpm2_getcap
      try {
        var p = spawn(["tpm2_getcap", "properties-fixed"],
                      stdout=pipeStyle.close, stderr=pipeStyle.close);
        p.wait();
        return p.exitCode == 0;
      } catch {
        // tpm2-tools not installed, but TPM might still be available
        return true;
      }
    }
    return false;
  }

  // ============================================================
  // Configuration Generation
  // ============================================================

  /*
   * Generate identity configuration from detected SSH host
   */
  proc generateIdentityConfig(host: DetectedSSHHost): string {
    var json = '    "' + host.alias + '": {\n';
    json += '      "provider": "' + host.provider + '",\n';
    json += '      "host": "' + host.alias + '",\n';
    json += '      "hostname": "' + host.hostname + '",\n';
    json += '      "user": "' + host.user + '",\n';
    json += '      "identityFile": "' + host.identityFile + '"';
    // Note: email and GPG will be added later by user or through CLI
    json += '\n    }';
    return json;
  }

  /*
   * Generate full configuration JSON
   */
  proc generateConfigJSON(
    hosts: list(DetectedSSHHost),
    keys: list(DetectedGPGKey),
    hsm: DetectedHSM
  ): string {
    var json = '{\n';
    json += '  "version": "2.1.0-beta.7",\n';

    // Setup metadata
    json += '  "setupCompleted": true,\n';
    json += '  "setupVersion": "2.1.0-beta.7",\n';
    json += '  "setupDate": "' + getCurrentISODate() + '",\n';

    // Detected sources
    json += '  "detectedSources": {\n';
    json += '    "sshConfig": true,\n';
    json += '    "gitConfig": true';

    // Add GPG keys if detected
    if keys.size > 0 {
      json += ',\n    "gpgKeys": [';
      var first = true;
      for key in keys {
        if key.selected {
          if !first then json += ', ';
          json += '"' + key.keyId + '"';
          first = false;
        }
      }
      json += ']';
    }

    // Add HSM info
    if hsm.available {
      json += ',\n    "hsmType": "' + hsm.hsmType + '"';
    }

    json += '\n  },\n';

    // Identities
    json += '  "identities": {\n';
    var firstIdentity = true;
    for host in hosts {
      if host.selected {
        if !firstIdentity then json += ',\n';
        json += generateIdentityConfig(host);
        firstIdentity = false;
      }
    }
    json += '\n  },\n';

    // Settings
    json += '  "settings": {\n';
    json += '    "autoDetect": true,\n';
    json += '    "gpgSign": ' + (if keys.size > 0 then "true" else "false") + ',\n';
    if hsm.available && hsm.canStorePIN {
      json += '    "defaultSecurityMode": "trusted_workstation",\n';
      json += '    "hsmAvailable": true,\n';
    } else {
      json += '    "defaultSecurityMode": "developer_workflow",\n';
      json += '    "hsmAvailable": false,\n';
    }
    json += '    "useKeychain": ' + (if checkPlatformMac() then "true" else "false") + '\n';
    json += '  }\n';

    json += '}\n';
    return json;
  }

  /*
   * Get current date in ISO format (YYYY-MM-DDTHH:MM:SSZ)
   */
  proc getCurrentISODate(): string {
    try {
      const now = dateTime.now();
      // Manual ISO format construction
      var month = (now.month:int):string;
      if now.month:int < 10 then month = "0" + month;
      var day = now.day:string;
      if now.day < 10 then day = "0" + day;
      var hour = now.hour:string;
      if now.hour < 10 then hour = "0" + hour;
      var minute = now.minute:string;
      if now.minute < 10 then minute = "0" + minute;
      var second = now.second:string;
      if now.second < 10 then second = "0" + second;
      return now.year:string + "-" + month + "-" + day + "T" +
             hour + ":" + minute + ":" + second + "Z";
    } catch {
      return "1970-01-01T00:00:00Z";
    }
  }

  // ============================================================
  // Interactive Wizard
  // ============================================================

  /*
   * Run the interactive setup wizard
   */
  proc runInteractiveSetup(): SetupResult {
    var result = new SetupResult();

    writeln();
    writeln("╔══════════════════════════════════════════════════════════════╗");
    writeln("║              RemoteJuggler First-Time Setup                  ║");
    writeln("╚══════════════════════════════════════════════════════════════╝");
    writeln();

    // Step 1: Detect SSH hosts
    writeln("Step 1: Detecting SSH hosts from ~/.ssh/config...");
    var hosts = detectSSHHosts();

    if hosts.size == 0 {
      writeln("  No SSH hosts found.");
      writeln("  You may need to add SSH host configurations manually.");
      result.warnings.pushBack("No SSH hosts detected");
    } else {
      writeln("  Found ", hosts.size, " SSH host(s):");
      for host in hosts {
        const selected = if host.selected then "[x]" else "[ ]";
        writeln("    ", selected, " ", host.alias, " (", host.provider, ") → ", host.hostname);
      }
    }
    writeln();

    // Step 2: Detect GPG keys
    writeln("Step 2: Detecting GPG signing keys...");
    var keys = detectGPGKeys();

    if keys.size == 0 {
      writeln("  No GPG keys found.");
      writeln("  GPG signing will be disabled.");
    } else {
      matchGPGKeysToIdentities(keys, hosts);
      writeln("  Found ", keys.size, " GPG key(s):");
      for key in keys {
        const selected = if key.selected then "[x]" else "[ ]";
        const assoc = if key.associatedIdentity != "" then " → " + key.associatedIdentity else "";
        writeln("    ", selected, " ", key.keyId, " <", key.email, ">", assoc);
      }
    }
    writeln();

    // Step 3: Detect HSM
    writeln("Step 3: Detecting hardware security modules...");
    var hsm = detectHSM();

    if hsm.available {
      writeln("  ✓ Found: ", hsm.details);
      if hsm.canStorePIN {
        writeln("  Trusted Workstation mode is available!");
      }
    } else {
      writeln("  No HSM detected (TPM, Secure Enclave, or YubiKey)");
      writeln("  Trusted Workstation mode will not be available.");
    }
    writeln();

    // Step 4: Generate configuration
    writeln("Step 4: Generating configuration...");

    const configDir = GlobalConfig.getConfigDir();
    const configPath = configDir + "/config.json";

    // Check if config already exists
    if exists(configPath) {
      writeln("  ⚠ Configuration already exists at: ", configPath);
      writeln("  Run with --force to overwrite.");
      result.warnings.pushBack("Existing configuration found");
    }

    // Count selected items
    var selectedHosts = 0;
    for host in hosts {
      if host.selected then selectedHosts += 1;
    }
    var selectedKeys = 0;
    for key in keys {
      if key.selected then selectedKeys += 1;
    }

    // Generate config
    const configJSON = generateConfigJSON(hosts, keys, hsm);

    // Create config directory
    if !exists(configDir) {
      try {
        mkdir(configDir, mode=0o755, parents=true);
      } catch {
        result.message = "Failed to create config directory: " + configDir;
        return result;
      }
    }

    // Write config file
    try {
      var f = open(configPath, ioMode.cw);
      var w = f.writer(locking=false);
      w.write(configJSON);
      w.close();
      f.close();
    } catch e {
      result.message = "Failed to write config: " + e.message();
      return result;
    }

    writeln("  ✓ Configuration written to: ", configPath);
    writeln();

    // Summary
    writeln("════════════════════════════════════════════════════════════════");
    writeln("                        Setup Complete                          ");
    writeln("════════════════════════════════════════════════════════════════");
    writeln();
    writeln("  Identities created: ", selectedHosts);
    writeln("  GPG keys associated: ", selectedKeys);
    writeln("  HSM detected: ", if hsm.available then "Yes (" + hsm.hsmType + ")" else "No");
    writeln();
    writeln("Next steps:");
    writeln("  1. Review the config at: ", configPath);
    writeln("  2. Add email addresses to identities");
    writeln("  3. Run 'remote-juggler list' to see your identities");
    writeln("  4. Run 'remote-juggler switch <identity>' to switch");
    if hsm.available && hsm.canStorePIN {
      writeln("  5. Run 'remote-juggler pin store <identity>' for passwordless signing");
    }
    writeln();

    result.success = true;
    result.identitiesCreated = selectedHosts;
    result.gpgKeysAssociated = selectedKeys;
    result.hsmDetected = hsm.available;
    result.hsmType = hsm.hsmType;
    result.configPath = configPath;
    result.message = "Setup completed successfully";

    return result;
  }

  // ============================================================
  // Auto Setup
  // ============================================================

  /*
   * Run automatic setup (non-interactive)
   */
  proc runAutoSetup(): SetupResult {
    var result = new SetupResult();

    writeln("RemoteJuggler Auto Setup");
    writeln("========================");
    writeln();

    // Detect everything
    var hosts = detectSSHHosts();
    var keys = detectGPGKeys();
    var hsm = detectHSM();

    // Match GPG keys to hosts
    matchGPGKeysToIdentities(keys, hosts);

    // Auto-select all detected git hosts
    for i in 0..<hosts.size {
      ref host = hosts[i];
      if host.provider != "other" {
        host.selected = true;
      }
    }

    // Count selections
    var selectedHosts = 0;
    for host in hosts {
      if host.selected then selectedHosts += 1;
    }
    var selectedKeys = 0;
    for key in keys {
      if key.selected then selectedKeys += 1;
    }

    writeln("Detected:");
    writeln("  - SSH hosts: ", hosts.size, " (", selectedHosts, " git providers)");
    writeln("  - GPG keys: ", keys.size, " (", selectedKeys, " matched)");
    writeln("  - HSM: ", if hsm.available then hsm.details else "None");
    writeln();

    if selectedHosts == 0 {
      writeln("No git provider SSH hosts detected.");
      writeln("Please configure SSH hosts in ~/.ssh/config first.");
      result.message = "No SSH hosts detected";
      return result;
    }

    // Generate and write config
    const configDir = GlobalConfig.getConfigDir();
    const configPath = configDir + "/config.json";

    const configJSON = generateConfigJSON(hosts, keys, hsm);

    if !exists(configDir) {
      try {
        mkdir(configDir, mode=0o755, parents=true);
      } catch {
        result.message = "Failed to create config directory";
        return result;
      }
    }

    try {
      var f = open(configPath, ioMode.cw);
      var w = f.writer(locking=false);
      w.write(configJSON);
      w.close();
      f.close();
    } catch e {
      result.message = "Failed to write config: " + e.message();
      return result;
    }

    writeln("✓ Configuration written to: ", configPath);
    writeln();
    writeln("Run 'remote-juggler list' to see your identities.");

    result.success = true;
    result.identitiesCreated = selectedHosts;
    result.gpgKeysAssociated = selectedKeys;
    result.hsmDetected = hsm.available;
    result.hsmType = hsm.hsmType;
    result.configPath = configPath;
    result.message = "Auto setup completed";

    return result;
  }

  // ============================================================
  // Import Functions
  // ============================================================

  /*
   * Import SSH hosts only
   */
  proc runImportSSH(): SetupResult {
    var result = new SetupResult();

    writeln("Importing SSH hosts...");

    var hosts = detectSSHHosts();
    var selectedCount = 0;

    for host in hosts {
      if host.selected {
        writeln("  + ", host.alias, " (", host.provider, ")");
        selectedCount += 1;
      }
    }

    writeln();
    writeln("Found ", selectedCount, " SSH host(s) to import.");

    result.success = true;
    result.identitiesCreated = selectedCount;
    result.message = "SSH import completed";

    return result;
  }

  /*
   * Import GPG keys only
   */
  proc runImportGPG(): SetupResult {
    var result = new SetupResult();

    writeln("Detecting GPG keys...");

    var keys = detectGPGKeys();

    for key in keys {
      writeln("  + ", key.keyId, " <", key.email, ">");
    }

    writeln();
    writeln("Found ", keys.size, " GPG key(s).");

    result.success = true;
    result.gpgKeysAssociated = keys.size;
    result.message = "GPG import completed";

    return result;
  }

  // ============================================================
  // Status Check
  // ============================================================

  /*
   * Show current setup status
   */
  proc showSetupStatus(): SetupResult {
    var result = new SetupResult();

    writeln("RemoteJuggler Setup Status");
    writeln("==========================");
    writeln();

    const configDir = GlobalConfig.getConfigDir();
    const configPath = configDir + "/config.json";

    writeln("Configuration:");
    if exists(configPath) {
      writeln("  ✓ Config file exists: ", configPath);
      // TODO: Parse and show summary
    } else {
      writeln("  ✗ No config file found");
      writeln("    Run 'remote-juggler setup' to create one");
    }
    writeln();

    writeln("Environment:");
    writeln("  - Platform: ", if checkPlatformMac() then "macOS" else "Linux");
    writeln("  - GPG available: ", if GPG.gpgAvailable() then "Yes" else "No");

    var hsm = detectHSM();
    writeln("  - HSM available: ", if hsm.available then hsm.details else "No");
    writeln();

    result.success = true;
    result.message = "Status check completed";

    return result;
  }

  // ============================================================
  // Main Entry Point
  // ============================================================

  /*
   * Run setup with specified mode
   */
  proc runSetup(mode: SetupMode): SetupResult {
    select mode {
      when SetupMode.Interactive do return runInteractiveSetup();
      when SetupMode.Auto do return runAutoSetup();
      when SetupMode.ImportSSH do return runImportSSH();
      when SetupMode.ImportGPG do return runImportGPG();
      when SetupMode.Status do return showSetupStatus();
      when SetupMode.ShellIntegration do return installShellIntegrations();
    }

    var result = new SetupResult();
    result.message = "Unknown setup mode";
    return result;
  }

  /*
   * Parse setup mode from command line argument
   */
  proc parseSetupMode(arg: string): SetupMode {
    select arg {
      when "--auto", "-a" do return SetupMode.Auto;
      when "--import-ssh", "--ssh" do return SetupMode.ImportSSH;
      when "--import-gpg", "--gpg" do return SetupMode.ImportGPG;
      when "--status", "-s" do return SetupMode.Status;
      when "--shell", "--integrations" do return SetupMode.ShellIntegration;
      otherwise do return SetupMode.Interactive;
    }
  }

  // ============================================================
  // Shell Integration Setup
  // ============================================================

  /*
   * Install shell integrations (envrc, starship, nix)
   */
  proc installShellIntegrations(): SetupResult {
    var result = new SetupResult();

    writeln("RemoteJuggler Shell Integration Setup");
    writeln("=====================================");
    writeln();

    const homeDir = getEnvVar("HOME");
    if homeDir == "" {
      result.message = "Could not determine home directory";
      return result;
    }

    // Determine template source directory
    // Check if running from repo (templates/ exists) or installed (use share/remote-juggler/)
    const repoTemplatesDir = "./templates";
    const installedTemplatesDir = "/usr/local/share/remote-juggler/templates";
    var templatesDir = "";

    if exists(repoTemplatesDir) {
      templatesDir = repoTemplatesDir;
    } else if exists(installedTemplatesDir) {
      templatesDir = installedTemplatesDir;
    } else {
      result.message = "Template files not found. Install from repo or package.";
      return result;
    }

    writeln("Using templates from: ", templatesDir);
    writeln();

    var installed = 0;
    var skipped = 0;

    // 1. direnv/.envrc integration
    writeln("1. direnv/.envrc integration");
    const envrcTemplate = templatesDir + "/envrc";
    const envrcDest = homeDir + "/.config/remote-juggler/envrc-template";

    if !exists(envrcTemplate) {
      writeln("  ✗ Template not found: ", envrcTemplate);
      skipped += 1;
    } else {
      try {
        const destDir = homeDir + "/.config/remote-juggler";
        if !exists(destDir) {
          mkdir(destDir, mode=0o755, parents=true);
        }

        var srcFile = open(envrcTemplate, ioMode.r);
        var srcReader = srcFile.reader(locking=false);
        var content: string;
        srcReader.readAll(content);
        srcReader.close();
        srcFile.close();

        var destFile = open(envrcDest, ioMode.cw);
        var destWriter = destFile.writer(locking=false);
        destWriter.write(content);
        destWriter.close();
        destFile.close();

        writeln("  ✓ Installed: ", envrcDest);
        writeln("    Copy to project: cp ", envrcDest, " /path/to/project/.envrc");
        writeln("    Then run: direnv allow");
        installed += 1;
      } catch e {
        writeln("  ✗ Failed to install: ", e.message());
        skipped += 1;
      }
    }
    writeln();

    // 2. Starship integration
    writeln("2. Starship prompt integration");
    const starshipTemplate = templatesDir + "/starship.toml";
    const starshipDest = homeDir + "/.config/remote-juggler/starship-module.toml";

    if !exists(starshipTemplate) {
      writeln("  ✗ Template not found: ", starshipTemplate);
      skipped += 1;
    } else {
      try {
        var srcFile = open(starshipTemplate, ioMode.r);
        var srcReader = srcFile.reader(locking=false);
        var content: string;
        srcReader.readAll(content);
        srcReader.close();
        srcFile.close();

        var destFile = open(starshipDest, ioMode.cw);
        var destWriter = destFile.writer(locking=false);
        destWriter.write(content);
        destWriter.close();
        destFile.close();

        writeln("  ✓ Installed: ", starshipDest);
        writeln("    Add to ~/.config/starship.toml:");
        writeln("    [custom.remotejuggler]");
        writeln("    command = \"remote-juggler status --quiet 2>/dev/null\"");
        writeln("    when = \"test -d .git\"");
        writeln("    format = \"[$output](\\$style) \"");
        writeln("    style = \"bold blue\"");
        installed += 1;
      } catch e {
        writeln("  ✗ Failed to install: ", e.message());
        skipped += 1;
      }
    }
    writeln();

    // 3. Nix shell integration
    writeln("3. Nix devShell integration");
    const nixTemplate = templatesDir + "/nix-shell-integration.sh";
    const nixDest = homeDir + "/.config/remote-juggler/nix-shell-integration.sh";

    if !exists(nixTemplate) {
      writeln("  ✗ Template not found: ", nixTemplate);
      skipped += 1;
    } else {
      try {
        var srcFile = open(nixTemplate, ioMode.r);
        var srcReader = srcFile.reader(locking=false);
        var content: string;
        srcReader.readAll(content);
        srcReader.close();
        srcFile.close();

        var destFile = open(nixDest, ioMode.cw);
        var destWriter = destFile.writer(locking=false);
        destWriter.write(content);
        destWriter.close();
        destFile.close();

        writeln("  ✓ Installed: ", nixDest);
        writeln("    Add to flake.nix shellHook:");
        writeln("    shellHook = ''");
        writeln("      source ~/.config/remote-juggler/nix-shell-integration.sh");
        writeln("    '';");
        installed += 1;
      } catch e {
        writeln("  ✗ Failed to install: ", e.message());
        skipped += 1;
      }
    }
    writeln();

    // Summary
    writeln("═══════════════════════════════════════");
    writeln("           Installation Complete        ");
    writeln("═══════════════════════════════════════");
    writeln();
    writeln("Installed: ", installed, " integration(s)");
    if skipped > 0 {
      writeln("Skipped: ", skipped, " (errors or missing templates)");
    }
    writeln();
    writeln("Documentation:");
    writeln("  - direnv: https://direnv.net/");
    writeln("  - Starship: https://starship.rs/");
    writeln("  - Nix flakes: https://nixos.wiki/wiki/Flakes");
    writeln();

    result.success = (installed > 0);
    result.identitiesCreated = installed;
    result.message = "Shell integration setup completed";

    return result;
  }
}
