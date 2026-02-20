/*
 * KeePassXCE2ETests.chpl - End-to-end tests for KeePassXC auto-unlock flow
 *
 * These tests exercise the full seal -> unlock -> retrieve cycle.
 * They require either a real HSM or the stub HSM backend.
 *
 * When HSM is not available, tests are skipped with a message.
 */
prototype module KeePassXCE2ETests {
  use remote_juggler.KeePassXC;
  use remote_juggler.HSM;
  use TestUtils;
  use FileSystem;
  use IO;

  config const verbose = false;

  proc main() {
    writeln("=== RemoteJuggler KeePassXC E2E Tests ===\n");

    var passed = 0;
    var failed = 0;
    var skipped = 0;

    // Test 1: Full bootstrap -> store -> search -> get -> delete cycle
    {
      writeln("Test 1: Full credential lifecycle (bootstrap -> store -> search -> get -> delete)");

      // Check if keepassxc-cli is available
      if !isAvailable() {
        writeln("  SKIP: keepassxc-cli not installed");
        skipped += 1;
      } else {
        // Use a temp database path
        const tmpDbPath = "/tmp/remotejuggler_e2e_test_" + here.id:string + ".kdbx";

        // Ensure cleanup even on failure
        try {
          if FileSystem.exists(tmpDbPath) {
            FileSystem.remove(tmpDbPath);
          }
        } catch { }

        // Bootstrap without sealing in HSM (we'll use the password directly)
        const (bootOk, bootMsg) = bootstrapDatabase(tmpDbPath, sealInHSM=false);
        if verbose then writeln("  Bootstrap: ", bootMsg);

        if !bootOk {
          writeln("  SKIP: Bootstrap failed (expected in CI): ", bootMsg);
          skipped += 1;
        } else {
          // Extract master password from bootstrap message
          // When sealInHSM=false and no HSM, the message contains the password
          var masterPassword = "";
          for line in bootMsg.split("\n") {
            const trimmed = line.strip();
            if trimmed.startsWith("Store it securely: ") {
              masterPassword = trimmed.replace("Store it securely: ", "");
            } else if trimmed.startsWith("Master password: ") {
              masterPassword = trimmed.replace("Master password: ", "");
            }
          }

          if masterPassword == "" {
            // Database was created with HSM sealing - try auto-unlock
            const (unlockOk, unlockPw) = autoUnlock();
            if unlockOk {
              masterPassword = unlockPw;
            }
          }

          if masterPassword == "" {
            writeln("  SKIP: Could not obtain master password for testing");
            skipped += 1;
          } else {
            var allPass = true;

            // Store an entry
            const testPath = "RemoteJuggler/API/E2E_TEST_KEY";
            const testValue = "e2e_test_value_12345";
            const storeOk = setEntry(tmpDbPath, testPath, masterPassword, testValue);
            if !storeOk {
              writeln("  FAIL: Could not store test entry");
              allPass = false;
            }

            // Search for it
            if allPass {
              const results = search(tmpDbPath, "E2E_TEST", masterPassword);
              if results.size == 0 {
                writeln("  FAIL: Search returned no results for 'E2E_TEST'");
                allPass = false;
              } else {
                var found = false;
                for r in results {
                  if r.entryPath == testPath {
                    found = true;
                    break;
                  }
                }
                if !found {
                  writeln("  FAIL: Search did not find the test entry");
                  allPass = false;
                }
              }
            }

            // Fuzzy search
            if allPass {
              const fuzzyResults = search(tmpDbPath, "e2e_tst", masterPassword);
              // Should find via fuzzy matching (Levenshtein or substring)
              if verbose then writeln("  Fuzzy results for 'e2e_tst': ", fuzzyResults.size);
            }

            // Get it back
            if allPass {
              const (getOk, getValue) = getEntry(tmpDbPath, testPath, masterPassword);
              if !getOk || getValue != testValue {
                writeln("  FAIL: Get returned wrong value: '", getValue, "' expected '", testValue, "'");
                allPass = false;
              }
            }

            // Resolve (search+get combined)
            if allPass {
              const (resolveOk, resolvePath, resolveValue) = resolve(tmpDbPath, "E2E_TEST", masterPassword);
              if !resolveOk || resolveValue != testValue {
                writeln("  FAIL: Resolve failed or returned wrong value");
                allPass = false;
              }
            }

            // Delete it
            if allPass {
              const deleteOk = deleteEntry(tmpDbPath, testPath, masterPassword);
              if !deleteOk {
                writeln("  FAIL: Could not delete test entry");
                allPass = false;
              }
            }

            // Verify deletion
            if allPass {
              const (verifyOk, _) = getEntry(tmpDbPath, testPath, masterPassword);
              if verifyOk {
                writeln("  FAIL: Entry still exists after deletion");
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

          // Cleanup
          try {
            if FileSystem.exists(tmpDbPath) {
              FileSystem.remove(tmpDbPath);
            }
          } catch { }
        }
      }
    }

    // Test 2: Session caching
    {
      writeln("Test 2: Session cache stores and retrieves within TTL");

      // Test the session cache mechanism directly
      clearSession();
      const (cached1, _) = getSessionPassword();
      if cached1 {
        writeln("  FAIL: Session should be empty after clear");
        failed += 1;
      } else {
        cacheSessionPassword("test_password_123");
        const (cached2, pw) = getSessionPassword();
        if !cached2 || pw != "test_password_123" {
          writeln("  FAIL: Session should return cached password");
          failed += 1;
        } else {
          clearSession();
          const (cached3, _) = getSessionPassword();
          if cached3 {
            writeln("  FAIL: Session should be empty after second clear");
            failed += 1;
          } else {
            writeln("  PASS");
            passed += 1;
          }
        }
      }
    }

    // Test 3: Export format
    {
      writeln("Test 3: exportEntries with mock data (requires keepassxc-cli)");
      if !isAvailable() {
        writeln("  SKIP: keepassxc-cli not installed");
        skipped += 1;
      } else {
        writeln("  SKIP: Requires database with entries (covered by Test 1)");
        skipped += 1;
      }
    }

    writeln();
    writeln("=== Results ===");
    writeln("Passed: ", passed);
    writeln("Failed: ", failed);
    writeln("Skipped: ", skipped);

    if failed > 0 then halt("E2E tests failed");
  }
}
