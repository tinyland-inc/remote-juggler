/*
 * ConfigTests.chpl - Unit tests for Config module
 *
 * Tests SSH config parsing, git config parsing, and URL rewriting.
 * Uses QuickChpl for property-based testing.
 */
prototype module ConfigTests {
  use remote_juggler.Config;
  use remote_juggler.Core;

  config const numTests = 100;
  config const verbose = false;

  proc main() {
    writeln("=== RemoteJuggler Config Module Tests ===\n");

    var passed = 0;
    var failed = 0;

    // Test SSH host pattern parsing
    {
      writeln("Test 1: SSH host pattern matching");

      // Simple host match
      const simplePattern = "gitlab-work";
      const simpleHost = "gitlab-work";

      var allPass = true;
      if !hostMatchesPattern(simpleHost, simplePattern) {
        writeln("  FAIL: Simple host should match");
        allPass = false;
      }

      // Wildcard pattern
      const wildcardPattern = "gitlab-*";
      const matchingHost = "gitlab-personal";
      const nonMatchingHost = "github-work";

      if !hostMatchesPattern(matchingHost, wildcardPattern) {
        writeln("  FAIL: Wildcard should match gitlab-personal");
        allPass = false;
      }

      if hostMatchesPattern(nonMatchingHost, wildcardPattern) {
        writeln("  FAIL: Wildcard should NOT match github-work");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test URL parsing
    {
      writeln("Test 2: Git URL parsing");

      var allPass = true;

      // SSH URL format
      const sshUrl = "git@gitlab-work:company/project.git";
      const (sshHost, sshPath) = parseGitUrl(sshUrl);

      if sshHost != "gitlab-work" {
        writeln("  FAIL: SSH host should be 'gitlab-work', got '", sshHost, "'");
        allPass = false;
      }
      if sshPath != "company/project.git" {
        writeln("  FAIL: SSH path should be 'company/project.git', got '", sshPath, "'");
        allPass = false;
      }

      // HTTPS URL format
      const httpsUrl = "https://gitlab.com/user/repo.git";
      const (httpsHost, httpsPath) = parseGitUrl(httpsUrl);

      if httpsHost != "gitlab.com" {
        writeln("  FAIL: HTTPS host should be 'gitlab.com', got '", httpsHost, "'");
        allPass = false;
      }
      if httpsPath != "user/repo.git" {
        writeln("  FAIL: HTTPS path should be 'user/repo.git', got '", httpsPath, "'");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test insteadOf URL rewriting
    {
      writeln("Test 3: Git URL insteadOf rewriting");

      var allPass = true;

      // Test that rewriting transforms URLs correctly
      const originalUrl = "https://gitlab.com/user/repo.git";
      const rewriteRule = "git@gitlab-work:";
      const rewriteFrom = "https://gitlab.com/";

      const rewritten = applyInsteadOf(originalUrl, rewriteFrom, rewriteRule);
      const expected = "git@gitlab-work:user/repo.git";

      if rewritten != expected {
        writeln("  FAIL: Expected '", expected, "', got '", rewritten, "'");
        allPass = false;
      }

      // Test non-matching URL (should not be rewritten)
      const otherUrl = "https://github.com/user/repo.git";
      const notRewritten = applyInsteadOf(otherUrl, rewriteFrom, rewriteRule);

      if notRewritten != otherUrl {
        writeln("  FAIL: Non-matching URL should not be rewritten");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test SSH config line parsing
    {
      writeln("Test 4: SSH config line tokenization");

      var allPass = true;

      // Host line
      const hostLine = "Host gitlab-work";
      const (hostKey, hostValue) = parseSshConfigLine(hostLine);

      if hostKey != "Host" || hostValue != "gitlab-work" {
        writeln("  FAIL: Host line parsing failed");
        allPass = false;
      }

      // HostName line with indentation
      const hostnameLine = "    HostName gitlab.com";
      const (hnKey, hnValue) = parseSshConfigLine(hostnameLine);

      if hnKey != "HostName" || hnValue != "gitlab.com" {
        writeln("  FAIL: HostName line parsing failed");
        allPass = false;
      }

      // IdentityFile with path
      const identityLine = "  IdentityFile ~/.ssh/id_ed25519_work";
      const (idKey, idValue) = parseSshConfigLine(identityLine);

      if idKey != "IdentityFile" || idValue != "~/.ssh/id_ed25519_work" {
        writeln("  FAIL: IdentityFile line parsing failed");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test git config section parsing
    {
      writeln("Test 5: Git config section header parsing");

      var allPass = true;

      const userSection = "[user]";
      const urlSection = "[url \"git@gitlab-work:\"]";
      const includeSection = "[includeIf \"gitdir:~/work/\"]";

      if !isGitConfigSection(userSection) {
        writeln("  FAIL: Should recognize [user] as section");
        allPass = false;
      }

      if !isGitConfigSection(urlSection) {
        writeln("  FAIL: Should recognize URL section");
        allPass = false;
      }

      if !isGitConfigSection(includeSection) {
        writeln("  FAIL: Should recognize includeIf section");
        allPass = false;
      }

      const notSection = "  email = user@example.com";
      if isGitConfigSection(notSection) {
        writeln("  FAIL: Should NOT recognize key=value as section");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test provider detection from hostname
    {
      writeln("Test 6: Provider detection from hostname");

      var allPass = true;

      if detectProviderFromHost("gitlab.com") != Provider.GitLab {
        writeln("  FAIL: gitlab.com should be GitLab");
        allPass = false;
      }

      if detectProviderFromHost("github.com") != Provider.GitHub {
        writeln("  FAIL: github.com should be GitHub");
        allPass = false;
      }

      if detectProviderFromHost("bitbucket.org") != Provider.Bitbucket {
        writeln("  FAIL: bitbucket.org should be Bitbucket");
        allPass = false;
      }

      if detectProviderFromHost("git.company.com") != Provider.Custom {
        writeln("  FAIL: Unknown host should be Custom");
        allPass = false;
      }

      // Self-hosted GitLab detection
      if detectProviderFromHost("gitlab.company.com") != Provider.GitLab {
        writeln("  FAIL: gitlab.company.com should be GitLab");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Property test: URL parsing roundtrip
    {
      writeln("Test 7: Property - URL host extraction is consistent");

      var allPass = true;

      // Test various URL formats all extract host correctly
      const urls = [
        ("git@host:path.git", "host"),
        ("ssh://git@host/path.git", "host"),
        ("https://host/path.git", "host"),
        ("git://host/path.git", "host")
      ];

      for (url, expectedHost) in urls {
        const (host, _) = parseGitUrl(url);
        if host != expectedHost {
          writeln("  FAIL: '", url, "' -> expected '", expectedHost, "', got '", host, "'");
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

    // Test empty/edge cases
    {
      writeln("Test 8: Edge cases - empty and malformed inputs");

      var allPass = true;

      // Empty URL
      const (emptyHost, emptyPath) = parseGitUrl("");
      if emptyHost != "" || emptyPath != "" {
        writeln("  FAIL: Empty URL should return empty host and path");
        allPass = false;
      }

      // Empty config line
      const (emptyKey, emptyValue) = parseSshConfigLine("");
      if emptyKey != "" || emptyValue != "" {
        writeln("  FAIL: Empty line should return empty key and value");
        allPass = false;
      }

      // Comment line
      const (commentKey, commentValue) = parseSshConfigLine("# This is a comment");
      if commentKey != "" || commentValue != "" {
        writeln("  FAIL: Comment line should return empty");
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
    writeln("Config Tests: ", passed, " passed, ", failed, " failed");
    writeln("=".repeat(50));

    if failed > 0 then exit(1);
  }
}
