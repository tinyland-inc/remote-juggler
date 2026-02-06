/*
 * KeePassXC.chpl - KeePassXC Credential Authority Module
 *
 * Wraps keepassxc-cli to provide CRUD operations on a kdbx database.
 * RemoteJuggler uses this as a trusted credential authority for ALL secrets:
 * SSH keys, GPG passphrases, API tokens, .env files, and infrastructure creds.
 *
 * Trust Model:
 *   TPM/SecureEnclave stores the kdbx master password.
 *   + YubiKey presence (ykman info succeeds)
 *   = Machine is TRUSTED -> agents get credential access without prompts.
 *
 * Database Layout (default path: ~/.remotejuggler/keys.kdbx):
 *   RemoteJuggler/
 *   ├── SSH/           - SSH key metadata, passphrases
 *   ├── GPG/           - GPG key IDs, passphrases
 *   ├── Tokens/        - Provider PATs (GitLab, GitHub)
 *   ├── API/           - API keys (PERPLEXITY_API_KEY, etc.)
 *   ├── Infrastructure/ - sudo passwords, kubeconfig creds
 *   └── Environments/  - Ingested .env files (path-based layout)
 *
 * All keepassxc-cli commands receive the master password via stdin pipe,
 * never as a CLI argument.
 *
 * :author: RemoteJuggler Team
 * :version: 2.0.0
 */
prototype module KeePassXC {
  use IO;
  use List;
  use FileSystem;
  use Subprocess;
  use Path;
  use super.Core only getEnvVar, getEnvOrDefault, expandTilde, verboseLog;
  public use super.HSM;

  // ============================================================================
  // Constants
  // ============================================================================

  /* Default database path */
  param DEFAULT_DB_PATH = "~/.remotejuggler/keys.kdbx";

  /* HSM identity label for the kdbx master password */
  param KDBX_HSM_IDENTITY = "kdbx-master";

  /* Default group hierarchy to create on bootstrap */
  const BOOTSTRAP_GROUPS = [
    "RemoteJuggler",
    "RemoteJuggler/SSH",
    "RemoteJuggler/GPG",
    "RemoteJuggler/Tokens",
    "RemoteJuggler/Tokens/GitLab",
    "RemoteJuggler/Tokens/GitHub",
    "RemoteJuggler/API",
    "RemoteJuggler/Infrastructure",
    "RemoteJuggler/Infrastructure/sudo",
    "RemoteJuggler/Infrastructure/kubeconfig",
    "RemoteJuggler/Infrastructure/ansible-vault",
    "RemoteJuggler/Environments"
  ];

  // ============================================================================
  // Search Result Type
  // ============================================================================

  /*
   * SearchResult - A single fuzzy search match.
   *
   * :var entryPath: Full path within the database (e.g., "RemoteJuggler/API/PERPLEXITY_API_KEY")
   * :var title: Entry title
   * :var matchContext: Brief description of why this matched
   * :var score: Relevance score (higher = better match)
   */
  record SearchResult {
    var entryPath: string = "";
    var title: string = "";
    var matchContext: string = "";
    var score: int = 0;

    proc init() {
      this.entryPath = "";
      this.title = "";
      this.matchContext = "";
      this.score = 0;
    }

    proc init(entryPath: string, title: string, matchContext: string, score: int) {
      this.entryPath = entryPath;
      this.title = title;
      this.matchContext = matchContext;
      this.score = score;
    }
  }

  // ============================================================================
  // Detection & Availability
  // ============================================================================

  /*
   * Check if keepassxc-cli is available on the system.
   *
   * :returns: true if keepassxc-cli is found in PATH
   */
  proc isAvailable(): bool {
    try {
      var p = spawn(["which", "keepassxc-cli"],
                    stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Get the configured database path.
   *
   * Reads from config settings, falls back to default.
   *
   * :returns: Expanded database file path
   */
  proc getDatabasePath(): string {
    // Try reading from config
    const configDbPath = getEnvVar("REMOTE_JUGGLER_KDBX_PATH");
    if configDbPath != "" {
      return expandTilde(configDbPath);
    }
    return expandTilde(DEFAULT_DB_PATH);
  }

  /*
   * Check if the database file exists.
   *
   * :returns: true if the kdbx file exists at the configured path
   */
  proc databaseExists(): bool {
    const dbPath = getDatabasePath();
    try {
      return FileSystem.exists(dbPath);
    } catch {
      return false;
    }
  }

  // ============================================================================
  // Unlock Flow (TPM/SE + YubiKey)
  // ============================================================================

  /*
   * Check if auto-unlock is possible.
   *
   * Auto-unlock requires:
   * 1. HSM available (TPM or Secure Enclave)
   * 2. Master password sealed in HSM
   * 3. YubiKey present (physical security anchor)
   *
   * :returns: true if all conditions met for auto-unlock
   */
  proc canAutoUnlock(): bool {
    // Check HSM
    if hsm_is_available() == 0 {
      return false;
    }

    // Check if master password is sealed
    if hsm_has_pin(KDBX_HSM_IDENTITY) == 0 {
      return false;
    }

    // Check YubiKey presence
    return isYubiKeyPresent();
  }

  /*
   * Check if a YubiKey is currently connected.
   *
   * :returns: true if ykman can detect a YubiKey
   */
  proc isYubiKeyPresent(): bool {
    try {
      var p = spawn(["ykman", "info"],
                    stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Auto-unlock the database by retrieving the master password from HSM.
   *
   * :returns: (success, masterPassword) - password is empty on failure
   */
  proc autoUnlock(): (bool, string) {
    if !canAutoUnlock() {
      return (false, "");
    }

    // Retrieve sealed master password from HSM
    var pinBuf: [0..#256] uint(8);
    var pinLen: c_size_t = 0;
    const result = hsm_retrieve_pin(KDBX_HSM_IDENTITY, c_ptrTo(pinBuf), pinLen);

    if result != HSM_SUCCESS {
      verboseLog("KeePassXC: Failed to retrieve master password from HSM: ",
                 hsm_error_message(result));
      return (false, "");
    }

    // Convert to string
    try {
      var password: string;
      for i in 0..<pinLen:int {
        password += chr(pinBuf[i]:int);
      }
      // Zero out the buffer
      for i in 0..<256 {
        pinBuf[i] = 0;
      }
      return (true, password);
    } catch {
      return (false, "");
    }
  }

  /*
   * Check if the database is currently accessible (can be opened).
   *
   * :returns: true if auto-unlock succeeds and database can be read
   */
  proc isUnlocked(): bool {
    if !databaseExists() {
      return false;
    }

    const (ok, password) = autoUnlock();
    if !ok {
      return false;
    }

    const dbPath = getDatabasePath();
    // Test by listing root group
    const (listOk, _) = listEntries(dbPath, "", password);
    return listOk;
  }

  // ============================================================================
  // CRUD Operations
  // ============================================================================

  /*
   * Get a secret value from the database.
   *
   * :arg dbPath: Path to the kdbx file
   * :arg entryPath: Entry path within the database
   * :arg password: Master password for the database
   * :returns: (success, secretValue)
   */
  proc getEntry(dbPath: string, entryPath: string, password: string): (bool, string) {
    try {
      var p = spawn(["keepassxc-cli", "show", "-s", "-a", "Password", dbPath, entryPath],
                    stdin=pipeStyle.pipe, stdout=pipeStyle.pipe, stderr=pipeStyle.pipe);
      p.stdin.write(password + "\n");
      p.stdin.close();
      p.wait();

      if p.exitCode == 0 {
        var value: string;
        p.stdout.readAll(value);
        return (true, value.strip());
      } else {
        var errMsg: string;
        p.stderr.readAll(errMsg);
        verboseLog("KeePassXC getEntry failed: ", errMsg.strip());
        return (false, "");
      }
    } catch e {
      verboseLog("KeePassXC getEntry error: ", e.message());
      return (false, "");
    }
  }

  /*
   * Store or update a secret in the database.
   *
   * Creates the entry if it doesn't exist, updates if it does.
   *
   * :arg dbPath: Path to the kdbx file
   * :arg entryPath: Entry path within the database
   * :arg password: Master password
   * :arg value: Secret value to store
   * :returns: true on success
   */
  proc setEntry(dbPath: string, entryPath: string, password: string, value: string): bool {
    // Try to edit first (entry exists)
    try {
      var p = spawn(["keepassxc-cli", "edit", "-p", dbPath, entryPath],
                    stdin=pipeStyle.pipe, stdout=pipeStyle.close, stderr=pipeStyle.pipe);
      p.stdin.write(password + "\n" + value + "\n");
      p.stdin.close();
      p.wait();

      if p.exitCode == 0 {
        return true;
      }
    } catch { }

    // Entry doesn't exist, create it
    try {
      var p = spawn(["keepassxc-cli", "add", "-p", dbPath, entryPath],
                    stdin=pipeStyle.pipe, stdout=pipeStyle.close, stderr=pipeStyle.pipe);
      p.stdin.write(password + "\n" + value + "\n");
      p.stdin.close();
      p.wait();

      return p.exitCode == 0;
    } catch e {
      verboseLog("KeePassXC setEntry error: ", e.message());
      return false;
    }
  }

  /*
   * Delete an entry from the database.
   *
   * :arg dbPath: Path to the kdbx file
   * :arg entryPath: Entry path within the database
   * :arg password: Master password
   * :returns: true on success
   */
  proc deleteEntry(dbPath: string, entryPath: string, password: string): bool {
    try {
      var p = spawn(["keepassxc-cli", "rm", dbPath, entryPath],
                    stdin=pipeStyle.pipe, stdout=pipeStyle.close, stderr=pipeStyle.pipe);
      p.stdin.write(password + "\n");
      p.stdin.close();
      p.wait();

      return p.exitCode == 0;
    } catch e {
      verboseLog("KeePassXC deleteEntry error: ", e.message());
      return false;
    }
  }

  /*
   * List entries in a group.
   *
   * :arg dbPath: Path to the kdbx file
   * :arg group: Group path (empty for root)
   * :arg password: Master password
   * :returns: (success, list of entry names)
   */
  proc listEntries(dbPath: string, group: string, password: string): (bool, list(string)) {
    var entries: list(string);
    try {
      var args: list(string);
      args.pushBack("keepassxc-cli");
      args.pushBack("ls");
      args.pushBack(dbPath);
      if group != "" {
        args.pushBack(group);
      }

      var p = spawn(args.toArray(),
                    stdin=pipeStyle.pipe, stdout=pipeStyle.pipe, stderr=pipeStyle.pipe);
      p.stdin.write(password + "\n");
      p.stdin.close();
      p.wait();

      if p.exitCode == 0 {
        var output: string;
        p.stdout.readAll(output);
        for line in output.split("\n") {
          const trimmed = line.strip();
          if trimmed != "" {
            entries.pushBack(trimmed);
          }
        }
        return (true, entries);
      } else {
        return (false, entries);
      }
    } catch e {
      verboseLog("KeePassXC listEntries error: ", e.message());
      return (false, entries);
    }
  }

  // ============================================================================
  // Search
  // ============================================================================

  /*
   * Search the database using keepassxc-cli search + in-process fuzzy matching.
   *
   * Strategy (fast path first):
   * 1. keepassxc-cli search for exact/prefix matches
   * 2. For fuzzy: list all entries, then in-process Levenshtein/substring match
   *
   * :arg dbPath: Path to the kdbx file
   * :arg query: Search query string
   * :arg password: Master password
   * :returns: List of ranked SearchResult (no secrets included)
   */
  proc search(dbPath: string, query: string, password: string): list(SearchResult) {
    var results: list(SearchResult);
    const lowerQuery = query.toLower();

    // Step 1: keepassxc-cli search for exact/prefix matches
    try {
      var p = spawn(["keepassxc-cli", "search", dbPath, query],
                    stdin=pipeStyle.pipe, stdout=pipeStyle.pipe, stderr=pipeStyle.close);
      p.stdin.write(password + "\n");
      p.stdin.close();
      p.wait();

      if p.exitCode == 0 {
        var output: string;
        p.stdout.readAll(output);
        for line in output.split("\n") {
          const trimmed = line.strip();
          if trimmed != "" {
            // Extract just the entry name (last path component)
            var title = trimmed;
            const lastSlash = trimmed.rfind("/");
            if lastSlash >= 0 {
              title = trimmed[lastSlash+1..];
            }
            results.pushBack(new SearchResult(
              entryPath = trimmed,
              title = title,
              matchContext = "exact match",
              score = 100
            ));
          }
        }
      }
    } catch { }

    // Step 2: If few results, do fuzzy matching against all entries
    if results.size < 5 {
      try {
        var p = spawn(["keepassxc-cli", "ls", "-R", dbPath],
                      stdin=pipeStyle.pipe, stdout=pipeStyle.pipe, stderr=pipeStyle.close);
        p.stdin.write(password + "\n");
        p.stdin.close();
        p.wait();

        if p.exitCode == 0 {
          var output: string;
          p.stdout.readAll(output);

          for line in output.split("\n") {
            const trimmed = line.strip();
            if trimmed == "" || trimmed.endsWith("/") {
              continue; // Skip empty lines and group headers
            }

            const lowerEntry = trimmed.toLower();

            // Skip entries already found
            var alreadyFound = false;
            for existing in results {
              if existing.entryPath == trimmed {
                alreadyFound = true;
                break;
              }
            }
            if alreadyFound then continue;

            // Substring match
            if lowerEntry.find(lowerQuery) != -1 {
              var title = trimmed;
              const lastSlash = trimmed.rfind("/");
              if lastSlash >= 0 {
                title = trimmed[lastSlash+1..];
              }
              results.pushBack(new SearchResult(
                entryPath = trimmed,
                title = title,
                matchContext = "substring match",
                score = 50
              ));
            }
          }
        }
      } catch { }
    }

    // Sort by score descending (simple bubble sort for small lists)
    for i in 0..<results.size {
      for j in i+1..<results.size {
        if results[j].score > results[i].score {
          const tmp = results[i];
          results[i] = results[j];
          results[j] = tmp;
        }
      }
    }

    return results;
  }

  // ============================================================================
  // Bootstrap
  // ============================================================================

  /*
   * Bootstrap a new kdbx database.
   *
   * 1. Generate random master password (32 chars)
   * 2. Create database with keepassxc-cli db-create
   * 3. Create group hierarchy
   * 4. Seal master password in TPM/SE
   * 5. Verify round-trip
   *
   * :arg dbPath: Path for the new database (created if not exists)
   * :arg sealInHSM: Whether to seal master password in HSM
   * :returns: (success, message)
   */
  proc bootstrapDatabase(dbPath: string, sealInHSM: bool = true): (bool, string) {
    if !isAvailable() {
      return (false, "keepassxc-cli not found in PATH. Install KeePassXC first.");
    }

    // Check if database already exists
    try {
      if FileSystem.exists(dbPath) {
        return (false, "Database already exists at " + dbPath +
                ". Use a different path or delete the existing database.");
      }
    } catch { }

    // Ensure parent directory exists
    const parentDir = dbPath[0..#dbPath.rfind("/")];
    try {
      if !FileSystem.exists(parentDir) {
        FileSystem.mkdir(parentDir, parents=true);
      }
    } catch e {
      return (false, "Failed to create directory: " + e.message());
    }

    // Generate random master password (32 chars, alphanumeric + symbols)
    var masterPassword = generateRandomPassword(32);

    // Create database
    try {
      var p = spawn(["keepassxc-cli", "db-create", "--set-password", dbPath],
                    stdin=pipeStyle.pipe, stdout=pipeStyle.pipe, stderr=pipeStyle.pipe);
      p.stdin.write(masterPassword + "\n" + masterPassword + "\n");
      p.stdin.close();
      p.wait();

      if p.exitCode != 0 {
        var errMsg: string;
        p.stderr.readAll(errMsg);
        return (false, "Failed to create database: " + errMsg.strip());
      }
    } catch e {
      return (false, "Error creating database: " + e.message());
    }

    // Create group hierarchy
    for group in BOOTSTRAP_GROUPS {
      try {
        var p = spawn(["keepassxc-cli", "mkdir", dbPath, group],
                      stdin=pipeStyle.pipe, stdout=pipeStyle.close, stderr=pipeStyle.close);
        p.stdin.write(masterPassword + "\n");
        p.stdin.close();
        p.wait();
      } catch {
        // Non-fatal: group may already exist
      }
    }

    // Seal master password in HSM if requested
    if sealInHSM {
      if hsm_is_available() != 0 {
        const sealResult = sealMasterPassword(KDBX_HSM_IDENTITY, masterPassword);
        if !sealResult {
          // Non-fatal: database is created, just can't auto-unlock
          return (true, "Database created at " + dbPath +
                  "\nWARNING: Failed to seal master password in HSM. " +
                  "Auto-unlock will not be available. " +
                  "Master password: " + masterPassword);
        }
      } else {
        return (true, "Database created at " + dbPath +
                "\nWARNING: No HSM available. Master password not sealed. " +
                "Store it securely: " + masterPassword);
      }
    }

    // Verify round-trip
    const (listOk, _) = listEntries(dbPath, "RemoteJuggler", masterPassword);
    if !listOk {
      return (false, "Database created but verification failed. " +
              "Master password: " + masterPassword);
    }

    // Clear master password from memory
    masterPassword = "";

    return (true, "Database created and sealed successfully at " + dbPath +
            "\nMaster password sealed in HSM (auto-unlock enabled)." +
            "\nGroup hierarchy created.");
  }

  /*
   * Seal the kdbx master password in TPM/SecureEnclave.
   *
   * :arg identity: HSM identity label
   * :arg masterPassword: The master password to seal
   * :returns: true on success
   */
  proc sealMasterPassword(identity: string, masterPassword: string): bool {
    const result = hsm_store_pin(identity, masterPassword, masterPassword.size);
    return result == HSM_SUCCESS;
  }

  // ============================================================================
  // .env File Ingestion
  // ============================================================================

  /*
   * Ingest a .env file into the database.
   *
   * Parses KEY=VALUE pairs and stores each as an entry under
   * RemoteJuggler/Environments/{canonical-path}/.env/{KEY}
   *
   * Handles: KEY=VALUE, KEY="quoted value", # comments, export prefixes
   *
   * :arg dbPath: Path to the kdbx file
   * :arg envFilePath: Path to the .env file to ingest
   * :arg password: Master password
   * :returns: (entriesAdded, entriesUpdated)
   */
  proc ingestEnvFile(dbPath: string, envFilePath: string, password: string): (int, int) {
    var added = 0;
    var updated = 0;

    // Read .env file
    var content: string;
    try {
      var f = open(envFilePath, ioMode.r);
      var reader = f.reader(locking=false);
      reader.readAll(content);
      reader.close();
      f.close();
    } catch e {
      verboseLog("KeePassXC ingestEnvFile: Failed to read ", envFilePath, ": ", e.message());
      return (0, 0);
    }

    // Canonical path for group name
    const canonicalPath = envFilePath.replace("/", "_").replace("~", "home");
    const groupPath = "RemoteJuggler/Environments/" + canonicalPath;

    // Ensure group exists
    try {
      var p = spawn(["keepassxc-cli", "mkdir", dbPath, groupPath],
                    stdin=pipeStyle.pipe, stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.stdin.write(password + "\n");
      p.stdin.close();
      p.wait();
    } catch { }

    // Parse and store each key-value pair
    for line in content.split("\n") {
      var trimmed = line.strip();

      // Skip comments and empty lines
      if trimmed == "" || trimmed.startsWith("#") {
        continue;
      }

      // Remove 'export ' prefix
      if trimmed.startsWith("export ") {
        trimmed = trimmed[7..];
      }

      // Find the = separator
      const eqPos = trimmed.find("=");
      if eqPos < 0 {
        continue;
      }

      const key = trimmed[0..#eqPos].strip();
      var value = trimmed[eqPos+1..].strip();

      // Remove surrounding quotes
      if value.size >= 2 {
        if (value.startsWith('"') && value.endsWith('"')) ||
           (value.startsWith("'") && value.endsWith("'")) {
          value = value[1..#(value.size-2)];
        }
      }

      if key == "" {
        continue;
      }

      // Store entry
      const entryPath = groupPath + "/" + key;

      // Check if entry already exists
      const (existsOk, existingValue) = getEntry(dbPath, entryPath, password);
      if existsOk {
        if existingValue != value {
          // Update
          if setEntry(dbPath, entryPath, password, value) {
            updated += 1;
          }
        }
        // Skip if unchanged
      } else {
        // Add new
        if setEntry(dbPath, entryPath, password, value) {
          added += 1;
        }
      }
    }

    return (added, updated);
  }

  /*
   * Sync a .env file (re-ingest, detecting changes).
   *
   * :arg dbPath: Path to the kdbx file
   * :arg envFilePath: Path to the .env file
   * :arg password: Master password
   * :returns: (added, updated) counts
   */
  proc syncEnvFile(dbPath: string, envFilePath: string, password: string): (int, int) {
    return ingestEnvFile(dbPath, envFilePath, password);
  }

  // ============================================================================
  // Utility Functions
  // ============================================================================

  /*
   * Generate a random password of the given length.
   *
   * Uses /dev/urandom for entropy.
   *
   * :arg length: Password length
   * :returns: Random password string
   */
  proc generateRandomPassword(length: int): string {
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+";
    var password = "";

    try {
      var f = open("/dev/urandom", ioMode.r);
      var reader = f.reader(locking=false);

      for i in 0..<length {
        var byte: uint(8);
        reader.readBinary(byte);
        const idx = (byte % charset.size:uint(8)):int;
        password += charset[idx];
      }

      reader.close();
      f.close();
    } catch {
      // Fallback: use timestamp-based seed (less secure)
      use Time;
      var seed = dateTime.now().second * 1000 + dateTime.now().hour * 60;
      for i in 0..<length {
        seed = (seed * 1103515245 + 12345) % (2**31);
        const idx = (seed % charset.size):int;
        password += charset[idx:int];
      }
    }

    return password;
  }

  /*
   * Import existing credentials from RemoteJuggler config into the kdbx database.
   *
   * Reads token env vars and SSH key paths from config and creates
   * corresponding entries in the kdbx database.
   *
   * :arg dbPath: Path to the kdbx file
   * :arg password: Master password
   * :returns: Number of entries imported
   */
  proc importExistingCredentials(dbPath: string, password: string): int {
    var imported = 0;

    // Import tokens from environment variables
    const envTokens = [
      ("GITLAB_TOKEN", "RemoteJuggler/Tokens/GitLab/default"),
      ("GITHUB_TOKEN", "RemoteJuggler/Tokens/GitHub/default"),
      ("PERPLEXITY_API_KEY", "RemoteJuggler/API/PERPLEXITY_API_KEY"),
      ("BRAVE_API_KEY", "RemoteJuggler/API/BRAVE_API_KEY"),
      ("SHODAN_API_KEY", "RemoteJuggler/API/SHODAN_API_KEY"),
      ("ZAI_BEARER_TOKEN", "RemoteJuggler/API/ZAI_BEARER_TOKEN"),
      ("Z_AI_API_KEY", "RemoteJuggler/API/Z_AI_API_KEY")
    ];

    for (envName, entryPath) in envTokens {
      const val = getEnvVar(envName);
      if val != "" {
        if setEntry(dbPath, entryPath, password, val) {
          imported += 1;
          verboseLog("KeePassXC: Imported ", envName, " -> ", entryPath);
        }
      }
    }

    return imported;
  }

  // ============================================================================
  // Status
  // ============================================================================

  /*
   * Get comprehensive status of the KeePassXC integration.
   *
   * :returns: Status string suitable for display
   */
  proc getStatus(): string {
    var output = "KeePassXC Credential Authority Status\n";
    output += "=====================================\n\n";

    // CLI availability
    output += "keepassxc-cli: " + (if isAvailable() then "installed" else "NOT FOUND") + "\n";

    // Database
    const dbPath = getDatabasePath();
    output += "Database: " + dbPath + "\n";
    output += "  Exists: " + (if databaseExists() then "yes" else "no") + "\n";

    // HSM
    const hsmType = hsm_detect_available();
    output += "HSM: " + (if hsmType != HSM_TYPE_NONE then hsm_type_name(hsmType) else "none") + "\n";

    // Master password sealed
    const hasMaster = hsm_has_pin(KDBX_HSM_IDENTITY) != 0;
    output += "Master Password Sealed: " + (if hasMaster then "yes" else "no") + "\n";

    // YubiKey
    output += "YubiKey: " + (if isYubiKeyPresent() then "present" else "not detected") + "\n";

    // Auto-unlock
    output += "Auto-Unlock: " + (if canAutoUnlock() then "ready" else "not available") + "\n";

    // Entry count (if accessible)
    if canAutoUnlock() && databaseExists() {
      const (ok, password) = autoUnlock();
      if ok {
        const (listOk, entries) = listEntries(dbPath, "RemoteJuggler", password);
        if listOk {
          output += "Root Groups: " + entries.size:string + "\n";
        }
      }
    }

    return output;
  }
}
