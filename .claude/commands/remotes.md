---
description: Manage git remotes with identity awareness
allowed-tools: "Bash(...), Read(...)"
---

View and manage git remotes with identity context.

Run `remote-juggler detect` to identify the current remote configuration
and suggest appropriate identity switches if needed.

This command will:
1. Parse the current repository's git remotes
2. Identify the provider (GitLab, GitHub, Bitbucket, custom)
3. Match against configured identities
4. Report any mismatches between remote and active identity
5. Suggest corrections if needed

Additional checks:
- Verify SSH host alias matches identity
- Check URL rewrite rules from gitconfig
- Validate remote is reachable with current credentials

Usage with arguments:
- `/remotes` - Show current remote analysis
- `/remotes fix` - Apply suggested identity switch
- `/remotes show` - Display raw git remote -v output
