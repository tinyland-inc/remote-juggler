# Running Tests

Test suite for RemoteJuggler.

## Test Structure

```
test/
  unit/
    CoreTests.chpl        # Core type tests
    ConfigTests.chpl      # Config parsing tests
    IdentityTests.chpl    # Identity operation tests
    RemoteTests.chpl      # Remote URL tests
```

## Running Tests

### All Tests

```bash
make test
```

Or using the test runner script:

```bash
./scripts/run-tests.sh
```

### Individual Test Modules

```bash
# Build and run specific test
chpl -M src/remote_juggler \
     -M src \
     --main-module CoreTests \
     test/unit/CoreTests.chpl \
     -o target/test/CoreTests

./target/test/CoreTests
```

### With Verbose Output

```bash
./target/test/CoreTests --verbose
```

## Test Runner

The test runner (`scripts/run-tests.sh`) provides:

- Automatic test discovery
- JUnit XML output
- Color-coded results
- Summary statistics

### Output Format

```
=== RemoteJuggler Test Suite ===

Running CoreTests...
[32mPASSED: CoreTests[0m

Running ConfigTests...
[32mPASSED: ConfigTests[0m

=== Test Summary ===
Passed: 4
Failed: 0

JUnit report: test-results.xml
```

### JUnit XML

Results are written to `test-results.xml` for CI integration:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="RemoteJuggler" tests="4" failures="0">
  <testsuite name="unit" tests="4" failures="0">
    <testcase name="CoreTests" classname="unit.CoreTests"/>
    <testcase name="ConfigTests" classname="unit.ConfigTests"/>
  </testsuite>
</testsuites>
```

## Writing Tests

### Test Module Structure

```chapel
prototype module MyTests {
  use remote_juggler.Core;

  config const verbose = false;

  proc main() {
    writeln("=== My Module Tests ===\n");

    var passed = 0;
    var failed = 0;

    // Test 1
    {
      writeln("Test 1: Description");
      var allPass = true;

      // Test assertions
      if someCondition != expected {
        writeln("  FAIL: Reason");
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
    writeln("Tests: ", passed, " passed, ", failed, " failed");
    writeln("=".repeat(50));

    if failed > 0 then exit(1);
  }
}
```

### Test Assertions

Simple assertion pattern:

```chapel
if actual != expected {
  writeln("  FAIL: Expected '", expected, "', got '", actual, "'");
  allPass = false;
}
```

### Property-Based Tests

Test invariants across multiple inputs:

```chapel
{
  writeln("Test: URL transformations preserve repo path");
  var allPass = true;

  const testUrls = [
    "git@gitlab.com:user/repo.git",
    "git@github.com:org/project.git",
  ];

  for url in testUrls {
    const originalPath = extractRepoPath(url);
    const transformed = transformUrlForIdentity(url, "new-host");
    const transformedPath = extractRepoPath(transformed);

    if originalPath != transformedPath {
      writeln("  FAIL: Path changed for ", url);
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
```

## Test Coverage

### Core Module Tests

- Provider enum round-trip conversion
- CredentialSource enum round-trip conversion
- GitIdentity record initialization
- GPGConfig defaults
- SwitchContext initialization
- ToolResult states
- Path expansion

### Config Module Tests

- SSH host pattern matching
- Git URL parsing
- URL rewriting (insteadOf)
- SSH config line parsing
- Git config section detection
- Provider detection from hostname
- Edge cases (empty, malformed)

### Identity Module Tests

- Identity name normalization
- Identity matching by SSH host
- Identity filtering by provider
- Identity validation
- Email format validation
- Priority scoring
- Equality comparison
- JSON serialization roundtrip
- Normalized name validation
- Active identity detection

### Remote Module Tests

- Remote URL normalization
- SSH alias URL detection
- Remote name parsing
- Host extraction
- Repository path extraction
- URL transformation
- Provider detection
- URL validation
- Path preservation property

## CI Integration

Tests run automatically in CI:

```yaml
test:
  stage: test
  script:
    - make test
  artifacts:
    reports:
      junit: test-results.xml
```

## Troubleshooting

### Test Compilation Fails

Check module paths:

```bash
chpl -M src/remote_juggler -M src test/unit/CoreTests.chpl
```

### Test Times Out

Increase timeout in `scripts/run-tests.sh` or run directly.

### Missing Dependencies

Some tests may require stub modules. Check test imports.
