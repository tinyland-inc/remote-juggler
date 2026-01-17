# Troubleshooting

Common issues and their solutions.

## Installation Issues

### Binary Not Found

**Symptom:** `command not found: remote-juggler`

**Solution:**

1. Check installation directory:
   ```bash
   ls ~/.local/bin/remote-juggler
   ```

2. Add to PATH:
   ```bash
   echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
   source ~/.bashrc
   ```

3. Or use full path:
   ```bash
   ~/.local/bin/remote-juggler status
   ```

### Permission Denied

**Symptom:** `Permission denied` when running

**Solution:**

```bash
chmod +x ~/.local/bin/remote-juggler
```

### macOS Gatekeeper Block

**Symptom:** "remote-juggler cannot be opened because it is from an unidentified developer"

**Solution:**

```bash
xattr -d com.apple.quarantine ~/.local/bin/remote-juggler
```

Or: System Preferences > Security & Privacy > Allow

## Configuration Issues

### No Identities Found

**Symptom:** `remote-juggler list` shows no identities

**Solution:**

1. Import from SSH config:
   ```bash
   remote-juggler config import
   ```

2. Or create config manually:
   ```bash
   remote-juggler config init
   # Edit ~/.config/remote-juggler/config.json
   ```

### Config File Not Found

**Symptom:** Configuration warnings

**Solution:**

```bash
# Initialize configuration
remote-juggler config init

# Verify location
remote-juggler config show
```

### JSON Parse Error

**Symptom:** `Failed to parse config file`

**Solution:**

1. Validate JSON:
   ```bash
   cat ~/.config/remote-juggler/config.json | python -m json.tool
   ```

2. Fix syntax errors (missing commas, quotes, braces)

3. Reset to default:
   ```bash
   rm ~/.config/remote-juggler/config.json
   remote-juggler config init
   ```

## SSH Issues

### Permission Denied (publickey)

**Symptom:** SSH connection fails with "Permission denied"

**Diagnosis:**

```bash
# Test SSH connection with verbose output
ssh -vT git@gitlab-work
```

**Solutions:**

1. Check key exists:
   ```bash
   ls -la ~/.ssh/id_ed25519_work*
   ```

2. Check key permissions:
   ```bash
   chmod 600 ~/.ssh/id_ed25519_work
   chmod 644 ~/.ssh/id_ed25519_work.pub
   ```

3. Add to SSH agent:
   ```bash
   ssh-add ~/.ssh/id_ed25519_work
   ```

4. Verify key is registered with provider

### Could Not Resolve Hostname

**Symptom:** `ssh: Could not resolve hostname gitlab-work`

**Solution:**

Check SSH config:
```bash
grep -A5 "Host gitlab-work" ~/.ssh/config
```

Ensure Host entry exists and is valid.

### Wrong Identity Used

**Symptom:** Commits show wrong email

**Diagnosis:**

```bash
remote-juggler status
git config user.email
```

**Solution:**

1. Verify current identity:
   ```bash
   remote-juggler status
   ```

2. Switch to correct identity:
   ```bash
   remote-juggler switch work
   ```

3. Verify SSH config has `IdentitiesOnly yes`:
   ```
   Host gitlab-work
       IdentitiesOnly yes
   ```

## Keychain Issues

### Token Not Found

**Symptom:** `No token found for identity`

**Solution:**

1. Store token:
   ```bash
   remote-juggler token set work
   # Enter token when prompted
   ```

2. Verify storage:
   ```bash
   security find-generic-password -s "remote-juggler.gitlab.work" -w
   ```

### Keychain Access Denied

**Symptom:** System prompts for Keychain access repeatedly

**Solution:**

1. Click "Always Allow" when prompted

2. Check Keychain Access app for any blocked items

3. Reset Keychain permissions:
   ```bash
   security unlock-keychain ~/Library/Keychains/login.keychain-db
   ```

### Not macOS

**Symptom:** `Keychain integration requires macOS`

**Solution:**

Use environment variables instead:

```bash
export GITLAB_WORK_TOKEN="glpat-..."
```

Or use provider CLI authentication:

```bash
glab auth login
```

## GPG Issues

### Failed to Sign Data

**Symptom:** `error: gpg failed to sign the data`

**Diagnosis:**

```bash
# Test GPG signing
echo "test" | gpg --clearsign
```

**Solutions:**

1. Set GPG TTY:
   ```bash
   export GPG_TTY=$(tty)
   ```

2. Restart GPG agent:
   ```bash
   gpgconf --kill gpg-agent
   ```

3. Install pinentry-mac (macOS):
   ```bash
   brew install pinentry-mac
   echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
   gpgconf --kill gpg-agent
   ```

### Secret Key Not Available

**Symptom:** `gpg: signing failed: secret key not available`

**Solution:**

1. List available keys:
   ```bash
   gpg --list-secret-keys
   ```

2. Verify key ID in config matches:
   ```bash
   remote-juggler gpg status
   ```

3. Import key if needed:
   ```bash
   gpg --import private-key.asc
   ```

## Provider CLI Issues

### glab Not Authenticated

**Symptom:** `glab not authenticated`

**Solution:**

```bash
# Authenticate with token
glab auth login -h gitlab.com

# Or with browser
glab auth login -h gitlab.com --web
```

### gh Not Found

**Symptom:** `gh not installed`

**Solution:**

```bash
# macOS
brew install gh

# Or download from https://cli.github.com
```

## MCP/ACP Issues

### Server Not Responding

**Symptom:** AI assistant can't connect to RemoteJuggler

**Diagnosis:**

```bash
# Test MCP server
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' | \
  remote-juggler --mode=mcp
```

**Solutions:**

1. Check binary path in configuration:
   ```json
   {
     "command": "/full/path/to/remote-juggler"
   }
   ```

2. Check permissions:
   ```bash
   chmod +x ~/.local/bin/remote-juggler
   ```

3. Enable debug logging:
   ```bash
   REMOTE_JUGGLER_VERBOSE=1 remote-juggler --mode=mcp 2>debug.log
   ```

### No Tools Available

**Symptom:** AI assistant sees no tools

**Solution:**

1. Test tools/list:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | remote-juggler --mode=mcp
   ```

2. Verify MCP configuration:
   ```json
   {
     "mcpServers": {
       "remote-juggler": {
         "command": "remote-juggler",
         "args": ["--mode=mcp"]
       }
     }
   }
   ```

## Getting Help

### Debug Output

Enable verbose logging:

```bash
remote-juggler --verbose <command>
```

### Version Information

```bash
remote-juggler --version
```

### Report Issues

File issues at: https://gitlab.com/tinyland/projects/remote-juggler/-/issues

Include:
- RemoteJuggler version
- OS and version
- Command that failed
- Error message
- Debug output (with secrets redacted)
