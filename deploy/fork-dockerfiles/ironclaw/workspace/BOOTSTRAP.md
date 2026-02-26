# IronClaw First-Run Bootstrap

This document describes the initialization sequence when IronClaw starts with a fresh workspace (new PVC or after reset).

## Bootstrap Sequence

### 1. Workspace Verification
The init container copies files from `/workspace-defaults/` to `/workspace/` only if `AGENTS.md` is missing. This preserves evolved state across restarts.

### 2. Git Identity
Environment variables configure git:
- `GIT_AUTHOR_NAME=rj-agent-bot[bot]`
- `GIT_AUTHOR_EMAIL=2945224+rj-agent-bot[bot]@users.noreply.github.com`
- `GIT_COMMITTER_NAME=rj-agent-bot[bot]`
- `GIT_COMMITTER_EMAIL=2945224+rj-agent-bot[bot]@users.noreply.github.com`
- SSH key mounted at `/home/agent/.ssh/id_ed25519`

### 3. MCP Access Verification
On first heartbeat, verify connectivity:
- Call `juggler_campaign_status()` to verify rj-gateway reachability
- Call `juggler_setec_list()` to verify Setec access
- Call `juggler_audit_log(count=1)` to verify audit trail

### 4. Memory Initialization
If `memory/MEMORY.md` is the default seed, the first memory-maintenance cron will begin populating it with observations from campaign results.

### 5. Workspace State
After bootstrap, the workspace should contain:
```
/workspace/
  AGENTS.md       — Agent instructions (this evolves over time)
  SOUL.md         — Persona and values (stable)
  IDENTITY.md     — Agent identity card (stable)
  TOOLS.md        — Tool reference (updated by memory-maintenance)
  HEARTBEAT.md    — Periodic checklist (stable)
  BOOTSTRAP.md    — This file (reference only)
  memory/
    MEMORY.md     — Long-term memory (grows over time)
```

## Emergency Reset
To force a full workspace reset, delete the PVC and let the init container re-copy defaults:
```bash
kubectl delete pvc ironclaw-workspace -n fuzzy-dev
kubectl delete pod -l app=ironclaw-agent -n fuzzy-dev
```
