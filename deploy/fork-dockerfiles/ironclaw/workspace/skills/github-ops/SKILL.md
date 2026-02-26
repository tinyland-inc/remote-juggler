---
name: github-ops
description: GitHub operations for file management, branch creation, pull requests, and security alerts
version: "1.0"
tags: [github, git, pr, security, codeql]
---

# GitHub Operations

Use this skill for all GitHub repository interactions. All operations are authenticated via the gateway's GitHub token (resolved from Setec).

## File Operations
- `github_fetch(owner, repo, path, ref?)` fetches file contents from a repository
  - Returns decoded content, SHA, and size
  - Use `ref` to target a specific branch or commit

## Code Scanning
- `github_list_alerts(owner, repo, state?, severity?)` lists CodeQL alerts
  - Filter by state: `open`, `closed`, `dismissed`, `fixed`
  - Filter by severity: `critical`, `high`, `medium`, `low`
- `github_get_alert(owner, repo, alert_number)` gets full details for a specific alert

## Branch & PR Workflow
1. `github_create_branch(owner, repo, branch_name, base?)` creates a new branch
   - Default base: `main`
2. `github_update_file(owner, repo, path, content, message, branch)` creates or updates a file
   - Handles SHA resolution automatically (update existing or create new)
3. `github_create_pr(owner, repo, title, head, body?, base?)` creates a pull request
   - Default base: `main`

## Bot Identity
- All operations are attributed to `rj-agent-bot[bot]` (GitHub App ID 2945224)
- Git commits use: `rj-agent-bot[bot] <2945224+rj-agent-bot[bot]@users.noreply.github.com>`
- SSH key at `/home/agent/.ssh/id_ed25519`

## Common Patterns
- **Fix CodeQL alert**: list_alerts -> fetch file -> create_branch -> update_file -> create_pr
- **Update config**: fetch current -> create_branch -> update_file -> create_pr
- **Reference comparison**: fetch from reference project -> compare with our repo
