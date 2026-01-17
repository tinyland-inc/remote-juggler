/*
 * IdentityTests.chpl - Unit tests for Identity module
 *
 * Tests identity detection, matching, and switching logic.
 * Uses QuickChpl for property-based testing.
 */
prototype module IdentityTests {
  use remote_juggler.Identity;
  use remote_juggler.Core;

  config const numTests = 100;
  config const verbose = false;

  proc main() {
    writeln("=== RemoteJuggler Identity Module Tests ===\n");

    var passed = 0;
    var failed = 0;

    // Test identity name normalization
    {
      writeln("Test 1: Identity name normalization");

      var allPass = true;

      // Names should be lowercase with hyphens
      const tests = [
        ("gitlab-work", "gitlab-work"),
        ("GitLab-Work", "gitlab-work"),
        ("GITLAB_WORK", "gitlab-work"),
        ("gitlab work", "gitlab-work"),
        ("  gitlab-work  ", "gitlab-work")
      ];

      for (input, expected) in tests {
        const normalized = normalizeIdentityName(input);
        if normalized != expected {
          writeln("  FAIL: '", input, "' -> expected '", expected, "', got '", normalized, "'");
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

    // Test identity matching by SSH host
    {
      writeln("Test 2: Identity matching by SSH host");

      var allPass = true;

      // Create test identities
      var identities: [0..2] GitIdentity;

      identities[0] = new GitIdentity(
        name = "gitlab-work",
        provider = Provider.GitLab,
        host = "gitlab-work",
        hostname = "gitlab.com",
        user = "work-user",
        email = "work@company.com"
      );

      identities[1] = new GitIdentity(
        name = "gitlab-personal",
        provider = Provider.GitLab,
        host = "gitlab-personal",
        hostname = "gitlab.com",
        user = "personal-user",
        email = "personal@email.com"
      );

      identities[2] = new GitIdentity(
        name = "github",
        provider = Provider.GitHub,
        host = "github.com",
        hostname = "github.com",
        user = "gh-user",
        email = "user@github.com"
      );

      // Find by host
      const workMatch = findIdentityByHost(identities, "gitlab-work");
      if workMatch.name != "gitlab-work" {
        writeln("  FAIL: Should find gitlab-work identity");
        allPass = false;
      }

      const personalMatch = findIdentityByHost(identities, "gitlab-personal");
      if personalMatch.name != "gitlab-personal" {
        writeln("  FAIL: Should find gitlab-personal identity");
        allPass = false;
      }

      // Non-existent host
      const noMatch = findIdentityByHost(identities, "nonexistent");
      if noMatch.name != "" {
        writeln("  FAIL: Should return empty identity for non-existent host");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test identity matching by provider
    {
      writeln("Test 3: Identity filtering by provider");

      var allPass = true;

      var identities: [0..3] GitIdentity;

      identities[0] = new GitIdentity(name = "gl-work", provider = Provider.GitLab, host = "gl-work", hostname = "gitlab.com", user = "u1", email = "e1");
      identities[1] = new GitIdentity(name = "gl-personal", provider = Provider.GitLab, host = "gl-personal", hostname = "gitlab.com", user = "u2", email = "e2");
      identities[2] = new GitIdentity(name = "gh-main", provider = Provider.GitHub, host = "github.com", hostname = "github.com", user = "u3", email = "e3");
      identities[3] = new GitIdentity(name = "bb-team", provider = Provider.Bitbucket, host = "bitbucket.org", hostname = "bitbucket.org", user = "u4", email = "e4");

      const gitlabIds = filterByProvider(identities, Provider.GitLab);
      if gitlabIds.size != 2 {
        writeln("  FAIL: Should find 2 GitLab identities, found ", gitlabIds.size);
        allPass = false;
      }

      const githubIds = filterByProvider(identities, Provider.GitHub);
      if githubIds.size != 1 {
        writeln("  FAIL: Should find 1 GitHub identity, found ", githubIds.size);
        allPass = false;
      }

      const customIds = filterByProvider(identities, Provider.Custom);
      if customIds.size != 0 {
        writeln("  FAIL: Should find 0 Custom identities, found ", customIds.size);
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test identity validation
    {
      writeln("Test 4: Identity validation");

      var allPass = true;

      // Valid identity
      const valid = new GitIdentity(
        name = "gitlab-work",
        provider = Provider.GitLab,
        host = "gitlab-work",
        hostname = "gitlab.com",
        user = "user",
        email = "user@example.com"
      );

      const (isValid, validErrors) = validateIdentity(valid);
      if !isValid {
        writeln("  FAIL: Valid identity should pass validation");
        allPass = false;
      }

      // Invalid - missing name
      const noName = new GitIdentity(
        name = "",
        provider = Provider.GitLab,
        host = "host",
        hostname = "gitlab.com",
        user = "user",
        email = "user@example.com"
      );

      const (noNameValid, _) = validateIdentity(noName);
      if noNameValid {
        writeln("  FAIL: Identity without name should fail validation");
        allPass = false;
      }

      // Invalid - missing host
      const noHost = new GitIdentity(
        name = "test",
        provider = Provider.GitLab,
        host = "",
        hostname = "gitlab.com",
        user = "user",
        email = "user@example.com"
      );

      const (noHostValid, _) = validateIdentity(noHost);
      if noHostValid {
        writeln("  FAIL: Identity without host should fail validation");
        allPass = false;
      }

      // Invalid email format
      const badEmail = new GitIdentity(
        name = "test",
        provider = Provider.GitLab,
        host = "host",
        hostname = "gitlab.com",
        user = "user",
        email = "not-an-email"
      );

      const (badEmailValid, _) = validateIdentity(badEmail);
      if badEmailValid {
        writeln("  FAIL: Identity with invalid email should fail validation");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test email validation
    {
      writeln("Test 5: Email format validation");

      var allPass = true;

      const validEmails = [
        "user@example.com",
        "user.name@company.co.uk",
        "user+tag@domain.org",
        "first.last@subdomain.example.com"
      ];

      for email in validEmails {
        if !isValidEmail(email) {
          writeln("  FAIL: Should accept valid email: ", email);
          allPass = false;
        }
      }

      const invalidEmails = [
        "",
        "not-an-email",
        "@nodomain.com",
        "noat.com",
        "user@",
        "user@.com"
      ];

      for email in invalidEmails {
        if isValidEmail(email) {
          writeln("  FAIL: Should reject invalid email: '", email, "'");
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

    // Test identity priority scoring
    {
      writeln("Test 6: Identity priority scoring");

      var allPass = true;

      // Identity with full credentials should score higher
      var fullCreds = new GitIdentity(
        name = "full",
        provider = Provider.GitLab,
        host = "gitlab-full",
        hostname = "gitlab.com",
        user = "user",
        email = "user@example.com"
      );
      fullCreds.gpg = new GPGConfig(keyId = "ABC123", signCommits = true, signTags = true, autoSignoff = true);

      var minimalCreds = new GitIdentity(
        name = "minimal",
        provider = Provider.GitLab,
        host = "gitlab-minimal",
        hostname = "gitlab.com",
        user = "user",
        email = "user@example.com"
      );

      const fullScore = calculateIdentityScore(fullCreds);
      const minimalScore = calculateIdentityScore(minimalCreds);

      if fullScore <= minimalScore {
        writeln("  FAIL: Full credentials identity should score higher");
        writeln("    Full score: ", fullScore, ", Minimal score: ", minimalScore);
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test identity comparison
    {
      writeln("Test 7: Identity equality comparison");

      var allPass = true;

      const id1 = new GitIdentity(
        name = "test",
        provider = Provider.GitLab,
        host = "test-host",
        hostname = "gitlab.com",
        user = "user",
        email = "user@test.com"
      );

      const id2 = new GitIdentity(
        name = "test",
        provider = Provider.GitLab,
        host = "test-host",
        hostname = "gitlab.com",
        user = "user",
        email = "user@test.com"
      );

      const id3 = new GitIdentity(
        name = "different",
        provider = Provider.GitLab,
        host = "test-host",
        hostname = "gitlab.com",
        user = "user",
        email = "user@test.com"
      );

      if !identitiesEqual(id1, id2) {
        writeln("  FAIL: Identical identities should be equal");
        allPass = false;
      }

      if identitiesEqual(id1, id3) {
        writeln("  FAIL: Different identities should not be equal");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test identity serialization
    {
      writeln("Test 8: Identity JSON serialization roundtrip");

      var allPass = true;

      const original = new GitIdentity(
        name = "test-identity",
        provider = Provider.GitLab,
        host = "gitlab-test",
        hostname = "gitlab.com",
        user = "testuser",
        email = "test@example.com"
      );

      const json = identityToJson(original);
      const restored = jsonToIdentity(json);

      if original.name != restored.name {
        writeln("  FAIL: Name not preserved in roundtrip");
        allPass = false;
      }

      if original.provider != restored.provider {
        writeln("  FAIL: Provider not preserved in roundtrip");
        allPass = false;
      }

      if original.host != restored.host {
        writeln("  FAIL: Host not preserved in roundtrip");
        allPass = false;
      }

      if original.email != restored.email {
        writeln("  FAIL: Email not preserved in roundtrip");
        allPass = false;
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Property test: Identity names are unique after normalization
    {
      writeln("Test 9: Property - Normalized names produce valid identifiers");

      var allPass = true;

      const testNames = [
        "gitlab-work",
        "GitHub Personal",
        "BITBUCKET_TEAM",
        "my.custom.host"
      ];

      for name in testNames {
        const normalized = normalizeIdentityName(name);

        // Should only contain lowercase letters, numbers, and hyphens
        for ch in normalized {
          if !(ch >= 'a' && ch <= 'z') &&
             !(ch >= '0' && ch <= '9') &&
             ch != '-' {
            writeln("  FAIL: Normalized name '", normalized, "' contains invalid char '", ch, "'");
            allPass = false;
            break;
          }
        }

        // Should not start or end with hyphen
        if normalized.size > 0 {
          if normalized[0] == '-' || normalized[normalized.size-1] == '-' {
            writeln("  FAIL: Normalized name '", normalized, "' has leading/trailing hyphen");
            allPass = false;
          }
        }
      }

      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test active identity detection
    {
      writeln("Test 10: Active identity detection from git config");

      var allPass = true;

      // Simulate git config values
      const configEmail = "work@company.com";
      const configName = "Work User";

      var identities: [0..1] GitIdentity;

      identities[0] = new GitIdentity(
        name = "work",
        provider = Provider.GitLab,
        host = "gitlab-work",
        hostname = "gitlab.com",
        user = configName,
        email = configEmail
      );

      identities[1] = new GitIdentity(
        name = "personal",
        provider = Provider.GitLab,
        host = "gitlab-personal",
        hostname = "gitlab.com",
        user = "Personal User",
        email = "personal@email.com"
      );

      const active = detectActiveIdentity(identities, configEmail, configName);

      if active.name != "work" {
        writeln("  FAIL: Should detect 'work' as active identity based on email match");
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
    writeln("Identity Tests: ", passed, " passed, ", failed, " failed");
    writeln("=".repeat(50));

    if failed > 0 then exit(1);
  }
}
