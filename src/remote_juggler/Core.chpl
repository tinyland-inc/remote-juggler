/*
  Core Module
  ===========

  Core types, constants, and configuration for RemoteJuggler.

  This module defines the fundamental data structures and compile-time
  configuration used throughout the RemoteJuggler system for git identity
  management across multiple providers (GitLab, GitHub, Bitbucket, etc.).

  **Configuration Constants:**

  All ``config const`` declarations can be overridden via command-line:

    ./remote-juggler --mode=mcp --verbose=true --configPath=/custom/path

  **Core Types:**

  - :type:`Provider` - Enumeration of supported git providers
  - :type:`CredentialSource` - How credentials are obtained
  - :record:`GPGConfig` - GPG signing configuration per identity
  - :record:`GitIdentity` - Complete identity definition
  - :record:`SwitchContext` - Current state tracking
  - :record:`ToolResult` - Operation result wrapper

  :author: RemoteJuggler Team
  :version: 2.0.0
  :license: MIT
*/
prototype module Core {
  use List;
  use IO;

  // =========================================================================
  // Configuration Constants (CLI-configurable)
  // =========================================================================

  /*
    Operational mode for RemoteJuggler.

    - ``cli`` - Interactive command-line interface (default)
    - ``mcp`` - Model Context Protocol STDIO server
    - ``acp`` - Agent Client Protocol STDIO server
  */
  config const mode: string = "cli";

  /*
    Enable verbose logging output.

    When true, displays detailed information about operations,
    credential resolution, and SSH config parsing.
  */
  config const verbose: bool = false;

  /*
    Override path to configuration file.

    If empty, uses default path: ``~/.config/remote-juggler/config.json``
  */
  config const configPath: string = "";

  /*
    Enable Darwin Keychain integration for credential storage.

    Only effective on macOS. When true, RemoteJuggler will attempt
    to store and retrieve tokens from the system keychain.
  */
  config const useKeychain: bool = true;

  /*
    Enable GPG signing configuration on identity switch.

    When true, switching identities will configure git's GPG
    signing settings (user.signingkey, commit.gpgsign) based
    on the target identity's GPG configuration.
  */
  config const gpgSign: bool = true;

  /*
    Display help message and exit.
  */
  config const help: bool = false;

  /*
    Filter identities by provider (for list command).

    Use "all" to show all providers, or specify a provider name
    like "gitlab", "github", "bitbucket", etc.
  */
  config const provider: string = "all";

  // =========================================================================
  // Version Information (compile-time params)
  // =========================================================================

  /*
    Full semantic version string.
  */
  param VERSION = "2.0.0";

  /*
    Major version number (breaking changes).
  */
  param VERSION_MAJOR = 2;

  /*
    Minor version number (new features, backward compatible).
  */
  param VERSION_MINOR = 0;

  /*
    Patch version number (bug fixes).
  */
  param VERSION_PATCH = 0;

  /*
    Project name for display and identification.
  */
  param PROJECT_NAME = "RemoteJuggler";

  /*
    Protocol version for MCP/ACP servers.
  */
  param PROTOCOL_VERSION = "2025-11-25";

  // =========================================================================
  // Enumerations
  // =========================================================================

  /*
    Git upstream provider types.

    First-class support is provided for major git hosting platforms.
    Use ``Custom`` for self-hosted git servers or other providers.

    - ``GitLab`` - GitLab.com and self-hosted GitLab instances
    - ``GitHub`` - GitHub.com and GitHub Enterprise
    - ``Bitbucket`` - Atlassian Bitbucket Cloud and Server
    - ``Custom`` - Any other git server (e.g., src.bates.edu)
  */
  enum Provider {
    GitLab,
    GitHub,
    Bitbucket,
    Custom
  }

  /*
    Credential source for authentication.

    Defines how RemoteJuggler obtains tokens for provider CLIs.
    Sources are tried in priority order: Keychain -> Environment -> CLIAuth -> None

    - ``Keychain`` - macOS Keychain (Darwin only, preferred)
    - ``Environment`` - Environment variable (e.g., GITLAB_TOKEN)
    - ``CLIAuth`` - Provider CLI stored auth (glab/gh auth token)
    - ``None`` - SSH-only mode, no token required
  */
  enum CredentialSource {
    Keychain,
    Environment,
    CLIAuth,
    None
  }

  /*
    Authentication mode after credential resolution.

    Indicates the result of the authentication process.

    - ``SSHOnly`` - No token, using SSH key authentication only
    - ``KeychainAuth`` - Token retrieved from system keychain
    - ``CLIAuthenticated`` - Token authenticated via provider CLI
    - ``TokenOnly`` - Token available but CLI not installed
    - ``Failed`` - Authentication failed
  */
  enum AuthMode {
    SSHOnly,
    KeychainAuth,
    CLIAuthenticated,
    TokenOnly,
    Failed
  }

  // =========================================================================
  // Records (Value Types)
  // =========================================================================

  /*
    GPG signing configuration for an identity.

    Configures how commits and tags are signed when using a
    particular git identity.

    :var keyId: GPG key ID or "auto" to detect from email
    :var signCommits: Enable automatic commit signing (git commit -S)
    :var signTags: Enable automatic tag signing (git tag -s)
    :var autoSignoff: Add Signed-off-by trailer to commits
  */
  record GPGConfig {
    var keyId: string = "";
    var signCommits: bool = false;
    var signTags: bool = false;
    var autoSignoff: bool = false;

    /*
      Initialize with default values.
    */
    proc init() {
      this.keyId = "";
      this.signCommits = false;
      this.signTags = false;
      this.autoSignoff = false;
    }

    /*
      Initialize with all values specified.

      :arg keyId: GPG key ID or "auto"
      :arg signCommits: Enable commit signing
      :arg signTags: Enable tag signing
      :arg autoSignoff: Enable Signed-off-by
    */
    proc init(keyId: string, signCommits: bool = false,
              signTags: bool = false, autoSignoff: bool = false) {
      this.keyId = keyId;
      this.signCommits = signCommits;
      this.signTags = signTags;
      this.autoSignoff = autoSignoff;
    }

    /*
      Check if GPG signing is configured.

      :returns: true if a key ID is specified
    */
    proc isConfigured(): bool {
      return keyId != "";
    }

    /*
      Check if key should be auto-detected from email.

      :returns: true if keyId is "auto"
    */
    proc isAutoDetect(): bool {
      return keyId == "auto";
    }
  }

  /*
    Git identity record.

    Complete definition of a git identity including SSH configuration,
    credential source, organization associations, and GPG settings.

    This is the primary data structure for identity management.

    :var name: Unique identity name (e.g., "personal", "work")
    :var provider: Git provider type
    :var host: SSH host alias from ~/.ssh/config
    :var hostname: Actual hostname (e.g., gitlab.com, github.com)
    :var user: Git username for this identity
    :var email: Git email for this identity
    :var sshKeyPath: Path to SSH private key
    :var credentialSource: How to obtain API token
    :var tokenEnvVar: Environment variable name (if source=Environment)
    :var keychainService: Keychain service name (if source=Keychain)
    :var organizations: Associated organization/group paths
    :var gpg: GPG signing configuration
  */
  record GitIdentity {
    var name: string = "";
    var provider: Provider = Provider.Custom;
    var host: string = "";
    var hostname: string = "";
    var user: string = "";
    var email: string = "";
    var sshKeyPath: string = "";
    var credentialSource: CredentialSource = CredentialSource.None;
    var tokenEnvVar: string = "";
    var keychainService: string = "";
    var organizations: list(string);
    var gpg: GPGConfig;

    /*
      Initialize with default values.
    */
    proc init() {
      this.name = "";
      this.provider = Provider.Custom;
      this.host = "";
      this.hostname = "";
      this.user = "";
      this.email = "";
      this.sshKeyPath = "";
      this.credentialSource = CredentialSource.None;
      this.tokenEnvVar = "";
      this.keychainService = "";
      this.organizations = new list(string);
      this.gpg = new GPGConfig();
    }

    /*
      Initialize with essential fields.

      :arg name: Identity name
      :arg provider: Git provider
      :arg host: SSH host alias
      :arg hostname: Actual hostname
      :arg user: Git username
      :arg email: Git email
    */
    proc init(name: string, provider: Provider, host: string,
              hostname: string, user: string, email: string) {
      this.name = name;
      this.provider = provider;
      this.host = host;
      this.hostname = hostname;
      this.user = user;
      this.email = email;
      this.sshKeyPath = "";
      this.credentialSource = CredentialSource.None;
      this.tokenEnvVar = "";
      this.keychainService = "";
      this.organizations = new list(string);
      this.gpg = new GPGConfig();
    }

    /*
      Check if identity has minimal required configuration.

      :returns: true if name, host, and user are set
    */
    proc isValid(): bool {
      return name != "" && host != "" && user != "";
    }

    /*
      Get the keychain service name for this identity.

      Format: ``remote-juggler.{provider}.{name}``

      :returns: Keychain service name
    */
    proc getKeychainService(): string {
      if keychainService != "" then return keychainService;
      return "remote-juggler." + providerToString(provider) + "." + name;
    }

    /*
      Check if this identity matches an organization path.

      :arg orgPath: Organization or group path to check
      :returns: true if orgPath is in organizations list
    */
    proc matchesOrganization(orgPath: string): bool {
      for org in organizations {
        if orgPath.startsWith(org) then return true;
      }
      return false;
    }
  }

  /*
    Switch context state.

    Tracks the current identity state and last switch operation.
    Persisted to state file for session continuity.

    :var currentIdentity: Name of currently active identity
    :var lastSwitch: ISO 8601 timestamp of last switch
    :var repoPath: Path to repository where switch was performed
    :var gpgKeyActive: Currently active GPG key ID (if any)
  */
  record SwitchContext {
    var currentIdentity: string = "";
    var lastSwitch: string = "";
    var repoPath: string = "";
    var gpgKeyActive: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.currentIdentity = "";
      this.lastSwitch = "";
      this.repoPath = "";
      this.gpgKeyActive = "";
    }

    /*
      Initialize with all values.

      :arg currentIdentity: Active identity name
      :arg lastSwitch: ISO timestamp
      :arg repoPath: Repository path
      :arg gpgKeyActive: Active GPG key
    */
    proc init(currentIdentity: string, lastSwitch: string = "",
              repoPath: string = "", gpgKeyActive: string = "") {
      this.currentIdentity = currentIdentity;
      this.lastSwitch = lastSwitch;
      this.repoPath = repoPath;
      this.gpgKeyActive = gpgKeyActive;
    }

    /*
      Check if a context is active.

      :returns: true if currentIdentity is set
    */
    proc hasActiveIdentity(): bool {
      return currentIdentity != "";
    }
  }

  /*
    Tool operation result.

    Generic result wrapper for operations that may succeed or fail.
    Used by MCP/ACP tool handlers and CLI commands.

    :var success: Whether operation succeeded
    :var message: Human-readable status message
    :var data: JSON payload with detailed result data
    :var errorCode: Error code (0 for success)
  */
  record ToolResult {
    var success: bool = false;
    var message: string = "";
    var data: string = "";
    var errorCode: int = 0;

    /*
      Initialize with default values (failure state).
    */
    proc init() {
      this.success = false;
      this.message = "";
      this.data = "";
      this.errorCode = 0;
    }

    /*
      Initialize a success result.

      :arg message: Success message
      :arg data: JSON payload
    */
    proc init(message: string, data: string = "") {
      this.success = true;
      this.message = message;
      this.data = data;
      this.errorCode = 0;
    }

    /*
      Initialize with explicit success flag.

      :arg success: Whether operation succeeded
      :arg message: Status message
      :arg data: JSON payload
      :arg errorCode: Error code
    */
    proc init(success: bool, message: string, data: string = "",
              errorCode: int = 0) {
      this.success = success;
      this.message = message;
      this.data = data;
      this.errorCode = errorCode;
    }
  }

  /*
    Authentication result.

    Result of credential resolution and provider authentication.

    :var success: Whether authentication succeeded
    :var mode: Authentication mode achieved
    :var message: Status message
    :var token: The resolved token (if any)
  */
  record AuthResult {
    var success: bool = false;
    var mode: AuthMode = AuthMode.Failed;
    var message: string = "";
    var token: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.success = false;
      this.mode = AuthMode.Failed;
      this.message = "";
      this.token = "";
    }

    /*
      Initialize with all values.

      :arg success: Whether authentication succeeded
      :arg mode: Authentication mode
      :arg message: Status message
    */
    proc init(success: bool, mode: AuthMode, message: string) {
      this.success = success;
      this.mode = mode;
      this.message = message;
      this.token = "";
    }
  }

  /*
    GPG verification result.

    Result of verifying GPG key registration with a provider.

    :var verified: Whether key is registered with provider
    :var message: Status message or error
    :var settingsURL: URL to provider's GPG key settings
  */
  record GPGVerifyResult {
    var verified: bool = false;
    var message: string = "";
    var settingsURL: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.verified = false;
      this.message = "";
      this.settingsURL = "";
    }

    /*
      Initialize with all values.

      :arg verified: Whether key is verified
      :arg message: Status message
      :arg settingsURL: URL to settings
    */
    proc init(verified: bool, message: string, settingsURL: string = "") {
      this.verified = verified;
      this.message = message;
      this.settingsURL = settingsURL;
    }
  }

  // =========================================================================
  // Helper Functions
  // =========================================================================

  /*
    Convert Provider enum to lowercase string.

    :arg p: Provider enum value
    :returns: Lowercase string representation
  */
  proc providerToString(p: Provider): string {
    select p {
      when Provider.GitLab do return "gitlab";
      when Provider.GitHub do return "github";
      when Provider.Bitbucket do return "bitbucket";
      when Provider.Custom do return "custom";
      otherwise do return "unknown";
    }
  }

  /*
    Parse Provider from string.

    :arg s: String representation (case-insensitive)
    :returns: Provider enum value, defaults to Custom
  */
  proc stringToProvider(s: string): Provider {
    const lower = s.toLower();
    if lower == "gitlab" then return Provider.GitLab;
    if lower == "github" then return Provider.GitHub;
    if lower == "bitbucket" then return Provider.Bitbucket;
    return Provider.Custom;
  }

  /*
    Convert CredentialSource enum to string.

    :arg cs: CredentialSource enum value
    :returns: String representation
  */
  proc credentialSourceToString(cs: CredentialSource): string {
    select cs {
      when CredentialSource.Keychain do return "keychain";
      when CredentialSource.Environment do return "environment";
      when CredentialSource.CLIAuth do return "cli";
      when CredentialSource.None do return "none";
      otherwise do return "unknown";
    }
  }

  /*
    Parse CredentialSource from string.

    :arg s: String representation (case-insensitive)
    :returns: CredentialSource enum value, defaults to None
  */
  proc stringToCredentialSource(s: string): CredentialSource {
    const lower = s.toLower();
    if lower == "keychain" then return CredentialSource.Keychain;
    if lower == "environment" || lower == "env" then return CredentialSource.Environment;
    if lower == "cli" || lower == "cliauth" then return CredentialSource.CLIAuth;
    return CredentialSource.None;
  }

  /*
    Convert AuthMode enum to string.

    :arg am: AuthMode enum value
    :returns: String representation
  */
  proc authModeToString(am: AuthMode): string {
    select am {
      when AuthMode.SSHOnly do return "ssh-only";
      when AuthMode.CLIAuthenticated do return "cli-authenticated";
      when AuthMode.TokenOnly do return "token-only";
      when AuthMode.Failed do return "failed";
      otherwise do return "unknown";
    }
  }

  /*
    Log message if verbose mode is enabled.

    :arg args: Values to print
  */
  proc verboseLog(args...) {
    if verbose {
      write("[DEBUG] ");
      for param i in 0..<args.size {
        write(args(i));
      }
      writeln();
    }
  }

  /*
    Expand tilde in path to home directory.

    :arg path: Path that may start with ~
    :returns: Expanded path
  */
  proc expandTilde(path: string): string {
    if path.startsWith("~") {
      const home = getEnvOrDefault("HOME", "/tmp");
      return home + path[1..];
    }
    return path;
  }

  /*
    Get environment variable with default value.

    :arg name: Environment variable name
    :arg defaultVal: Default if not set
    :returns: Environment value or default
  */
  proc getEnvOrDefault(name: string, defaultVal: string = ""): string {
    use OS.POSIX only getenv;
    use CTypes;

    const result = getenv(name.c_str());
    if result != nil {
      try {
        return string.createCopyingBuffer(result);
      } catch {
        return defaultVal;
      }
    }
    return defaultVal;
  }
}
