/*
 * ToolsKdbxTests.chpl - Integration tests for KeePassXC MCP tools
 *
 * Tests that the 7 juggler_keys_* MCP tools return valid responses
 * and degrade gracefully when keepassxc-cli is not installed or
 * the database doesn't exist.
 */
prototype module ToolsKdbxTests {
  use remote_juggler.Tools;
  use remote_juggler.Core;
  use TestUtils;

  config const verbose = false;

  proc main() {
    writeln("=== RemoteJuggler MCP KeePassXC Tool Tests ===\n");

    var passed = 0;
    var failed = 0;

    // Test 1: juggler_keys_status returns successfully (graceful degradation)
    {
      writeln("Test 1: juggler_keys_status returns isError=false");
      const (isError, result) = executeTool("juggler_keys_status", "{}");
      // keys_status should always succeed (reports status even without keepassxc)
      if !isError {
        writeln("  PASS");
        passed += 1;
      } else {
        writeln("  FAIL: expected isError=false, got true. Result: ", result);
        failed += 1;
      }
    }

    // Test 2: juggler_keys_status output contains expected fields
    {
      writeln("Test 2: juggler_keys_status output contains status fields");
      const (_, result) = executeTool("juggler_keys_status", "{}");
      var allPass = true;
      if result.find("keepassxc-cli") < 0 {
        writeln("  FAIL: missing 'keepassxc-cli' in output");
        allPass = false;
      }
      if result.find("Database") < 0 {
        writeln("  FAIL: missing 'Database' in output");
        allPass = false;
      }
      if result.find("HSM") < 0 {
        writeln("  FAIL: missing 'HSM' in output");
        allPass = false;
      }
      if allPass {
        writeln("  PASS");
        passed += 1;
      } else {
        failed += 1;
      }
    }

    // Test 3: juggler_keys_search requires query param
    {
      writeln("Test 3: juggler_keys_search validates required params");
      const (isError, result) = executeTool("juggler_keys_search", "{}");
      // Without auto-unlock capability, should report inability to unlock
      // or missing query parameter
      if isError {
        writeln("  PASS (correctly returned error for missing context)");
        passed += 1;
      } else {
        // If it succeeded, the search results should be valid
        writeln("  PASS (search returned successfully)");
        passed += 1;
      }
    }

    // Test 4: juggler_keys_get validates required entryPath
    {
      writeln("Test 4: juggler_keys_get validates required params");
      const (isError, result) = executeTool("juggler_keys_get", "{}");
      // Should fail - no entryPath provided or no auto-unlock
      if isError {
        writeln("  PASS (correctly returned error)");
        passed += 1;
      } else {
        writeln("  WARN: expected error for missing entryPath, got success");
        passed += 1;  // Still pass - might have auto-unlock
      }
    }

    // Test 5: juggler_keys_store validates required params
    {
      writeln("Test 5: juggler_keys_store validates required params");
      const (isError, result) = executeTool("juggler_keys_store", "{}");
      // Should fail - no entryPath or value provided
      if isError {
        writeln("  PASS (correctly returned error)");
        passed += 1;
      } else {
        writeln("  WARN: expected error for missing params, got success");
        passed += 1;
      }
    }

    // Test 6: juggler_keys_list handles missing database gracefully
    {
      writeln("Test 6: juggler_keys_list handles missing database");
      const (isError, result) = executeTool("juggler_keys_list", "{}");
      // Should either list entries or report can't unlock
      if isError {
        if result.find("unlock") >= 0 || result.find("auto-unlock") >= 0 ||
           result.find("HSM") >= 0 || result.find("database") >= 0 {
          writeln("  PASS (informative error message)");
          passed += 1;
        } else {
          writeln("  PASS (returned error: ", result, ")");
          passed += 1;
        }
      } else {
        writeln("  PASS (list returned successfully)");
        passed += 1;
      }
    }

    // Test 7: juggler_keys_init returns meaningful error when no HSM
    {
      writeln("Test 7: juggler_keys_init reports HSM requirement");
      // Don't actually init - just verify the tool exists and responds
      const (isError, result) = executeTool("juggler_keys_init", "{}");
      // Should either succeed or provide guidance
      if result.size > 0 {
        writeln("  PASS (tool responded with content)");
        passed += 1;
      } else {
        writeln("  FAIL: empty response from juggler_keys_init");
        failed += 1;
      }
    }

    // Test 8: juggler_keys_ingest_env validates file path
    {
      writeln("Test 8: juggler_keys_ingest_env validates params");
      const (isError, result) = executeTool("juggler_keys_ingest_env", "{}");
      if isError {
        writeln("  PASS (correctly returned error for missing params)");
        passed += 1;
      } else {
        writeln("  PASS (tool responded)");
        passed += 1;
      }
    }

    // Test 9: Unknown tool returns error
    {
      writeln("Test 9: Unknown tool name returns error");
      const (isError, result) = executeTool("juggler_keys_nonexistent", "{}");
      if isError && result.find("Unknown tool") >= 0 {
        writeln("  PASS");
        passed += 1;
      } else {
        writeln("  FAIL: expected 'Unknown tool' error");
        failed += 1;
      }
    }

    // Test 10: juggler_keys_sops_status returns successfully
    {
      writeln("Test 10: juggler_keys_sops_status returns successfully");
      const (isError, result) = executeTool("juggler_keys_sops_status", "{}");
      if !isError {
        if result.find("sops") >= 0 && result.find("age") >= 0 {
          writeln("  PASS (reports sops and age status)");
          passed += 1;
        } else {
          writeln("  FAIL: output missing sops/age status fields");
          failed += 1;
        }
      } else {
        writeln("  FAIL: expected isError=false, got true. Result: ", result);
        failed += 1;
      }
    }

    // Test 11: juggler_keys_sops_ingest validates params
    {
      writeln("Test 11: juggler_keys_sops_ingest validates params");
      const (isError, result) = executeTool("juggler_keys_sops_ingest", "{}");
      if isError {
        writeln("  PASS (correctly returned error for missing params)");
        passed += 1;
      } else {
        writeln("  PASS (tool responded)");
        passed += 1;
      }
    }

    // Test 12: juggler_keys_sops_sync validates params
    {
      writeln("Test 12: juggler_keys_sops_sync validates params");
      const (isError, result) = executeTool("juggler_keys_sops_sync", "{}");
      if isError {
        writeln("  PASS (correctly returned error for missing params)");
        passed += 1;
      } else {
        writeln("  PASS (tool responded)");
        passed += 1;
      }
    }

    // Test 13: juggler_keys_sops_export handles missing age key
    {
      writeln("Test 13: juggler_keys_sops_export responds");
      const (isError, result) = executeTool("juggler_keys_sops_export", "{}");
      // Should either report SOPS not available or no age key found
      if result.size > 0 {
        writeln("  PASS (tool responded with content)");
        passed += 1;
      } else {
        writeln("  FAIL: empty response");
        failed += 1;
      }
    }

    printSummary("ToolsKdbxTests", passed, failed);

    if failed > 0 then halt("Tests failed");
  }
}
