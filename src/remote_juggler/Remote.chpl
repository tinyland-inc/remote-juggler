/*
  Remote Module
  =============

  Git remote operations for RemoteJuggler.

  This module provides comprehensive git remote management functionality
  including remote listing, URL parsing, modification operations, branch
  tracking, SSH connectivity validation, and remote URL transformation
  for identity switching.

  **Key URL Patterns Supported:**

  - ``git@gitlab-personal:tinyland/projects/repo.git`` - SSH with host alias
  - ``git@gitlab.com:org/repo.git`` - Standard SSH
  - ``git@github.com:user/repo.git`` - GitHub SSH
  - ``https://gitlab.com/org/repo.git`` - HTTPS
  - ``ssh://git@gitlab.com/org/repo.git`` - Explicit SSH protocol
  - ``ssh://git@gitlab.com:22/org/repo.git`` - SSH with port

  **Example Usage:**

  .. code-block:: chapel

     use Remote;

     // List all remotes
     const remotes = listRemotes(".");
     for remote in remotes {
       writeln(remote.name, ": ", remote.fetchURL);
     }

     // Parse a remote URL
     const parsed = parseRemoteURL("git@gitlab-personal:tinyland/repo.git");
     if parsed.valid {
       writeln("Provider: ", parsed.provider);
       writeln("Host: ", parsed.host);
       writeln("Repo: ", parsed.repoPath);
     }

     // Transform URL for identity
     var identity = new GitIdentity();
     identity.host = "gitlab-work";
     const newURL = transformRemoteForIdentity(
       "git@gitlab.com:org/repo.git", identity);
     // Result: git@gitlab-work:org/repo.git

  :author: RemoteJuggler Team
  :version: 2.0.0
  :license: MIT
*/
prototype module Remote {
  use Subprocess;
  use IO;
  use List;
  use Map;

  // Import types from Core module
  public use super.Core only Provider, GitIdentity, providerToString, stringToProvider,
                       verboseLog;

  //============================================================================
  // Remote Information Records
  //============================================================================

  /*
    Git remote record.

    Represents a git remote with separate fetch and push URLs.
    Push URLs can differ from fetch URLs in fork workflows.

    :var name: Remote name (e.g., "origin", "upstream", "fork")
    :var fetchURL: URL used for git fetch/pull operations
    :var pushURL: URL used for git push operations
  */
  record GitRemote {
    var name: string = "";
    var fetchURL: string = "";
    var pushURL: string = "";

    /*
      Default initializer.
    */
    proc init() {
      this.name = "";
      this.fetchURL = "";
      this.pushURL = "";
    }

    /*
      Initialize with all values.

      :arg name: Remote name
      :arg fetchURL: Fetch URL
      :arg pushURL: Push URL (defaults to fetchURL if empty)
    */
    proc init(name: string, fetchURL: string = "", pushURL: string = "") {
      this.name = name;
      this.fetchURL = fetchURL;
      this.pushURL = if pushURL == "" then fetchURL else pushURL;
    }

    /*
      Get the primary URL (fetch URL, or push URL if fetch is empty).

      :returns: Primary URL for this remote
    */
    proc url(): string {
      return if fetchURL != "" then fetchURL else pushURL;
    }

    /*
      Check if remote has separate push URL.

      :returns: true if push URL differs from fetch URL
    */
    proc hasSeparatePushURL(): bool {
      return pushURL != "" && pushURL != fetchURL;
    }
  }

  /*
    Result of parsing a remote URL.

    Contains all components extracted from a git remote URL,
    including detected provider and parsed path components.

    :var valid: Whether URL parsing succeeded
    :var provider: Detected provider (GitLab, GitHub, Bitbucket, Custom)
    :var protocol: Protocol used (ssh, https, http, git)
    :var host: SSH host alias or hostname as specified in URL
    :var hostname: Resolved hostname (same as host for HTTPS)
    :var port: Port number if specified (0 for default)
    :var orgPath: First path component (organization/user)
    :var repoPath: Full repository path (org/subgroup/repo)
    :var repoName: Repository name without .git suffix
  */
  record RemoteParseResult {
    var valid: bool = false;
    var provider: Provider = Provider.Custom;
    var protocol: string = "";
    var host: string = "";
    var hostname: string = "";
    var port: int = 0;
    var orgPath: string = "";
    var repoPath: string = "";
    var repoName: string = "";

    /*
      Default initializer (invalid result).
    */
    proc init() {
      this.valid = false;
      this.provider = Provider.Custom;
      this.protocol = "";
      this.host = "";
      this.hostname = "";
      this.port = 0;
      this.orgPath = "";
      this.repoPath = "";
      this.repoName = "";
    }

    /*
      Initialize with validity flag.

      :arg valid: Whether parsing succeeded
    */
    proc init(valid: bool) {
      this.valid = valid;
      this.provider = Provider.Custom;
      this.protocol = "";
      this.host = "";
      this.hostname = "";
      this.port = 0;
      this.orgPath = "";
      this.repoPath = "";
      this.repoName = "";
    }

    /*
      Initialize with validity and protocol.

      :arg valid: Whether parsing succeeded
      :arg protocol: Protocol string
    */
    proc init(valid: bool, protocol: string) {
      this.valid = valid;
      this.provider = Provider.Custom;
      this.protocol = protocol;
      this.host = "";
      this.hostname = "";
      this.port = 0;
      this.orgPath = "";
      this.repoPath = "";
      this.repoName = "";
    }

    /*
      Check if this is an SSH-based URL.

      :returns: true for ssh:// or SCP-style URLs
    */
    proc isSSH(): bool {
      return protocol == "ssh";
    }

    /*
      Check if this is an HTTPS URL.

      :returns: true for https:// URLs
    */
    proc isHTTPS(): bool {
      return protocol == "https" || protocol == "http";
    }

    /*
      Get the full clone URL reconstructed from components.

      :returns: Reconstructed URL in SCP-style SSH format
    */
    proc toSSHURL(): string {
      return "git@" + host + ":" + repoPath + ".git";
    }

    /*
      Get HTTPS version of this URL.

      :returns: HTTPS URL
    */
    proc toHTTPSURL(): string {
      return "https://" + hostname + "/" + repoPath + ".git";
    }
  }

  /*
    Result of a remote operation.

    Generic result type for remote modification operations.

    :var success: Whether operation succeeded
    :var message: Human-readable status message
    :var errorCode: Error code (0 for success)
  */
  record RemoteOpResult {
    var success: bool = false;
    var message: string = "";
    var errorCode: int = 0;

    /*
      Default initializer.
    */
    proc init() {
      this.success = false;
      this.message = "";
      this.errorCode = 0;
    }

    /*
      Initialize a success result.

      :arg message: Success message
    */
    proc init(message: string) {
      this.success = true;
      this.message = message;
      this.errorCode = 0;
    }

    /*
      Initialize with explicit success flag.

      :arg success: Whether operation succeeded
      :arg message: Status message
      :arg errorCode: Error code
    */
    proc init(success: bool, message: string, errorCode: int = 0) {
      this.success = success;
      this.message = message;
      this.errorCode = errorCode;
    }
  }

  /*
    SSH connectivity test result.

    Detailed result from SSH connectivity validation.

    :var connected: Whether SSH connection succeeded
    :var authenticated: Whether authentication succeeded
    :var username: Username returned by server (if any)
    :var message: Server welcome message or error
  */
  record SSHTestResult {
    var connected: bool = false;
    var authenticated: bool = false;
    var username: string = "";
    var message: string = "";

    proc init() {
      this.connected = false;
      this.authenticated = false;
      this.username = "";
      this.message = "";
    }

    proc init(connected: bool, authenticated: bool,
              username: string = "", message: string = "") {
      this.connected = connected;
      this.authenticated = authenticated;
      this.username = username;
      this.message = message;
    }
  }

  //============================================================================
  // URL Parsing Constants and Patterns
  //============================================================================

  // Common git hosting providers and their hostnames
  private const GITLAB_HOSTS = ["gitlab.com", "gitlab"];
  private const GITHUB_HOSTS = ["github.com", "github"];
  private const BITBUCKET_HOSTS = ["bitbucket.org", "bitbucket"];

  //============================================================================
  // Remote Listing and Retrieval
  //============================================================================

  /*
   * List all remotes in a git repository
   *
   * @param repoPath Path to the git repository (default: current directory)
   * @return List of GitRemote records
   */
  proc listRemotes(repoPath: string = "."): list(GitRemote) {
    var remotes: list(GitRemote);
    var remoteMap: map(string, GitRemote);

    // Run git remote -v to get verbose remote listing
    var sub = spawn(["git", "-C", repoPath, "remote", "-v"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    // Read all output
    var line: string;
    while sub.stdout.readLine(line) {
      // Parse lines like: "origin\tgit@github.com:user/repo.git (fetch)"
      // Format: <name>\t<url> (<type>)
      const trimmed = line.strip();
      if trimmed.isEmpty() then continue;

      // Split by tab
      const tabIdx = trimmed.find("\t");
      if tabIdx == -1 then continue;

      const remoteName = trimmed[..tabIdx-1];
      const remainder = trimmed[tabIdx+1..];

      // Extract URL and type (fetch/push)
      const parenIdx = remainder.rfind("(");
      if parenIdx == -1 then continue;

      const url = remainder[..parenIdx-1].strip();
      const typeStr = remainder[parenIdx+1..].strip();
      const isFetch = typeStr.startsWith("fetch");
      const isPush = typeStr.startsWith("push");

      // Update or create remote entry
      if remoteMap.contains(remoteName) {
        var remote = remoteMap[remoteName];
        if isFetch then remote.fetchURL = url;
        if isPush then remote.pushURL = url;
        remoteMap[remoteName] = remote;
      } else {
        var remote = new GitRemote(
          name = remoteName,
          fetchURL = if isFetch then url else "",
          pushURL = if isPush then url else ""
        );
        remoteMap.add(remoteName, remote);
      }
    }

    sub.wait();

    // Convert map to list
    for name in remoteMap.keys() {
      remotes.pushBack(remoteMap[name]);
    }

    return remotes;
  }

  /*
   * Get a specific remote by name
   *
   * @param repoPath Path to the git repository
   * @param name Remote name to retrieve
   * @return Tuple of (found: bool, remote: GitRemote)
   */
  proc getRemote(repoPath: string, name: string): (bool, GitRemote) {
    const remotes = listRemotes(repoPath);

    for remote in remotes {
      if remote.name == name {
        return (true, remote);
      }
    }

    return (false, new GitRemote());
  }

  //============================================================================
  // URL Parsing
  //============================================================================

  /*
   * Parse a git remote URL into its components
   *
   * Handles multiple URL formats:
   *   - git@gitlab-personal:tinyland/projects/repo.git  (SSH with host alias)
   *   - git@gitlab.com:org/repo.git                     (SSH standard)
   *   - git@github.com:user/repo.git                    (GitHub SSH)
   *   - https://gitlab.com/org/repo.git                 (HTTPS)
   *   - https://github.com/user/repo.git                (GitHub HTTPS)
   *   - ssh://git@gitlab.com/org/repo.git               (SSH explicit)
   *   - ssh://git@gitlab.com:22/org/repo.git            (SSH with port)
   *
   * @param url The remote URL to parse
   * @return RemoteParseResult with parsed components
   */
  proc parseRemoteURL(url: string): RemoteParseResult {
    var result = new RemoteParseResult(valid = false);

    if url.isEmpty() {
      return result;
    }

    const trimmedURL = url.strip();

    // Try different URL patterns
    if trimmedURL.startsWith("https://") || trimmedURL.startsWith("http://") {
      return parseHTTPSURL(trimmedURL);
    } else if trimmedURL.startsWith("ssh://") {
      return parseExplicitSSHURL(trimmedURL);
    } else if trimmedURL.startsWith("git://") {
      return parseGitProtocolURL(trimmedURL);
    } else if trimmedURL.find("@") != -1 && trimmedURL.find(":") != -1 {
      // SCP-style SSH URL: git@host:path
      return parseSCPStyleURL(trimmedURL);
    }

    return result;
  }

  /*
   * Parse HTTPS URL format: https://hostname/org/repo.git
   */
  private proc parseHTTPSURL(url: string): RemoteParseResult {
    var result = new RemoteParseResult(valid = false, protocol = "https");

    // Remove protocol prefix
    var remainder: string;
    if url.startsWith("https://") {
      remainder = url[8..];
    } else if url.startsWith("http://") {
      remainder = url[7..];
      result.protocol = "http";
    } else {
      return result;
    }

    // Split host and path
    const slashIdx = remainder.find("/");
    if slashIdx == -1 {
      return result;
    }

    const hostPart = remainder[..slashIdx-1];
    var pathPart = remainder[slashIdx+1..];

    // Handle port in host
    const colonIdx = hostPart.find(":");
    if colonIdx != -1 {
      result.host = hostPart[..colonIdx-1];
      try {
        result.port = hostPart[colonIdx+1..]:int;
      } catch {
        result.port = 0;
      }
    } else {
      result.host = hostPart;
      result.port = 0;
    }
    result.hostname = result.host;

    // Remove .git suffix if present
    if pathPart.endsWith(".git") {
      pathPart = pathPart[..pathPart.size-5];
    }

    result.repoPath = pathPart;

    // Extract org and repo name
    const pathSlashIdx = pathPart.find("/");
    if pathSlashIdx != -1 {
      result.orgPath = pathPart[..pathSlashIdx-1];
      const lastSlash = pathPart.rfind("/");
      result.repoName = pathPart[lastSlash+1..];
    } else {
      result.orgPath = "";
      result.repoName = pathPart;
    }

    // Detect provider
    result.provider = detectProvider(result.hostname);
    result.valid = true;

    return result;
  }

  /*
   * Parse explicit SSH URL format: ssh://git@hostname[:port]/org/repo.git
   */
  private proc parseExplicitSSHURL(url: string): RemoteParseResult {
    var result = new RemoteParseResult(valid = false, protocol = "ssh");

    // Remove ssh:// prefix
    if !url.startsWith("ssh://") {
      return result;
    }
    var remainder = url[6..];

    // Extract user@ part
    const atIdx = remainder.find("@");
    if atIdx != -1 {
      remainder = remainder[atIdx+1..];
    }

    // Find path separator (first / after host)
    const slashIdx = remainder.find("/");
    if slashIdx == -1 {
      return result;
    }

    const hostPart = remainder[..slashIdx-1];
    var pathPart = remainder[slashIdx+1..];

    // Handle port in host
    const colonIdx = hostPart.find(":");
    if colonIdx != -1 {
      result.host = hostPart[..colonIdx-1];
      try {
        result.port = hostPart[colonIdx+1..]:int;
      } catch {
        result.port = 22;
      }
    } else {
      result.host = hostPart;
      result.port = 0;
    }
    result.hostname = result.host;

    // Remove .git suffix
    if pathPart.endsWith(".git") {
      pathPart = pathPart[..pathPart.size-5];
    }

    result.repoPath = pathPart;

    // Extract org and repo name
    const pathSlashIdx = pathPart.find("/");
    if pathSlashIdx != -1 {
      result.orgPath = pathPart[..pathSlashIdx-1];
      const lastSlash = pathPart.rfind("/");
      result.repoName = pathPart[lastSlash+1..];
    } else {
      result.orgPath = "";
      result.repoName = pathPart;
    }

    result.provider = detectProvider(result.hostname);
    result.valid = true;

    return result;
  }

  /*
   * Parse git:// protocol URL: git://hostname/org/repo.git
   */
  private proc parseGitProtocolURL(url: string): RemoteParseResult {
    var result = new RemoteParseResult(valid = false, protocol = "git");

    if !url.startsWith("git://") {
      return result;
    }
    var remainder = url[6..];

    const slashIdx = remainder.find("/");
    if slashIdx == -1 {
      return result;
    }

    result.host = remainder[..slashIdx-1];
    result.hostname = result.host;
    var pathPart = remainder[slashIdx+1..];

    if pathPart.endsWith(".git") {
      pathPart = pathPart[..pathPart.size-5];
    }

    result.repoPath = pathPart;

    const pathSlashIdx = pathPart.find("/");
    if pathSlashIdx != -1 {
      result.orgPath = pathPart[..pathSlashIdx-1];
      const lastSlash = pathPart.rfind("/");
      result.repoName = pathPart[lastSlash+1..];
    } else {
      result.orgPath = "";
      result.repoName = pathPart;
    }

    result.provider = detectProvider(result.hostname);
    result.valid = true;

    return result;
  }

  /*
   * Parse SCP-style SSH URL: git@host:org/repo.git
   * This is the most common SSH format
   */
  private proc parseSCPStyleURL(url: string): RemoteParseResult {
    var result = new RemoteParseResult(valid = false, protocol = "ssh");

    // Find @ and : separators
    const atIdx = url.find("@");
    const colonIdx = url.find(":");

    if atIdx == -1 || colonIdx == -1 || colonIdx < atIdx {
      return result;
    }

    // Extract host (between @ and :)
    result.host = url[atIdx+1..colonIdx-1];
    result.hostname = result.host;  // May be alias, resolved later by caller

    // Extract path (after :)
    var pathPart = url[colonIdx+1..];

    // Remove .git suffix
    if pathPart.endsWith(".git") {
      pathPart = pathPart[..pathPart.size-5];
    }

    result.repoPath = pathPart;

    // Extract org and repo name
    const slashIdx = pathPart.find("/");
    if slashIdx != -1 {
      result.orgPath = pathPart[..slashIdx-1];
      const lastSlash = pathPart.rfind("/");
      result.repoName = pathPart[lastSlash+1..];
    } else {
      result.orgPath = "";
      result.repoName = pathPart;
    }

    // Detect provider from host
    result.provider = detectProvider(result.host);
    result.valid = true;

    return result;
  }

  /*
   * Detect the git provider from hostname
   */
  private proc detectProvider(hostname: string): Provider {
    const lowerHost = hostname.toLower();

    // Check for GitLab
    for host in GITLAB_HOSTS {
      if lowerHost.find(host) != -1 {
        return Provider.GitLab;
      }
    }

    // Check for GitHub
    for host in GITHUB_HOSTS {
      if lowerHost.find(host) != -1 {
        return Provider.GitHub;
      }
    }

    // Check for Bitbucket
    for host in BITBUCKET_HOSTS {
      if lowerHost.find(host) != -1 {
        return Provider.Bitbucket;
      }
    }

    return Provider.Custom;
  }

  //============================================================================
  // Remote Modification Operations
  //============================================================================

  /*
   * Add a new remote to the repository
   *
   * @param repoPath Path to the git repository
   * @param name Name for the new remote
   * @param url URL for the remote
   * @return Success status
   */
  proc addRemote(repoPath: string, name: string, url: string): bool {
    var sub = spawn(["git", "-C", repoPath, "remote", "add", name, url],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Set/update the URL for an existing remote
   *
   * @param repoPath Path to the git repository
   * @param name Remote name to update
   * @param url New URL for the remote
   * @return Success status
   */
  proc setRemoteURL(repoPath: string, name: string, url: string): bool {
    var sub = spawn(["git", "-C", repoPath, "remote", "set-url", name, url],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Set separate push URL for a remote (useful for fork workflows)
   *
   * @param repoPath Path to the git repository
   * @param name Remote name
   * @param pushURL URL to use for push operations
   * @return Success status
   */
  proc setRemotePushURL(repoPath: string, name: string, pushURL: string): bool {
    var sub = spawn(["git", "-C", repoPath, "remote", "set-url", "--push", name, pushURL],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Remove a remote from the repository
   *
   * @param repoPath Path to the git repository
   * @param name Remote name to remove
   * @return Success status
   */
  proc removeRemote(repoPath: string, name: string): bool {
    var sub = spawn(["git", "-C", repoPath, "remote", "remove", name],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Rename a remote
   *
   * @param repoPath Path to the git repository
   * @param oldName Current remote name
   * @param newName New remote name
   * @return Success status
   */
  proc renameRemote(repoPath: string, oldName: string, newName: string): bool {
    var sub = spawn(["git", "-C", repoPath, "remote", "rename", oldName, newName],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  //============================================================================
  // Branch Tracking Operations
  //============================================================================

  /*
   * Get the current branch name
   *
   * @param repoPath Path to the git repository
   * @return Tuple of (success: bool, branchName: string)
   */
  proc getCurrentBranch(repoPath: string = "."): (bool, string) {
    var sub = spawn(["git", "-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var branch: string;
    if sub.stdout.readLine(branch) {
      sub.wait();
      if sub.exitCode == 0 {
        return (true, branch.strip());
      }
    } else {
      sub.wait();
    }

    return (false, "");
  }

  /*
   * Set the upstream tracking branch
   *
   * @param repoPath Path to the git repository
   * @param remote Remote name
   * @param branch Branch name on the remote
   * @return Success status
   */
  proc setUpstreamBranch(repoPath: string, remote: string, branch: string): bool {
    const upstream = remote + "/" + branch;
    var sub = spawn(["git", "-C", repoPath, "branch", "--set-upstream-to=" + upstream],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Set upstream for a specific local branch
   *
   * @param repoPath Path to the git repository
   * @param localBranch Local branch name
   * @param remote Remote name
   * @param remoteBranch Branch name on the remote
   * @return Success status
   */
  proc setUpstreamForBranch(repoPath: string, localBranch: string,
                            remote: string, remoteBranch: string): bool {
    const upstream = remote + "/" + remoteBranch;
    var sub = spawn(["git", "-C", repoPath, "branch", "-u", upstream, localBranch],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Get the upstream tracking branch for a local branch
   *
   * @param repoPath Path to the git repository
   * @param branch Local branch name
   * @return Tuple of (found: bool, upstream: string) where upstream is "remote/branch"
   */
  proc getUpstreamBranch(repoPath: string, branch: string): (bool, string) {
    var sub = spawn(["git", "-C", repoPath, "rev-parse", "--abbrev-ref",
                     branch + "@{upstream}"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var upstream: string;
    if sub.stdout.readLine(upstream) {
      sub.wait();
      if sub.exitCode == 0 {
        return (true, upstream.strip());
      }
    } else {
      sub.wait();
    }

    return (false, "");
  }

  /*
   * Unset upstream tracking for current branch
   *
   * @param repoPath Path to the git repository
   * @return Success status
   */
  proc unsetUpstreamBranch(repoPath: string): bool {
    var sub = spawn(["git", "-C", repoPath, "branch", "--unset-upstream"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  //============================================================================
  // Remote URL Transformation
  //============================================================================

  /*
   * Transform a remote URL to use a different SSH host alias
   *
   * Example:
   *   Input:  git@gitlab.com:org/repo.git
   *   Identity host: gitlab-personal
   *   Output: git@gitlab-personal:org/repo.git
   *
   * @param currentURL The current remote URL
   * @param identity The target identity with host alias
   * @return Transformed URL
   */
  proc transformRemoteForIdentity(currentURL: string, identity: GitIdentity): string {
    const parsed = parseRemoteURL(currentURL);

    if !parsed.valid {
      return currentURL;  // Cannot transform invalid URL
    }

    // Build new URL based on protocol
    select parsed.protocol {
      when "ssh" {
        // SCP-style SSH URL
        return "git@" + identity.host + ":" + parsed.repoPath + ".git";
      }
      when "https", "http" {
        // For HTTPS, we typically want to convert to SSH for identity-based auth
        return "git@" + identity.host + ":" + parsed.repoPath + ".git";
      }
      otherwise {
        // Keep original format but change host
        return currentURL.replace(parsed.host, identity.host);
      }
    }
  }

  /*
   * Build a remote URL for a given identity and repository path
   *
   * @param identity The git identity to use
   * @param repoPath Repository path (org/repo format)
   * @return SSH URL for the remote
   */
  proc buildRemoteURL(identity: GitIdentity, repoPath: string): string {
    var path = repoPath;

    // Ensure .git suffix
    if !path.endsWith(".git") {
      path += ".git";
    }

    return "git@" + identity.host + ":" + path;
  }

  /*
   * Build an HTTPS remote URL
   *
   * @param hostname Hostname (e.g., gitlab.com)
   * @param repoPath Repository path
   * @return HTTPS URL
   */
  proc buildHTTPSRemoteURL(hostname: string, repoPath: string): string {
    var path = repoPath;
    if !path.endsWith(".git") {
      path += ".git";
    }
    return "https://" + hostname + "/" + path;
  }

  //============================================================================
  // SSH Connectivity Validation
  //============================================================================

  /*
    Validate SSH connectivity to a host.

    Tests SSH connection by attempting ``ssh -T git@host``.
    GitLab and GitHub return exit code 1 but with a welcome message
    indicating successful authentication.

    **Example:**

    .. code-block:: chapel

       if validateSSHConnectivity("gitlab-personal") {
         writeln("SSH connection successful!");
       }

    :arg host: SSH host alias or hostname
    :returns: true if SSH authentication succeeds
  */
  proc validateSSHConnectivity(host: string): bool {
    const result = testSSHConnectivity(host);
    return result.authenticated;
  }

  /*
    Detailed SSH connectivity test.

    Performs SSH connection test and returns detailed results including
    the username from the server response if authentication succeeds.

    **SSH Options Used:**

    - ``-T``: Disable pseudo-terminal allocation
    - ``-o BatchMode=yes``: Disable password prompts
    - ``-o ConnectTimeout=5``: 5-second timeout
    - ``-o StrictHostKeyChecking=accept-new``: Accept new host keys

    :arg host: SSH host alias or hostname
    :returns: SSHTestResult with connection details
  */
  proc testSSHConnectivity(host: string): SSHTestResult {
    var result = new SSHTestResult();

    // Run SSH with test flag
    var sub = spawn(["ssh", "-T", "git@" + host,
                     "-o", "BatchMode=yes",
                     "-o", "ConnectTimeout=5",
                     "-o", "StrictHostKeyChecking=accept-new"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    // Read all output
    var stderrContent: string;
    var stdoutContent: string;
    var line: string;

    while sub.stderr.readLine(line) {
      stderrContent += line + "\n";
    }
    while sub.stdout.readLine(line) {
      stdoutContent += line + "\n";
    }

    sub.wait();

    const allOutput = stdoutContent + stderrContent;
    const lowerOutput = allOutput.toLower();

    // Check for explicit failure indicators first
    const failurePatterns = [
      "permission denied",
      "connection refused",
      "connection timed out",
      "host key verification failed",
      "no such host",
      "could not resolve hostname",
      "network is unreachable"
    ];

    for pattern in failurePatterns {
      if lowerOutput.find(pattern) != -1 {
        result.connected = lowerOutput.find("connection refused") == -1 &&
                           lowerOutput.find("could not resolve") == -1 &&
                           lowerOutput.find("network is unreachable") == -1;
        result.authenticated = false;
        result.message = allOutput.strip();
        return result;
      }
    }

    // Connection succeeded if no network errors
    result.connected = true;

    // Check for success patterns
    // GitLab: "Welcome to GitLab, @username!"
    // GitHub: "Hi username! You've successfully authenticated"

    if lowerOutput.find("welcome to gitlab") != -1 {
      result.authenticated = true;
      // Extract username from "Welcome to GitLab, @username!"
      const atIdx = allOutput.find("@");
      if atIdx != -1 {
        const excIdx = allOutput.find("!", atIdx..);
        if excIdx != -1 {
          result.username = allOutput[atIdx+1..excIdx-1];
        }
      }
      result.message = allOutput.strip();
    } else if lowerOutput.find("hi ") != -1 && lowerOutput.find("successfully authenticated") != -1 {
      result.authenticated = true;
      // Extract username from "Hi username!"
      const hiIdx = lowerOutput.find("hi ");
      if hiIdx != -1 {
        const remainder = allOutput[hiIdx+3..];
        const excIdx = remainder.find("!");
        if excIdx != -1 {
          result.username = remainder[..excIdx-1];
        }
      }
      result.message = allOutput.strip();
    } else if lowerOutput.find("successfully authenticated") != -1 ||
              lowerOutput.find("logged in as") != -1 {
      result.authenticated = true;
      result.message = allOutput.strip();
    } else if sub.exitCode == 0 {
      // Exit code 0 always means success
      result.authenticated = true;
      result.message = allOutput.strip();
    } else if sub.exitCode == 1 && allOutput.strip() != "" {
      // Exit code 1 with non-error output is typically success for git hosts
      result.authenticated = true;
      result.message = allOutput.strip();
    }

    return result;
  }

  /*
   * Test remote access by attempting to connect
   *
   * @param repoPath Path to the git repository
   * @param remote Remote name to test
   * @return True if remote is accessible
   */
  proc testRemoteAccess(repoPath: string, remote: string): bool {
    // Use git ls-remote to test connectivity
    var sub = spawn(["git", "-C", repoPath, "ls-remote", "--exit-code", remote],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    // Timeout after 10 seconds - read output to avoid blocking
    var line: string;
    while sub.stdout.readLine(line) { }
    while sub.stderr.readLine(line) { }

    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Fetch from a remote (without merging)
   *
   * @param repoPath Path to the git repository
   * @param remote Remote name
   * @return Success status
   */
  proc fetchRemote(repoPath: string, remote: string): bool {
    var sub = spawn(["git", "-C", repoPath, "fetch", remote],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    // Read output to avoid blocking
    var line: string;
    while sub.stdout.readLine(line) { }
    while sub.stderr.readLine(line) { }

    sub.wait();
    return sub.exitCode == 0;
  }

  //============================================================================
  // Repository Detection
  //============================================================================

  /*
   * Check if a path is inside a git repository
   *
   * @param path Path to check
   * @return True if path is inside a git repository
   */
  proc isGitRepository(path: string): bool {
    var sub = spawn(["git", "-C", path, "rev-parse", "--is-inside-work-tree"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var result: string;
    sub.stdout.readLine(result);
    sub.wait();

    return sub.exitCode == 0 && result.strip() == "true";
  }

  /*
   * Get the root directory of the git repository
   *
   * @param path Path inside the repository
   * @return Tuple of (found: bool, rootPath: string)
   */
  proc getRepositoryRoot(path: string): (bool, string) {
    var sub = spawn(["git", "-C", path, "rev-parse", "--show-toplevel"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var rootPath: string;
    if sub.stdout.readLine(rootPath) {
      sub.wait();
      if sub.exitCode == 0 {
        return (true, rootPath.strip());
      }
    } else {
      sub.wait();
    }

    return (false, "");
  }

  /*
   * Get the path relative to repository root
   *
   * @param path Absolute path
   * @return Tuple of (found: bool, relativePath: string)
   */
  proc getRelativePath(path: string): (bool, string) {
    var sub = spawn(["git", "-C", path, "rev-parse", "--show-prefix"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var relPath: string;
    if sub.stdout.readLine(relPath) {
      sub.wait();
      if sub.exitCode == 0 {
        return (true, relPath.strip());
      }
    } else {
      sub.wait();
    }

    return (false, "");
  }

  //============================================================================
  // Git Configuration Helpers
  //============================================================================

  /*
   * Get a git configuration value
   *
   * @param repoPath Path to repository (use "" for global)
   * @param key Configuration key
   * @return Tuple of (found: bool, value: string)
   */
  proc getGitConfig(repoPath: string, key: string): (bool, string) {
    var args: list(string);
    args.pushBack("git");

    if repoPath != "" {
      args.pushBack("-C");
      args.pushBack(repoPath);
    }

    args.pushBack("config");
    args.pushBack("--get");
    args.pushBack(key);

    var sub = spawn(args.toArray(), stdout = pipeStyle.pipe, stderr = pipeStyle.pipe);

    var value: string;
    if sub.stdout.readLine(value) {
      sub.wait();
      if sub.exitCode == 0 {
        return (true, value.strip());
      }
    } else {
      sub.wait();
    }

    return (false, "");
  }

  /*
   * Set a git configuration value
   *
   * @param repoPath Path to repository (use "" for global)
   * @param key Configuration key
   * @param value Configuration value
   * @return Success status
   */
  proc setGitConfig(repoPath: string, key: string, value: string): bool {
    var args: list(string);
    args.pushBack("git");

    if repoPath != "" {
      args.pushBack("-C");
      args.pushBack(repoPath);
    }

    args.pushBack("config");
    args.pushBack(key);
    args.pushBack(value);

    var sub = spawn(args.toArray(), stdout = pipeStyle.pipe, stderr = pipeStyle.pipe);
    sub.wait();
    return sub.exitCode == 0;
  }

  /*
   * Set git user information for a repository
   *
   * @param repoPath Path to repository
   * @param name User name
   * @param email User email
   * @return Success status
   */
  proc setGitUser(repoPath: string, name: string, email: string): bool {
    const nameOk = setGitConfig(repoPath, "user.name", name);
    const emailOk = setGitConfig(repoPath, "user.email", email);
    return nameOk && emailOk;
  }

  //============================================================================
  // Utility Functions
  //============================================================================

  /*
   * Get origin remote URL (convenience function)
   *
   * @param repoPath Path to repository
   * @return Tuple of (found: bool, url: string)
   */
  proc getOriginURL(repoPath: string = "."): (bool, string) {
    const (found, remote) = getRemote(repoPath, "origin");
    if found {
      return (true, if remote.fetchURL != "" then remote.fetchURL else remote.pushURL);
    }
    return (false, "");
  }

  /*
   * Update origin remote to use a different identity
   *
   * @param repoPath Path to repository
   * @param identity Target identity
   * @return Success status and transformed URL
   */
  proc updateOriginForIdentity(repoPath: string, identity: GitIdentity): (bool, string) {
    const (found, currentURL) = getOriginURL(repoPath);
    if !found {
      return (false, "");
    }

    const newURL = transformRemoteForIdentity(currentURL, identity);
    const success = setRemoteURL(repoPath, "origin", newURL);

    return (success, newURL);
  }

  /*
    Print debug information about a remote URL.

    Outputs detailed URL analysis to stdout for debugging purposes.

    :arg url: URL to analyze
  */
  proc debugRemoteURL(url: string) {
    const parsed = parseRemoteURL(url);

    writeln("URL Analysis: ", url);
    writeln("  Valid:      ", parsed.valid);
    writeln("  Protocol:   ", parsed.protocol);
    writeln("  Provider:   ", parsed.provider);
    writeln("  Host:       ", parsed.host);
    writeln("  Hostname:   ", parsed.hostname);
    writeln("  Port:       ", parsed.port);
    writeln("  Org Path:   ", parsed.orgPath);
    writeln("  Repo Path:  ", parsed.repoPath);
    writeln("  Repo Name:  ", parsed.repoName);
  }

  //============================================================================
  // Identity Detection Helpers
  //============================================================================

  /*
    Detect the provider and host from a repository's origin remote.

    Analyzes the origin remote URL to determine the provider type
    and SSH host alias/hostname being used.

    **Example:**

    .. code-block:: chapel

       const (found, result) = detectRepositoryProvider(".");
       if found {
         writeln("Provider: ", result.provider);
         writeln("Host: ", result.host);
         writeln("Org: ", result.orgPath);
       }

    :arg repoPath: Path to git repository
    :returns: Tuple of (found, RemoteParseResult)
  */
  proc detectRepositoryProvider(repoPath: string = "."): (bool, RemoteParseResult) {
    const (found, url) = getOriginURL(repoPath);
    if !found {
      return (false, new RemoteParseResult());
    }

    const parsed = parseRemoteURL(url);
    return (parsed.valid, parsed);
  }

  /*
    Check if a repository is using a specific SSH host.

    :arg repoPath: Path to git repository
    :arg host: SSH host alias to check for
    :returns: true if origin uses the specified host
  */
  proc isUsingSSHHost(repoPath: string, host: string): bool {
    const (found, parsed) = detectRepositoryProvider(repoPath);
    if !found then return false;
    return parsed.host == host;
  }

  /*
    Get the organization/group path from a repository.

    :arg repoPath: Path to git repository
    :returns: Tuple of (found, orgPath)
  */
  proc getRepositoryOrg(repoPath: string = "."): (bool, string) {
    const (found, parsed) = detectRepositoryProvider(repoPath);
    if !found then return (false, "");
    return (true, parsed.orgPath);
  }

  /*
    Get the full repository path (org/repo) from origin.

    :arg repoPath: Path to git repository
    :returns: Tuple of (found, repoPath)
  */
  proc getRepositoryPath(repoPath: string = "."): (bool, string) {
    const (found, parsed) = detectRepositoryProvider(repoPath);
    if !found then return (false, "");
    return (true, parsed.repoPath);
  }

  //============================================================================
  // Batch Operations
  //============================================================================

  /*
    Update all remotes to use a new SSH host.

    Transforms all remotes in a repository to use the specified
    identity's SSH host configuration.

    :arg repoPath: Path to git repository
    :arg identity: Target identity with host configuration
    :returns: Number of remotes successfully updated
  */
  proc updateAllRemotesForIdentity(repoPath: string, identity: GitIdentity): int {
    const remotes = listRemotes(repoPath);
    var updated = 0;

    for remote in remotes {
      if remote.fetchURL != "" {
        const newFetchURL = transformRemoteForIdentity(remote.fetchURL, identity);
        if setRemoteURL(repoPath, remote.name, newFetchURL) {
          updated += 1;
        }
      }

      // Handle separate push URL if present
      if remote.hasSeparatePushURL() {
        const newPushURL = transformRemoteForIdentity(remote.pushURL, identity);
        setRemotePushURL(repoPath, remote.name, newPushURL);
      }
    }

    return updated;
  }

  /*
    Verify all remotes are accessible.

    Tests connectivity to all configured remotes.

    :arg repoPath: Path to git repository
    :returns: List of remote names that failed connectivity test
  */
  proc verifyAllRemotes(repoPath: string = "."): list(string) {
    var failedRemotes: list(string);
    const remotes = listRemotes(repoPath);

    for remote in remotes {
      if !testRemoteAccess(repoPath, remote.name) {
        failedRemotes.pushBack(remote.name);
      }
    }

    return failedRemotes;
  }

  //============================================================================
  // Git Status Helpers
  //============================================================================

  /*
    Check if repository has uncommitted changes.

    :arg repoPath: Path to git repository
    :returns: true if there are uncommitted changes
  */
  proc hasUncommittedChanges(repoPath: string = "."): bool {
    var sub = spawn(["git", "-C", repoPath, "status", "--porcelain"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var hasOutput = false;
    var line: string;
    if sub.stdout.readLine(line) {
      hasOutput = true;
    }

    // Drain remaining output
    while sub.stdout.readLine(line) { }
    while sub.stderr.readLine(line) { }

    sub.wait();
    return hasOutput;
  }

  /*
    Get the current HEAD commit hash (short form).

    :arg repoPath: Path to git repository
    :returns: Tuple of (found, commitHash)
  */
  proc getHeadCommit(repoPath: string = "."): (bool, string) {
    var sub = spawn(["git", "-C", repoPath, "rev-parse", "--short", "HEAD"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var hash: string;
    if sub.stdout.readLine(hash) {
      sub.wait();
      if sub.exitCode == 0 {
        return (true, hash.strip());
      }
    } else {
      sub.wait();
    }

    return (false, "");
  }

  /*
    Get the current HEAD commit hash (full form).

    :arg repoPath: Path to git repository
    :returns: Tuple of (found, commitHash)
  */
  proc getHeadCommitFull(repoPath: string = "."): (bool, string) {
    var sub = spawn(["git", "-C", repoPath, "rev-parse", "HEAD"],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    var hash: string;
    if sub.stdout.readLine(hash) {
      sub.wait();
      if sub.exitCode == 0 {
        return (true, hash.strip());
      }
    } else {
      sub.wait();
    }

    return (false, "");
  }

  //============================================================================
  // Remote Prune Operations
  //============================================================================

  /*
    Prune stale remote-tracking branches.

    Removes remote-tracking references that no longer exist on the remote.

    :arg repoPath: Path to git repository
    :arg remote: Remote name to prune (default: "origin")
    :returns: Success status
  */
  proc pruneRemote(repoPath: string, remote: string = "origin"): bool {
    var sub = spawn(["git", "-C", repoPath, "remote", "prune", remote],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    // Drain output
    var line: string;
    while sub.stdout.readLine(line) { }
    while sub.stderr.readLine(line) { }

    sub.wait();
    return sub.exitCode == 0;
  }

  /*
    Update remote references (fetch + prune).

    :arg repoPath: Path to git repository
    :arg remote: Remote name (default: "origin")
    :returns: Success status
  */
  proc updateRemote(repoPath: string, remote: string = "origin"): bool {
    var sub = spawn(["git", "-C", repoPath, "fetch", "--prune", remote],
                    stdout = pipeStyle.pipe,
                    stderr = pipeStyle.pipe);

    // Drain output
    var line: string;
    while sub.stdout.readLine(line) { }
    while sub.stderr.readLine(line) { }

    sub.wait();
    return sub.exitCode == 0;
  }

}

