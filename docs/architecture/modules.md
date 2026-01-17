# Chapel Modules

RemoteJuggler consists of 14 Chapel modules in `src/remote_juggler/`.

## Module Dependency Graph

```mermaid
flowchart LR
    subgraph Main["remote_juggler.chpl"]
        M[main]
    end

    subgraph Core["Core Modules"]
        Core[Core]
        Config[Config]
        GlobalConfig[GlobalConfig]
        State[State]
    end

    subgraph Identity["Identity Layer"]
        Id[Identity]
        Remote[Remote]
        GPG[GPG]
        ProviderCLI[ProviderCLI]
    end

    subgraph External["External"]
        Keychain[Keychain]
    end

    subgraph Protocol["Protocol Layer"]
        Proto[Protocol]
        MCP[MCP]
        ACP[ACP]
        Tools[Tools]
    end

    M --> Core
    M --> Config
    M --> Id
    M --> MCP
    M --> ACP

    MCP --> Proto
    MCP --> Tools
    ACP --> Proto
    ACP --> Tools

    Tools --> Id
    Tools --> GlobalConfig
    Tools --> Keychain

    Id --> ProviderCLI
    Id --> GPG
    Id --> Remote
    Id --> Config

    Config --> GlobalConfig
    GlobalConfig --> State

    ProviderCLI --> Keychain
```

## Module Reference

### Core.chpl

Type definitions and enums used throughout the codebase.

**Location:** `src/remote_juggler/Core.chpl`

**Key Types:**

```chapel
enum Provider { GitLab, GitHub, Bitbucket, Custom }
enum CredentialSource { Keychain, Environment, CLIAuth, None }
enum AuthMode { KeychainAuth, CLIAuthenticated, TokenOnly, SSHOnly }

record GitIdentity {
  var name: string;
  var provider: Provider;
  var host: string;
  var hostname: string;
  var user: string;
  var email: string;
  var identityFile: string;
  var tokenEnvVar: string;
  var gpg: GPGConfig;
  var credentialSource: CredentialSource;
}

record GPGConfig {
  var keyId: string;
  var signCommits: bool;
  var signTags: bool;
  var autoSignoff: bool;
}
```

**Constants:**

```chapel
const VERSION = "2.0.0";
```

---

### Config.chpl

SSH and git configuration parsing.

**Location:** `src/remote_juggler/Config.chpl`

**Key Functions:**

```chapel
proc parseSSHConfig(path: string): list(SSHHostEntry)
proc parseGitConfigRewrites(path: string): list(URLRewrite)
proc parseGitUserConfig(path: string): GitUserConfig
```

**SSHHostEntry Record:**

```chapel
record SSHHostEntry {
  var host: string;       // Host alias (e.g., "gitlab-work")
  var hostname: string;   // Actual hostname (e.g., "gitlab.com")
  var user: string;       // User (typically "git")
  var identityFile: string;
  var port: int = 22;
  var proxyJump: string;
}
```

---

### GlobalConfig.chpl

Configuration file management and identity CRUD operations.

**Location:** `src/remote_juggler/GlobalConfig.chpl`

**Key Functions:**

```chapel
proc getConfigPath(): string
proc loadIdentities(): list(GitIdentity)
proc loadSettings(): Settings
proc getIdentity(name: string): GitIdentity
proc saveIdentity(identity: GitIdentity): bool
proc removeIdentity(name: string): bool
proc importFromSSHConfig(): ImportResult
proc syncManagedBlocks(): SyncResult
```

---

### State.chpl

Runtime state persistence (current identity, last switch time).

**Location:** `src/remote_juggler/State.chpl`

**Key Types:**

```chapel
record SwitchContext {
  var currentIdentity: string;
  var lastSwitch: string;
  var repoPath: string;
}
```

**Key Functions:**

```chapel
proc loadState(): SwitchContext
proc saveState(ctx: SwitchContext): bool
```

---

### Identity.chpl

Identity operations: listing, detection, switching, validation.

**Location:** `src/remote_juggler/Identity.chpl`

**Key Functions:**

```chapel
proc listIdentities(providerFilter: Provider = Provider.Custom): list(GitIdentity)
proc listIdentityNames(): list(string)
proc getIdentity(name: string): (bool, GitIdentity)
proc detectIdentity(repoPath: string): (bool, GitIdentity, string)
proc detectIdentityDetailed(repoPath: string): DetectionResult
proc switchIdentity(name: string, setRemote: bool, repoPath: string): SwitchResult
proc validateIdentity(name: string, checkGPG: bool): ValidationResult
```

---

### Remote.chpl

Git remote URL manipulation.

**Location:** `src/remote_juggler/Remote.chpl`

**Key Functions:**

```chapel
proc isGitRepository(path: string): bool
proc getRepositoryRoot(path: string): (bool, string)
proc getOriginURL(repoPath: string): (bool, string)
proc getCurrentBranch(repoPath: string): (bool, string)
proc getUpstreamBranch(repoPath: string, branch: string): (bool, string)
proc setRemoteURL(repoPath: string, remote: string, url: string): bool
proc extractHostFromURL(url: string): string
proc extractRepoPath(url: string): string
proc transformURLForHost(url: string, newHost: string): string
```

---

### Keychain.chpl

macOS Security.framework FFI for secure token storage.

**Location:** `src/remote_juggler/Keychain.chpl`

**C Interface (require directive):**

```chapel
require "../../c_src/keychain.h", "../../c_src/keychain.c";
```

**Key Functions:**

```chapel
proc isDarwin(): bool
proc storeToken(provider: string, identity: string, account: string, token: string): bool
proc retrieveToken(provider: string, identity: string, account: string): (bool, string)
proc deleteToken(provider: string, identity: string, account: string): bool
```

See [Keychain Integration](keychain.md) for implementation details.

---

### GPG.chpl

GPG key management and provider verification.

**Location:** `src/remote_juggler/GPG.chpl`

**Key Functions:**

```chapel
proc listKeys(): list(GPGKey)
proc getKeyForEmail(email: string): (bool, string)
proc verifyKeyWithProvider(identity: GitIdentity): GPGVerifyResult
proc getGPGSettingsURL(identity: GitIdentity): string
```

---

### ProviderCLI.chpl

glab and gh CLI integration.

**Location:** `src/remote_juggler/ProviderCLI.chpl`

**Key Functions:**

```chapel
proc isGlabAvailable(): bool
proc isGhAvailable(): bool
proc glabAuthStatus(hostname: string): (bool, string)
proc ghAuthStatus(hostname: string): (bool, string)
proc glabAuthLogin(hostname: string, token: string): bool
proc ghAuthLogin(hostname: string, token: string): bool
proc resolveCredential(identity: GitIdentity): (bool, string)
```

---

### Protocol.chpl

JSON-RPC 2.0 base protocol implementation.

**Location:** `src/remote_juggler/Protocol.chpl`

**Key Functions:**

```chapel
proc parseJsonRpcRequest(line: string): (bool, int, string, string)
proc formatJsonRpcResponse(id: int, result: string): string
proc formatJsonRpcError(id: int, code: int, message: string): string
proc extractJsonString(json: string, key: string): (bool, string)
proc extractJsonObject(json: string, key: string): (bool, string)
```

---

### MCP.chpl

Model Context Protocol server implementation.

**Location:** `src/remote_juggler/MCP.chpl`

**Key Functions:**

```chapel
proc runMCPServer()
proc handleInitialize(id: int, params: string): string
proc handleToolsList(id: int): string
proc handleToolsCall(id: int, params: string): string
```

---

### ACP.chpl

Agent Communication Protocol server implementation.

**Location:** `src/remote_juggler/ACP.chpl`

**Key Functions:**

```chapel
proc runACPServer()
proc handleACPInitialize(id: int, params: string): string
proc handleACPToolsList(id: int): string
proc handleACPExecuteAction(id: int, params: string): string
```

---

### Tools.chpl

MCP/ACP tool definitions and handlers.

**Location:** `src/remote_juggler/Tools.chpl`

**Tool List:**

| Tool | Handler Function |
|------|-----------------|
| `juggler_list_identities` | `handleListIdentities` |
| `juggler_detect_identity` | `handleDetectIdentity` |
| `juggler_switch` | `handleSwitch` |
| `juggler_status` | `handleStatus` |
| `juggler_validate` | `handleValidate` |
| `juggler_store_token` | `handleStoreToken` |
| `juggler_sync_config` | `handleSyncConfig` |

**Key Functions:**

```chapel
proc getToolDefinitions(): list(ToolDefinition)
proc executeTool(name: string, params: string): (bool, string)
```

## Build Configuration

Modules are included via the main entry point:

```chapel
// src/remote_juggler.chpl
prototype module remote_juggler {
  include module Core;
  include module Config;
  include module GlobalConfig;
  include module State;
  include module Keychain;
  include module ProviderCLI;
  include module GPG;
  include module Remote;
  include module Identity;
  include module Protocol;
  include module MCP;
  include module ACP;
  include module Tools;

  public use Core;
  // ... public re-exports
}
```

The `prototype module` declaration enables fatal error handling for unhandled exceptions.
