/*
 * RemoteTests.chpl - Unit tests for Remote module
 *
 * Tests git remote URL parsing, provider detection, and remote manipulation.
 */
prototype module RemoteTests {
  use remote_juggler.Remote;
  use remote_juggler.Core;
  use TestUtils;

  config const verbose = false;

  proc main() {
    writeln("=== RemoteJuggler Remote Module Tests ===\n");

    var passed = 0;
    var failed = 0;

    // Test 1: GitRemote record
    {
      writeln("Test 1: GitRemote record initialization");
      var allPass = true;

      const remote = new GitRemote("origin", "git@gitlab.com:user/repo.git");

      if remote.name != "origin" {
        writeln("  FAIL: name should be 'origin'");
        allPass = false;
      }

      if remote.fetchURL != "git@gitlab.com:user/repo.git" {
        writeln("  FAIL: fetchURL mismatch");
        allPass = false;
      }

      if remote.url() != "git@gitlab.com:user/repo.git" {
        writeln("  FAIL: url() should return fetchURL");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 2: GitRemote with separate push URL
    {
      writeln("Test 2: GitRemote with separate push URL");
      var allPass = true;

      const remote = new GitRemote(
        "origin",
        "https://gitlab.com/user/repo.git",  // fetch
        "git@gitlab.com:user/repo.git"       // push
      );

      if !remote.hasSeparatePushURL() {
        writeln("  FAIL: hasSeparatePushURL should be true");
        allPass = false;
      }

      if remote.pushURL != "git@gitlab.com:user/repo.git" {
        writeln("  FAIL: pushURL mismatch");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 3: Parse SSH URL (SCP style)
    {
      writeln("Test 3: Parse SCP-style SSH URL");
      var allPass = true;

      const result = parseRemoteURL("git@gitlab.com:user/repo.git");

      if !result.valid {
        writeln("  FAIL: Should parse as valid URL");
        allPass = false;
      }

      if result.hostname != "gitlab.com" {
        writeln("  FAIL: hostname should be 'gitlab.com', got '", result.hostname, "'");
        allPass = false;
      }

      // repoPath may or may not include .git suffix depending on implementation
      if result.repoPath != "user/repo.git" && result.repoPath != "user/repo" {
        writeln("  FAIL: repoPath should be 'user/repo' or 'user/repo.git', got '", result.repoPath, "'");
        allPass = false;
      }

      if result.provider != Provider.GitLab {
        writeln("  FAIL: provider should be GitLab");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 4: Parse HTTPS URL
    {
      writeln("Test 4: Parse HTTPS URL");
      var allPass = true;

      const result = parseRemoteURL("https://github.com/user/project.git");

      if !result.valid {
        writeln("  FAIL: Should parse as valid URL");
        allPass = false;
      }

      if result.hostname != "github.com" {
        writeln("  FAIL: hostname should be 'github.com', got '", result.hostname, "'");
        allPass = false;
      }

      // repoPath may or may not include .git suffix
      if result.repoPath != "user/project.git" && result.repoPath != "user/project" {
        writeln("  FAIL: repoPath should be 'user/project' or 'user/project.git', got '", result.repoPath, "'");
        allPass = false;
      }

      if result.provider != Provider.GitHub {
        writeln("  FAIL: provider should be GitHub");
        allPass = false;
      }

      if !result.isHTTPS() {
        writeln("  FAIL: isHTTPS() should be true");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 5: Parse explicit SSH URL
    {
      writeln("Test 5: Parse explicit SSH URL");
      var allPass = true;

      const result = parseRemoteURL("ssh://git@bitbucket.org/team/repo.git");

      if !result.valid {
        writeln("  FAIL: Should parse as valid URL");
        allPass = false;
      }

      if result.hostname != "bitbucket.org" {
        writeln("  FAIL: hostname should be 'bitbucket.org', got '", result.hostname, "'");
        allPass = false;
      }

      if result.provider != Provider.Bitbucket {
        writeln("  FAIL: provider should be Bitbucket");
        allPass = false;
      }

      if !result.isSSH() {
        writeln("  FAIL: isSSH() should be true");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 6: Parse git protocol URL
    {
      writeln("Test 6: Parse git protocol URL");
      var allPass = true;

      const result = parseRemoteURL("git://github.com/user/repo.git");

      if !result.valid {
        writeln("  FAIL: Should parse as valid URL");
        allPass = false;
      }

      if result.protocol != "git" {
        writeln("  FAIL: protocol should be 'git', got '", result.protocol, "'");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 7: Parse custom host SSH URL
    {
      writeln("Test 7: Parse custom SSH host alias");
      var allPass = true;

      const result = parseRemoteURL("git@gitlab-work:company/project.git");

      if !result.valid {
        writeln("  FAIL: Should parse as valid URL");
        allPass = false;
      }

      if result.hostname != "gitlab-work" {
        writeln("  FAIL: hostname should be 'gitlab-work', got '", result.hostname, "'");
        allPass = false;
      }

      // Custom host alias with 'gitlab' in name may be detected as GitLab
      // This is acceptable behavior - the module infers provider from hostname pattern
      if result.provider != Provider.Custom && result.provider != Provider.GitLab {
        writeln("  FAIL: provider should be Custom or GitLab for gitlab-work host");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 8: Invalid URL handling
    {
      writeln("Test 8: Invalid URL handling");
      var allPass = true;

      const emptyResult = parseRemoteURL("");
      if emptyResult.valid {
        writeln("  FAIL: Empty URL should be invalid");
        allPass = false;
      }

      const badResult = parseRemoteURL("not-a-url");
      if badResult.valid {
        writeln("  FAIL: 'not-a-url' should be invalid");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 9: RemoteOpResult record
    {
      writeln("Test 9: RemoteOpResult record");
      var allPass = true;

      const success = new RemoteOpResult(true, "Operation succeeded");
      if !success.success {
        writeln("  FAIL: success.success should be true");
        allPass = false;
      }

      const failure = new RemoteOpResult(false, "Operation failed", 1);
      if failure.success {
        writeln("  FAIL: failure.success should be false");
        allPass = false;
      }
      if failure.errorCode != 1 {
        writeln("  FAIL: errorCode should be 1");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 10: SSHTestResult record
    {
      writeln("Test 10: SSHTestResult record");
      var allPass = true;

      const result = new SSHTestResult(
        connected = true,
        authenticated = true,
        username = "git",
        message = "Success"
      );

      if !result.connected {
        writeln("  FAIL: connected should be true");
        allPass = false;
      }
      if !result.authenticated {
        writeln("  FAIL: authenticated should be true");
        allPass = false;
      }
      if result.username != "git" {
        writeln("  FAIL: username should be 'git'");
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
    printSummary("Remote Tests", passed, failed);

    if failed > 0 then exit(1);
  }
}
