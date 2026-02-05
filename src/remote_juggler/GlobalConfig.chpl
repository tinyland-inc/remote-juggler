/*
  GlobalConfig Module
  ===================

  Global configuration management with managed blocks for RemoteJuggler.

  This module handles the main configuration file at
  ``~/.config/remote-juggler/config.json`` which stores:

  - Identity definitions
  - Managed blocks (auto-synced from SSH/git configs)
  - Application settings
  - Current state

  **Managed Blocks:**

  Certain sections of the config are auto-generated from system files
  and marked with special comments:

  - ``ssh-hosts`` - Synced from ~/.ssh/config
  - ``gitconfig-rewrites`` - Synced from ~/.gitconfig URL rules

  These blocks should not be manually edited as they will be overwritten
  on the next sync operation.

  :author: RemoteJuggler Team
  :version: 2.0.0
*/
prototype module GlobalConfig {
  use IO;
  use List;
  use Map;
  use Time;
  use FileSystem;
  public use super.Core;
  public use super.Config;

  // =========================================================================
  // Configuration Paths
  // =========================================================================

  /*
    Default configuration directory path.
  */
  param CONFIG_DIR = "~/.config/remote-juggler";

  /*
    Default configuration file path.
  */
  param CONFIG_PATH = "~/.config/remote-juggler/config.json";

  /*
    Default state file path.
  */
  param STATE_PATH = "~/.config/remote-juggler/state.json";

  /*
    Managed block identifier for SSH hosts.
  */
  param MANAGED_BLOCK_SSH = "ssh-hosts";

  /*
    Managed block identifier for git URL rewrites.
  */
  param MANAGED_BLOCK_GIT = "gitconfig-rewrites";

  /*
    Configuration schema version.
  */
  param CONFIG_SCHEMA_VERSION = "2.0.0";

  // =========================================================================
  // Managed Block Types
  // =========================================================================

  /*
    Managed SSH hosts block.

    Auto-generated from ~/.ssh/config, not meant for manual editing.

    :var notice: Warning message about auto-generation
    :var lastSync: ISO timestamp of last sync
    :var hosts: Map of host alias to SSHHost record
  */
  record ManagedSSHBlock {
    var notice: string = "Auto-generated from ~/.ssh/config - DO NOT EDIT MANUALLY";
    var lastSync: string = "";
    var hosts: list(SSHHost);

    /*
      Initialize with default values.
    */
    proc init() {
      this.notice = "Auto-generated from ~/.ssh/config - DO NOT EDIT MANUALLY";
      this.lastSync = "";
      this.hosts = new list(SSHHost);
    }

    /*
      Initialize with hosts list.

      :arg hosts: List of SSH hosts
      :arg timestamp: Sync timestamp
    */
    proc init(hosts: list(SSHHost), timestamp: string = "") {
      this.notice = "Auto-generated from ~/.ssh/config - DO NOT EDIT MANUALLY";
      this.lastSync = if timestamp == "" then getCurrentTimestamp() else timestamp;
      this.hosts = hosts;
    }
  }

  /*
    Managed git URL rewrites block.

    Auto-generated from ~/.gitconfig URL sections.

    :var notice: Warning message about auto-generation
    :var lastSync: ISO timestamp of last sync
    :var rewrites: List of URL rewrite rules
  */
  record ManagedGitBlock {
    var notice: string = "Auto-generated from ~/.gitconfig - DO NOT EDIT MANUALLY";
    var lastSync: string = "";
    var rewrites: list(URLRewrite);

    /*
      Initialize with default values.
    */
    proc init() {
      this.notice = "Auto-generated from ~/.gitconfig - DO NOT EDIT MANUALLY";
      this.lastSync = "";
      this.rewrites = new list(URLRewrite);
    }

    /*
      Initialize with rewrites list.

      :arg rewrites: List of URL rewrites
      :arg timestamp: Sync timestamp
    */
    proc init(rewrites: list(URLRewrite), timestamp: string = "") {
      this.notice = "Auto-generated from ~/.gitconfig - DO NOT EDIT MANUALLY";
      this.lastSync = if timestamp == "" then getCurrentTimestamp() else timestamp;
      this.rewrites = rewrites;
    }
  }

  /*
    Application settings.

    User-configurable behavior options.

    :var defaultProvider: Default provider for new identities
    :var autoDetect: Enable automatic identity detection
    :var useKeychain: Enable Darwin Keychain integration
    :var gpgSign: Enable GPG signing on identity switch
    :var gpgVerifyWithProvider: Verify GPG keys with provider API
    :var fallbackToSSH: Allow SSH-only mode when no token
    :var verboseLogging: Enable verbose output
    :var defaultSecurityMode: Default security mode for new identities:
        - "maximum_security": PIN required for every operation
        - "developer_workflow": PIN cached for session (default)
        - "trusted_workstation": PIN stored in TPM/SecureEnclave
    :var hsmAvailable: Whether hardware security module is available (runtime detection)
    :var trustedWorkstationRequiresHSM: Require HSM for trusted_workstation mode
  */
  record AppSettings {
    var defaultProvider: Provider = Provider.GitLab;
    var autoDetect: bool = true;
    var useKeychain: bool = true;
    var gpgSign: bool = true;
    var gpgVerifyWithProvider: bool = true;
    var fallbackToSSH: bool = true;
    var verboseLogging: bool = false;
    var defaultSecurityMode: string = "developer_workflow";
    var hsmAvailable: bool = false;
    var trustedWorkstationRequiresHSM: bool = true;

    /*
      Initialize with default values.
    */
    proc init() {
      this.defaultProvider = Provider.GitLab;
      this.autoDetect = true;
      this.useKeychain = true;
      this.gpgSign = true;
      this.gpgVerifyWithProvider = true;
      this.fallbackToSSH = true;
      this.verboseLogging = false;
      this.defaultSecurityMode = "developer_workflow";
      this.hsmAvailable = false;
      this.trustedWorkstationRequiresHSM = true;
    }

    /*
      Validate security mode string.

      :arg mode: Security mode to validate
      :returns: true if mode is valid
    */
    proc isValidSecurityMode(mode: string): bool {
      return mode == "maximum_security" ||
             mode == "developer_workflow" ||
             mode == "trusted_workstation";
    }

    /*
      Check if trusted workstation mode is allowed.

      :returns: true if HSM not required or HSM is available
    */
    proc canUseTrustedWorkstation(): bool {
      return !trustedWorkstationRequiresHSM || hsmAvailable;
    }
  }

  // =========================================================================
  // Main Configuration Record
  // =========================================================================

  /*
    RemoteJuggler configuration.

    Main configuration record containing all settings and data.

    :var version: Configuration schema version
    :var generated: Timestamp when config was created/updated
    :var identities: Map of identity name to GitIdentity
    :var managedSSHHosts: Auto-synced SSH hosts
    :var managedGitRewrites: Auto-synced URL rewrites
    :var settings: Application settings
    :var state: Current switch context state
  */
  record RemoteJugglerConfig {
    var version: string = CONFIG_SCHEMA_VERSION;
    var generated: string = "";
    var identities: list(GitIdentity);
    var managedSSHHosts: ManagedSSHBlock;
    var managedGitRewrites: ManagedGitBlock;
    var settings: AppSettings;
    var state: SwitchContext;

    /*
      Initialize with default values.
    */
    proc init() {
      this.version = CONFIG_SCHEMA_VERSION;
      this.generated = getCurrentTimestamp();
      this.identities = new list(GitIdentity);
      this.managedSSHHosts = new ManagedSSHBlock();
      this.managedGitRewrites = new ManagedGitBlock();
      this.settings = new AppSettings();
      this.state = new SwitchContext();
    }

    /*
      Get identity by name.

      :arg name: Identity name to find
      :returns: GitIdentity if found, empty identity otherwise
    */
    proc getIdentity(name: string): GitIdentity {
      for identity in identities {
        if identity.name == name then return identity;
      }
      return new GitIdentity();
    }

    /*
      Check if identity exists.

      :arg name: Identity name to check
      :returns: true if identity exists
    */
    proc hasIdentity(name: string): bool {
      for identity in identities {
        if identity.name == name then return true;
      }
      return false;
    }

    /*
      Add or update an identity.

      :arg identity: Identity to add/update
    */
    proc ref addIdentity(identity: GitIdentity) {
      // Remove existing if present
      for i in 0..<identities.size {
        if identities[i].name == identity.name {
          identities.getAndRemove(i);
          break;
        }
      }
      identities.pushBack(identity);
    }

    /*
      Remove an identity by name.

      :arg name: Identity name to remove
      :returns: true if removed, false if not found
    */
    proc ref removeIdentity(name: string): bool {
      for i in 0..<identities.size {
        if identities[i].name == name {
          identities.getAndRemove(i);
          return true;
        }
      }
      return false;
    }

    /*
      Get list of identity names.

      :returns: List of identity name strings
    */
    proc getIdentityNames(): list(string) {
      var names: list(string);
      for identity in identities {
        names.pushBack(identity.name);
      }
      return names;
    }

    /*
      Find identities by provider.

      :arg provider: Provider to filter by
      :returns: List of matching identities
    */
    proc getIdentitiesByProvider(provider: Provider): list(GitIdentity) {
      var result: list(GitIdentity);
      for identity in identities {
        if identity.provider == provider {
          result.pushBack(identity);
        }
      }
      return result;
    }

    /*
      Find identity for SSH host alias.

      :arg hostAlias: SSH host alias
      :returns: Matching identity or empty identity
    */
    proc getIdentityByHost(hostAlias: string): GitIdentity {
      for identity in identities {
        if identity.host == hostAlias then return identity;
      }
      return new GitIdentity();
    }

    /*
      Find SSH host info from managed block.

      :arg hostAlias: SSH host alias
      :returns: SSHHost if found
    */
    proc getManagedSSHHost(hostAlias: string): SSHHost {
      for h in managedSSHHosts.hosts {
        if h.host == hostAlias then return h;
      }
      return new SSHHost();
    }

    /*
      Apply URL rewrites to a remote URL.

      :arg url: Original URL
      :returns: Rewritten URL (or original if no match)
    */
    proc rewriteRemoteURL(url: string): string {
      for rule in managedGitRewrites.rewrites {
        if rule.appliesTo(url) {
          return rule.apply(url);
        }
      }
      return url;
    }
  }

  // =========================================================================
  // Configuration File Operations
  // =========================================================================

  /*
    Get the effective configuration file path.

    Uses configPath config const if set, otherwise default.

    :returns: Expanded configuration file path
  */
  proc getConfigPath(): string {
    if configPath != "" {
      return expandTilde(configPath);
    }
    return expandTilde(CONFIG_PATH);
  }

  /*
    Get the configuration directory path.

    :returns: Expanded configuration directory path
  */
  proc getConfigDir(): string {
    return expandTilde(CONFIG_DIR);
  }

  /*
    Ensure configuration directory exists.

    Creates ~/.config/remote-juggler if it doesn't exist.

    :returns: true if directory exists or was created
  */
  proc ensureConfigDir(): bool {
    const dir = getConfigDir();
    try {
      if !exists(dir) {
        mkdir(dir, parents=true);
        verboseLog("Created config directory: ", dir);
      }
      return true;
    } catch e {
      verboseLog("Failed to create config directory: ", e.message());
      return false;
    }
  }

  /*
    Load configuration from file.

    Reads and parses the JSON configuration file. If the file doesn't
    exist or is invalid, returns a default configuration.

    :returns: RemoteJugglerConfig record

    Example::

      var cfg = loadConfig();
      for identity in cfg.identities {
        writeln(identity.name, ": ", identity.user);
      }
  */
  proc loadConfig(): RemoteJugglerConfig {
    var cfg = new RemoteJugglerConfig();
    const path = getConfigPath();

    verboseLog("Loading config from: ", path);

    if !exists(path) {
      verboseLog("Config file not found, using defaults");
      return cfg;
    }

    try {
      var f = open(path, ioMode.r);
      defer { try! f.close(); }
      var reader = f.reader(locking=false);
      defer { try! reader.close(); }

      // Read entire file content
      var content: string;
      reader.readAll(content);

      // Parse JSON content manually
      cfg = parseConfigJSON(content);

      verboseLog("Loaded ", cfg.identities.size, " identities");
    } catch e {
      verboseLog("Error loading config: ", e.message());
    }

    return cfg;
  }

  /*
    Save configuration to file.

    Serializes the configuration to JSON and writes to the config file.
    Creates the config directory if needed.

    :arg config: Configuration to save
    :returns: true if saved successfully

    Example::

      var cfg = loadConfig();
      cfg.addIdentity(newIdentity);
      saveConfig(cfg);
  */
  proc saveConfig(ref cfg: RemoteJugglerConfig): bool {
    if !ensureConfigDir() {
      return false;
    }

    const path = getConfigPath();
    cfg.generated = getCurrentTimestamp();

    verboseLog("Saving config to: ", path);

    try {
      var f = open(path, ioMode.cw);
      defer { try! f.close(); }
      var writer = f.writer(locking=false);
      defer { try! writer.close(); }

      // Generate JSON
      const json = serializeConfigJSON(cfg);
      writer.write(json);

      verboseLog("Config saved successfully");
      return true;
    } catch e {
      verboseLog("Error saving config: ", e.message());
      return false;
    }
  }

  // =========================================================================
  // Convenience Accessor Functions
  // =========================================================================

  /*
    Load just the identities list from config.
    Convenience function for CLI operations.

    :returns: List of configured identities
  */
  proc loadIdentities(): list(GitIdentity) {
    const cfg = loadConfig();
    return cfg.identities;
  }

  /*
    Load just the settings from config.

    :returns: Application settings
  */
  proc loadSettings(): AppSettings {
    const cfg = loadConfig();
    return cfg.settings;
  }

  /*
    Get managed SSH hosts list.

    :returns: List of SSH hosts from managed block
  */
  proc getManagedSSHHosts(): list(SSHHost) {
    const cfg = loadConfig();
    return cfg.managedSSHHosts.hosts;
  }

  /*
    Get managed git URL rewrites list.

    :returns: List of URL rewrite rules from managed block
  */
  proc getManagedGitRewrites(): list(URLRewrite) {
    const cfg = loadConfig();
    return cfg.managedGitRewrites.rewrites;
  }

  /*
    Get a specific identity by name.

    :arg name: Identity name to look up
    :returns: GitIdentity record (empty if not found)
  */
  proc getIdentity(name: string): GitIdentity {
    const cfg = loadConfig();
    for identity in cfg.identities {
      if identity.name == name {
        return identity;
      }
    }
    return new GitIdentity();
  }

  /*
    Remove an identity by name.

    :arg name: Identity name to remove
    :returns: true if removed, false if not found
  */
  proc removeIdentity(name: string): bool {
    var cfg = loadConfig();
    var found = false;
    var newIdentities = new list(GitIdentity);

    for identity in cfg.identities {
      if identity.name != name {
        newIdentities.pushBack(identity);
      } else {
        found = true;
      }
    }

    if found {
      cfg.identities = newIdentities;
      saveConfig(cfg);
    }
    return found;
  }

  /*
    Set the global security mode for GPG operations.

    :arg mode: Security mode to set (maximum_security, developer_workflow, trusted_workstation)
    :returns: true if mode was set successfully
  */
  proc setSecurityMode(mode: string): bool {
    var cfg = loadConfig();

    // Validate mode
    if !cfg.settings.isValidSecurityMode(mode) {
      return false;
    }

    cfg.settings.defaultSecurityMode = mode;
    return saveConfig(cfg);
  }

  /*
    Update HSM availability status in settings.

    :arg available: Whether HSM is available
    :returns: true if setting was updated
  */
  proc setHSMAvailability(available: bool): bool {
    var cfg = loadConfig();
    cfg.settings.hsmAvailable = available;
    return saveConfig(cfg);
  }

  // =========================================================================
  // Import and Initialize Functions
  // =========================================================================

  /*
    Result of SSH config import operation.
  */
  record ImportResult {
    var imported: int = 0;
    var skipped: int = 0;
    var names: list(string);

    proc init() {
      this.imported = 0;
      this.skipped = 0;
      this.names = new list(string);
    }
  }

  /*
    Import identities from SSH config.
    Adds new identities for git-related hosts.

    :returns: ImportResult with count of imported/skipped
  */
  proc importFromSSHConfig(): ImportResult {
    var result = new ImportResult();
    var cfg = loadConfig();

    try {
      const sshHosts = parseSSHConfig();

      for h in sshHosts {
        if h.isGitHost() {
          // Check if identity already exists
          var exists = false;
          for existing in cfg.identities {
            if existing.host == h.host {
              exists = true;
              result.skipped += 1;
              break;
            }
          }

          if !exists {
            var identity = new GitIdentity();
            identity.name = h.host;
            identity.provider = h.inferProvider();
            identity.host = h.host;
            identity.hostname = h.hostname;
            identity.sshKeyPath = h.identityFile;
            identity.user = if h.user == "git" then "" else h.user;

            cfg.identities.pushBack(identity);
            result.names.pushBack(h.host);
            result.imported += 1;
          }
        }
      }

      cfg.managedSSHHosts = new ManagedSSHBlock(sshHosts);
      saveConfig(cfg);
    } catch e {
      verboseLog("Error importing SSH config: ", e.message());
    }

    return result;
  }

  /*
    Initialize configuration from scratch.
    Creates default config and imports from SSH.

    :returns: true if successful
  */
  proc initializeConfig(): bool {
    var cfg = initConfig(importSSH=true);
    return saveConfig(cfg);
  }

  /*
    Initialize a new configuration.

    Creates a fresh configuration file with default settings.
    Optionally imports SSH hosts from ~/.ssh/config.

    :arg importSSH: Whether to import SSH hosts
    :returns: New RemoteJugglerConfig
  */
  proc initConfig(importSSH: bool = true): RemoteJugglerConfig {
    var cfg = new RemoteJugglerConfig();

    if importSSH {
      try {
        const sshHosts = parseSSHConfig();
        cfg.managedSSHHosts = new ManagedSSHBlock(sshHosts);

        // Auto-create identities for git hosts
        for h in sshHosts {
          if h.isGitHost() {
            var identity = new GitIdentity();
            identity.name = h.host;
            identity.provider = h.inferProvider();
            identity.host = h.host;
            identity.hostname = h.hostname;
            identity.sshKeyPath = h.identityFile;
            identity.user = if h.user == "git" then "" else h.user;
            cfg.addIdentity(identity);
          }
        }
      } catch e {
        verboseLog("Error importing SSH config: ", e.message());
      }
    }

    // Try to import git config rewrites
    try {
      const gitConfig = parseGitConfig();
      cfg.managedGitRewrites = new ManagedGitBlock(gitConfig.urlRewrites);
    } catch e {
      verboseLog("Error importing git config: ", e.message());
    }

    saveConfig(cfg);
    return cfg;
  }

  // =========================================================================
  // Managed Block Synchronization
  // =========================================================================

  /*
    Sync result record.

    Reports what was updated during a sync operation.

    :var sshHostsUpdated: Whether SSH hosts were changed
    :var gitRewritesUpdated: Whether URL rewrites were changed
    :var newSSHHostCount: Number of new SSH hosts found
    :var newRewriteCount: Number of new URL rewrites found
    :var timestamp: When sync was performed
  */
  record SyncResult {
    var sshHostsUpdated: bool = false;
    var gitRewritesUpdated: bool = false;
    var newSSHHostCount: int = 0;
    var newRewriteCount: int = 0;
    var timestamp: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.sshHostsUpdated = false;
      this.gitRewritesUpdated = false;
      this.newSSHHostCount = 0;
      this.newRewriteCount = 0;
      this.timestamp = getCurrentTimestamp();
    }

    /*
      Check if any changes were made.

      :returns: true if anything was updated
    */
    proc hasChanges(): bool {
      return sshHostsUpdated || gitRewritesUpdated;
    }
  }

  /*
    Synchronize managed blocks from system config files.

    Re-parses ~/.ssh/config and ~/.gitconfig and updates the
    managed blocks in the configuration. User-defined identities
    are preserved.

    :returns: SyncResult indicating what changed

    Example::

      var result = syncManagedBlocks();
      if result.hasChanges() {
        writeln("Updated at ", result.timestamp);
        if result.sshHostsUpdated {
          writeln("  SSH hosts refreshed");
        }
      }
  */
  proc syncManagedBlocks(): SyncResult {
    var result = new SyncResult();
    var cfg = loadConfig();

    verboseLog("Syncing managed blocks...");

    // Sync SSH hosts
    try {
      const sshHosts = parseSSHConfig();
      const oldCount = cfg.managedSSHHosts.hosts.size;

      // Check if SSH hosts changed
      var changed = sshHosts.size != oldCount;
      if !changed {
        // Deep comparison would go here
        // For now, always update to be safe
        changed = true;
      }

      if changed {
        cfg.managedSSHHosts = new ManagedSSHBlock(sshHosts, result.timestamp);
        result.sshHostsUpdated = true;
        result.newSSHHostCount = sshHosts.size;
        verboseLog("  SSH hosts updated: ", sshHosts.size, " hosts");
      }
    } catch e {
      verboseLog("  Error syncing SSH config: ", e.message());
    }

    // Sync git URL rewrites
    try {
      const gitConfig = parseGitConfig();
      const oldCount = cfg.managedGitRewrites.rewrites.size;

      var changed = gitConfig.urlRewrites.size != oldCount;
      if !changed {
        changed = true;  // Safe default
      }

      if changed {
        cfg.managedGitRewrites = new ManagedGitBlock(gitConfig.urlRewrites,
                                                        result.timestamp);
        result.gitRewritesUpdated = true;
        result.newRewriteCount = gitConfig.urlRewrites.size;
        verboseLog("  URL rewrites updated: ", gitConfig.urlRewrites.size, " rules");
      }
    } catch e {
      verboseLog("  Error syncing git config: ", e.message());
    }

    // Save updated config
    if result.hasChanges() {
      saveConfig(cfg);
    }

    return result;
  }

  /*
    Validation result record.

    Reports issues found during config validation.

    :var valid: Whether configuration is valid
    :var issues: List of issue descriptions
    :var warnings: List of warning messages
  */
  record ConfigValidationResult {
    var valid: bool = true;
    var issues: list(string);
    var warnings: list(string);

    /*
      Initialize with default values.
    */
    proc init() {
      this.valid = true;
      this.issues = new list(string);
      this.warnings = new list(string);
    }

    /*
      Add an issue (makes config invalid).

      :arg issue: Issue description
    */
    proc ref addIssue(issue: string) {
      issues.pushBack(issue);
      valid = false;
    }

    /*
      Add a warning (doesn't invalidate config).

      :arg warning: Warning message
    */
    proc ref addWarning(warning: string) {
      warnings.pushBack(warning);
    }
  }

  /*
    Validate managed blocks against source files.

    Checks if managed blocks are in sync with system configs
    and reports any discrepancies or potential issues.

    :returns: ConfigValidationResult with any issues found
  */
  proc validateManagedBlocks(): ConfigValidationResult {
    var result = new ConfigValidationResult();
    const cfg = loadConfig();

    verboseLog("Validating managed blocks...");

    // Validate SSH hosts
    try {
      const currentSSH = parseSSHConfig();
      const managedCount = cfg.managedSSHHosts.hosts.size;
      const currentCount = currentSSH.size;

      if currentCount != managedCount {
        result.addWarning("SSH hosts out of sync: " +
                         managedCount:string + " managed vs " +
                         currentCount:string + " current. Run 'config sync'.");
      }

      // Check for orphaned identities (host no longer in SSH config)
      for identity in cfg.identities {
        var found = false;
        for h in currentSSH {
          if h.host == identity.host {
            found = true;
            break;
          }
        }
        if !found && identity.host != "" && identity.host != identity.hostname {
          result.addWarning("Identity '" + identity.name +
                           "' references unknown SSH host: " + identity.host);
        }
      }
    } catch e {
      result.addWarning("Could not read SSH config: " + e.message());
    }

    // Validate git config
    try {
      const currentGit = parseGitConfig();
      const managedCount = cfg.managedGitRewrites.rewrites.size;
      const currentCount = currentGit.urlRewrites.size;

      if currentCount != managedCount {
        result.addWarning("URL rewrites out of sync: " +
                         managedCount:string + " managed vs " +
                         currentCount:string + " current. Run 'config sync'.");
      }
    } catch e {
      result.addWarning("Could not read git config: " + e.message());
    }

    // Validate identities
    for identity in cfg.identities {
      if !identity.isValid() {
        result.addIssue("Invalid identity: '" + identity.name +
                       "' missing required fields");
      }

      // Check SSH key exists
      if identity.sshKeyPath != "" {
        const keyPath = expandTilde(identity.sshKeyPath);
        if !exists(keyPath) {
          result.addWarning("SSH key not found for '" + identity.name +
                           "': " + keyPath);
        }
      }
    }

    return result;
  }

  // =========================================================================
  // JSON Serialization Helpers
  // =========================================================================

  /*
    Parse configuration from JSON string.

    Basic JSON parser for config file format.

    :arg json: JSON string
    :returns: Parsed RemoteJugglerConfig
  */
  proc parseConfigJSON(json: string): RemoteJugglerConfig {
    var cfg = new RemoteJugglerConfig();

    // Simple JSON parsing - extract key sections
    // In production, would use Chapel's JSON module

    // Extract version
    cfg.version = extractJSONString(json, "version", CONFIG_SCHEMA_VERSION);
    cfg.generated = extractJSONString(json, "generated", "");

    // Extract identities array
    const identitiesSection = extractJSONSection(json, "identities");
    if identitiesSection != "" {
      cfg.identities = parseIdentitiesJSON(identitiesSection);
    }

    // Extract settings
    const settingsSection = extractJSONSection(json, "settings");
    if settingsSection != "" {
      cfg.settings = parseSettingsJSON(settingsSection);
    }

    // Extract state
    const stateSection = extractJSONSection(json, "state");
    if stateSection != "" {
      cfg.state = parseStateJSON(stateSection);
    }

    // Extract managed SSH hosts
    const sshSection = extractJSONSection(json, "_managed_ssh_hosts");
    if sshSection != "" {
      cfg.managedSSHHosts = parseSSHBlockJSON(sshSection);
    }

    // Extract managed git rewrites
    const gitSection = extractJSONSection(json, "_managed_gitconfig_rewrites");
    if gitSection != "" {
      cfg.managedGitRewrites = parseGitBlockJSON(gitSection);
    }

    return cfg;
  }

  /*
    Serialize configuration to JSON string.

    :arg config: Configuration to serialize
    :returns: JSON string representation
  */
  proc serializeConfigJSON(cfg: RemoteJugglerConfig): string {
    var json = "{\n";
    json += '  "$schema": "https://remote-juggler.dev/schema/v2.json",\n';
    json += '  "version": "' + cfg.version + '",\n';
    json += '  "generated": "' + cfg.generated + '",\n';
    json += '\n';

    // Identities
    json += '  "identities": {\n';
    var first = true;
    for identity in cfg.identities {
      if !first then json += ",\n";
      first = false;
      json += serializeIdentityJSON(identity, "    ");
    }
    json += '\n  },\n';
    json += '\n';

    // Managed SSH block
    json += '  "/* BEGIN MANAGED BLOCK: ' + MANAGED_BLOCK_SSH + ' */": null,\n';
    json += '  "_managed_ssh_hosts": {\n';
    json += '    "_notice": "' + cfg.managedSSHHosts.notice + '",\n';
    json += '    "_lastSync": "' + cfg.managedSSHHosts.lastSync + '",\n';
    json += '    "hosts": {\n';
    first = true;
    for h in cfg.managedSSHHosts.hosts {
      if !first then json += ",\n";
      first = false;
      json += serializeSSHHostJSON(h, "      ");
    }
    json += '\n    }\n';
    json += '  },\n';
    json += '  "/* END MANAGED BLOCK: ' + MANAGED_BLOCK_SSH + ' */": null,\n';
    json += '\n';

    // Managed git block
    json += '  "/* BEGIN MANAGED BLOCK: ' + MANAGED_BLOCK_GIT + ' */": null,\n';
    json += '  "_managed_gitconfig_rewrites": {\n';
    json += '    "_notice": "' + cfg.managedGitRewrites.notice + '",\n';
    json += '    "_lastSync": "' + cfg.managedGitRewrites.lastSync + '",\n';
    json += '    "rewrites": [\n';
    first = true;
    for rule in cfg.managedGitRewrites.rewrites {
      if !first then json += ",\n";
      first = false;
      json += '      {"from": "' + escapeJSON(rule.fromURL) +
              '", "to": "' + escapeJSON(rule.toURL) + '"}';
    }
    json += '\n    ]\n';
    json += '  },\n';
    json += '  "/* END MANAGED BLOCK: ' + MANAGED_BLOCK_GIT + ' */": null,\n';
    json += '\n';

    // Settings
    json += '  "settings": {\n';
    json += '    "defaultProvider": "' + providerToString(cfg.settings.defaultProvider) + '",\n';
    json += '    "autoDetect": ' + cfg.settings.autoDetect:string + ',\n';
    json += '    "useKeychain": ' + cfg.settings.useKeychain:string + ',\n';
    json += '    "gpgSign": ' + cfg.settings.gpgSign:string + ',\n';
    json += '    "gpgVerifyWithProvider": ' + cfg.settings.gpgVerifyWithProvider:string + ',\n';
    json += '    "fallbackToSSH": ' + cfg.settings.fallbackToSSH:string + ',\n';
    json += '    "verboseLogging": ' + cfg.settings.verboseLogging:string + ',\n';
    json += '    "defaultSecurityMode": "' + cfg.settings.defaultSecurityMode + '",\n';
    json += '    "hsmAvailable": ' + cfg.settings.hsmAvailable:string + ',\n';
    json += '    "trustedWorkstationRequiresHSM": ' + cfg.settings.trustedWorkstationRequiresHSM:string + '\n';
    json += '  },\n';
    json += '\n';

    // State
    json += '  "state": {\n';
    json += '    "currentIdentity": "' + escapeJSON(cfg.state.currentIdentity) + '",\n';
    json += '    "lastSwitch": "' + cfg.state.lastSwitch + '"\n';
    json += '  }\n';

    json += "}\n";
    return json;
  }

  /*
    Serialize a single identity to JSON.

    :arg identity: Identity to serialize
    :arg indent: Indentation prefix
    :returns: JSON fragment
  */
  proc serializeIdentityJSON(identity: GitIdentity, indent: string): string {
    var json = indent + '"' + escapeJSON(identity.name) + '": {\n';
    json += indent + '  "provider": "' + providerToString(identity.provider) + '",\n';
    json += indent + '  "host": "' + escapeJSON(identity.host) + '",\n';
    json += indent + '  "hostname": "' + escapeJSON(identity.hostname) + '",\n';
    json += indent + '  "user": "' + escapeJSON(identity.user) + '",\n';
    json += indent + '  "email": "' + escapeJSON(identity.email) + '",\n';
    json += indent + '  "sshKeyPath": "' + escapeJSON(identity.sshKeyPath) + '",\n';
    json += indent + '  "credentialSource": "' + credentialSourceToString(identity.credentialSource) + '",\n';

    if identity.tokenEnvVar != "" {
      json += indent + '  "tokenEnvVar": "' + escapeJSON(identity.tokenEnvVar) + '",\n';
    }
    if identity.keychainService != "" {
      json += indent + '  "keychainService": "' + escapeJSON(identity.keychainService) + '",\n';
    }

    // Organizations array
    json += indent + '  "organizations": [';
    var first = true;
    for org in identity.organizations {
      if !first then json += ", ";
      first = false;
      json += '"' + escapeJSON(org) + '"';
    }
    json += '],\n';

    // GPG config
    json += indent + '  "gpg": {\n';
    json += indent + '    "keyId": "' + escapeJSON(identity.gpg.keyId) + '",\n';
    json += indent + '    "signCommits": ' + identity.gpg.signCommits:string + ',\n';
    json += indent + '    "signTags": ' + identity.gpg.signTags:string + ',\n';
    json += indent + '    "autoSignoff": ' + identity.gpg.autoSignoff:string + ',\n';
    json += indent + '    "hardwareKey": ' + identity.gpg.hardwareKey:string + ',\n';
    json += indent + '    "touchPolicy": "' + escapeJSON(identity.gpg.touchPolicy) + '",\n';
    json += indent + '    "securityMode": "' + escapeJSON(identity.gpg.securityMode) + '",\n';
    json += indent + '    "pinStorageMethod": "' + escapeJSON(identity.gpg.pinStorageMethod) + '"\n';
    json += indent + '  }\n';

    json += indent + '}';
    return json;
  }

  /*
    Serialize SSH host to JSON.

    :arg host: SSH host to serialize
    :arg indent: Indentation prefix
    :returns: JSON fragment
  */
  proc serializeSSHHostJSON(host: SSHHost, indent: string): string {
    var json = indent + '"' + escapeJSON(host.host) + '": {\n';
    json += indent + '  "hostname": "' + escapeJSON(host.hostname) + '",\n';
    json += indent + '  "identityFile": "' + escapeJSON(host.identityFile) + '",\n';
    json += indent + '  "user": "' + escapeJSON(host.user) + '"';
    if host.port != 22 {
      json += ',\n' + indent + '  "port": ' + host.port:string;
    }
    if host.identitiesOnly {
      json += ',\n' + indent + '  "identitiesOnly": true';
    }
    json += '\n' + indent + '}';
    return json;
  }

  // =========================================================================
  // JSON Parsing Helpers
  // =========================================================================

  /*
    Extract a string value from JSON.

    :arg json: JSON string
    :arg key: Key to find
    :arg defaultVal: Default if not found
    :returns: Extracted value
  */
  proc extractJSONString(json: string, key: string, defaultVal: string): string {
    const pattern = '"' + key + '": "';
    const start = json.find(pattern);
    if start < 0 then return defaultVal;

    const valueStart = start + pattern.size;
    const valueEnd = json.find('"', valueStart..);
    if valueEnd < 0 then return defaultVal;

    return json[valueStart..<valueEnd];
  }

  /*
    Extract a JSON object section.

    :arg json: JSON string
    :arg key: Section key
    :returns: Content between braces, or empty string
  */
  proc extractJSONSection(json: string, key: string): string {
    const pattern = '"' + key + '":';
    const start = json.find(pattern);
    if start < 0 then return "";

    // Find opening brace
    var pos = start + pattern.size;
    while pos < json.size && json[pos] != '{' && json[pos] != '[' {
      pos += 1;
    }
    if pos >= json.size then return "";

    const openChar = json[pos];
    const closeChar = if openChar == '{' then '}' else ']';

    // Find matching close
    var depth = 1;
    var endPos = pos + 1;
    while endPos < json.size && depth > 0 {
      if json[endPos] == openChar then depth += 1;
      else if json[endPos] == closeChar then depth -= 1;
      endPos += 1;
    }

    if depth == 0 {
      return json[pos..<endPos];
    }
    return "";
  }

  /*
    Parse identities from JSON object.

    :arg json: JSON object string
    :returns: List of parsed identities
  */
  proc parseIdentitiesJSON(json: string): list(GitIdentity) {
    var identities: list(GitIdentity);

    // Parse JSON object where keys are identity names
    // Format: { "identity-name": { "provider": "...", ... }, ... }

    // Skip opening brace and whitespace
    var pos = 0;
    while pos < json.size && (json[pos] == '{' || json[pos] == ' ' ||
                               json[pos] == '\n' || json[pos] == '\t') {
      pos += 1;
    }

    while pos < json.size {
      // Skip whitespace
      while pos < json.size && (json[pos] == ' ' || json[pos] == '\n' ||
                                 json[pos] == '\t' || json[pos] == ',') {
        pos += 1;
      }

      // Check for end of object
      if pos >= json.size || json[pos] == '}' then break;

      // Expect opening quote for key
      if json[pos] != '"' then break;
      pos += 1;

      // Extract identity name (key)
      var nameEnd = pos;
      while nameEnd < json.size && json[nameEnd] != '"' {
        nameEnd += 1;
      }
      if nameEnd >= json.size then break;

      const identityName = json[pos..<nameEnd];
      pos = nameEnd + 1;

      // Skip colon and whitespace to find opening brace
      while pos < json.size && json[pos] != '{' {
        pos += 1;
      }
      if pos >= json.size then break;

      // Find matching closing brace for this identity object
      var depth = 1;
      var objStart = pos;
      pos += 1;
      while pos < json.size && depth > 0 {
        if json[pos] == '{' then depth += 1;
        else if json[pos] == '}' then depth -= 1;
        pos += 1;
      }

      // Extract the identity object JSON
      const identityJSON = json[objStart..<pos];

      // Parse identity fields
      const provider = extractJSONString(identityJSON, "provider", "custom");
      const host = extractJSONString(identityJSON, "host", "");
      const hostname = extractJSONString(identityJSON, "hostname", "");
      const user = extractJSONString(identityJSON, "user", "");
      const email = extractJSONString(identityJSON, "email", "");
      const sshKeyPath = extractJSONString(identityJSON, "sshKeyPath", "");

      // Parse GPG section if present
      const gpgSection = extractJSONSection(identityJSON, "gpg");
      var gpgConfig = new GPGConfig();
      if gpgSection != "" {
        gpgConfig.keyId = extractJSONString(gpgSection, "keyId", "");
        gpgConfig.format = extractJSONString(gpgSection, "format", "gpg");

        const signCommits = extractJSONString(gpgSection, "signCommits", "false");
        gpgConfig.signCommits = signCommits == "true";

        const signTags = extractJSONString(gpgSection, "signTags", "false");
        gpgConfig.signTags = signTags == "true";

        const autoSignoff = extractJSONString(gpgSection, "autoSignoff", "false");
        gpgConfig.autoSignoff = autoSignoff == "true";

        const hardwareKey = extractJSONString(gpgSection, "hardwareKey", "false");
        gpgConfig.hardwareKey = hardwareKey == "true";

        gpgConfig.touchPolicy = extractJSONString(gpgSection, "touchPolicy", "");

        // New security mode fields
        gpgConfig.securityMode = extractJSONString(gpgSection, "securityMode", "developer_workflow");
        gpgConfig.pinStorageMethod = extractJSONString(gpgSection, "pinStorageMethod", "");
      }

      // Create identity with parsed values
      var identity = new GitIdentity(
        identityName,
        stringToProvider(provider),
        host,
        hostname,
        user,
        email
      );
      identity.sshKeyPath = sshKeyPath;
      identity.gpg = gpgConfig;

      // Only add valid identities (must have name, host, user)
      if identity.isValid() {
        identities.pushBack(identity);
      }
    }

    return identities;
  }

  /*
    Parse settings from JSON object.

    :arg json: JSON object string
    :returns: Parsed AppSettings
  */
  proc parseSettingsJSON(json: string): AppSettings {
    var settings = new AppSettings();
    // Extract boolean/string fields
    const autoDetect = extractJSONString(json, "autoDetect", "true");
    settings.autoDetect = autoDetect == "true";

    const useKeychain = extractJSONString(json, "useKeychain", "true");
    settings.useKeychain = useKeychain == "true";

    const gpgSign = extractJSONString(json, "gpgSign", "true");
    settings.gpgSign = gpgSign == "true";

    return settings;
  }

  /*
    Parse state from JSON object.

    :arg json: JSON object string
    :returns: Parsed SwitchContext
  */
  proc parseStateJSON(json: string): SwitchContext {
    var state = new SwitchContext();
    state.currentIdentity = extractJSONString(json, "currentIdentity", "");
    state.lastSwitch = extractJSONString(json, "lastSwitch", "");
    return state;
  }

  /*
    Parse managed SSH block from JSON.

    :arg json: JSON object string
    :returns: Parsed ManagedSSHBlock
  */
  proc parseSSHBlockJSON(json: string): ManagedSSHBlock {
    var block = new ManagedSSHBlock();
    block.lastSync = extractJSONString(json, "_lastSync", "");
    // Host parsing would be more complex
    return block;
  }

  /*
    Parse managed git block from JSON.

    :arg json: JSON object string
    :returns: Parsed ManagedGitBlock
  */
  proc parseGitBlockJSON(json: string): ManagedGitBlock {
    var block = new ManagedGitBlock();
    block.lastSync = extractJSONString(json, "_lastSync", "");
    // Rewrite parsing would be more complex
    return block;
  }

  /*
    Escape special characters for JSON string.

    :arg s: String to escape
    :returns: JSON-safe string
  */
  proc escapeJSON(s: string): string {
    var result = "";
    for ch in s {
      select ch {
        when '"' do result += '\\"';
        when '\\' do result += "\\\\";
        when '\n' do result += "\\n";
        when '\r' do result += "\\r";
        when '\t' do result += "\\t";
        otherwise do result += ch;
      }
    }
    return result;
  }

  // =========================================================================
  // Utility Functions
  // =========================================================================

  /*
    Get current timestamp in ISO 8601 format.

    :returns: Timestamp string (e.g., "2026-01-15T10:30:00Z")
  */
  proc getCurrentTimestamp(): string {
    try {
      const now = dateTime.now();
      // Manual ISO 8601 formatting
      return "%04i-%02i-%02iT%02i:%02i:%02iZ".format(
        now.year, now.month:int, now.day,
        now.hour, now.minute, now.second
      );
    } catch {
      return "";
    }
  }

  /*
    Check if a file exists.

    :arg path: File path to check
    :returns: true if file exists
  */
  proc exists(path: string): bool {
    try {
      return FileSystem.exists(path);
    } catch {
      return false;
    }
  }

  /*
    Create directory with parents.

    :arg path: Directory path to create
    :arg parents: Create parent directories if needed
  */
  proc mkdir(path: string, parents: bool = false) throws {
    if parents {
      FileSystem.mkdir(path, parents=true);
    } else {
      FileSystem.mkdir(path);
    }
  }
}
