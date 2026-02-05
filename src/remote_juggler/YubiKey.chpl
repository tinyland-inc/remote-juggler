/*
  YubiKey Module - YubiKey Manager (ykman) Integration
  ====================================================

  Provides Chapel bindings for YubiKey Manager (ykman) to configure
  OpenPGP settings for optimal Trusted Workstation mode operation.

  Features:
  - Detect ykman availability and version
  - Read/set signature PIN policy (once/always)
  - Read/set touch policies (sig/enc/aut)
  - Get YubiKey device information

  This module wraps the ykman CLI tool which is BSD-2-Clause licensed
  (compatible with RemoteJuggler's zlib license).

  Reference: https://docs.yubico.com/software/yubikey/tools/ykman/OpenPGP_Commands.html

  :author: RemoteJuggler Team
  :version: 2.0.0
  :license: zlib
*/
prototype module YubiKey {
  use Subprocess;
  use IO;
  use List;
  use CTypes;
  public use super.Core;

  // =========================================================================
  // YubiKey Data Types
  // =========================================================================

  /*
    Comprehensive YubiKey OpenPGP information.

    Contains device identification, firmware version, and all
    configurable policies for OpenPGP operations.

    :var serialNumber: YubiKey serial number (e.g., "26503492")
    :var firmware: Firmware version (e.g., "5.4.3")
    :var formFactor: Device form factor (e.g., "USB-A Keychain")
    :var sigTouchPolicy: Touch policy for signing ("on", "off", "cached", "fixed")
    :var sigPinPolicy: PIN policy for signing ("once", "always")
    :var encTouchPolicy: Touch policy for encryption
    :var autTouchPolicy: Touch policy for authentication
    :var sigKeyPresent: Whether a signing key is loaded
    :var encKeyPresent: Whether an encryption key is loaded
    :var autKeyPresent: Whether an authentication key is loaded
    :var version: OpenPGP application version
    :var retries: PIN retry counters (PIN, reset, admin)
  */
  record YubiKeyInfo {
    var serialNumber: string = "";
    var firmware: string = "";
    var formFactor: string = "";
    var sigTouchPolicy: string = "";
    var sigPinPolicy: string = "";
    var encTouchPolicy: string = "";
    var autTouchPolicy: string = "";
    var sigKeyPresent: bool = false;
    var encKeyPresent: bool = false;
    var autKeyPresent: bool = false;
    var version: string = "";
    var pinRetries: int = 0;
    var resetRetries: int = 0;
    var adminRetries: int = 0;

    /*
      Initialize with default values.
    */
    proc init() {
      this.serialNumber = "";
      this.firmware = "";
      this.formFactor = "";
      this.sigTouchPolicy = "";
      this.sigPinPolicy = "";
      this.encTouchPolicy = "";
      this.autTouchPolicy = "";
      this.sigKeyPresent = false;
      this.encKeyPresent = false;
      this.autKeyPresent = false;
      this.version = "";
      this.pinRetries = 0;
      this.resetRetries = 0;
      this.adminRetries = 0;
    }

    /*
      Check if any touch is required for signing.

      :returns: true if touch policy is "on" or "fixed"
    */
    proc requiresSigningTouch(): bool {
      return sigTouchPolicy == "on" || sigTouchPolicy == "fixed";
    }

    /*
      Check if touch can be cached (15-second window).

      :returns: true if touch policy is "cached"
    */
    proc canCacheSigningTouch(): bool {
      return sigTouchPolicy == "cached";
    }

    /*
      Check if PIN is required for every signature.

      :returns: true if PIN policy is "always"
    */
    proc requiresPinEveryTime(): bool {
      return sigPinPolicy == "always";
    }

    /*
      Check if device is configured for Trusted Workstation mode.

      Optimal settings:
      - PIN policy: "once" (PIN once per session)
      - Touch policy: "cached" or "off" (for automation)

      :returns: true if configured for trusted workstation use
    */
    proc isTrustedWorkstationReady(): bool {
      return sigPinPolicy == "once" &&
             (sigTouchPolicy == "cached" || sigTouchPolicy == "off");
    }

    /*
      Get a summary of the YubiKey configuration.

      :returns: Human-readable summary string
    */
    proc summary(): string {
      if serialNumber == "" then return "No YubiKey detected";

      var s = "YubiKey " + serialNumber;
      if firmware != "" then s += " (FW " + firmware + ")";
      s += "\n";

      if sigPinPolicy != "" then s += "  PIN Policy: " + sigPinPolicy + "\n";
      if sigTouchPolicy != "" then s += "  Touch: sig=" + sigTouchPolicy;
      if encTouchPolicy != "" then s += ", enc=" + encTouchPolicy;
      if autTouchPolicy != "" then s += ", aut=" + autTouchPolicy;

      return s;
    }
  }

  /*
    Touch policy options for OpenPGP key slots.
  */
  enum TouchPolicy {
    On,       // Touch required for every operation
    Off,      // Touch never required
    Cached,   // Touch required once, then cached for 15 seconds
    Fixed     // Touch required, cannot be changed
  }

  /*
    PIN policy options for signature operations.
  */
  enum PinPolicy {
    Once,     // PIN required once per session
    Always    // PIN required for every signature
  }

  // =========================================================================
  // ykman Availability and Version
  // =========================================================================

  /*
    Check if ykman (YubiKey Manager CLI) is available in PATH.

    :returns: true if ykman is installed and executable
  */
  proc isYkmanAvailable(): bool {
    try {
      var p = spawn(["which", "ykman"],
                    stdout=pipeStyle.close,
                    stderr=pipeStyle.close);
      p.wait();
      return p.exitCode == 0;
    } catch {
      return false;
    }
  }

  /*
    Get the ykman version string.

    :returns: Version string (e.g., "5.5.0") or empty if not available
  */
  proc getYkmanVersion(): string {
    if !isYkmanAvailable() then return "";

    try {
      var p = spawn(["ykman", "--version"],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode != 0 then return "";

      var output: string;
      p.stdout.readAll(output);

      // Parse "YubiKey Manager (ykman) version: X.Y.Z"
      const versionPrefix = "version:";
      const idx = output.toLower().find(versionPrefix);
      if idx != -1 {
        const afterPrefix = output[idx + versionPrefix.size..];
        return afterPrefix.strip();
      }

      // Fallback: return trimmed output
      return output.strip();
    } catch {
      return "";
    }
  }

  /*
    Check if a YubiKey is currently connected.

    Uses `ykman list` to detect connected devices.

    :returns: true if at least one YubiKey is connected
  */
  proc isYubiKeyConnected(): bool {
    if !isYkmanAvailable() then return false;

    try {
      var p = spawn(["ykman", "list"],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode != 0 then return false;

      var output: string;
      p.stdout.readAll(output);

      // If output is non-empty, a YubiKey is connected
      return output.strip().size > 0;
    } catch {
      return false;
    }
  }

  // =========================================================================
  // YubiKey Information
  // =========================================================================

  /*
    Get comprehensive YubiKey device and OpenPGP information.

    Combines output from `ykman info` and `ykman openpgp info`.

    :returns: YubiKeyInfo record with device details
  */
  proc getYubiKeyInfo(): YubiKeyInfo {
    var info = new YubiKeyInfo();

    if !isYkmanAvailable() || !isYubiKeyConnected() {
      return info;
    }

    // Get basic device info
    info = getBasicInfo(info);

    // Get OpenPGP-specific info
    info = getOpenPGPInfo(info);

    return info;
  }

  /*
    Get basic YubiKey device information from `ykman info`.

    :arg info: YubiKeyInfo to populate
    :returns: Updated YubiKeyInfo
  */
  private proc getBasicInfo(in info: YubiKeyInfo): YubiKeyInfo {
    try {
      var p = spawn(["ykman", "info"],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode != 0 then return info;

      var output: string;
      p.stdout.readAll(output);

      for line in output.split("\n") {
        const lineLower = line.toLower();
        const colonIdx = line.find(":");

        if colonIdx == -1 then continue;

        const key = line[..colonIdx-1].strip().toLower();
        const value = line[colonIdx+1..].strip();

        select key {
          when "serial number" do info.serialNumber = value;
          when "firmware version" do info.firmware = value;
          when "form factor" do info.formFactor = value;
          when "device type" {
            // Extract form factor from device type if not set
            if info.formFactor == "" then info.formFactor = value;
          }
        }
      }
    } catch {
      // Return partial info on error
    }

    return info;
  }

  /*
    Get OpenPGP-specific information from `ykman openpgp info`.

    Parses touch policies, PIN policies, and key presence.

    :arg info: YubiKeyInfo to populate
    :returns: Updated YubiKeyInfo
  */
  private proc getOpenPGPInfo(in info: YubiKeyInfo): YubiKeyInfo {
    try {
      var p = spawn(["ykman", "openpgp", "info"],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.close);
      p.wait();

      if p.exitCode != 0 then return info;

      var output: string;
      p.stdout.readAll(output);

      // Track which section we're in
      var inTouchPolicies = false;
      var inKeys = false;
      var inRetries = false;

      for line in output.split("\n") {
        const lineLower = line.toLower();
        const trimmedLine = line.strip();

        // Section detection
        if lineLower.find("touch polic") != -1 {
          inTouchPolicies = true;
          inKeys = false;
          inRetries = false;
          continue;
        } else if lineLower.find("key slot") != -1 || lineLower.find("keys:") != -1 {
          inTouchPolicies = false;
          inKeys = true;
          inRetries = false;
          continue;
        } else if lineLower.find("pin retr") != -1 || lineLower.find("retries") != -1 {
          inTouchPolicies = false;
          inKeys = false;
          inRetries = true;
          continue;
        }

        // Parse touch policies section
        if inTouchPolicies {
          if lineLower.find("sig") != -1 {
            info.sigTouchPolicy = extractTouchPolicy(line);
          } else if lineLower.find("enc") != -1 {
            info.encTouchPolicy = extractTouchPolicy(line);
          } else if lineLower.find("aut") != -1 {
            info.autTouchPolicy = extractTouchPolicy(line);
          }
        }

        // Parse PIN policy for signature
        if lineLower.find("signature pin policy") != -1 ||
           (lineLower.find("pin policy") != -1 && lineLower.find("sig") != -1) {
          if lineLower.find("once") != -1 {
            info.sigPinPolicy = "once";
          } else if lineLower.find("always") != -1 {
            info.sigPinPolicy = "always";
          }
        }

        // Parse key presence
        if inKeys {
          if lineLower.find("sig") != -1 && lineLower.find("empty") == -1 &&
             lineLower.find("not set") == -1 {
            info.sigKeyPresent = true;
          }
          if lineLower.find("enc") != -1 && lineLower.find("empty") == -1 &&
             lineLower.find("not set") == -1 {
            info.encKeyPresent = true;
          }
          if lineLower.find("aut") != -1 && lineLower.find("empty") == -1 &&
             lineLower.find("not set") == -1 {
            info.autKeyPresent = true;
          }
        }

        // Parse OpenPGP version
        if lineLower.find("openpgp version") != -1 || lineLower.find("version:") != -1 {
          const colonIdx = line.find(":");
          if colonIdx != -1 {
            info.version = line[colonIdx+1..].strip();
          }
        }

        // Parse PIN retries
        if inRetries || lineLower.find("pin retries") != -1 {
          // Format: "PIN retries: 3/3/3" or "3, 3, 3"
          const colonIdx = line.find(":");
          if colonIdx != -1 {
            const retriesStr = line[colonIdx+1..].strip();
            const parts = retriesStr.split("/");
            if parts.size >= 3 {
              try {
                info.pinRetries = parts[0].strip(): int;
                info.resetRetries = parts[1].strip(): int;
                info.adminRetries = parts[2].strip(): int;
              } catch {
                // Parsing failed, try comma-separated
                const commaParts = retriesStr.split(",");
                if commaParts.size >= 3 {
                  try {
                    info.pinRetries = commaParts[0].strip(): int;
                    info.resetRetries = commaParts[1].strip(): int;
                    info.adminRetries = commaParts[2].strip(): int;
                  } catch { }
                }
              }
            }
          }
        }
      }
    } catch {
      // Return partial info on error
    }

    return info;
  }

  /*
    Extract touch policy value from a line.

    :arg line: Line containing touch policy information
    :returns: Policy string ("on", "off", "cached", "fixed")
  */
  private proc extractTouchPolicy(line: string): string {
    const lineLower = line.toLower();

    if lineLower.find("fixed") != -1 then return "fixed";
    if lineLower.find("cached") != -1 then return "cached";
    if lineLower.find("on") != -1 then return "on";
    if lineLower.find("off") != -1 || lineLower.find("disabled") != -1 then return "off";

    // Try to extract from colon-separated value
    const colonIdx = line.find(":");
    if colonIdx != -1 {
      const value = line[colonIdx+1..].strip().toLower();
      if value == "on" || value == "off" || value == "cached" || value == "fixed" {
        return value;
      }
    }

    return "";
  }

  // =========================================================================
  // PIN Policy Configuration
  // =========================================================================

  /*
    Set the signature PIN policy.

    Controls whether PIN is required for every signature or once per session.

    :arg policy: "once" for session caching, "always" for every operation
    :returns: true if successful
  */
  proc setSignaturePinPolicy(policy: string): bool {
    if !isYkmanAvailable() || !isYubiKeyConnected() {
      return false;
    }

    const normalizedPolicy = policy.toLower();
    if normalizedPolicy != "once" && normalizedPolicy != "always" {
      verboseLog("Invalid PIN policy: ", policy, ". Must be 'once' or 'always'");
      return false;
    }

    try {
      // Command: ykman openpgp access set-signature-policy <once|always>
      // Note: This may require admin PIN
      var p = spawn(["ykman", "openpgp", "access", "set-signature-policy", normalizedPolicy],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.pipe);
      p.wait();

      if p.exitCode != 0 {
        var errOutput: string;
        p.stderr.readAll(errOutput);
        verboseLog("Failed to set PIN policy: ", errOutput);
        return false;
      }

      return true;
    } catch {
      return false;
    }
  }

  /*
    Get the current signature PIN policy.

    :returns: "once", "always", or empty string if unknown
  */
  proc getSignaturePinPolicy(): string {
    const info = getYubiKeyInfo();
    return info.sigPinPolicy;
  }

  // =========================================================================
  // Touch Policy Configuration
  // =========================================================================

  /*
    Set the touch policy for a key slot.

    :arg slot: Key slot ("sig", "enc", "aut")
    :arg policy: Touch policy ("on", "off", "cached")
    :returns: true if successful

    Note: "fixed" cannot be set via ykman - it's a factory setting.
    Note: Some policies may require admin PIN confirmation.
  */
  proc setTouchPolicy(slot: string, policy: string): bool {
    if !isYkmanAvailable() || !isYubiKeyConnected() {
      return false;
    }

    const normalizedSlot = slot.toLower();
    const normalizedPolicy = policy.toLower();

    // Validate slot
    if normalizedSlot != "sig" && normalizedSlot != "enc" && normalizedSlot != "aut" {
      verboseLog("Invalid slot: ", slot, ". Must be 'sig', 'enc', or 'aut'");
      return false;
    }

    // Validate policy
    if normalizedPolicy != "on" && normalizedPolicy != "off" && normalizedPolicy != "cached" {
      verboseLog("Invalid touch policy: ", policy, ". Must be 'on', 'off', or 'cached'");
      return false;
    }

    try {
      // Command: ykman openpgp keys set-touch <sig|enc|aut> <on|off|cached>
      var p = spawn(["ykman", "openpgp", "keys", "set-touch", normalizedSlot, normalizedPolicy],
                    stdout=pipeStyle.pipe,
                    stderr=pipeStyle.pipe);
      p.wait();

      if p.exitCode != 0 {
        var errOutput: string;
        p.stderr.readAll(errOutput);
        verboseLog("Failed to set touch policy: ", errOutput);
        return false;
      }

      return true;
    } catch {
      return false;
    }
  }

  /*
    Get the touch policy for a key slot.

    :arg slot: Key slot ("sig", "enc", "aut")
    :returns: Policy string ("on", "off", "cached", "fixed") or empty
  */
  proc getTouchPolicy(slot: string): string {
    const info = getYubiKeyInfo();
    const normalizedSlot = slot.toLower();

    select normalizedSlot {
      when "sig" do return info.sigTouchPolicy;
      when "enc" do return info.encTouchPolicy;
      when "aut" do return info.autTouchPolicy;
      otherwise do return "";
    }
  }

  // =========================================================================
  // YubiKey Serial Number and Firmware
  // =========================================================================

  /*
    Get the YubiKey serial number.

    :returns: Serial number string or empty if not connected
  */
  proc getSerialNumber(): string {
    const info = getYubiKeyInfo();
    return info.serialNumber;
  }

  /*
    Get the YubiKey firmware version.

    :returns: Firmware version string or empty if not connected
  */
  proc getFirmwareVersion(): string {
    const info = getYubiKeyInfo();
    return info.firmware;
  }

  // =========================================================================
  // Configuration Helpers
  // =========================================================================

  /*
    Configure YubiKey for optimal Trusted Workstation mode.

    Sets:
    - Signature PIN policy to "once" (PIN cached for session)
    - Signature touch policy to "cached" (touch cached for 15 seconds)

    :returns: (success, message) tuple
  */
  proc configureForTrustedWorkstation(): (bool, string) {
    if !isYkmanAvailable() {
      return (false, "ykman is not installed");
    }

    if !isYubiKeyConnected() {
      return (false, "No YubiKey connected");
    }

    var messages: list(string);
    var allSuccess = true;

    // Set PIN policy to "once"
    if !setSignaturePinPolicy("once") {
      messages.pushBack("Failed to set PIN policy to 'once'");
      allSuccess = false;
    } else {
      messages.pushBack("PIN policy set to 'once'");
    }

    // Set touch policy to "cached"
    if !setTouchPolicy("sig", "cached") {
      messages.pushBack("Failed to set touch policy to 'cached'");
      allSuccess = false;
    } else {
      messages.pushBack("Touch policy set to 'cached'");
    }

    var resultMessage = "";
    for msg in messages {
      if resultMessage != "" then resultMessage += "; ";
      resultMessage += msg;
    }

    if allSuccess {
      return (true, "YubiKey configured for Trusted Workstation mode: " + resultMessage);
    } else {
      return (false, "Partial configuration: " + resultMessage);
    }
  }

  /*
    Check if YubiKey requires admin PIN for policy changes.

    Some operations require the admin PIN. This function attempts
    to detect if the admin PIN is needed.

    :returns: true if admin PIN is likely required
  */
  proc requiresAdminPin(): bool {
    // Touch policy changes always require admin PIN
    // PIN policy changes require admin PIN
    return true;
  }

  /*
    Get a formatted status string for display.

    :returns: Multi-line status string
  */
  proc getStatusString(): string {
    if !isYkmanAvailable() {
      return "ykman: Not installed\n" +
             "  Install with: pip install yubikey-manager";
    }

    const version = getYkmanVersion();
    var status = "ykman: " + (if version != "" then version else "Available") + "\n";

    if !isYubiKeyConnected() {
      status += "YubiKey: Not connected\n";
      return status;
    }

    const info = getYubiKeyInfo();
    status += "YubiKey: " + info.serialNumber;
    if info.firmware != "" {
      status += " (FW " + info.firmware + ")";
    }
    status += "\n";

    if info.formFactor != "" {
      status += "  Form Factor: " + info.formFactor + "\n";
    }

    status += "\n  OpenPGP Configuration:\n";
    status += "    PIN Policy:   " + (if info.sigPinPolicy != "" then info.sigPinPolicy else "unknown") + "\n";
    status += "    Touch Policy: sig=" + (if info.sigTouchPolicy != "" then info.sigTouchPolicy else "?");
    status += ", enc=" + (if info.encTouchPolicy != "" then info.encTouchPolicy else "?");
    status += ", aut=" + (if info.autTouchPolicy != "" then info.autTouchPolicy else "?");
    status += "\n";

    // Key slot status
    status += "\n  Key Slots:\n";
    status += "    Signature:      " + (if info.sigKeyPresent then "Present" else "Empty") + "\n";
    status += "    Encryption:     " + (if info.encKeyPresent then "Present" else "Empty") + "\n";
    status += "    Authentication: " + (if info.autKeyPresent then "Present" else "Empty") + "\n";

    // PIN retries
    if info.pinRetries > 0 {
      status += "\n  PIN Retries: " + info.pinRetries:string + "/" +
                info.resetRetries:string + "/" + info.adminRetries:string + "\n";
    }

    // Trusted Workstation readiness
    status += "\n  Trusted Workstation: ";
    if info.isTrustedWorkstationReady() {
      status += "Ready\n";
    } else {
      status += "Not configured\n";
      if info.sigPinPolicy == "always" {
        status += "    - PIN policy should be 'once' (currently 'always')\n";
      }
      if info.sigTouchPolicy == "on" || info.sigTouchPolicy == "fixed" {
        status += "    - Touch policy prevents automation (currently '" + info.sigTouchPolicy + "')\n";
      }
    }

    return status;
  }

  // =========================================================================
  // Diagnostic Functions
  // =========================================================================

  /*
    Run a diagnostic check on the YubiKey and ykman setup.

    :returns: List of diagnostic messages
  */
  proc runDiagnostics(): list(string) {
    var results: list(string);

    // Check ykman availability
    if isYkmanAvailable() {
      const version = getYkmanVersion();
      results.pushBack("[OK] ykman installed: " + version);
    } else {
      results.pushBack("[FAIL] ykman not found in PATH");
      results.pushBack("       Install: pip install yubikey-manager");
      return results;
    }

    // Check YubiKey connection
    if isYubiKeyConnected() {
      results.pushBack("[OK] YubiKey connected");
    } else {
      results.pushBack("[FAIL] No YubiKey detected");
      results.pushBack("       Insert YubiKey and try again");
      return results;
    }

    // Get device info
    const info = getYubiKeyInfo();

    if info.serialNumber != "" {
      results.pushBack("[OK] Serial: " + info.serialNumber);
    }

    if info.firmware != "" {
      results.pushBack("[OK] Firmware: " + info.firmware);
    }

    // Check OpenPGP keys
    if info.sigKeyPresent {
      results.pushBack("[OK] Signing key present");
    } else {
      results.pushBack("[WARN] No signing key on YubiKey");
    }

    // Check PIN policy
    if info.sigPinPolicy == "once" {
      results.pushBack("[OK] PIN policy: once (optimal for automation)");
    } else if info.sigPinPolicy == "always" {
      results.pushBack("[WARN] PIN policy: always (requires PIN for each signature)");
      results.pushBack("       Consider: remote-juggler yubikey set-pin-policy once");
    } else {
      results.pushBack("[INFO] PIN policy: unknown");
    }

    // Check touch policy
    if info.sigTouchPolicy == "off" {
      results.pushBack("[OK] Touch policy: off (no touch required)");
    } else if info.sigTouchPolicy == "cached" {
      results.pushBack("[OK] Touch policy: cached (touch cached for 15s)");
    } else if info.sigTouchPolicy == "on" {
      results.pushBack("[WARN] Touch policy: on (touch required for each signature)");
      results.pushBack("       Consider: remote-juggler yubikey set-touch sig cached");
    } else if info.sigTouchPolicy == "fixed" {
      results.pushBack("[INFO] Touch policy: fixed (cannot be changed)");
    }

    // PIN retries warning
    if info.pinRetries > 0 && info.pinRetries <= 2 {
      results.pushBack("[WARN] Low PIN retries remaining: " + info.pinRetries:string);
    }

    return results;
  }
}
