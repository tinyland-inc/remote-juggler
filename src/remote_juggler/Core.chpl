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
  :license: Zlib
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
  param VERSION = "2.1.0-beta.7";

  /*
    Major version number (breaking changes).
  */
  param VERSION_MAJOR = 2;

  /*
    Minor version number (new features, backward compatible).
  */
  param VERSION_MINOR = 1;

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
    KeePassXC,
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
    GPG/SSH signing configuration for an identity.

    Configures how commits and tags are signed when using a
    particular git identity. Supports both GPG and SSH signing.

    :var keyId: GPG key ID or "auto" to detect from email (for GPG format)
    :var format: Signing format - "gpg" or "ssh" (default: gpg)
    :var sshKeyPath: Path to SSH public key (for SSH format)
    :var signCommits: Enable automatic commit signing (git commit -S)
    :var signTags: Enable automatic tag signing (git tag -s)
    :var autoSignoff: Add Signed-off-by trailer to commits
    :var hardwareKey: Whether key is on hardware token (YubiKey)
    :var touchPolicy: Touch policy for signing ("on", "cached", "off")
    :var securityMode: Security mode for PIN handling:
        - "maximum_security": PIN required for every operation (default YubiKey behavior)
        - "developer_workflow": PIN cached for session (default)
        - "trusted_workstation": PIN stored in TPM/SecureEnclave
    :var pinStorageMethod: Where PIN is stored for trusted_workstation mode:
        - "tpm": Linux TPM 2.0
        - "secure_enclave": macOS Secure Enclave
        - "keychain": System keychain (fallback)
        - "none": No storage (auto-detected if empty)
  */
  record GPGConfig {
    var keyId: string = "";
    var format: string = "gpg";
    var sshKeyPath: string = "";
    var signCommits: bool = false;
    var signTags: bool = false;
    var autoSignoff: bool = false;
    var hardwareKey: bool = false;
    var touchPolicy: string = "";
    var securityMode: string = "developer_workflow";
    var pinStorageMethod: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.keyId = "";
      this.format = "gpg";
      this.sshKeyPath = "";
      this.signCommits = false;
      this.signTags = false;
      this.autoSignoff = false;
      this.hardwareKey = false;
      this.touchPolicy = "";
      this.securityMode = "developer_workflow";
      this.pinStorageMethod = "";
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
      this.format = "gpg";
      this.sshKeyPath = "";
      this.signCommits = signCommits;
      this.signTags = signTags;
      this.autoSignoff = autoSignoff;
      this.hardwareKey = false;
      this.touchPolicy = "";
      this.securityMode = "developer_workflow";
      this.pinStorageMethod = "";
    }

    /*
      Initialize with format specified.

      :arg keyId: GPG key ID or "auto" (for GPG format)
      :arg format: Signing format ("gpg" or "ssh")
      :arg sshKeyPath: Path to SSH public key (for SSH format)
      :arg signCommits: Enable commit signing
      :arg signTags: Enable tag signing
      :arg hardwareKey: Whether key is on hardware token
      :arg touchPolicy: Touch policy for signing
      :arg securityMode: Security mode for PIN handling
      :arg pinStorageMethod: PIN storage method for trusted_workstation
    */
    proc init(keyId: string, format: string, sshKeyPath: string,
              signCommits: bool = false, signTags: bool = false,
              hardwareKey: bool = false, touchPolicy: string = "",
              securityMode: string = "developer_workflow",
              pinStorageMethod: string = "") {
      this.keyId = keyId;
      this.format = format;
      this.sshKeyPath = sshKeyPath;
      this.signCommits = signCommits;
      this.signTags = signTags;
      this.autoSignoff = false;
      this.hardwareKey = hardwareKey;
      this.touchPolicy = touchPolicy;
      this.securityMode = securityMode;
      this.pinStorageMethod = pinStorageMethod;
    }

    /*
      Check if signing is configured.

      :returns: true if a key ID or SSH key path is specified
    */
    proc isConfigured(): bool {
      return keyId != "" || sshKeyPath != "";
    }

    /*
      Check if key should be auto-detected from email.

      :returns: true if keyId is "auto"
    */
    proc isAutoDetect(): bool {
      return keyId == "auto";
    }

    /*
      Check if using SSH signing format.

      :returns: true if format is "ssh"
    */
    proc isSSHFormat(): bool {
      return format.toLower() == "ssh";
    }

    /*
      Check if signing requires physical touch.

      :returns: true if hardware key with touch policy "on"
    */
    proc requiresTouch(): bool {
      return hardwareKey && touchPolicy == "on";
    }

    /*
      Get the signing key for git configuration.

      :returns: GPG key ID or SSH key path depending on format
    */
    proc getSigningKey(): string {
      if isSSHFormat() {
        return sshKeyPath;
      }
      return keyId;
    }

    /*
      Check if security mode is valid.

      :returns: true if securityMode is a recognized value
    */
    proc isValidSecurityMode(): bool {
      return securityMode == "maximum_security" ||
             securityMode == "developer_workflow" ||
             securityMode == "trusted_workstation";
    }

    /*
      Check if trusted workstation mode is enabled.

      :returns: true if securityMode is "trusted_workstation"
    */
    proc isTrustedWorkstation(): bool {
      return securityMode == "trusted_workstation";
    }

    /*
      Check if PIN storage is configured.

      :returns: true if pinStorageMethod is set and valid
    */
    proc hasPinStorage(): bool {
      return pinStorageMethod == "tpm" ||
             pinStorageMethod == "secure_enclave" ||
             pinStorageMethod == "keychain";
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
    var keePassEntry: string = "";

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
    Signing format for commits and tags.

    Git 2.34+ supports SSH signing as an alternative to GPG.

    - ``GPG`` - Traditional GPG signing (default)
    - ``SSH`` - SSH key signing (requires git 2.34+)
    - ``None`` - No signing configured
  */
  enum SigningFormat {
    GPG,
    SSH,
    None
  }

  /*
    Convert SigningFormat enum to string.

    :arg sf: SigningFormat enum value
    :returns: String representation
  */
  proc signingFormatToString(sf: SigningFormat): string {
    select sf {
      when SigningFormat.GPG do return "gpg";
      when SigningFormat.SSH do return "ssh";
      when SigningFormat.None do return "none";
      otherwise do return "unknown";
    }
  }

  /*
    Parse SigningFormat from string.

    :arg s: String representation (case-insensitive)
    :returns: SigningFormat enum value, defaults to GPG
  */
  proc stringToSigningFormat(s: string): SigningFormat {
    const lower = s.toLower();
    if lower == "ssh" then return SigningFormat.SSH;
    if lower == "none" || lower == "" then return SigningFormat.None;
    return SigningFormat.GPG;
  }

  /*
    Hardware token (YubiKey/SmartCard) information.

    Captures the state of a connected hardware token for GPG operations.
    Used by agents to determine if physical touch is required.

    :var present: Whether a hardware token is connected
    :var serial: Token serial number (e.g., "26503492")
    :var cardType: Token type (e.g., "YubiKey 5 NFC")
    :var firmware: Firmware version
    :var touchSig: Touch policy for signing ("on", "cached", "off")
    :var touchEnc: Touch policy for encryption
    :var touchAut: Touch policy for authentication
    :var sigKeyGrip: Key grip of signing key on card
    :var autKeyGrip: Key grip of authentication key on card
    :var encKeyGrip: Key grip of encryption key on card
  */
  record CardInfo {
    var present: bool = false;
    var serialNum: string = "";
    var cardType: string = "";
    var firmware: string = "";
    var touchSig: string = "";
    var touchEnc: string = "";
    var touchAut: string = "";
    var sigKeyGrip: string = "";
    var autKeyGrip: string = "";
    var encKeyGrip: string = "";

    /*
      Initialize with default values (no card present).
    */
    proc init() {
      this.present = false;
      this.serialNum = "";
      this.cardType = "";
      this.firmware = "";
      this.touchSig = "";
      this.touchEnc = "";
      this.touchAut = "";
      this.sigKeyGrip = "";
      this.autKeyGrip = "";
      this.encKeyGrip = "";
    }

    /*
      Check if signing requires physical touch.

      :returns: true if touch policy is "on" for signing
    */
    proc requiresSigningTouch(): bool {
      return present && touchSig == "on";
    }

    /*
      Check if authentication can be cached.

      :returns: true if touch policy is "cached" for authentication
    */
    proc canCacheAuth(): bool {
      return present && touchAut == "cached";
    }

    /*
      Get a human-readable summary of touch requirements.

      :returns: Summary string for display
    */
    proc touchSummary(): string {
      if !present then return "No hardware token";
      var parts: string = "";
      if touchSig != "" then parts += "sig=" + touchSig;
      if touchEnc != "" then parts += (if parts != "" then ", " else "") + "enc=" + touchEnc;
      if touchAut != "" then parts += (if parts != "" then ", " else "") + "aut=" + touchAut;
      return if parts != "" then parts else "unknown";
    }
  }

  /*
    GPG status result for hardware token detection.

    Extended result type that includes hardware token information.

    :var available: Whether GPG is available
    :var keyId: The signing key ID
    :var isHardwareKey: Whether the key is on a hardware token
    :var card: Hardware token information
    :var format: Signing format (GPG or SSH)
    :var canSign: Whether signing is possible (false if hardware touch needed without user)
    :var message: Status message or guidance
  */
  record GPGStatusResult {
    var available: bool = false;
    var keyId: string = "";
    var isHardwareKey: bool = false;
    var card: CardInfo;
    var format: SigningFormat = SigningFormat.GPG;
    var canSign: bool = false;
    var message: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.available = false;
      this.keyId = "";
      this.isHardwareKey = false;
      this.card = new CardInfo();
      this.format = SigningFormat.GPG;
      this.canSign = false;
      this.message = "";
    }

    /*
      Initialize with all values.

      :arg available: Whether GPG is available
      :arg keyId: The signing key ID
      :arg isHardwareKey: Whether key is on hardware
      :arg card: Card information
      :arg format: Signing format
      :arg canSign: Whether automated signing is possible
      :arg message: Status message
    */
    proc init(available: bool, keyId: string, isHardwareKey: bool,
              card: CardInfo, format: SigningFormat,
              canSign: bool, message: string) {
      this.available = available;
      this.keyId = keyId;
      this.isHardwareKey = isHardwareKey;
      this.card = card;
      this.format = format;
      this.canSign = canSign;
      this.message = message;
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
  // ANSI Color Codes
  // =========================================================================

  /*
    ANSI color codes for terminal output formatting.
  */
  enum ANSIColor {
    Reset,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    Bold,
    Dim,
    Underline
  }

  /*
    Get the ANSI escape sequence for a color.

    :arg c: ANSIColor enum value
    :returns: ANSI escape sequence string
  */
  proc colorCode(c: ANSIColor): string {
    select c {
      when ANSIColor.Reset do return "\x1b[0m";
      when ANSIColor.Red do return "\x1b[31m";
      when ANSIColor.Green do return "\x1b[32m";
      when ANSIColor.Yellow do return "\x1b[33m";
      when ANSIColor.Blue do return "\x1b[34m";
      when ANSIColor.Magenta do return "\x1b[35m";
      when ANSIColor.Cyan do return "\x1b[36m";
      when ANSIColor.Bold do return "\x1b[1m";
      when ANSIColor.Dim do return "\x1b[2m";
      when ANSIColor.Underline do return "\x1b[4m";
      otherwise do return "";
    }
  }

  /*
    Apply ANSI color formatting to a string.

    Uses environment variables to determine color support:
    - NO_COLOR: If set, disables all colors
    - TERM: If "dumb" or empty, disables colors

    :arg s: String to colorize
    :arg c: ANSIColor to apply
    :returns: Colorized string (or plain if colors not supported)
  */
  proc colorize(s: string, c: ANSIColor): string {
    // Check for color support
    const noColor = getEnvVar("NO_COLOR");
    const term = getEnvVar("TERM");

    if noColor != "" || term == "" || term == "dumb" {
      return s;
    }

    return colorCode(c) + s + colorCode(ANSIColor.Reset);
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
      when CredentialSource.KeePassXC do return "keepassxc";
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
    if lower == "keepassxc" || lower == "kdbx" then return CredentialSource.KeePassXC;
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
    Get environment variable value.

    :arg name: Environment variable name
    :returns: Environment value or empty string if not set
  */
  proc getEnvVar(name: string): string {
    return getEnvOrDefault(name, "");
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
