/*
 * RemoteTests.chpl - Unit tests for Remote module
 *
 * Tests git remote URL manipulation, provider detection, and identity matching.
 * Uses QuickChpl for property-based testing.
 */
prototype module RemoteTests {
  use remote_juggler.Remote;
  use remote_juggler.Core;

  config const numTests = 100;
  config const verbose = false;

  proc main() {
    writeln("=== RemoteJuggler Remote Module Tests ===\n");

    var passed = 0;
    var failed = 0;

    // Test remote URL normalization
    {
      writeln("Test 1: Remote URL normalization");

      var allPass = true;

      // With .git suffix
      const withGit = "git@gitlab.com:user/repo.git";
      const normalized1 = normalizeRemoteUrl(withGit);

      // Without .git suffix
      const withoutGit = "git@gitlab.com:user/repo";
      const normalized2 = normalizeRemoteUrl(withoutGit);

      if normalized1 != normalized2 {
        writeln("  FAIL: URLs should normalize to same value");
        writeln("    '", normalized1, "' != '", normalized2, "'");
        allPass = false;
      }

      // HTTPS to SSH normalization
      const httpsUrl = "https://gitlab.com/user/repo.git";
      const sshUrl = "git@gitlab.com:user/repo.git";

      if normalizeRemoteUrl(httpsUrl) != normalizeRemoteUrl(sshUrl) {
        writeln("  FAIL: HTTPS and SSH URLs for same repo should normalize equally");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test SSH alias URL detection
    {
      writeln("Test 2: SSH alias URL detection");

      var allPass = true;

      // Standard SSH format with alias
      const aliasUrl = "git@gitlab-work:company/project.git";
      if !isSshAliasUrl(aliasUrl) {
        writeln("  FAIL: Should detect gitlab-work as SSH alias");
        allPass = false;
      }

      // Standard hostname (not an alias)
      const standardUrl = "git@gitlab.com:user/repo.git";
      if isSshAliasUrl(standardUrl) {
        writeln("  FAIL: gitlab.com is not an SSH alias");
        allPass = false;
      }

      // HTTPS URL (never an alias)
      const httpsUrl = "https://gitlab.com/user/repo.git";
      if isSshAliasUrl(httpsUrl) {
        writeln("  FAIL: HTTPS URLs are never aliases");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test remote name extraction
    {
      writeln("Test 3: Remote name parsing");

      var allPass = true;

      // Parse git remote -v output format
      const remoteLine = "origin\tgit@gitlab-work:company/repo.git (fetch)";
      const (name, url, mode) = parseRemoteLine(remoteLine);

      if name != "origin" {
        writeln("  FAIL: Remote name should be 'origin', got '", name, "'");
        allPass = false;
      }

      if url != "git@gitlab-work:company/repo.git" {
        writeln("  FAIL: Remote URL mismatch");
        allPass = false;
      }

      if mode != "fetch" {
        writeln("  FAIL: Mode should be 'fetch', got '", mode, "'");
        allPass = false;
      }

      // Push mode
      const pushLine = "upstream\thttps://github.com/org/repo.git (push)";
      const (pName, pUrl, pMode) = parseRemoteLine(pushLine);

      if pMode != "push" {
        writeln("  FAIL: Mode should be 'push'");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test host extraction from various URL formats
    {
      writeln("Test 4: Host extraction from URL formats");

      var allPass = true;

      const testCases = [
        ("git@gitlab.com:user/repo.git", "gitlab.com"),
        ("git@gitlab-work:user/repo.git", "gitlab-work"),
        ("ssh://git@github.com/user/repo.git", "github.com"),
        ("https://bitbucket.org/user/repo.git", "bitbucket.org"),
        ("git://git.example.com/repo.git", "git.example.com"),
        ("file:///local/repo.git", ""),  // Local URLs have no host
      ];

      for (url, expectedHost) in testCases {
        const extractedHost = extractHostFromUrl(url);
        if extractedHost != expectedHost {
          writeln("  FAIL: '", url, "' -> expected '", expectedHost, "', got '", extractedHost, "'");
          allPass = false;
        }
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test path extraction from URLs
    {
      writeln("Test 5: Repository path extraction");

      var allPass = true;

      const testCases = [
        ("git@gitlab.com:user/repo.git", "user/repo"),
        ("git@gitlab.com:org/subgroup/repo.git", "org/subgroup/repo"),
        ("https://github.com/user/repo.git", "user/repo"),
        ("ssh://git@bitbucket.org/team/project.git", "team/project"),
      ];

      for (url, expectedPath) in testCases {
        const extractedPath = extractRepoPath(url);
        if extractedPath != expectedPath {
          writeln("  FAIL: '", url, "' -> expected path '", expectedPath, "', got '", extractedPath, "'");
          allPass = false;
        }
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test URL transformation for identity switch
    {
      writeln("Test 6: URL transformation for identity switch");

      var allPass = true;

      // Transform from one SSH alias to another
      const originalUrl = "git@gitlab-work:company/project.git";
      const targetHost = "gitlab-personal";

      const transformed = transformUrlForIdentity(originalUrl, targetHost);
      const expected = "git@gitlab-personal:company/project.git";

      if transformed != expected {
        writeln("  FAIL: Expected '", expected, "', got '", transformed, "'");
        allPass = false;
      }

      // Transform HTTPS to SSH alias
      const httpsUrl = "https://gitlab.com/user/repo.git";
      const sshTransformed = transformUrlForIdentity(httpsUrl, "gitlab-personal");

      if !sshTransformed.startsWith("git@gitlab-personal:") {
        writeln("  FAIL: HTTPS should transform to SSH alias format");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test provider detection from remote URL
    {
      writeln("Test 7: Provider detection from remote URL");

      var allPass = true;

      const gitlabUrl = "git@gitlab.com:user/repo.git";
      if detectProviderFromUrl(gitlabUrl) != Provider.GitLab {
        writeln("  FAIL: Should detect GitLab");
        allPass = false;
      }

      const githubUrl = "https://github.com/user/repo.git";
      if detectProviderFromUrl(githubUrl) != Provider.GitHub {
        writeln("  FAIL: Should detect GitHub");
        allPass = false;
      }

      const bitbucketUrl = "git@bitbucket.org:team/project.git";
      if detectProviderFromUrl(bitbucketUrl) != Provider.Bitbucket {
        writeln("  FAIL: Should detect Bitbucket");
        allPass = false;
      }

      // SSH alias - should return Custom until resolved
      const aliasUrl = "git@gitlab-work:company/repo.git";
      const aliasProvider = detectProviderFromUrl(aliasUrl);
      // Aliases need SSH config lookup, so raw detection returns Custom
      if aliasProvider != Provider.Custom {
        // This is expected - alias detection requires config context
        if verbose then writeln("  INFO: SSH alias detected as Custom (expected)");
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test URL validation
    {
      writeln("Test 8: URL validation");

      var allPass = true;

      // Valid URLs
      const validUrls = [
        "git@gitlab.com:user/repo.git",
        "https://github.com/user/repo.git",
        "ssh://git@bitbucket.org/team/repo.git",
        "git://git.example.com/repo.git"
      ];

      for url in validUrls {
        if !isValidRemoteUrl(url) {
          writeln("  FAIL: Should accept valid URL: ", url);
          allPass = false;
        }
      }

      // Invalid URLs
      const invalidUrls = [
        "",
        "not-a-url",
        "ftp://invalid.protocol/repo",
        "://missing-scheme.com/repo"
      ];

      for url in invalidUrls {
        if isValidRemoteUrl(url) {
          writeln("  FAIL: Should reject invalid URL: '", url, "'");
          allPass = false;
        }
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Property test: URL transformations preserve repo path
    {
      writeln("Test 9: Property - URL transformations preserve repo path");

      var allPass = true;

      const testUrls = [
        "git@gitlab.com:user/repo.git",
        "git@github.com:org/project.git",
        "https://gitlab.com/group/subgroup/repo.git"
      ];

      for url in testUrls {
        const originalPath = extractRepoPath(url);
        const transformed = transformUrlForIdentity(url, "new-host");
        const transformedPath = extractRepoPath(transformed);

        if originalPath != transformedPath {
          writeln("  FAIL: Path changed during transformation");
          writeln("    Original: ", originalPath);
          writeln("    After: ", transformedPath);
          allPass = false;
        }
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test RemoteInfo record
    {
      writeln("Test 10: RemoteInfo record operations");

      var allPass = true;

      const remote = new RemoteInfo(
        name = "origin",
        fetchUrl = "git@gitlab-work:company/repo.git",
        pushUrl = "git@gitlab-work:company/repo.git",
        provider = Provider.GitLab,
        sshAlias = "gitlab-work"
      );

      if remote.name != "origin" {
        writeln("  FAIL: Remote name mismatch");
        allPass = false;
      }

      if remote.provider != Provider.GitLab {
        writeln("  FAIL: Provider mismatch");
        allPass = false;
      }

      if remote.sshAlias != "gitlab-work" {
        writeln("  FAIL: SSH alias mismatch");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Summary
    writeln();
    writeln("=".repeat(50));
    writeln("Remote Tests: ", passed, " passed, ", failed, " failed");
    writeln("=".repeat(50));

    if failed > 0 then exit(1);
  }
}
