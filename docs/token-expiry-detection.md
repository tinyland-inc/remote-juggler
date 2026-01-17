# Token Expiry Detection

RemoteJuggler v2.0+ includes comprehensive token expiry detection and health monitoring to help you stay ahead of expired credentials.

## Features

- **Automatic token validation** - Verify tokens with provider APIs (GitLab/GitHub)
- **Expiry warnings** - Get notified when tokens are approaching expiration
- **Health monitoring** - Track token status across all identities
- **Renewal workflow** - Guided token renewal process
- **Metadata persistence** - Store token creation and verification dates

## Quick Start

### Check Token Health for All Identities

```bash
remote-juggler token check-expiry
```

### Check Specific Identity

```bash
remote-juggler token check-expiry personal
```

### Verify All Credentials

```bash
remote-juggler token verify
```

### Renew Expiring Token

```bash
remote-juggler token renew work
```

## CLI Commands

### `token check-expiry [identity]`

Check expiration status for all identities or a specific one.

**Output includes**:
- Token validity status
- Days until expiry (if available)
- Expiry warnings for tokens < 30 days
- Expired token notifications

**Example**:
```
Token Health Summary
════════════════════════════════════════════════════════════

personal (gitlab):
  Status: [OK] Token is healthy (expires in 45 days)
  Scopes: api

work (gitlab):
  Status: [WARNING]  Token expires in 15 days - renewal recommended
  Scopes: api
```

### `token verify`

Test credential availability for all identities.

Now includes expiry warnings for each identity:
- [OK] Token found and valid
- [WARNING]  Token found but expiring soon (< 30 days)
- [FAILED] Token expired
- (yellow) Token not found (SSH-only mode)

### `token renew <identity>`

Interactive token renewal workflow.

**Steps**:
1. Shows current token health
2. Provides provider-specific token creation URL
3. Prompts for new token
4. Verifies new token with provider
5. Stores in keychain (Darwin) or provides instructions

**Example**:
```bash
$ remote-juggler token renew personal

Current Token Status:

  Status: [WARNING]  Token expires in 15 days - renewal recommended

Token Renewal for: personal
Provider: gitlab

Steps to renew your token:
1. Open: https://gitlab.com/-/user_settings/personal_access_tokens
2. Create a new Personal Access Token with appropriate scopes
3. Copy the new token
4. Run: remote-juggler token set personal
```

## Integration with Other Commands

### Identity Switching

The `switch` command now includes automatic expiry warnings:

```bash
$ remote-juggler switch work

[OK] Switched to work

  Provider: gitlab
  User:     jsullivan2 <jess@tinyland.dev>
  SSH Host: gitlab-work
  Auth:     Keychain authenticated
  Remote:   Updated for identity

[WARNING]  WARNING: Token for work expires in 15 days
   Consider renewing soon.
   Run: remote-juggler token renew work
```

### Identity Validation

The `validate` command now includes token expiry checking:

```bash
$ remote-juggler validate work

Validating: work (gitlab)

  SSH Connection... OK
  Credentials...    OK
  GPG Key...        OK
  GPG Registered... OK
  Token Expiry...   Expiring soon (15 days)
```

## Token Metadata Storage

Token metadata is stored in `~/.config/remote-juggler/tokens.json`:

```json
{
  "version": "1.0",
  "tokens": {
    "gitlab:personal": {
      "identityName": "personal",
      "provider": "gitlab",
      "createdAt": 1737139200.0,
      "lastVerified": 1737139200.0,
      "expiresAt": 1741056000.0,
      "tokenType": "pat",
      "isValid": true,
      "warningIssued": 0.0
    }
  }
}
```

**Fields**:
- `createdAt` - Unix timestamp when token was stored
- `lastVerified` - Last time token was checked with provider API
- `expiresAt` - Unix timestamp when token expires (0 if unknown)
- `isValid` - Last verification result
- `warningIssued` - Last time expiry warning was shown

## Provider API Integration

### GitLab

Queries `/api/v4/personal_access_tokens/self` endpoint via `glab api`.

**Note**: Full expiry date parsing requires proper JSON parsing in Chapel. Currently validates token but reports "unknown expiry" for GitLab tokens. This will be enhanced in future versions when Chapel's JSON support improves.

### GitHub

Queries `/user` endpoint via `gh api`.

GitHub Personal Access Tokens don't expose expiry dates via API, so tokens are verified for validity but expiry is reported as "unknown".

### Future Providers

Custom providers can implement token verification by:
1. Adding provider-specific API calls in `TokenHealth.chpl`
2. Parsing token expiry from API responses
3. Following the (bool, real, list(string)) return signature

## Expiry Thresholds

- **Expired**: Token cannot be used (API returns 401/403)
- **Needs Renewal**: < 30 days until expiry
- **Healthy**: > 30 days until expiry
- **Unknown**: Provider doesn't expose expiry date

## Best Practices

1. **Regular Checks**: Run `token check-expiry` monthly
2. **Renewal Timing**: Renew tokens when < 30 days remaining
3. **Validation**: Use `validate` before important operations
4. **Automation**: Set up calendar reminders for token renewal

## Troubleshooting

### "Could not verify token with provider API"

**Causes**:
- Provider CLI (glab/gh) not installed
- Token lacks required API scopes
- Network connectivity issues
- Provider API rate limiting

**Solutions**:
- Install glab: `brew install glab`
- Install gh: `brew install gh`
- Verify token has `api` scope
- Check network connection

### "Token expiry...   Unknown expiry"

**Causes**:
- Provider doesn't expose expiry via API (GitHub)
- Token type doesn't support expiry queries
- API query failed

**This is normal** for GitHub tokens and some GitLab configurations.

### Token metadata not persisting

**Causes**:
- Permission issues creating `~/.config/remote-juggler/`
- Disk full
- Invalid JSON format

**Solutions**:
```bash
# Check directory permissions
ls -la ~/.config/remote-juggler/

# Manually create if needed
mkdir -p ~/.config/remote-juggler/

# Check disk space
df -h ~
```

## Security Considerations

- Token metadata does NOT store actual tokens
- Metadata is stored unencrypted (contains no sensitive data)
- Actual tokens remain in Darwin Keychain (encrypted)
- Token verification queries don't log token values

## Limitations

### Current

- **GitLab expiry parsing**: Requires proper JSON parser (planned)
- **GitHub expiry**: Not exposed by GitHub API (provider limitation)
- **Metadata storage**: Simple JSON (will use proper library when available)
- **Rate limiting**: No protection against API rate limits

### Planned Enhancements

- Full JSON parsing for GitLab token expiry dates
- Automatic token refresh for OAuth tokens
- Rate limit handling and backoff
- Token expiry notifications (desktop/email)
- Integration with password managers (1Password, Bitwarden)

## Related Commands

```bash
# Token management
remote-juggler token set <identity>        # Store new token
remote-juggler token get <identity>        # View token (masked)
remote-juggler token clear <identity>      # Remove token
remote-juggler token verify                # Verify all tokens
remote-juggler token check-expiry          # Check expiry for all
remote-juggler token check-expiry <id>     # Check specific identity
remote-juggler token renew <identity>      # Renew expiring token

# Identity operations (now with expiry warnings)
remote-juggler switch <identity>           # Switch + expiry check
remote-juggler validate <identity>         # Validate + expiry check
remote-juggler status                      # Show current identity
```

## API Documentation

For developers extending RemoteJuggler, see `src/remote_juggler/TokenHealth.chpl`:

- `checkTokenHealth(identity: GitIdentity): TokenHealthResult`
- `verifyTokenWithProvider(identity: GitIdentity, token: string): (bool, real, list(string))`
- `warnIfExpiring(identity: GitIdentity): bool`
- `renewToken(identity: GitIdentity): bool`

## Contributing

Token expiry detection is a new feature. Contributions welcome for:

- Enhanced JSON parsing for GitLab tokens
- Additional provider support
- Automated renewal workflows
- Desktop notification integration

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

## See Also

- [Configuration Guide](getting-started/configuration.md)
- [Keychain Integration](architecture/keychain.md)
- [CLI Commands](cli/commands.md)
- [Troubleshooting](operations/troubleshooting.md)
