/*
 * CoreTests.chpl - Unit tests for Core module
 *
 * Tests type definitions, enum conversions, and helper functions.
 * Uses QuickChpl for property-based testing.
 */
prototype module CoreTests {
  use remote_juggler.Core;

  config const numTests = 100;
  config const verbose = false;

  proc main() {
    writeln("=== RemoteJuggler Core Module Tests ===\n");

    var passed = 0;
    var failed = 0;

    // Test Provider enum conversions
    {
      writeln("Test 1: Provider enum round-trip conversion");
      var allPass = true;

      for p in Provider {
        const str = providerToString(p);
        const back = stringToProvider(str);
        if back != p {
          writeln("  FAIL: ", p, " -> '", str, "' -> ", back);
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

    // Test CredentialSource enum conversions
    {
      writeln("Test 2: CredentialSource enum round-trip conversion");
      var allPass = true;

      for cs in CredentialSource {
        const str = credentialSourceToString(cs);
        const back = stringToCredentialSource(str);
        if back != cs {
          writeln("  FAIL: ", cs, " -> '", str, "' -> ", back);
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

    // Test GitIdentity record creation
    {
      writeln("Test 3: GitIdentity record initialization");

      const identity = new GitIdentity(
        name = "test-identity",
        provider = Provider.GitLab,
        host = "gitlab-test",
        hostname = "gitlab.com",
        user = "testuser",
        email = "test@example.com"
      );

      var allPass = true;
      if identity.name != "test-identity" { allPass = false; writeln("  FAIL: name"); }
      if identity.provider != Provider.GitLab { allPass = false; writeln("  FAIL: provider"); }
      if identity.host != "gitlab-test" { allPass = false; writeln("  FAIL: host"); }
      if identity.hostname != "gitlab.com" { allPass = false; writeln("  FAIL: hostname"); }
      if identity.user != "testuser" { allPass = false; writeln("  FAIL: user"); }
      if identity.email != "test@example.com" { allPass = false; writeln("  FAIL: email"); }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test GPGConfig record
    {
      writeln("Test 4: GPGConfig record defaults");

      const gpg = new GPGConfig();

      var allPass = true;
      if gpg.keyId != "" { allPass = false; writeln("  FAIL: keyId should be empty"); }
      if gpg.signCommits != false { allPass = false; writeln("  FAIL: signCommits should be false"); }
      if gpg.signTags != false { allPass = false; writeln("  FAIL: signTags should be false"); }
      if gpg.autoSignoff != false { allPass = false; writeln("  FAIL: autoSignoff should be false"); }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test SwitchContext record
    {
      writeln("Test 5: SwitchContext record initialization");

      const ctx = new SwitchContext(
        currentIdentity = "personal",
        lastSwitch = "2026-01-15T10:00:00Z",
        repoPath = "/home/user/project"
      );

      var allPass = true;
      if ctx.currentIdentity != "personal" { allPass = false; }
      if ctx.lastSwitch != "2026-01-15T10:00:00Z" { allPass = false; }
      if ctx.repoPath != "/home/user/project" { allPass = false; }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test ToolResult record
    {
      writeln("Test 6: ToolResult success and failure states");

      const success = new ToolResult(success = true, message = "OK", data = "{}");
      const failure = new ToolResult(success = false, message = "Error", data = "");

      var allPass = true;
      if !success.success { allPass = false; writeln("  FAIL: success.success"); }
      if success.message != "OK" { allPass = false; writeln("  FAIL: success.message"); }
      if failure.success { allPass = false; writeln("  FAIL: failure.success"); }
      if failure.message != "Error" { allPass = false; writeln("  FAIL: failure.message"); }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test expandTilde helper
    {
      writeln("Test 7: expandTilde path expansion");

      // This test depends on HOME being set
      const home = getEnvOrDefault("HOME", "/tmp");
      const expanded = expandTilde("~/.config/test");
      const expected = home + "/.config/test";

      if expanded == expected {
        writeln("  PASS");
        passed += 1;
      } else {
        writeln("  FAIL: expected '", expected, "', got '", expanded, "'");
        failed += 1;
      }
    }

    // Property-based test: Provider string conversion is never empty
    {
      writeln("Test 8: Property - Provider strings are non-empty");

      var allPass = true;
      for p in Provider {
        const str = providerToString(p);
        if str.size == 0 {
          writeln("  FAIL: Provider ", p, " has empty string");
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

    // Summary
    writeln();
    writeln("=".repeat(50));
    writeln("Core Tests: ", passed, " passed, ", failed, " failed");
    writeln("=".repeat(50));

    if failed > 0 then exit(1);
  }
}
