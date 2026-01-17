---
description: Switch git identity context using RemoteJuggler
allowed-tools: "Bash(...), Read(...)"
---

Switch to the requested git identity context.

Arguments: $ARGUMENTS (identity name like "personal", "work", "github-personal")

Steps:
1. Run `remote-juggler detect` to show current identity
2. Run `remote-juggler switch $ARGUMENTS` to switch
3. Verify the switch with `remote-juggler status`

Example usage:
- `/juggle personal` - Switch to personal GitLab identity
- `/juggle work` - Switch to work GitLab identity
- `/juggle github-personal` - Switch to personal GitHub identity

The command will:
- Authenticate with the provider (glab/gh CLI)
- Update git remote URLs if needed
- Configure GPG signing for the identity
- Store state for future reference
