# RemoteJuggler Examples

This directory contains example configurations and scripts for common RemoteJuggler use cases.

## Configuration Examples

| File | Description |
|------|-------------|
| [config-minimal.json](config-minimal.json) | Minimal single-identity setup |
| [config-multi-provider.json](config-multi-provider.json) | GitLab + GitHub + Bitbucket setup |
| [config-enterprise.json](config-enterprise.json) | Enterprise with self-hosted GitLab |
| [config-trusted-workstation.json](config-trusted-workstation.json) | TPM/Secure Enclave configuration |

## SSH Configuration Examples

| File | Description |
|------|-------------|
| [ssh-config-example](ssh-config-example) | SSH config with host aliases |

## Shell Integration

| File | Description |
|------|-------------|
| [shell-aliases.sh](shell-aliases.sh) | Bash/Zsh aliases for power users |
| [fish-functions.fish](fish-functions.fish) | Fish shell functions |

## CI/CD Integration

| File | Description |
|------|-------------|
| [gitlab-ci-example.yml](gitlab-ci-example.yml) | GitLab CI identity switching |
| [github-actions-example.yml](github-actions-example.yml) | GitHub Actions integration |

## Usage

Copy and modify these examples for your own setup:

```bash
# Copy minimal config as starting point
cp examples/config-minimal.json ~/.config/remote-juggler/config.json

# Edit with your details
$EDITOR ~/.config/remote-juggler/config.json
```

See the [documentation](https://remote-juggler.dev/docs) for detailed explanations.
