/*
 * RemoteJuggler - Backend-agnostic git identity management
 *
 * Main entry point and CLI interface.
 * Supports CLI mode (default), MCP server mode, and ACP server mode.
 *
 * Copyright (c) 2026 Jess Sullivan
 * SPDX-License-Identifier: MIT
 */
prototype module remote_juggler {
  // Standard library imports
  use IO;
  use List;
  use Map;
  use Time;
  use CTypes;
  use Path;

  // Include and re-export submodules
  // These are located in src/remote_juggler/ directory
  include module Core;
  include module Config;
  include module GlobalConfig;
  include module State;
  include module Keychain;
  include module ProviderCLI;
  include module GPG;
  include module Remote;
  include module Identity;
  include module TokenHealth;
  include module Protocol;
  include module MCP;
  include module ACP;
  include module Tools;

  // Public re-exports for external consumers
  public use Core;
  public use Config;
  public use GlobalConfig;
  public use State;
  public use Keychain;
  public use ProviderCLI;
  public use GPG;
  public use Remote;
  public use Identity;
  public use TokenHealth;
  public use Protocol;
  public use MCP;
  public use ACP;
  public use Tools;

  // ==========================================================================
  // ANSI Color/Formatting Helpers
  // ==========================================================================

  // Convenience wrappers using Core.colorize
  // These provide a cleaner API for common color operations

  proc green(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Green);
  }

  proc red(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Red);
  }

  proc yellow(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Yellow);
  }

  proc blue(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Blue);
  }

  proc cyan(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Cyan);
  }

  proc magenta(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Magenta);
  }

  proc bold(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Bold);
  }

  proc dim(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Dim);
  }

  proc underline(s: string): string {
    return Core.colorize(s, Core.ANSIColor.Underline);
  }

  // ==========================================================================
  // List Helpers
  // ==========================================================================

  // Create a sublist from index start to end
  proc sublist(lst: list(string), start: int): list(string) {
    var result = new list(string);
    for i in start..<lst.size {
      result.pushBack(lst[i]);
    }
    return result;
  }

  // Create an empty list for arguments
  proc emptyArgs(): list(string) {
    return new list(string);
  }

  // ==========================================================================
  // Output Formatting
  // ==========================================================================

  proc printSuccess(message: string) {
    writeln(green("[OK]"), " ", message);
  }

  proc printError(message: string) {
    writeln(red("[ERROR]"), " ", message);
  }

  proc printWarning(message: string) {
    writeln(yellow("[WARN]"), " ", message);
  }

  proc printInfo(message: string) {
    writeln(cyan("[INFO]"), " ", message);
  }

  proc printDebug(message: string) {
    if verbose {
      writeln(dim("[DEBUG]"), " ", message);
    }
  }

  // Print header with version
  proc printHeader() {
    writeln(bold("RemoteJuggler"), " v", Core.VERSION);
    writeln();
  }

  // Print usage/help information
  proc printUsage() {
    printHeader();

    writeln(bold("USAGE:"));
    writeln("  remote-juggler [OPTIONS] <COMMAND> [ARGS]");
    writeln();

    writeln(bold("OPTIONS:"));
    writeln("  --mode=<mode>     Operation mode: cli (default), mcp, acp");
    writeln("  --verbose         Enable verbose output");
    writeln("  --help            Show this help message");
    writeln("  --configPath=<p>  Override config file path");
    writeln("  --useKeychain     Enable/disable keychain (Darwin, default: true)");
    writeln("  --gpgSign         Enable/disable GPG signing (default: true)");
    writeln("  --provider=<p>    Filter by provider: gitlab, github, bitbucket, all");
    writeln();

    writeln(bold("COMMANDS:"));
    writeln();

    writeln("  ", bold("Identity Management:"));
    writeln("    list              List all configured identities");
    writeln("    detect            Detect identity for current repository");
    writeln("    switch <name>     Switch to identity (alias: 'to')");
    writeln("    to <name>         Alias for switch");
    writeln("    validate <name>   Test SSH/API connectivity for identity");
    writeln("    verify            Verify identity matches expected for repo");
    writeln("    status            Show current identity status");
    writeln();

    writeln("  ", bold("Configuration:"));
    writeln("    config show       Display configuration");
    writeln("    config add <n>    Add new identity interactively");
    writeln("    config edit <n>   Edit existing identity");
    writeln("    config remove <n> Remove identity");
    writeln("    config import     Import identities from SSH config");
    writeln("    config sync       Synchronize managed blocks");
    writeln();

    writeln("  ", bold("Token Management:"));
    writeln("    token set <n>     Store token in keychain (Darwin)");
    writeln("    token get <n>     Retrieve token (masked output)");
    writeln("    token clear <n>   Remove token from keychain");
    writeln("    token verify      Test all configured credentials");
    writeln("    token check-expiry [n]  Check token expiration status");
    writeln("    token renew <n>   Renew expired/expiring token");
    writeln();

    writeln("  ", bold("GPG Signing:"));
    writeln("    gpg status        Show GPG configuration");
    writeln("    gpg configure <n> Configure GPG for identity");
    writeln("    gpg verify        Check provider registration");
    writeln();

    writeln("  ", bold("Debug:"));
    writeln("    debug ssh-config  Show parsed SSH configuration");
    writeln("    debug git-config  Show parsed gitconfig rewrites");
    writeln("    debug keychain    Test keychain access");
    writeln();

    writeln(bold("SERVER MODES:"));
    writeln("  remote-juggler --mode=mcp    Run as MCP STDIO server");
    writeln("  remote-juggler --mode=acp    Run as ACP STDIO server");
    writeln();

    writeln(bold("EXAMPLES:"));
    writeln("  remote-juggler                       # Show current status");
    writeln("  remote-juggler list                  # List all identities");
    writeln("  remote-juggler list --provider=gitlab");
    writeln("  remote-juggler switch personal       # Switch to personal identity");
    writeln("  remote-juggler to work               # Switch to work identity");
    writeln("  remote-juggler token set personal    # Store token in keychain");
    writeln("  remote-juggler --mode=mcp            # Start MCP server");
    writeln();

    writeln(dim("For more information: https://gitlab.com/tinyland/projects/remote-juggler"));
  }

  // Print a table of identities
  proc printIdentityTable(identities: list(GitIdentity)) {
    if identities.size == 0 {
      writeln(dim("No identities configured."));
      writeln();
      writeln("Run 'remote-juggler config import' to import from SSH config");
      writeln("or 'remote-juggler config add <name>' to add manually.");
      return;
    }

    // Calculate column widths
    var nameWidth = 8;   // "Identity"
    var providerWidth = 8; // "Provider"
    var hostWidth = 8;   // "SSH Host"
    var userWidth = 4;   // "User"
    var emailWidth = 5;  // "Email"

    for identity in identities {
      if identity.name.size > nameWidth then nameWidth = identity.name.size;
      const provStr = providerToString(identity.provider);
      if provStr.size > providerWidth then providerWidth = provStr.size;
      if identity.host.size > hostWidth then hostWidth = identity.host.size;
      if identity.user.size > userWidth then userWidth = identity.user.size;
      if identity.email.size > emailWidth then emailWidth = identity.email.size;
    }

    // Add padding
    nameWidth += 2;
    providerWidth += 2;
    hostWidth += 2;
    userWidth += 2;
    emailWidth += 2;

    // Header - use simple write to avoid format string issues with ANSI codes
    write(padRight(bold("Identity"), nameWidth));
    write(padRight(bold("Provider"), providerWidth));
    write(padRight(bold("SSH Host"), hostWidth));
    write(padRight(bold("User"), userWidth));
    write(padRight(bold("Email"), emailWidth));
    writeln(bold("GPG"));

    // Separator
    write(repeatChar("-", nameWidth + providerWidth + hostWidth + userWidth + emailWidth + 12));
    writeln();

    // Get current identity for highlighting
    const currentCtx = State.loadState();

    // Rows
    for identity in identities {
      const isCurrent = (identity.name == currentCtx.currentIdentity);
      const marker = if isCurrent then green("*") else " ";
      const nameStr = if isCurrent then green(identity.name) else identity.name;
      const gpgStatus = if identity.gpg.keyId != "" && identity.gpg.keyId != "none"
                        then green("Yes")
                        else dim("No");

      // Use simple write to avoid format string issues with ANSI codes
      write(marker);
      write(padRight(nameStr, nameWidth - 1));
      write(padRight(providerToString(identity.provider), providerWidth));
      write(padRight(identity.host, hostWidth));
      write(padRight(identity.user, userWidth));
      write(padRight(identity.email, emailWidth));
      writeln(gpgStatus);
    }
  }

  // Helper to pad string to width (right-aligned padding on left)
  proc padRight(s: string, width: int): string {
    // Calculate visible length (ignoring ANSI codes)
    var visibleLen = 0;
    var inEscape = false;
    for ch in s {
      if ch == '\x1b' then inEscape = true;
      else if inEscape && ch == 'm' then inEscape = false;
      else if !inEscape then visibleLen += 1;
    }

    if visibleLen >= width then return s + " ";

    var padding = "";
    for i in 1..(width - visibleLen) {
      padding += " ";
    }
    return s + padding;
  }

  // Helper to repeat a character
  proc repeatChar(c: string, count: int): string {
    var result = "";
    for i in 1..count {
      result += c;
    }
    return result;
  }

  // Print detailed status
  proc printStatus(ctx: SwitchContext, identity: GitIdentity) {
    printHeader();

    writeln(bold("Current Identity: "), green(identity.name),
            " (", providerToString(identity.provider), ")");

    writeln("  User:     ", identity.user, " <", identity.email, ">");
    writeln("  SSH Host: ", identity.host);

    // GPG status
    if identity.gpg.keyId != "" && identity.gpg.keyId != "none" {
      const signStatus = if identity.gpg.signCommits then green("commits signed") else dim("signing disabled");
      writeln("  GPG Key:  ", identity.gpg.keyId, " (", signStatus, ")");
    } else {
      writeln("  GPG Key:  ", dim("not configured"));
    }

    // Credential source
    write("  Auth:     ");
    select identity.credentialSource {
      when Core.CredentialSource.Keychain do writeln(green("Keychain"));
      when Core.CredentialSource.Environment do writeln(cyan("Environment ($" + identity.tokenEnvVar + ")"));
      when Core.CredentialSource.CLIAuth do writeln(cyan("CLI Auth (glab/gh)"));
      when Core.CredentialSource.None do writeln(yellow("SSH-only"));
    }

    writeln();

    // Repository info (if in a git repo)
    const (isRepo, repoRoot) = Remote.getRepositoryRoot(".");
    if isRepo {
      writeln(bold("Repository: "), repoRoot);

      const (hasRemote, remoteUrl) = Remote.getOriginURL(repoRoot);
      if hasRemote {
        writeln("  Remote:   origin -> ", dim(remoteUrl));
      }

      const (hasBranch, branchName) = Remote.getCurrentBranch(repoRoot);
      if hasBranch {
        const (hasUpstream, upstream) = Remote.getUpstreamBranch(repoRoot, branchName);
        if hasUpstream {
          writeln("  Branch:   ", branchName, " -> ", dim(upstream));
        } else {
          writeln("  Branch:   ", branchName, " ", dim("(no upstream)"));
        }
      }

      // Check if remote matches identity using Identity module
      if hasRemote {
        const (detected, detectedIdentity, _) = Identity.detectIdentity(repoRoot);
        if detected && detectedIdentity.name != identity.name {
          writeln();
          printWarning("Remote URL suggests identity '" + detectedIdentity.name + "'");
          writeln("  Run 'remote-juggler switch ", detectedIdentity.name, "' to match");
        }
      }
    } else {
      writeln(dim("Not in a git repository"));
    }

    // Last switch time
    if ctx.lastSwitch != "" {
      writeln();
      writeln(dim("Last switched: "), dim(ctx.lastSwitch));
    }
  }

  // Print simple status line (for detect command)
  proc printDetectedIdentity(identityName: string, confidence: string, reasons: list(string)) {
    writeln(bold("Detected Identity: "), green(identityName));
    writeln("  Confidence: ", confidence);

    if reasons.size > 0 {
      writeln("  Reasons:");
      for reason in reasons {
        writeln("    - ", reason);
      }
    }
  }

  // ==========================================================================
  // Command Handlers
  // ==========================================================================

  // Handle 'list' command
  proc handleList(args: list(string)) {
    printDebug("Executing list command");

    // Load identities - filter by provider if specified
    var identities: list(GitIdentity);
    if provider != "all" {
      const targetProvider = stringToProvider(provider);
      identities = Identity.listIdentities(targetProvider);
    } else {
      // Pass Custom as "all" filter per Identity module convention
      identities = Identity.listIdentities(Core.Provider.Custom);
    }

    printIdentityTable(identities);
  }

  // Handle 'detect' command
  proc handleDetect(args: list(string)) {
    printDebug("Executing detect command");

    const repoPath = if args.size > 0 then args[0] else ".";

    if !Remote.isGitRepository(repoPath) {
      printError("Not in a git repository");
      return;
    }

    const (hasRemote, remoteUrl) = Remote.getOriginURL(repoPath);
    if !hasRemote {
      printError("No remote 'origin' found");
      return;
    }

    // Use the detectIdentityDetailed from Identity module
    const detection = Identity.detectIdentityDetailed(repoPath);

    if !detection.found {
      printWarning("Could not detect identity from remote URL");
      writeln("  Remote URL: ", remoteUrl);
      writeln("  Reason: ", detection.reason);
      writeln();
      writeln("Run 'remote-juggler config import' to import SSH identities");
      return;
    }

    var reasons: list(string);
    reasons.pushBack(detection.reason);
    printDetectedIdentity(detection.identity.name, detection.confidence, reasons);
  }

  // Handle 'switch' / 'to' command
  proc handleSwitch(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler switch <identity>");
      return;
    }

    const targetIdentity = args[0];
    printDebug("Switching to identity: " + targetIdentity);

    // Check if identity exists
    const (found, identity) = Identity.getIdentity(targetIdentity);
    if !found {
      printError("Identity not found: " + targetIdentity);
      writeln();
      writeln("Available identities:");
      const identities = Identity.listIdentityNames();
      for name in identities {
        writeln("  - ", name);
      }
      return;
    }

    // Perform the switch using the switchIdentity function
    const result = Identity.switchIdentity(targetIdentity, true, ".");

    if result.success {
      printSuccess("Switched to " + result.identity.name);
      writeln();
      writeln("  Provider: ", providerToString(result.identity.provider));
      writeln("  User:     ", result.identity.user, " <", result.identity.email, ">");
      writeln("  SSH Host: ", result.identity.host);

      // Auth status
      write("  Auth:     ");
      select result.authMode {
        when Core.AuthMode.KeychainAuth do writeln(green("Keychain authenticated"));
        when Core.AuthMode.CLIAuthenticated do writeln(green("CLI authenticated"));
        when Core.AuthMode.TokenOnly do writeln(cyan("Token available"));
        when Core.AuthMode.SSHOnly do writeln(yellow("SSH-only mode"));
      }

      // GPG status
      if result.gpgConfigured {
        writeln("  GPG:      ", green("Signing configured"));
      }

      // Show remote update status
      if result.remoteUpdated {
        writeln("  Remote:   ", green("Updated for identity"));
      }

      // Check for token expiry warnings
      writeln();
      TokenHealth.warnIfExpiring(result.identity);

    } else {
      printError("Failed to switch: " + result.message);
    }
  }

  // Handle 'validate' command
  proc handleValidate(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler validate <identity>");
      return;
    }

    const targetIdentity = args[0];
    printDebug("Validating identity: " + targetIdentity);

    // Use Identity module's validation
    const result = Identity.validateIdentity(targetIdentity, gpgSign);

    if result.issues.size > 0 && !result.sshConnectivity {
      printError("Identity not found or validation failed: " + targetIdentity);
      for issue in result.issues {
        writeln("  ", issue);
      }
      return;
    }

    // Get the identity for display
    const (found, identity) = Identity.getIdentity(targetIdentity);
    if !found {
      printError("Identity not found: " + targetIdentity);
      return;
    }

    writeln(bold("Validating: "), identity.name, " (", providerToString(identity.provider), ")");
    writeln();

    // SSH connectivity test
    write("  SSH Connection... ");
    if result.sshConnectivity {
      writeln(green("OK"));
    } else {
      writeln(red("FAILED"));
    }

    // Credential test
    write("  Credentials...    ");
    if result.credentialAvailable {
      writeln(green("OK"));
    } else {
      writeln(yellow("Not found"), " (SSH-only mode)");
    }

    // GPG key test
    if identity.gpg.isConfigured() {
      write("  GPG Key...        ");
      if result.gpgKeyFound {
        writeln(green("OK"));
      } else {
        writeln(red("FAILED"));
      }

      // Check provider registration
      write("  GPG Registered... ");
      if result.gpgRegistered {
        writeln(green("OK"));
      } else {
        writeln(yellow("Not verified"));
        writeln("    Add at: ", GPG.getGPGSettingsURL(identity));
      }
    }

    // Check token expiry if credentials are available
    if result.credentialAvailable {
      write("  Token Expiry...   ");
      const healthResult = TokenHealth.checkTokenHealth(identity);
      if healthResult.isExpired {
        writeln(red("EXPIRED"));
      } else if healthResult.needsRenewal {
        writeln(yellow("Expiring soon"), " (", healthResult.daysUntilExpiry, " days)");
      } else if healthResult.daysUntilExpiry < 999999 {
        writeln(green("OK"), " ", dim("(" + healthResult.daysUntilExpiry:string + " days)"));
      } else {
        writeln(green("OK"), " ", dim("(unknown expiry)"));
      }
    }

    // Show any issues
    if result.issues.size > 0 {
      writeln();
      writeln(yellow("Issues found:"));
      for issue in result.issues {
        writeln("  - ", issue);
      }
    }

    writeln();
  }

  // Handle 'verify' command (pre-commit hook verification)
  proc handleVerify(args: list(string)) {
    printDebug("Executing verify command");

    var isPreCommit = false;
    var isPrePush = false;

    // Parse flags
    for arg in args {
      if arg == "--pre-commit" then isPreCommit = true;
      else if arg == "--pre-push" then isPrePush = true;
    }

    const repoPath = ".";

    // Check if we're in a git repo
    if !Remote.isGitRepository(repoPath) {
      if !isPreCommit {
        printError("Not in a git repository");
      }
      halt(1);
    }

    // Get current git config user.email
    const (gotEmail, currentEmail) = Remote.getGitConfig(repoPath, "user.email");
    if !gotEmail || currentEmail == "" {
      if !isPreCommit {
        printError("No git user.email configured");
      }
      halt(1);
    }

    // Detect expected identity for this repo
    const (found, expectedIdentity, reason) = Identity.detectIdentity(repoPath);
    if !found {
      // No identity matched, cannot verify
      if !isPreCommit {
        printWarning("Could not detect expected identity for this repository");
        writeln("Run 'remote-juggler config import' to import identities");
      }
      // In pre-commit mode, allow commits if no identity is matched (user may have unconfigured repos)
      if isPreCommit {
        halt(0);
      }
      halt(1);
    }

    // Compare current git config with expected identity
    if currentEmail != expectedIdentity.email {
      if isPreCommit {
        stderr.writeln("[RemoteJuggler] Identity mismatch!");
        stderr.writeln("  Current:  ", currentEmail);
        stderr.writeln("  Expected: ", expectedIdentity.email, " (", expectedIdentity.name, ")");
      } else {
        printError("Identity mismatch!");
        writeln("  Current git config: ", currentEmail);
        writeln("  Expected identity:  ", expectedIdentity.email, " (", expectedIdentity.name, ")");
        writeln();
        writeln("Run: remote-juggler switch ", expectedIdentity.name);
      }
      halt(1);
    }

    // Verification passed
    if !isPreCommit {
      printSuccess("Identity verified: " + expectedIdentity.name);
      writeln("  Email: ", expectedIdentity.email);
      writeln("  Reason: ", reason);
    }
    // Exit 0 on success (implicit)
  }

  // Handle 'status' command
  proc handleStatus() {
    printDebug("Executing status command");

    const ctx = State.loadState();

    if ctx.currentIdentity == "" || !ctx.hasActiveIdentity() {
      printHeader();
      writeln(yellow("No identity currently active."));
      writeln();
      writeln("Run 'remote-juggler detect' to detect based on repository");
      writeln("or 'remote-juggler switch <identity>' to set one.");
      return;
    }

    const (found, identity) = Identity.getIdentity(ctx.currentIdentity);
    if !found {
      printHeader();
      printWarning("Current identity '" + ctx.currentIdentity + "' not found in config");
      return;
    }

    printStatus(ctx, identity);
  }

  // Handle 'config' subcommands
  proc handleConfig(args: list(string)) {
    if args.size < 1 {
      // Default to show
      handleConfigShow(emptyArgs());
      return;
    }

    const subcommand = args[0];
    const subArgs = if args.size > 1 then sublist(args, 1) else new list(string);

    select subcommand {
      when "show" do handleConfigShow(subArgs);
      when "add" do handleConfigAdd(subArgs);
      when "edit" do handleConfigEdit(subArgs);
      when "remove", "rm", "delete" do handleConfigRemove(subArgs);
      when "import" do handleConfigImport();
      when "sync" do handleConfigSync();
      when "init" do handleConfigInit();
      otherwise {
        printError("Unknown config subcommand: " + subcommand);
        writeln("Available: show, add, edit, remove, import, sync");
      }
    }
  }

  proc handleConfigShow(args: list(string)) {
    printDebug("Showing configuration");

    const configPath = GlobalConfig.getConfigPath();
    writeln(bold("Configuration: "), configPath);
    writeln();

    // Check if specific section requested
    if args.size > 0 {
      const section = args[0];
      select section {
        when "identities" {
          const identities = GlobalConfig.loadIdentities();
          printIdentityTable(identities);
        }
        when "settings" {
          const settings = GlobalConfig.loadSettings();
          writeln(bold("Settings:"));
          writeln("  defaultProvider:     ", settings.defaultProvider);
          writeln("  autoDetect:          ", settings.autoDetect);
          writeln("  useKeychain:         ", settings.useKeychain);
          writeln("  gpgSign:             ", settings.gpgSign);
          writeln("  gpgVerifyWithProvider: ", settings.gpgVerifyWithProvider);
          writeln("  fallbackToSSH:       ", settings.fallbackToSSH);
        }
        when "ssh-hosts", "ssh" {
          const hosts = GlobalConfig.getManagedSSHHosts();
          writeln(bold("Managed SSH Hosts:"));
          writeln(dim("  (Auto-generated from ~/.ssh/config)"));
          writeln();
          for h in hosts {
            writeln("  ", bold(h.host));
            writeln("    Hostname: ", h.hostname);
            writeln("    Key:      ", h.identityFile);
          }
        }
        when "rewrites", "git" {
          const rewrites = GlobalConfig.getManagedGitRewrites();
          writeln(bold("Git URL Rewrites:"));
          writeln(dim("  (Auto-generated from ~/.gitconfig)"));
          writeln();
          for rewrite in rewrites {
            writeln("  ", rewrite.fromURL, " -> ", rewrite.toURL);
          }
        }
        otherwise {
          printError("Unknown section: " + section);
          writeln("Available: identities, settings, ssh-hosts, rewrites");
        }
      }
      return;
    }

    // Show full configuration summary
    const identities = GlobalConfig.loadIdentities();
    const settings = GlobalConfig.loadSettings();

    writeln(bold("Identities: "), identities.size, " configured");
    printIdentityTable(identities);

    writeln();
    writeln(bold("Settings:"));
    writeln("  Auto-detect: ", if settings.autoDetect then green("enabled") else dim("disabled"));
    writeln("  Keychain:    ", if settings.useKeychain then green("enabled") else dim("disabled"));
    writeln("  GPG Sign:    ", if settings.gpgSign then green("enabled") else dim("disabled"));
  }

  proc handleConfigAdd(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler config add <name>");
      return;
    }

    const name = args[0];
    printDebug("Adding identity: " + name);

    // Check if already exists
    const existing = GlobalConfig.getIdentity(name);
    if existing.name != "" {
      printError("Identity already exists: " + name);
      writeln("Use 'remote-juggler config edit ", name, "' to modify it");
      return;
    }

    writeln(bold("Adding identity: "), name);
    writeln();

    // Interactive prompts (basic implementation)
    // In a full implementation, this would use proper interactive input
    writeln("Please edit the config file directly at:");
    writeln("  ", GlobalConfig.getConfigPath());
    writeln();
    writeln("Or use 'remote-juggler config import' to auto-detect from SSH config.");
  }

  proc handleConfigEdit(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler config edit <name>");
      return;
    }

    const name = args[0];
    printDebug("Editing identity: " + name);

    const identity = GlobalConfig.getIdentity(name);
    if identity.name == "" {
      printError("Identity not found: " + name);
      return;
    }

    writeln(bold("Edit identity: "), name);
    writeln();
    writeln("Current configuration:");
    writeln("  Provider: ", providerToString(identity.provider));
    writeln("  Host:     ", identity.host);
    writeln("  Hostname: ", identity.hostname);
    writeln("  User:     ", identity.user);
    writeln("  Email:    ", identity.email);
    writeln();
    writeln("Please edit the config file directly at:");
    writeln("  ", GlobalConfig.getConfigPath());
  }

  proc handleConfigRemove(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler config remove <name>");
      return;
    }

    const name = args[0];
    printDebug("Removing identity: " + name);

    const existing = GlobalConfig.getIdentity(name);
    if existing.name == "" {
      printError("Identity not found: " + name);
      return;
    }

    const result = GlobalConfig.removeIdentity(name);
    if result {
      printSuccess("Removed identity: " + name);
    } else {
      printError("Failed to remove identity");
    }
  }

  proc handleConfigImport() {
    printDebug("Importing identities from SSH config");

    writeln(bold("Importing from SSH config..."));
    writeln();

    const result = GlobalConfig.importFromSSHConfig();

    if result.imported > 0 {
      printSuccess("Imported " + result.imported:string + " identities");
      writeln();
      for name in result.names {
        writeln("  - ", name);
      }
    } else if result.skipped > 0 {
      printInfo("No new identities to import (" + result.skipped:string + " already exist)");
    } else {
      printWarning("No git-related SSH hosts found in ~/.ssh/config");
    }
  }

  proc handleConfigSync() {
    printDebug("Synchronizing managed blocks");

    writeln(bold("Synchronizing configuration..."));
    writeln();

    const result = GlobalConfig.syncManagedBlocks();

    if result.sshHostsUpdated {
      printSuccess("SSH hosts updated");
    } else {
      writeln("  SSH hosts: ", dim("up to date"));
    }

    if result.gitRewritesUpdated {
      printSuccess("Git rewrites updated");
    } else {
      writeln("  Git rewrites: ", dim("up to date"));
    }
  }

  proc handleConfigInit() {
    printDebug("Initializing configuration");

    const result = GlobalConfig.initializeConfig();
    if result {
      printSuccess("Configuration initialized at:");
      writeln("  ", GlobalConfig.getConfigPath());
    } else {
      printError("Failed to initialize configuration");
    }
  }

  // Handle 'token' subcommands
  proc handleToken(args: list(string)) {
    if args.size < 1 {
      printError("Missing subcommand");
      writeln("Usage: remote-juggler token <set|get|clear|verify|check-expiry|renew> [identity]");
      return;
    }

    const subcommand = args[0];
    const subArgs = if args.size > 1 then sublist(args, 1) else new list(string);

    select subcommand {
      when "set" do handleTokenSet(subArgs);
      when "get" do handleTokenGet(subArgs);
      when "clear", "delete", "rm" do handleTokenClear(subArgs);
      when "verify", "test" do handleTokenVerify();
      when "check-expiry", "expiry", "check" do handleTokenCheckExpiry(subArgs);
      when "renew", "refresh" do handleTokenRenew(subArgs);
      otherwise {
        printError("Unknown token subcommand: " + subcommand);
        writeln("Available: set, get, clear, verify, check-expiry, renew");
      }
    }
  }

  proc handleTokenSet(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler token set <identity>");
      return;
    }

    const name = args[0];
    printDebug("Setting token for: " + name);

    // Check if keychain is available
    if !Keychain.isDarwin() {
      printError("Keychain integration requires macOS");
      writeln("Use environment variables or CLI auth instead.");
      return;
    }

    const identity = GlobalConfig.getIdentity(name);
    if identity.name == "" {
      printError("Identity not found: " + name);
      return;
    }

    // Read token from stdin (for security)
    writeln("Enter token for ", identity.name, " (input hidden):");
    write("> ");

    // In a full implementation, we would disable echo
    // For now, read from stdin
    var token: string;
    if !stdin.readLine(token) {
      printError("Failed to read token");
      return;
    }
    token = token.strip();

    if token == "" {
      printError("Token cannot be empty");
      return;
    }

    const result = Keychain.storeToken(providerToString(identity.provider), identity.name, identity.user, token);
    if result {
      printSuccess("Token stored in keychain");
    } else {
      printError("Failed to store token");
    }
  }

  proc handleTokenGet(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler token get <identity>");
      return;
    }

    const name = args[0];
    printDebug("Getting token for: " + name);

    if !Keychain.isDarwin() {
      printError("Keychain integration requires macOS");
      return;
    }

    const identity = GlobalConfig.getIdentity(name);
    if identity.name == "" {
      printError("Identity not found: " + name);
      return;
    }

    const (found, token) = Keychain.retrieveToken(providerToString(identity.provider), identity.name, identity.user);
    if found {
      // Mask the token for display
      const masked = if token.size > 8
                     then token[0..3] + "..." + token[token.size-4..]
                     else "****";
      writeln(bold("Token: "), masked);
      writeln(dim("(Use 'security find-generic-password' for full token)"));
    } else {
      printWarning("No token found for " + name);
    }
  }

  proc handleTokenClear(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler token clear <identity>");
      return;
    }

    const name = args[0];
    printDebug("Clearing token for: " + name);

    if !Keychain.isDarwin() {
      printError("Keychain integration requires macOS");
      return;
    }

    const identity = GlobalConfig.getIdentity(name);
    if identity.name == "" {
      printError("Identity not found: " + name);
      return;
    }

    const result = Keychain.deleteToken(providerToString(identity.provider), identity.name, identity.user);
    if result {
      printSuccess("Token removed from keychain");
    } else {
      printWarning("No token found to remove");
    }
  }

  proc handleTokenVerify() {
    printDebug("Verifying all tokens");

    writeln(bold("Verifying credentials..."));
    writeln();

    const identities = Identity.listIdentities();

    for identity in identities {
      write("  ", identity.name, "... ");

      const (hasToken, _) = ProviderCLI.resolveCredential(identity);
      if hasToken {
        writeln(green("OK"));

        // Also check for expiry warnings
        const healthResult = TokenHealth.checkTokenHealth(identity);
        if healthResult.needsRenewal {
          writeln("    ", yellow("[WARNING] Expires in " + healthResult.daysUntilExpiry:string + " days"));
        } else if healthResult.isExpired {
          writeln("    ", red("[EXPIRED]"));
        }
      } else {
        writeln(yellow("Not found"));
      }
    }
  }

  proc handleTokenCheckExpiry(args: list(string)) {
    printDebug("Checking token expiry");

    const identities = Identity.listIdentities();

    if args.size > 0 {
      // Check specific identity
      const name = args[0];
      const identity = GlobalConfig.getIdentity(name);

      if identity.name == "" {
        printError("Identity not found: " + name);
        return;
      }

      writeln(bold("Token Health: "), identity.name);
      writeln();

      const healthResult = TokenHealth.checkTokenHealth(identity);
      write(TokenHealth.formatHealthResult(healthResult));

    } else {
      // Check all identities
      TokenHealth.printTokenHealthSummary(identities);
    }
  }

  proc handleTokenRenew(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler token renew <identity>");
      return;
    }

    const name = args[0];
    printDebug("Renewing token for: " + name);

    const identity = GlobalConfig.getIdentity(name);
    if identity.name == "" {
      printError("Identity not found: " + name);
      return;
    }

    // Show current token health
    writeln(bold("Current Token Status:"));
    writeln();
    const healthResult = TokenHealth.checkTokenHealth(identity);
    write(TokenHealth.formatHealthResult(healthResult));
    writeln();

    // Prompt for renewal
    const renewed = TokenHealth.renewToken(identity);
    if renewed {
      printSuccess("Token renewed successfully");
    } else {
      printError("Token renewal failed or cancelled");
    }
  }

  // Handle 'gpg' subcommands
  proc handleGPG(args: list(string)) {
    if args.size < 1 {
      // Default to status
      handleGPGStatus();
      return;
    }

    const subcommand = args[0];
    const subArgs = if args.size > 1 then sublist(args, 1) else new list(string);

    select subcommand {
      when "status" do handleGPGStatus();
      when "configure", "config" do handleGPGConfigure(subArgs);
      when "verify", "check" do handleGPGVerify();
      otherwise {
        printError("Unknown gpg subcommand: " + subcommand);
        writeln("Available: status, configure, verify");
      }
    }
  }

  proc handleGPGStatus() {
    printDebug("Showing GPG status");

    writeln(bold("GPG Configuration:"));
    writeln();

    // List available keys
    const keys = GPG.listKeys();

    if keys.size == 0 {
      writeln(dim("No GPG secret keys found"));
      writeln();
      writeln("Generate a key with: gpg --full-generate-key");
      return;
    }

    writeln(bold("Available Keys:"));
    for key in keys {
      writeln("  ", bold(key.keyId));
      writeln("    Name:   ", key.name);
      writeln("    Email:  ", key.email);
      if key.expires != "" {
        writeln("    Expires: ", key.expires);
      }
      writeln();
    }

    // Show identity GPG configuration
    writeln(bold("Identity GPG Settings:"));
    const identities = Identity.listIdentities();

    for identity in identities {
      write("  ", identity.name, ": ");
      if identity.gpg.isConfigured() {
        writeln(identity.gpg.keyId);
        writeln("    Sign commits: ", if identity.gpg.signCommits then green("yes") else dim("no"));
        writeln("    Sign tags:    ", if identity.gpg.signTags then green("yes") else dim("no"));
        writeln("    Auto signoff: ", if identity.gpg.autoSignoff then green("yes") else dim("no"));
      } else {
        writeln(dim("not configured"));
      }
    }
  }

  proc handleGPGConfigure(args: list(string)) {
    if args.size < 1 {
      printError("Missing identity name");
      writeln("Usage: remote-juggler gpg configure <identity>");
      return;
    }

    const name = args[0];
    printDebug("Configuring GPG for: " + name);

    const (exists, identity) = Identity.getIdentity(name);
    if !exists {
      printError("Identity not found: " + name);
      return;
    }

    writeln(bold("Configuring GPG for: "), identity.name);
    writeln();

    // Try to find key by email
    const (found, keyId) = GPG.getKeyForEmail(identity.email);
    if found {
      writeln("Found GPG key for ", identity.email, ": ", bold(keyId));
      writeln();
      writeln("Update the config file to add this key:");
      writeln("  ", GlobalConfig.getConfigPath());
    } else {
      printWarning("No GPG key found for " + identity.email);
      writeln();
      writeln("Generate a key with:");
      writeln("  gpg --full-generate-key");
      writeln();
      writeln("Use the same email: ", identity.email);
    }
  }

  proc handleGPGVerify() {
    printDebug("Verifying GPG keys with providers");

    writeln(bold("Verifying GPG registration..."));
    writeln();

    const identities = Identity.listIdentities();

    for identity in identities {
      if !identity.gpg.isConfigured() {
        continue;
      }

      write("  ", identity.name, " (", identity.gpg.keyId, ")... ");

      const result = GPG.verifyKeyWithProvider(identity);
      if result.verified {
        writeln(green("registered"));
      } else {
        writeln(yellow("not verified"));
        if verbose {
          writeln("    ", result.message);
        }
        writeln("    Add at: ", GPG.getGPGSettingsURL(identity));
      }
    }
  }

  // Handle 'debug' subcommands
  proc handleDebug(args: list(string)) {
    if args.size < 1 {
      printError("Missing subcommand");
      writeln("Usage: remote-juggler debug <ssh-config|git-config|keychain>");
      return;
    }

    const subcommand = args[0];

    select subcommand {
      when "ssh-config", "ssh" do handleDebugSSH();
      when "git-config", "gitconfig", "git" do handleDebugGit();
      when "keychain" do handleDebugKeychain();
      otherwise {
        printError("Unknown debug subcommand: " + subcommand);
        writeln("Available: ssh-config, git-config, keychain");
      }
    }
  }

  proc handleDebugSSH() {
    printDebug("Dumping SSH config");

    writeln(bold("Parsed SSH Configuration:"));
    writeln();

    const sshConfigPath = expandPath("~/.ssh/config");
    writeln("Source: ", sshConfigPath);
    writeln();

    const hosts = Config.parseSSHConfig(sshConfigPath);

    for host in hosts {
      writeln(bold("Host "), host.host);
      writeln("  Hostname:     ", host.hostname);
      writeln("  User:         ", host.user);
      writeln("  IdentityFile: ", host.identityFile);
      if host.port != 22 {
        writeln("  Port:         ", host.port);
      }
      if host.proxyJump != "" {
        writeln("  ProxyJump:    ", host.proxyJump);
      }
      writeln();
    }
  }

  proc handleDebugGit() {
    printDebug("Dumping gitconfig");

    writeln(bold("Parsed Git Configuration:"));
    writeln();

    const gitConfigPath = expandPath("~/.gitconfig");
    writeln("Source: ", gitConfigPath);
    writeln();

    const rewrites = Config.parseGitConfigRewrites(gitConfigPath);

    writeln(bold("URL Rewrites (insteadOf):"));
    for rewrite in rewrites {
      writeln("  ", rewrite.fromURL, " -> ", rewrite.toURL);
    }
    writeln();

    // Also show user config
    writeln(bold("User Configuration:"));
    const userConfig = Config.parseGitUserConfig(gitConfigPath);
    writeln("  name:  ", userConfig.name);
    writeln("  email: ", userConfig.email);
    if userConfig.signingKey != "" {
      writeln("  signingKey: ", userConfig.signingKey);
    }
  }

  proc handleDebugKeychain() {
    printDebug("Testing keychain access");

    writeln(bold("Keychain Status:"));
    writeln();

    if !Keychain.isDarwin() {
      writeln(yellow("Platform: "), "Not macOS - keychain not available");
      return;
    }

    writeln(green("Platform: "), "macOS - keychain available");
    writeln();

    // Test storing and retrieving
    const testProvider = "test";
    const testIdentity = "test-identity";
    const testAccount = "test-account";
    const testToken = "test-token-" + Time.timeSinceEpoch().totalSeconds():string;

    write("  Store test token... ");
    const storeResult = Keychain.storeToken(testProvider, testIdentity, testAccount, testToken);
    if storeResult {
      writeln(green("OK"));
    } else {
      writeln(red("FAILED"));
      return;
    }

    write("  Retrieve test token... ");
    const (retrieveOk, retrieved) = Keychain.retrieveToken(testProvider, testIdentity, testAccount);
    if retrieveOk && retrieved == testToken {
      writeln(green("OK"));
    } else {
      writeln(red("FAILED"));
    }

    write("  Delete test token... ");
    const deleteResult = Keychain.deleteToken(testProvider, testIdentity, testAccount);
    if deleteResult {
      writeln(green("OK"));
    } else {
      writeln(red("FAILED"));
    }
  }

  // Helper to expand ~ in paths
  proc expandPath(path: string): string {
    if path.startsWith("~") {
      const home = Core.getEnvVar("HOME");
      return home + path[1..];
    }
    return path;
  }

  // ==========================================================================
  // Main Entry Point
  // ==========================================================================

  proc main(args: [] string) {
    // Handle server modes first (these don't return)
    if mode == "mcp" {
      printDebug("Starting MCP server");
      MCP.runMCPServer();
      return;
    }

    if mode == "acp" {
      printDebug("Starting ACP server");
      ACP.runACPServer();
      return;
    }

    // CLI mode
    printDebug("CLI mode, args: " + args.size:string);

    // Handle help flag
    if help {
      printUsage();
      return;
    }

    // Handle no arguments (show status)
    if args.size < 2 {
      handleStatus();
      return;
    }

    // Parse command (args[0] is program name, args[1] is command)
    const command = args[1];

    // Convert remaining arguments to list for handler functions
    var subArgs = new list(string);
    for i in 2..<args.size {
      subArgs.pushBack(args[i]);
    }

    // Route to command handler
    select command {
      when "list", "ls" do handleList(subArgs);
      when "detect" do handleDetect(subArgs);
      when "switch", "to" do handleSwitch(subArgs);
      when "validate", "test" do handleValidate(subArgs);
      when "verify" do handleVerify(subArgs);
      when "status" do handleStatus();
      when "config" do handleConfig(subArgs);
      when "token" do handleToken(subArgs);
      when "gpg" do handleGPG(subArgs);
      when "debug" do handleDebug(subArgs);
      when "help", "--help", "-h" do printUsage();
      when "version", "--version", "-v" {
        writeln("RemoteJuggler v", Core.VERSION);
      }
      otherwise {
        printError("Unknown command: " + command);
        writeln();
        writeln("Run 'remote-juggler help' for usage information.");
      }
    }
  }
}
