/*
  Config Module
  =============

  SSH and Git configuration file parsing for RemoteJuggler.

  This module provides parsers for system configuration files that define
  SSH hosts and git URL rewrite rules. These are synchronized into
  RemoteJuggler's managed configuration blocks.

  **SSH Config Parsing:**

  Parses ``~/.ssh/config`` to extract Host definitions with:
  - Host (alias)
  - HostName (actual server)
  - IdentityFile (SSH key path)
  - User (SSH user)
  - IdentitiesOnly (strict key usage)

  **Git Config Parsing:**

  Parses ``~/.gitconfig`` to extract:
  - ``[url "..."]`` sections with ``insteadOf`` rules
  - User name/email defaults

  :author: RemoteJuggler Team
  :version: 2.0.0
*/
prototype module Config {
  use IO;
  use List;
  use Map;
  use Regex;
  public use super.Core;

  // =========================================================================
  // SSH Config Types
  // =========================================================================

  /*
    SSH host configuration entry.

    Represents a single Host block from ~/.ssh/config.

    :var host: Host alias (used in SSH commands)
    :var hostname: Actual server hostname or IP
    :var identityFile: Path to SSH private key
    :var user: SSH username (default: git)
    :var identitiesOnly: Only use specified identity file
    :var port: SSH port (default: 22)
    :var proxyJump: Jump host for tunneling
  */
  record SSHHost {
    var host: string = "";
    var hostname: string = "";
    var identityFile: string = "";
    var user: string = "git";
    var identitiesOnly: bool = false;
    var port: int = 22;
    var proxyJump: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.host = "";
      this.hostname = "";
      this.identityFile = "";
      this.user = "git";
      this.identitiesOnly = false;
      this.port = 22;
      this.proxyJump = "";
    }

    /*
      Initialize with host alias.

      :arg host: SSH host alias
    */
    proc init(host: string) {
      this.host = host;
      this.hostname = "";
      this.identityFile = "";
      this.user = "git";
      this.identitiesOnly = false;
      this.port = 22;
      this.proxyJump = "";
    }

    /*
      Initialize with essential fields.

      :arg host: SSH host alias
      :arg hostname: Actual server hostname
      :arg identityFile: Path to SSH key
      :arg user: SSH username
    */
    proc init(host: string, hostname: string, identityFile: string,
              user: string = "git") {
      this.host = host;
      this.hostname = hostname;
      this.identityFile = identityFile;
      this.user = user;
      this.identitiesOnly = false;
      this.port = 22;
      this.proxyJump = "";
    }

    /*
      Check if this host entry is valid.

      :returns: true if host alias is set
    */
    proc isValid(): bool {
      return host != "" && host != "*";
    }

    /*
      Check if this appears to be a git hosting service.

      Detects common git hosting hostnames.

      :returns: true if hostname suggests git service
    */
    proc isGitHost(): bool {
      if hostname == "" then return false;
      const lower = hostname.toLower();
      return lower.find("gitlab") >= 0 ||
             lower.find("github") >= 0 ||
             lower.find("bitbucket") >= 0 ||
             lower.find("git.") >= 0 ||
             lower.find(".git") >= 0 ||
             user == "git";
    }

    /*
      Infer the git provider from hostname.

      :returns: Provider enum based on hostname analysis
    */
    proc inferProvider(): Provider {
      if hostname == "" then return Provider.Custom;
      const lower = hostname.toLower();
      if lower.find("gitlab") >= 0 then return Provider.GitLab;
      if lower.find("github") >= 0 then return Provider.GitHub;
      if lower.find("bitbucket") >= 0 then return Provider.Bitbucket;
      return Provider.Custom;
    }
  }

  // =========================================================================
  // Git Config Types
  // =========================================================================

  /*
    URL rewrite rule from gitconfig.

    Represents a ``[url "to"]`` section with ``insteadOf = from`` rule.

    :var fromURL: Original URL pattern to match
    :var toURL: Replacement URL pattern
  */
  record URLRewrite {
    var fromURL: string = "";
    var toURL: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.fromURL = "";
      this.toURL = "";
    }

    /*
      Initialize with both URLs.

      :arg fromURL: Original URL pattern
      :arg toURL: Replacement URL pattern
    */
    proc init(fromURL: string, toURL: string) {
      this.fromURL = fromURL;
      this.toURL = toURL;
    }

    /*
      Check if this rewrite rule is valid.

      :returns: true if both URLs are set
    */
    proc isValid(): bool {
      return fromURL != "" && toURL != "";
    }

    /*
      Check if this rule applies to a given URL.

      :arg url: URL to check
      :returns: true if URL starts with fromURL pattern
    */
    proc appliesTo(url: string): bool {
      return url.startsWith(fromURL);
    }

    /*
      Apply this rewrite rule to a URL.

      :arg url: URL to transform
      :returns: Transformed URL if rule applies, original otherwise
    */
    proc apply(url: string): string {
      if appliesTo(url) {
        return toURL + url[fromURL.size..];
      }
      return url;
    }
  }

  /*
    Git configuration data.

    Aggregates parsed gitconfig values relevant to RemoteJuggler.

    :var userName: Default user.name
    :var userEmail: Default user.email
    :var signingKey: Default user.signingkey
    :var gpgSign: Default commit.gpgsign
    :var urlRewrites: List of URL rewrite rules
  */
  record GitConfigData {
    var userName: string = "";
    var userEmail: string = "";
    var signingKey: string = "";
    var gpgSign: bool = false;
    var urlRewrites: list(URLRewrite);

    /*
      Initialize with default values.
    */
    proc init() {
      this.userName = "";
      this.userEmail = "";
      this.signingKey = "";
      this.gpgSign = false;
      this.urlRewrites = new list(URLRewrite);
    }

    /*
      Apply all rewrite rules to a URL.

      Applies rules in order until one matches.

      :arg url: URL to transform
      :returns: Transformed URL
    */
    proc rewriteURL(url: string): string {
      for rule in urlRewrites {
        if rule.appliesTo(url) {
          return rule.apply(url);
        }
      }
      return url;
    }
  }

  // =========================================================================
  // SSH Config Parser
  // =========================================================================

  /*
    Parse SSH config file.

    Reads and parses ``~/.ssh/config`` (or specified path) into a list
    of SSHHost records. Handles multi-line Host blocks and common
    directives.

    **Supported Directives:**
    - Host
    - HostName
    - IdentityFile
    - User
    - IdentitiesOnly
    - Port
    - ProxyJump

    :arg path: Path to SSH config file (default: ~/.ssh/config)
    :returns: List of parsed SSHHost entries
    :throws: FileNotFoundError if config doesn't exist

    Example::

      var hosts = parseSSHConfig("~/.ssh/config");
      for h in hosts {
        writeln(h.host, " -> ", h.hostname);
      }
  */
  proc parseSSHConfig(path: string = "~/.ssh/config"): list(SSHHost) throws {
    var hosts: list(SSHHost);
    const expandedPath = expandTilde(path);

    verboseLog("Parsing SSH config: ", expandedPath);

    var f: file;
    try {
      f = open(expandedPath, ioMode.r);
    } catch e: FileNotFoundError {
      verboseLog("SSH config not found: ", expandedPath);
      return hosts;
    } catch e {
      verboseLog("Error opening SSH config: ", e.message());
      return hosts;
    }
    defer { try! f.close(); }

    var reader = f.reader(locking=false);
    defer { try! reader.close(); }

    var currentHost: SSHHost;
    var inHostBlock = false;

    for line in reader.lines() {
      const trimmed = line.strip();

      // Skip empty lines and comments
      if trimmed == "" || trimmed.startsWith("#") {
        continue;
      }

      // Parse directive and value
      const (directive, value) = parseSSHDirective(trimmed);

      if directive.toLower() == "host" {
        // Save previous host if valid
        if inHostBlock && currentHost.isValid() {
          hosts.pushBack(currentHost);
        }

        // Start new host block
        currentHost = new SSHHost(value);
        inHostBlock = true;
        verboseLog("  Found Host: ", value);
      }
      else if inHostBlock {
        // Parse directives within host block
        select directive.toLower() {
          when "hostname" {
            currentHost.hostname = value;
          }
          when "identityfile" {
            currentHost.identityFile = expandTilde(value);
          }
          when "user" {
            currentHost.user = value;
          }
          when "identitiesonly" {
            currentHost.identitiesOnly = value.toLower() == "yes";
          }
          when "port" {
            try {
              currentHost.port = value:int;
            } catch {
              currentHost.port = 22;
            }
          }
          when "proxyjump" {
            currentHost.proxyJump = value;
          }
        }
      }
    }

    // Save last host
    if inHostBlock && currentHost.isValid() {
      hosts.pushBack(currentHost);
    }

    verboseLog("  Parsed ", hosts.size, " SSH hosts");
    return hosts;
  }

  /*
    Parse a single SSH config directive line.

    Handles both space-separated and equals-separated formats:
    - ``HostName gitlab.com``
    - ``HostName=gitlab.com``

    :arg line: Trimmed config line
    :returns: (directive, value) tuple
  */
  proc parseSSHDirective(line: string): (string, string) {
    // Handle equals format: Key=Value
    const eqIdx = line.find("=");
    if eqIdx >= 0 {
      const key = line[0:byteIndex..<eqIdx].strip();
      const value = line[eqIdx+1..].strip();
      return (key, value);
    }

    // Handle space format: Key Value
    var parts: list(string);
    var inQuote = false;
    var current = "";

    for ch in line {
      if ch == '"' {
        inQuote = !inQuote;
      } else if (ch == ' ' || ch == '\t') && !inQuote {
        if current != "" {
          parts.pushBack(current);
          current = "";
        }
      } else {
        current += ch;
      }
    }
    if current != "" {
      parts.pushBack(current);
    }

    if parts.size >= 2 {
      // Rejoin all parts after first as value (handles paths with spaces)
      var value = "";
      for i in 1..<parts.size {
        if i > 1 then value += " ";
        value += parts[i];
      }
      return (parts[0], value);
    } else if parts.size == 1 {
      return (parts[0], "");
    }

    return ("", "");
  }

  // =========================================================================
  // Git Config Parser
  // =========================================================================

  /*
    Parse git config file.

    Reads and parses ``~/.gitconfig`` (or specified path) into a
    GitConfigData record. Extracts user info and URL rewrite rules.

    **Parsed Sections:**
    - ``[user]`` - name, email, signingkey
    - ``[commit]`` - gpgsign
    - ``[url "..."]`` - insteadOf rules

    :arg path: Path to gitconfig file (default: ~/.gitconfig)
    :returns: Parsed GitConfigData
    :throws: FileNotFoundError if config doesn't exist

    Example::

      var cfg = parseGitConfig("~/.gitconfig");
      writeln("User: ", gitCfg.userName, " <", gitCfg.userEmail, ">");
      for rule in gitCfg.urlRewrites {
        writeln("  ", rule.fromURL, " -> ", rule.toURL);
      }
  */
  proc parseGitConfig(path: string = "~/.gitconfig"): GitConfigData throws {
    var gitCfg: GitConfigData;
    const expandedPath = expandTilde(path);

    verboseLog("Parsing git config: ", expandedPath);

    var f: file;
    try {
      f = open(expandedPath, ioMode.r);
    } catch e: FileNotFoundError {
      verboseLog("Git config not found: ", expandedPath);
      return gitCfg;
    } catch e {
      verboseLog("Error opening git config: ", e.message());
      return gitCfg;
    }
    defer { try! f.close(); }

    var reader = f.reader(locking=false);
    defer { try! reader.close(); }

    var currentSection = "";
    var currentSubsection = "";  // For [url "..."] sections

    for line in reader.lines() {
      const trimmed = line.strip();

      // Skip empty lines and comments
      if trimmed == "" || trimmed.startsWith("#") || trimmed.startsWith(";") {
        continue;
      }

      // Check for section header
      if trimmed.startsWith("[") {
        const (section, subsection) = parseGitSection(trimmed);
        currentSection = section.toLower();
        currentSubsection = subsection;
        verboseLog("  Section: [", currentSection, "] sub=", currentSubsection);
        continue;
      }

      // Parse key=value within section
      const (key, value) = parseGitKeyValue(trimmed);
      if key == "" then continue;

      select currentSection {
        when "user" {
          select key.toLower() {
            when "name" do gitCfg.userName = value;
            when "email" do gitCfg.userEmail = value;
            when "signingkey" do gitCfg.signingKey = value;
          }
        }
        when "commit" {
          if key.toLower() == "gpgsign" {
            gitCfg.gpgSign = value.toLower() == "true";
          }
        }
        when "url" {
          // URL rewrite section: [url "replacement"] insteadOf = original
          if key.toLower() == "insteadof" && currentSubsection != "" {
            var rewrite = new URLRewrite(value, currentSubsection);
            gitCfg.urlRewrites.pushBack(rewrite);
            verboseLog("    URL rewrite: ", value, " -> ", currentSubsection);
          }
        }
      }
    }

    verboseLog("  Parsed ", gitCfg.urlRewrites.size, " URL rewrites");
    return gitCfg;
  }

  /*
    Parse git config section header.

    Handles both simple and subsection formats:
    - ``[section]`` -> ("section", "")
    - ``[section "subsection"]`` -> ("section", "subsection")

    :arg line: Section header line (including brackets)
    :returns: (section, subsection) tuple
  */
  proc parseGitSection(line: string): (string, string) {
    // Remove brackets
    var content = line;
    if content.startsWith("[") then content = content[1..];
    if content.endsWith("]") then content = content[..<content.size-1];
    content = content.strip();

    // Check for subsection: section "subsection"
    const quoteStart = content.find("\"");
    if quoteStart >= 0 {
      const section = content[0:byteIndex..<quoteStart].strip();
      var subsection = content[quoteStart+1..];
      // Remove trailing quote
      const quoteEnd = subsection.find("\"");
      if quoteEnd >= 0 {
        subsection = subsection[0:byteIndex..<quoteEnd];
      }
      return (section, subsection);
    }

    return (content, "");
  }

  /*
    Parse git config key-value line.

    Handles various formats:
    - ``key = value``
    - ``key=value``
    - ``key = "value with spaces"``

    :arg line: Config line
    :returns: (key, value) tuple, stripped of quotes
  */
  proc parseGitKeyValue(line: string): (string, string) {
    const eqIdx = line.find("=");
    if eqIdx < 0 then return ("", "");

    const key = line[0:byteIndex..<eqIdx].strip();
    var value = line[eqIdx+1..].strip();

    // Remove surrounding quotes
    if value.startsWith("\"") && value.endsWith("\"") && value.size >= 2 {
      value = value[1..<value.size-1];
    }

    return (key, value);
  }

  /*
    Extract URL rewrites from git config.

    Convenience function that parses gitconfig and returns only
    the URL rewrite rules.

    :arg path: Path to gitconfig (default: ~/.gitconfig)
    :returns: List of URLRewrite records
  */
  proc parseURLRewrites(path: string = "~/.gitconfig"): list(URLRewrite) throws {
    const gitCfg = parseGitConfig(path);
    return gitCfg.urlRewrites;
  }

  /*
    Git user configuration subset.
    Contains just the user-related settings.
  */
  record GitUserConfig {
    var name: string = "";
    var email: string = "";
    var signingKey: string = "";

    proc init() {
      this.name = "";
      this.email = "";
      this.signingKey = "";
    }
  }

  /*
    Parse URL rewrites from git config.
    Convenience function with error handling.

    :arg path: Path to gitconfig (default: ~/.gitconfig)
    :returns: List of URLRewrite records (empty on error)
  */
  proc parseGitConfigRewrites(path: string = "~/.gitconfig"): list(URLRewrite) {
    try {
      const gitCfg = parseGitConfig(path);
      return gitCfg.urlRewrites;
    } catch {
      return new list(URLRewrite);
    }
  }

  /*
    Parse user configuration from git config.
    Extracts name, email, and signing key.

    :arg path: Path to gitconfig (default: ~/.gitconfig)
    :returns: GitUserConfig record
  */
  proc parseGitUserConfig(path: string = "~/.gitconfig"): GitUserConfig {
    var userCfg = new GitUserConfig();

    try {
      const gitCfg = parseGitConfig(path);
      userCfg.name = gitCfg.userName;
      userCfg.email = gitCfg.userEmail;
      userCfg.signingKey = gitCfg.signingKey;
    } catch {
      // Return empty config on error
    }

    return userCfg;
  }

  // =========================================================================
  // Identity Detection Helpers
  // =========================================================================

  /*
    Find SSH host by alias.

    :arg hosts: List of parsed SSH hosts
    :arg alias: Host alias to find
    :returns: SSHHost if found, empty SSHHost otherwise
  */
  proc findSSHHost(hosts: list(SSHHost), alias: string): SSHHost {
    for h in hosts {
      if h.host == alias then return h;
    }
    return new SSHHost();
  }

  /*
    Find SSH hosts for a hostname.

    Returns all SSH hosts that map to a given actual hostname
    (useful when multiple identities point to same server).

    :arg hosts: List of parsed SSH hosts
    :arg hostname: Actual hostname to match
    :returns: List of matching SSHHost entries
  */
  proc findSSHHostsByHostname(hosts: list(SSHHost),
                               hostname: string): list(SSHHost) {
    var result: list(SSHHost);
    for h in hosts {
      if h.hostname == hostname {
        result.pushBack(h);
      }
    }
    return result;
  }

  /*
    Extract host alias from git remote URL.

    Parses various git URL formats:
    - ``git@host:path/repo.git`` -> "host"
    - ``ssh://git@host/path/repo.git`` -> "host"
    - ``https://host/path/repo.git`` -> "host"

    :arg remoteURL: Git remote URL
    :returns: Host or alias portion of URL
  */
  proc extractHostFromRemote(remoteURL: string): string {
    var url = remoteURL;

    // Handle SSH format: git@host:path
    if url.find("@") >= 0 && url.find(":") > url.find("@") {
      const atIdx = url.find("@");
      const colonIdx = url.find(":");
      if colonIdx > atIdx {
        return url[atIdx+1..<colonIdx];
      }
    }

    // Handle ssh:// format
    if url.startsWith("ssh://") {
      url = url["ssh://".size..];
      if url.find("@") >= 0 {
        url = url[url.find("@")+1..];
      }
      const slashIdx = url.find("/");
      if slashIdx >= 0 {
        return url[0:byteIndex..<slashIdx];
      }
      return url;
    }

    // Handle https:// format
    if url.startsWith("https://") || url.startsWith("http://") {
      const protoEnd = url.find("://");
      url = url[protoEnd+3..];
      const slashIdx = url.find("/");
      if slashIdx >= 0 {
        return url[0:byteIndex..<slashIdx];
      }
      return url;
    }

    return url;
  }

  /*
    Extract organization/path from git remote URL.

    Parses repository path from various git URL formats.

    :arg remoteURL: Git remote URL
    :returns: Organization/path portion (e.g., "tinyland/projects")
  */
  proc extractPathFromRemote(remoteURL: string): string {
    var url = remoteURL;

    // Handle SSH format: git@host:path/repo.git
    if url.find(":") >= 0 && !url.startsWith("http") && !url.startsWith("ssh:") {
      const colonIdx = url.find(":");
      url = url[colonIdx+1..];
    }

    // Handle protocol prefixes
    if url.startsWith("ssh://") || url.startsWith("https://") ||
       url.startsWith("http://") {
      const protoEnd = url.find("://") + 3;
      const slashIdx = url.find("/", protoEnd..);
      if slashIdx >= 0 {
        url = url[slashIdx+1..];
      }
    }

    // Remove .git suffix
    if url.endsWith(".git") {
      url = url[..<url.size-4];
    }

    // Return path without repo name (just org/group)
    const lastSlash = url.rfind("/");
    if lastSlash >= 0 {
      return url[0:byteIndex..<lastSlash];
    }

    return "";
  }

  /*
    Match SSH host to a remote URL.

    Finds the SSH host that corresponds to a git remote URL,
    applying URL rewrite rules if necessary.

    :arg hosts: List of parsed SSH hosts
    :arg rewrites: URL rewrite rules from gitconfig
    :arg remoteURL: Git remote URL to match
    :returns: Matching SSHHost or empty SSHHost if not found
  */
  proc matchSSHHostToRemote(hosts: list(SSHHost),
                            rewrites: list(URLRewrite),
                            remoteURL: string): SSHHost {
    // First, try direct host match
    const directHost = extractHostFromRemote(remoteURL);
    for h in hosts {
      if h.host == directHost then return h;
    }

    // Try hostname match
    for h in hosts {
      if h.hostname == directHost then return h;
    }

    // Apply rewrites and try again
    for rule in rewrites {
      if rule.appliesTo(remoteURL) {
        const rewritten = rule.apply(remoteURL);
        const rewrittenHost = extractHostFromRemote(rewritten);
        for h in hosts {
          if h.host == rewrittenHost then return h;
        }
      }
    }

    return new SSHHost();
  }
}
