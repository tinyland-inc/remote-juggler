# CI Variables for RemoteJuggler

This document describes the CI/CD variables required for RemoteJuggler builds across GitLab CI and GitHub Actions.

## Overview

RemoteJuggler uses Nix flakes for reproducible builds with Attic binary cache for faster rebuilds. The CI pipelines support:

- Multi-architecture Linux builds (x86_64, aarch64)
- Multi-architecture macOS builds (Intel, Apple Silicon)
- GTK GUI builds (Linux only)
- Chapel compiler caching

---

## Attic Binary Cache

Attic is a self-hosted Nix binary cache that provides significantly faster builds by caching derivations, including the expensive Chapel compiler.

### Server Information

| Property | Value |
|----------|-------|
| **Server URL** | `https://nix-cache.fuzzy-dev.tinyland.dev` |
| **Cache Name** | `tinyland` |
| **Substituter URL** | `https://nix-cache.fuzzy-dev.tinyland.dev/tinyland` |
| **Public Key** | `tinyland:O1ECUdLTRVhoyLTQ3hYy6xFhFyhlcVqbILJxBVOTwRY=` |

### Required Variables

| Variable | Platform | Protected | Masked | Description |
|----------|----------|-----------|--------|-------------|
| `ATTIC_TOKEN` | Both | Yes | Yes | Attic authentication token with push access |

### Optional Variables (with Defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `ATTIC_SERVER` | `https://nix-cache.fuzzy-dev.tinyland.dev` | Attic server URL |
| `ATTIC_CACHE` | `tinyland` | Attic cache name |

---

## GitLab CI Setup

### Adding Variables

1. Navigate to: **Settings > CI/CD > Variables**
2. Click **Add variable**
3. Configure each variable:

| Key | Value | Type | Protected | Masked | Expand |
|-----|-------|------|-----------|--------|--------|
| `ATTIC_TOKEN` | (token from Attic) | Variable | Yes | Yes | No |

### Generating ATTIC_TOKEN

```bash
# Install attic CLI
nix profile install nixpkgs#attic-client

# Login to Attic server
attic login default https://nix-cache.fuzzy-dev.tinyland.dev

# Generate push token for CI
attic token create gitlab-ci-push --push tinyland

# Copy the token output and add to GitLab CI variables
```

### Verifying Configuration

```bash
# Test connectivity
curl -I https://nix-cache.fuzzy-dev.tinyland.dev/v1/cache/tinyland

# Verify token (from local machine)
attic login test https://nix-cache.fuzzy-dev.tinyland.dev <your-token>
attic cache info tinyland
```

---

## GitHub Actions Setup

### Adding Secrets

1. Navigate to: **Settings > Secrets and variables > Actions**
2. Click **New repository secret**
3. Add the secret:

| Name | Value | Description |
|------|-------|-------------|
| `ATTIC_TOKEN` | (token from Attic) | Attic authentication token |

### Generating ATTIC_TOKEN

```bash
# Generate a dedicated token for GitHub Actions
attic login default https://nix-cache.fuzzy-dev.tinyland.dev
attic token create github-ci-push --push tinyland
```

### Verifying GitHub Actions

Check the workflow logs for:
```
Configuring Attic cache client...
Attic configured for https://nix-cache.fuzzy-dev.tinyland.dev
```

If you see:
```
ATTIC_TOKEN not set - skipping cache push
```

The secret is not configured correctly.

---

## flake.nix Configuration

The flake.nix includes Attic as a substituter for faster local development:

```nix
nixConfig = {
  extra-substituters = [
    "https://nix-cache.fuzzy-dev.tinyland.dev/tinyland"
  ];
  extra-trusted-public-keys = [
    "tinyland:O1ECUdLTRVhoyLTQ3hYy6xFhFyhlcVqbILJxBVOTwRY="
  ];
};
```

Users will be prompted to trust this substituter on first use. To trust automatically:

```bash
# Add to /etc/nix/nix.conf or ~/.config/nix/nix.conf
trusted-substituters = https://nix-cache.fuzzy-dev.tinyland.dev/tinyland
trusted-public-keys = tinyland:O1ECUdLTRVhoyLTQ3hYy6xFhFyhlcVqbILJxBVOTwRY=
```

---

## Cache Behavior

### Build Time Savings

| Component | Uncached | Cached |
|-----------|----------|--------|
| Chapel compiler | ~30 min | ~30 sec |
| RemoteJuggler CLI | ~5 min | ~10 sec |
| GTK GUI | ~10 min | ~20 sec |
| Full devShell | ~45 min | ~1 min |

### Cache Hit Strategy

The CI pipeline checks substituters in order:
1. **Attic** (primary) - `https://nix-cache.fuzzy-dev.tinyland.dev/tinyland`
2. **nix-community** (fallback) - `https://nix-community.cachix.org`
3. **Garnix** (fallback) - `https://cache.garnix.io`

### Push Strategy

- Builds on `main` branch push results to Attic
- Tagged releases push to Attic
- Pull requests do NOT push to cache (read-only)
- Manual workflow dispatch can force cache push

---

## Troubleshooting

### Cache Push Fails

**Symptom**: `ATTIC_TOKEN not set - skipping cache push`

**Solution**:
1. Verify token is set in CI variables/secrets
2. Check token is not expired
3. Regenerate token if needed

### Authentication Error

**Symptom**: `attic push` fails with 401/403

**Solution**:
```bash
# Verify token permissions
attic cache info tinyland

# Regenerate with explicit push permission
attic token create ci-push-new --push tinyland
```

### Slow Builds Despite Cache

**Symptom**: Builds still take a long time

**Possible Causes**:
1. **Cache miss**: Check if derivation hash changed
2. **Network latency**: Attic server may be slow/unavailable
3. **First build**: Cache needs to be populated first

**Diagnosis**:
```bash
# Check if path exists in cache
nix path-info --store https://nix-cache.fuzzy-dev.tinyland.dev .#remote-juggler

# Check substituter connectivity
curl -I https://nix-cache.fuzzy-dev.tinyland.dev/nix-cache-info
```

### Public Key Mismatch

**Symptom**: `untrusted public key` warning

**Solution**:
1. Get current public key: `attic cache info tinyland`
2. Update `flake.nix` with new key
3. Update CI configs with new key

---

## Security Considerations

### Token Scope

- Tokens should have minimal permissions (push only)
- Use separate tokens for GitLab and GitHub
- Rotate tokens periodically (recommended: quarterly)

### Protected Variables

- Always mark `ATTIC_TOKEN` as protected
- Always mask `ATTIC_TOKEN` in logs
- Do not log token values

### Network Security

- Attic server uses HTTPS (TLS 1.3)
- Hosted on Civo Kubernetes with Let's Encrypt
- Behind Cloudflare for DDoS protection

---

## References

- [Attic Documentation](https://docs.attic.rs/)
- [RemoteJuggler GitLab CI](../ci/gitlab-nix.yml)
- [RemoteJuggler GitHub Actions](../.github/workflows/nix-ci.yml)
- [crush-dots CI Variables](https://gitlab.com/tinyland/crush-dots/-/blob/main/docs/CI_VARIABLES.md)
