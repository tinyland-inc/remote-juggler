/*
 * GPG.chpl - GPG signing integration for RemoteJuggler
 *
 * Part of RemoteJuggler - Backend-agnostic git identity management
 * Provides GPG key discovery, git configuration, and provider verification.
 *
 * Features:
 *   - List and parse GPG secret keys
 *   - Auto-detect GPG key by email address
 *   - Configure git for GPG signing
 *   - Verify GPG key registration with GitLab/GitHub
 *   - Generate helpful URLs for key registration
 */
prototype module GPG {
  use Subprocess;
  use IO;
  use List;
  public use super.Core;
  public use super.ProviderCLI;
  import super.ProviderCLI;

  // ============================================================
  // GPG Key Types
  // ============================================================

  /*
   * Represents a GPG secret key
   */
  record GPGKey {
    var keyId: string;         // Short or long key ID
    var fingerprint: string;   // Full fingerprint
    var email: string;         // Primary email associated with key
    var name: string;          // User name on the key
    var expires: string;       // Expiration date or empty if no expiry
    var algorithm: string;     // Key algorithm (e.g., "ed25519", "rsa4096")
    var created: string;       // Creation date
  }

  // ============================================================
  // GPG Key Discovery
  // ============================================================

  /*
   * Check if GPG is available in PATH
   */
  proc gpgAvailable(): bool {
    try {
      var p = spawn(["which", "gpg"], stdout=pipeStyle.close, stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * List all available GPG secret keys
   *
   * Parses output of: gpg --list-secret-keys --keyid-format=long
   *
   * Returns:
   *   A list of GPGKey records
   */
  proc listKeys(): list(GPGKey) {
    var keys: list(GPGKey);

    if !gpgAvailable() then return keys;

    try {
      var p = spawn(["gpg", "--list-secret-keys", "--keyid-format=long", "--with-colons"],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode != 0 then return keys;

      var output: string;
      p.stdout.readAll(output);

      // Parse colon-delimited output
      // Format: type:validity:keylen:algo:keyid:created:expires:...:uid:...
      var currentKey: GPGKey;
      var hasKey = false;

      for line in output.split("\n") {
        const fields = line.split(":");

        if fields.size < 2 then continue;

        const recordType = fields[0];

        select recordType {
          // Secret key record
          when "sec" {
            // Save previous key if any
            if hasKey && currentKey.keyId != "" {
              keys.pushBack(currentKey);
            }

            // Start new key
            currentKey = new GPGKey();
            hasKey = true;

            if fields.size > 4 then currentKey.keyId = fields[4];
            if fields.size > 5 then currentKey.created = fields[5];
            if fields.size > 6 then currentKey.expires = fields[6];
            if fields.size > 3 {
              // Algorithm is in field 3
              const algoNum = fields[3];
              currentKey.algorithm = gpgAlgorithmName(algoNum);
            }
          }
          // Fingerprint record
          when "fpr" {
            if hasKey && fields.size > 9 {
              currentKey.fingerprint = fields[9];
            }
          }
          // User ID record
          when "uid" {
            if hasKey && fields.size > 9 && currentKey.email == "" {
              // Parse uid field: "Name <email>"
              const uid = fields[9];
              const (parsedName, parsedEmail) = parseUID(uid);
              currentKey.name = parsedName;
              currentKey.email = parsedEmail;
            }
          }
        }
      }

      // Don't forget the last key
      if hasKey && currentKey.keyId != "" {
        keys.pushBack(currentKey);
      }

    } catch {
      // Return empty list on error
    }

    return keys;
  }

  /*
   * Convert GPG algorithm number to human-readable name
   */
  proc gpgAlgorithmName(algoNum: string): string {
    select algoNum {
      when "1" do return "rsa";
      when "16" do return "elgamal";
      when "17" do return "dsa";
      when "18" do return "ecdh";
      when "19" do return "ecdsa";
      when "22" do return "ed25519";
      otherwise do return "unknown";
    }
  }

  /*
   * Parse a UID string like "Name <email@example.com>"
   *
   * Returns:
   *   Tuple of (name, email)
   */
  proc parseUID(uid: string): (string, string) {
    var name = "";
    var email = "";

    const ltIdx = uid.find("<");
    const gtIdx = uid.find(">");

    if ltIdx != -1 && gtIdx != -1 && gtIdx > ltIdx {
      name = uid[..ltIdx-1].strip();
      email = uid[ltIdx+1..gtIdx-1].strip();
    } else {
      // No angle brackets - might be just email or just name
      if uid.find("@") != -1 {
        email = uid.strip();
      } else {
        name = uid.strip();
      }
    }

    return (name, email);
  }

  /*
   * Get GPG key ID for a specific email address
   *
   * Args:
   *   email: The email address to search for
   *
   * Returns:
   *   Tuple of (found, keyId)
   */
  proc getKeyForEmail(email: string): (bool, string) {
    if !gpgAvailable() then return (false, "");

    try {
      // Use gpg to search for keys with this email
      var p = spawn(["gpg", "--list-secret-keys", "--keyid-format=long", "--with-colons", email],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var output: string;
        p.stdout.readAll(output);

        // Parse for sec record to get key ID
        for line in output.split("\n") {
          const fields = line.split(":");
          if fields.size > 4 && fields[0] == "sec" {
            return (true, fields[4]);
          }
        }
      }
    } catch {
      // Fall through
    }

    // Alternative: search all keys for matching email
    const allKeys = listKeys();
    for key in allKeys {
      if key.email.toLower() == email.toLower() {
        return (true, key.keyId);
      }
    }

    return (false, "");
  }

  /*
   * Get the public key armor block for a key ID
   *
   * Args:
   *   keyId: The GPG key ID
   *
   * Returns:
   *   Tuple of (success, armorBlock)
   */
  proc exportPublicKey(keyId: string): (bool, string) {
    if !gpgAvailable() then return (false, "");

    try {
      var p = spawn(["gpg", "--armor", "--export", keyId],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var armor: string;
        p.stdout.readAll(armor);
        return (true, armor.strip());
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  // ============================================================
  // Git GPG Configuration
  // ============================================================

  /*
   * Run git config command
   *
   * Args:
   *   repoPath: Path to the git repository (use "." for current)
   *   key: The config key
   *   value: The config value
   *
   * Returns:
   *   true if successful, false otherwise
   */
  proc gitConfig(repoPath: string, key: string, value: string): bool {
    try {
      var argList: list(string);
      argList.pushBack("git");
      argList.pushBack("-C");
      argList.pushBack(repoPath);
      argList.pushBack("config");
      argList.pushBack(key);
      argList.pushBack(value);

      var p = spawn(argList.toArray(),
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
   * Get a git config value
   *
   * Args:
   *   repoPath: Path to the git repository
   *   key: The config key
   *
   * Returns:
   *   Tuple of (found, value)
   */
  proc getGitConfig(repoPath: string, key: string): (bool, string) {
    try {
      var argList: list(string);
      argList.pushBack("git");
      argList.pushBack("-C");
      argList.pushBack(repoPath);
      argList.pushBack("config");
      argList.pushBack("--get");
      argList.pushBack(key);

      var p = spawn(argList.toArray(),
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode == 0 {
        var value: string;
        p.stdout.readAll(value);
        return (true, value.strip());
      }
    } catch {
      // Fall through
    }
    return (false, "");
  }

  /*
   * Configure git for GPG signing
   *
   * Args:
   *   repoPath: Path to the git repository
   *   keyId: The GPG key ID to use for signing
   *   signCommits: Whether to sign commits by default
   *   autoSignoff: Whether to add Signed-off-by line (stored in RemoteJuggler config)
   *
   * Returns:
   *   true if all configurations succeeded, false otherwise
   */
  proc configureGitGPG(repoPath: string, keyId: string,
                       signCommits: bool, autoSignoff: bool): bool {
    var success = true;

    // Set signing key
    success = success && gitConfig(repoPath, "user.signingkey", keyId);

    // Enable/disable commit signing
    const signValue = if signCommits then "true" else "false";
    success = success && gitConfig(repoPath, "commit.gpgsign", signValue);

    // Set GPG program (use gpg by default)
    success = success && gitConfig(repoPath, "gpg.program", "gpg");

    // Note: autoSignoff is not a native git config - it's handled by RemoteJuggler
    // via commit hooks or wrapper scripts. We store it in our own config.
    if verbose && autoSignoff {
      writeln("  Note: Auto-signoff enabled (handled by RemoteJuggler hooks)");
    }

    return success;
  }

  /*
   * Remove GPG signing configuration from a repository
   *
   * Args:
   *   repoPath: Path to the git repository
   *
   * Returns:
   *   true if successful
   */
  proc disableGitGPG(repoPath: string): bool {
    var success = true;

    try {
      // Unset signing key
      var p1 = spawn(["git", "-C", repoPath, "config", "--unset", "user.signingkey"],
                     stdout=pipeStyle.close, stderr=pipeStyle.close);
      p1.wait();
      // Don't check exit code - unset returns non-zero if key doesn't exist

      // Disable commit signing
      success = success && gitConfig(repoPath, "commit.gpgsign", "false");
    } catch {
      return false;
    }

    return success;
  }

  // ============================================================
  // Provider GPG Verification
  // ============================================================

  /*
   * Verify GPG key is registered with the provider
   *
   * Args:
   *   identity: The GitIdentity to verify against
   *
   * Returns:
   *   GPGVerifyResult with verification status
   */
  proc verifyKeyWithProvider(identity: GitIdentity): GPGVerifyResult {
    select identity.provider {
      when Provider.GitLab {
        return verifyGitLabGPG(identity);
      }
      when Provider.GitHub {
        return verifyGitHubGPG(identity);
      }
      otherwise {
        return new GPGVerifyResult(
          verified = false,
          message = "GPG verification not supported for " + providerToString(identity.provider),
          settingsURL = ""
        );
      }
    }
  }

  /*
   * Verify GPG key with GitLab
   *
   * Uses glab API to check if the key is registered
   */
  proc verifyGitLabGPG(identity: GitIdentity): GPGVerifyResult {
    const settingsURLVal = getGPGSettingsURL(identity);

    if !ProviderCLI.glabAvailable() {
      return new GPGVerifyResult(
        verified = false,
        message = "glab CLI required for GPG verification",
        settingsURL = settingsURLVal
      );
    }

    // Get the key ID from identity
    var keyId = identity.gpg.keyId;
    if keyId == "auto" || keyId == "" {
      const (found, autoKeyId) = getKeyForEmail(identity.email);
      if !found {
        return new GPGVerifyResult(
          verified = false,
          message = "No GPG key found for email: " + identity.email,
          settingsURL = settingsURLVal
        );
      }
      keyId = autoKeyId;
    }

    // Query GitLab API for GPG keys
    const (ok, response) = ProviderCLI.glabAPI("user/gpg_keys", identity.hostname);

    if !ok {
      return new GPGVerifyResult(
        verified = false,
        message = "Failed to query GitLab GPG keys API",
        settingsURL = settingsURLVal
      );
    }

    // Check if our key ID is in the response
    // Response is JSON array of key objects with "id", "key", etc.
    // We look for our key ID in the response text (simple check)
    if response.find(keyId) != -1 || response.find(keyId.toLower()) != -1 {
      return new GPGVerifyResult(
        verified = true,
        message = "GPG key " + keyId + " is registered with GitLab",
        settingsURL = ""
      );
    }

    // Also check fingerprint if we have it
    const allKeys = listKeys();
    for key in allKeys {
      if key.keyId == keyId && key.fingerprint != "" {
        if response.find(key.fingerprint) != -1 {
          return new GPGVerifyResult(
            verified = true,
            message = "GPG key " + keyId + " is registered with GitLab",
            settingsURL = ""
          );
        }
      }
    }

    return new GPGVerifyResult(
      verified = false,
      message = "GPG key " + keyId + " not found on GitLab",
      settingsURL = settingsURLVal
    );
  }

  /*
   * Verify GPG key with GitHub
   *
   * Uses gh API to check if the key is registered
   */
  proc verifyGitHubGPG(identity: GitIdentity): GPGVerifyResult {
    const settingsURLVal = getGPGSettingsURL(identity);

    if !ProviderCLI.ghAvailable() {
      return new GPGVerifyResult(
        verified = false,
        message = "gh CLI required for GPG verification",
        settingsURL = settingsURLVal
      );
    }

    // Get the key ID from identity
    var keyId = identity.gpg.keyId;
    if keyId == "auto" || keyId == "" {
      const (found, autoKeyId) = getKeyForEmail(identity.email);
      if !found {
        return new GPGVerifyResult(
          verified = false,
          message = "No GPG key found for email: " + identity.email,
          settingsURL = settingsURLVal
        );
      }
      keyId = autoKeyId;
    }

    // Query GitHub API for GPG keys
    const (ok, response) = ProviderCLI.ghAPI("user/gpg_keys", identity.hostname);

    if !ok {
      return new GPGVerifyResult(
        verified = false,
        message = "Failed to query GitHub GPG keys API",
        settingsURL = settingsURLVal
      );
    }

    // Check if our key ID is in the response
    if response.find(keyId) != -1 || response.find(keyId.toLower()) != -1 {
      return new GPGVerifyResult(
        verified = true,
        message = "GPG key " + keyId + " is registered with GitHub",
        settingsURL = ""
      );
    }

    // Also check fingerprint
    const allKeys = listKeys();
    for key in allKeys {
      if key.keyId == keyId && key.fingerprint != "" {
        if response.find(key.fingerprint) != -1 {
          return new GPGVerifyResult(
            verified = true,
            message = "GPG key " + keyId + " is registered with GitHub",
            settingsURL = ""
          );
        }
      }
    }

    return new GPGVerifyResult(
      verified = false,
      message = "GPG key " + keyId + " not found on GitHub",
      settingsURL = settingsURLVal
    );
  }

  // ============================================================
  // Helper URLs
  // ============================================================

  /*
   * Get the URL for GPG key settings on a provider
   *
   * Args:
   *   identity: The GitIdentity
   *
   * Returns:
   *   URL string for the GPG settings page
   */
  proc getGPGSettingsURL(identity: GitIdentity): string {
    select identity.provider {
      when Provider.GitLab {
        return "https://" + identity.hostname + "/-/profile/gpg_keys";
      }
      when Provider.GitHub {
        // GitHub uses a different URL structure
        if identity.hostname == "github.com" {
          return "https://github.com/settings/keys";
        } else {
          // GitHub Enterprise
          return "https://" + identity.hostname + "/settings/keys";
        }
      }
      when Provider.Bitbucket {
        return "https://bitbucket.org/account/settings/gpg-keys/";
      }
      otherwise {
        return "";
      }
    }
  }

  /*
   * Get the GPG export command for user convenience
   *
   * Args:
   *   keyId: The GPG key ID
   *
   * Returns:
   *   The command string to export the public key
   */
  proc getExportCommand(keyId: string): string {
    return "gpg --armor --export " + keyId;
  }

  // ============================================================
  // GPG Status and Diagnostics
  // ============================================================

  /*
   * Get a summary of GPG status for an identity
   *
   * Args:
   *   identity: The GitIdentity
   *
   * Returns:
   *   Formatted status string
   */
  proc getGPGStatus(identity: GitIdentity): string {
    var status: string = "";

    if !gpgAvailable() {
      return "GPG: Not installed\n";
    }

    status += "GPG: Available\n";

    var keyId = identity.gpg.keyId;
    if keyId == "" {
      status += "  Signing: Disabled\n";
      return status;
    }

    if keyId == "auto" {
      const (found, autoKeyId) = getKeyForEmail(identity.email);
      if found {
        keyId = autoKeyId;
        status += "  Key: " + keyId + " (auto-detected from " + identity.email + ")\n";
      } else {
        status += "  Key: Not found for " + identity.email + "\n";
        return status;
      }
    } else {
      status += "  Key: " + keyId + "\n";
    }

    // Get key details
    const allKeys = listKeys();
    for key in allKeys {
      if key.keyId == keyId {
        status += "  Name: " + key.name + "\n";
        status += "  Email: " + key.email + "\n";
        if key.expires != "" {
          status += "  Expires: " + key.expires + "\n";
        }
        break;
      }
    }

    status += "  Sign Commits: " + (if identity.gpg.signCommits then "Yes" else "No") + "\n";
    status += "  Sign Tags: " + (if identity.gpg.signTags then "Yes" else "No") + "\n";
    status += "  Auto Signoff: " + (if identity.gpg.autoSignoff then "Yes" else "No") + "\n";

    return status;
  }

  /*
   * Verify that a GPG key can sign (test signing operation)
   *
   * Args:
   *   keyId: The GPG key ID to test
   *
   * Returns:
   *   true if signing works, false otherwise
   */
  proc testSigning(keyId: string): bool {
    if !gpgAvailable() then return false;

    try {
      // Create a test signature
      var p = spawn(["gpg", "--batch", "--yes", "-u", keyId, "--clearsign"],
                    stdin=pipeStyle.pipe,
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);

      p.stdin.write("test");
      p.stdin.close();
      p.wait();

      return p.exitCode == 0;
    } catch {
      return false;
    }
  }
}
