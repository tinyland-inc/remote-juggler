---
description: Show or manage git identities with RemoteJuggler
allowed-tools: "Bash(...), Read(...)"
---

Manage git identities across GitLab and GitHub.

Usage:
- /identity list - List all configured identities
- /identity detect - Detect current repository's identity
- /identity validate <name> - Validate an identity's connectivity
- /identity status - Show current identity and configuration

Run the appropriate remote-juggler command based on $ARGUMENTS.

Commands mapping:
- `list` -> `remote-juggler list`
- `detect` -> `remote-juggler detect`
- `validate <name>` -> `remote-juggler validate <name>`
- `status` -> `remote-juggler status`

If no argument is provided, default to showing status.

Output includes:
- Identity name and provider (GitLab/GitHub)
- User name and email
- SSH host alias and key path
- Credential source (keychain/environment/CLI)
- GPG signing configuration
- Organization associations
