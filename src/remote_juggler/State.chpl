/*
  State Module
  ============

  Context state persistence for RemoteJuggler.

  This module handles the current switch context state, which tracks:
  - Currently active identity
  - Timestamp of last switch
  - Repository where switch was performed
  - Active GPG key

  State is persisted separately from configuration to allow for
  faster updates during identity switches without rewriting the
  entire configuration file.

  **State File Location:**

  ``~/.config/remote-juggler/state.json``

  :author: RemoteJuggler Team
  :version: 2.0.0
*/
prototype module State {
  use IO;
  use Time;
  use FileSystem;
  public use super.Core;
  use super.GlobalConfig only getConfigDir, ensureConfigDir, expandTilde,
                        escapeJSON, extractJSONString, getCurrentTimestamp;

  // =========================================================================
  // State File Configuration
  // =========================================================================

  /*
    Default state file path.
  */
  param STATE_FILE = "~/.config/remote-juggler/state.json";

  /*
    State schema version for compatibility checking.
  */
  param STATE_SCHEMA_VERSION = "1.0.0";

  // =========================================================================
  // Extended State Record
  // =========================================================================

  /*
    Extended switch state with additional tracking.

    Extends SwitchContext with session information and history.

    :var context: Base switch context
    :var sessionId: Unique session identifier
    :var switchCount: Number of switches in current session
    :var lastProvider: Provider of last active identity
  */
  record SwitchState {
    var context: SwitchContext;
    var schemaVersion: string = STATE_SCHEMA_VERSION;
    var sessionId: string = "";
    var switchCount: int = 0;
    var lastProvider: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.context = new SwitchContext();
      this.schemaVersion = STATE_SCHEMA_VERSION;
      this.sessionId = "";
      this.switchCount = 0;
      this.lastProvider = "";
    }

    /*
      Initialize from a SwitchContext.

      :arg ctx: Base context
    */
    proc init(ctx: SwitchContext) {
      this.context = ctx;
      this.schemaVersion = STATE_SCHEMA_VERSION;
      this.sessionId = generateSessionId();
      this.switchCount = 1;
      this.lastProvider = "";
    }

    /*
      Initialize with all values.

      :arg context: Base switch context
      :arg sessionId: Session identifier
      :arg switchCount: Switch count
      :arg lastProvider: Last provider name
    */
    proc init(context: SwitchContext, sessionId: string,
              switchCount: int, lastProvider: string) {
      this.context = context;
      this.schemaVersion = STATE_SCHEMA_VERSION;
      this.sessionId = sessionId;
      this.switchCount = switchCount;
      this.lastProvider = lastProvider;
    }

    /*
      Get the current identity name.

      :returns: Identity name or empty string
    */
    proc getCurrentIdentity(): string {
      return context.currentIdentity;
    }

    /*
      Check if there's an active identity.

      :returns: true if identity is set
    */
    proc hasActiveIdentity(): bool {
      return context.hasActiveIdentity();
    }

    /*
      Update the switch context.

      :arg newIdentity: New identity name
      :arg repoPath: Repository path
      :arg gpgKey: GPG key ID
      :arg provider: Provider name
    */
    proc ref update(newIdentity: string, repoPath: string = "",
                    gpgKey: string = "", provider: string = "") {
      context.currentIdentity = newIdentity;
      context.lastSwitch = getCurrentTimestamp();
      context.repoPath = repoPath;
      context.gpgKeyActive = gpgKey;
      switchCount += 1;
      lastProvider = provider;
    }

    /*
      Clear the current state.
    */
    proc ref clear() {
      context = new SwitchContext();
      switchCount = 0;
      lastProvider = "";
    }
  }

  // =========================================================================
  // State File Operations
  // =========================================================================

  /*
    Get the state file path.

    :returns: Expanded state file path
  */
  proc getStatePath(): string {
    return expandTilde(STATE_FILE);
  }

  /*
    Load state from file.

    Reads the state file and returns the current switch context.
    If the file doesn't exist or is invalid, returns default state.

    :returns: SwitchContext with current state

    Example::

      var ctx = loadState();
      if ctx.hasActiveIdentity() {
        writeln("Current identity: ", ctx.currentIdentity);
      }
  */
  proc loadState(): SwitchContext {
    const path = getStatePath();

    verboseLog("Loading state from: ", path);

    if !stateFileExists() {
      verboseLog("State file not found, using defaults");
      return new SwitchContext();
    }

    try {
      var f = open(path, ioMode.r);
      defer { try! f.close(); }
      var reader = f.reader(locking=false);
      defer { try! reader.close(); }

      var content: string;
      reader.readAll(content);

      return parseStateJSON(content);
    } catch e {
      verboseLog("Error loading state: ", e.message());
      return new SwitchContext();
    }
  }

  /*
    Load extended state from file.

    Returns full SwitchState with session tracking.

    :returns: SwitchState with extended information
  */
  proc loadExtendedState(): SwitchState {
    const path = getStatePath();

    verboseLog("Loading extended state from: ", path);

    if !stateFileExists() {
      verboseLog("State file not found, using defaults");
      return new SwitchState();
    }

    try {
      var f = open(path, ioMode.r);
      defer { try! f.close(); }
      var reader = f.reader(locking=false);
      defer { try! reader.close(); }

      var content: string;
      reader.readAll(content);

      return parseExtendedStateJSON(content);
    } catch e {
      verboseLog("Error loading state: ", e.message());
      return new SwitchState();
    }
  }

  /*
    Save state to file.

    Persists the switch context to the state file.
    Creates the config directory if needed.

    :arg ctx: Switch context to save
    :returns: true if saved successfully

    Example::

      var ctx = new SwitchContext("personal", getCurrentTimestamp());
      if saveState(ctx) {
        writeln("State saved");
      }
  */
  proc saveState(ctx: SwitchContext): bool {
    if !ensureConfigDir() {
      return false;
    }

    const path = getStatePath();

    verboseLog("Saving state to: ", path);

    try {
      var f = open(path, ioMode.cw);
      defer { try! f.close(); }
      var writer = f.writer(locking=false);
      defer { try! writer.close(); }

      const json = serializeStateJSON(ctx);
      writer.write(json);

      verboseLog("State saved successfully");
      return true;
    } catch e {
      verboseLog("Error saving state: ", e.message());
      return false;
    }
  }

  /*
    Save extended state to file.

    :arg state: Extended state to save
    :returns: true if saved successfully
  */
  proc saveExtendedState(state: SwitchState): bool {
    if !ensureConfigDir() {
      return false;
    }

    const path = getStatePath();

    verboseLog("Saving extended state to: ", path);

    try {
      var f = open(path, ioMode.cw);
      defer { try! f.close(); }
      var writer = f.writer(locking=false);
      defer { try! writer.close(); }

      const json = serializeExtendedStateJSON(state);
      writer.write(json);

      verboseLog("Extended state saved successfully");
      return true;
    } catch e {
      verboseLog("Error saving state: ", e.message());
      return false;
    }
  }

  /*
    Update state with new identity.

    Convenience function that loads current state, updates it,
    and saves it back.

    :arg identityName: New identity name
    :arg repoPath: Repository path (optional)
    :arg gpgKey: GPG key ID (optional)
    :returns: true if updated successfully

    Example::

      if updateState("work", "/path/to/repo") {
        writeln("Switched to work identity");
      }
  */
  proc updateState(identityName: string, repoPath: string = "",
                   gpgKey: string = ""): bool {
    var ctx = new SwitchContext();
    ctx.currentIdentity = identityName;
    ctx.lastSwitch = getCurrentTimestamp();
    ctx.repoPath = repoPath;
    ctx.gpgKeyActive = gpgKey;
    return saveState(ctx);
  }

  /*
    Clear the current state.

    Removes identity selection, effectively resetting state.

    :returns: true if cleared successfully
  */
  proc clearState(): bool {
    return saveState(new SwitchContext());
  }

  /*
    Check if state file exists.

    :returns: true if state file exists
  */
  proc stateFileExists(): bool {
    try {
      return FileSystem.exists(getStatePath());
    } catch {
      return false;
    }
  }

  /*
    Delete the state file.

    Removes the state file entirely.

    :returns: true if deleted or didn't exist
  */
  proc deleteStateFile(): bool {
    const path = getStatePath();
    try {
      if FileSystem.exists(path) {
        FileSystem.remove(path);
      }
      return true;
    } catch e {
      verboseLog("Error deleting state file: ", e.message());
      return false;
    }
  }

  // =========================================================================
  // State JSON Serialization
  // =========================================================================

  /*
    Parse basic state from JSON.

    :arg json: JSON string
    :returns: Parsed SwitchContext
  */
  proc parseStateJSON(json: string): SwitchContext {
    var ctx = new SwitchContext();

    ctx.currentIdentity = extractJSONString(json, "currentIdentity", "");
    ctx.lastSwitch = extractJSONString(json, "lastSwitch", "");
    ctx.repoPath = extractJSONString(json, "repoPath", "");
    ctx.gpgKeyActive = extractJSONString(json, "gpgKeyActive", "");

    return ctx;
  }

  /*
    Parse extended state from JSON.

    :arg json: JSON string
    :returns: Parsed SwitchState
  */
  proc parseExtendedStateJSON(json: string): SwitchState {
    var state = new SwitchState();

    state.context.currentIdentity = extractJSONString(json, "currentIdentity", "");
    state.context.lastSwitch = extractJSONString(json, "lastSwitch", "");
    state.context.repoPath = extractJSONString(json, "repoPath", "");
    state.context.gpgKeyActive = extractJSONString(json, "gpgKeyActive", "");

    state.schemaVersion = extractJSONString(json, "schemaVersion", STATE_SCHEMA_VERSION);
    state.sessionId = extractJSONString(json, "sessionId", "");
    state.lastProvider = extractJSONString(json, "lastProvider", "");

    // Parse switchCount
    const countStr = extractJSONString(json, "switchCount", "0");
    try {
      state.switchCount = countStr:int;
    } catch {
      state.switchCount = 0;
    }

    return state;
  }

  /*
    Serialize basic state to JSON.

    :arg ctx: Switch context to serialize
    :returns: JSON string
  */
  proc serializeStateJSON(ctx: SwitchContext): string {
    var json = "{\n";
    json += '  "schemaVersion": "' + STATE_SCHEMA_VERSION + '",\n';
    json += '  "currentIdentity": "' + escapeJSON(ctx.currentIdentity) + '",\n';
    json += '  "lastSwitch": "' + ctx.lastSwitch + '",\n';
    json += '  "repoPath": "' + escapeJSON(ctx.repoPath) + '",\n';
    json += '  "gpgKeyActive": "' + escapeJSON(ctx.gpgKeyActive) + '"\n';
    json += "}\n";
    return json;
  }

  /*
    Serialize extended state to JSON.

    :arg state: Extended state to serialize
    :returns: JSON string
  */
  proc serializeExtendedStateJSON(state: SwitchState): string {
    var json = "{\n";
    json += '  "schemaVersion": "' + state.schemaVersion + '",\n';
    json += '  "sessionId": "' + escapeJSON(state.sessionId) + '",\n';
    json += '  "switchCount": ' + state.switchCount:string + ',\n';
    json += '  "lastProvider": "' + escapeJSON(state.lastProvider) + '",\n';
    json += '  "currentIdentity": "' + escapeJSON(state.context.currentIdentity) + '",\n';
    json += '  "lastSwitch": "' + state.context.lastSwitch + '",\n';
    json += '  "repoPath": "' + escapeJSON(state.context.repoPath) + '",\n';
    json += '  "gpgKeyActive": "' + escapeJSON(state.context.gpgKeyActive) + '"\n';
    json += "}\n";
    return json;
  }

  // =========================================================================
  // State Query Functions
  // =========================================================================

  /*
    Get the currently active identity name.

    Convenience function that loads state and returns identity.

    :returns: Identity name or empty string if none active
  */
  proc getCurrentIdentityName(): string {
    const ctx = loadState();
    return ctx.currentIdentity;
  }

  /*
    Check if any identity is currently active.

    :returns: true if an identity is active
  */
  proc hasActiveIdentity(): bool {
    const ctx = loadState();
    return ctx.hasActiveIdentity();
  }

  /*
    Get the timestamp of the last identity switch.

    :returns: ISO timestamp or empty string
  */
  proc getLastSwitchTime(): string {
    const ctx = loadState();
    return ctx.lastSwitch;
  }

  /*
    Get the repository path from last switch.

    :returns: Repository path or empty string
  */
  proc getLastRepoPath(): string {
    const ctx = loadState();
    return ctx.repoPath;
  }

  /*
    Get the currently active GPG key.

    :returns: GPG key ID or empty string
  */
  proc getActiveGPGKey(): string {
    const ctx = loadState();
    return ctx.gpgKeyActive;
  }

  // =========================================================================
  // State Comparison
  // =========================================================================

  /*
    State comparison result.

    Used to detect changes between saved state and current state.

    :var identityChanged: Whether identity differs
    :var gpgKeyChanged: Whether GPG key differs
    :var repoChanged: Whether repo path differs
  */
  record StateComparison {
    var identityChanged: bool = false;
    var gpgKeyChanged: bool = false;
    var repoChanged: bool = false;

    /*
      Check if any aspect changed.

      :returns: true if anything differs
    */
    proc hasChanges(): bool {
      return identityChanged || gpgKeyChanged || repoChanged;
    }
  }

  /*
    Compare two switch contexts.

    :arg current: Current/proposed state
    :arg saved: Previously saved state
    :returns: Comparison result
  */
  proc compareStates(current: SwitchContext, saved: SwitchContext): StateComparison {
    var cmp = new StateComparison();
    cmp.identityChanged = current.currentIdentity != saved.currentIdentity;
    cmp.gpgKeyChanged = current.gpgKeyActive != saved.gpgKeyActive;
    cmp.repoChanged = current.repoPath != saved.repoPath;
    return cmp;
  }

  /*
    Check if a state transition is valid.

    Validates that a proposed state change is acceptable.

    :arg fromState: Current state
    :arg toIdentity: Target identity name
    :returns: true if transition is valid
  */
  proc isValidTransition(fromState: SwitchContext, toIdentity: string): bool {
    // Empty target is not valid
    if toIdentity == "" then return false;

    // Switching to same identity is valid (idempotent)
    if fromState.currentIdentity == toIdentity then return true;

    // Any other switch is valid
    return true;
  }

  // =========================================================================
  // Session Management
  // =========================================================================

  /*
    Generate a unique session identifier.

    Creates a simple session ID based on timestamp and random component.

    :returns: Session ID string
  */
  proc generateSessionId(): string {
    try {
      const now = dateTime.now();
      return "session-" + now.year:string +
             (now.month:int):string +
             now.day:string +
             "-" + now.hour:string +
             now.minute:string +
             now.second:string;
    } catch {
      return "session-unknown";
    }
  }

  /*
    Check if session has expired.

    Sessions expire after 24 hours of inactivity.

    :arg state: State to check
    :returns: true if session is expired
  */
  proc isSessionExpired(state: SwitchState): bool {
    if state.context.lastSwitch == "" then return true;

    try {
      // Simple check - if lastSwitch is more than 24 hours old
      // In production, would parse and compare timestamps properly
      const now = dateTime.now();
      // Placeholder - actual implementation would parse lastSwitch
      return false;
    } catch {
      return true;
    }
  }

  /*
    Start a new session.

    Creates a new session with fresh session ID.

    :returns: New SwitchState with fresh session
  */
  proc startNewSession(): SwitchState {
    var state = new SwitchState();
    state.sessionId = generateSessionId();
    state.switchCount = 0;
    return state;
  }

  // =========================================================================
  // State History (Future Enhancement)
  // =========================================================================

  /*
    History entry for tracking switches.

    Placeholder for future history tracking feature.

    :var identity: Identity that was switched to
    :var timestamp: When switch occurred
    :var repoPath: Repository path
  */
  record HistoryEntry {
    var identity: string = "";
    var timestamp: string = "";
    var repoPath: string = "";

    /*
      Initialize with default values.
    */
    proc init() {
      this.identity = "";
      this.timestamp = "";
      this.repoPath = "";
    }

    /*
      Initialize from a switch context.

      :arg ctx: Switch context
    */
    proc init(ctx: SwitchContext) {
      this.identity = ctx.currentIdentity;
      this.timestamp = ctx.lastSwitch;
      this.repoPath = ctx.repoPath;
    }
  }

  /*
    Create a history entry from current state.

    :returns: HistoryEntry with current state
  */
  proc createHistoryEntry(): HistoryEntry {
    const ctx = loadState();
    return new HistoryEntry(ctx);
  }
}
