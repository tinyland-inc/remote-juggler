# GitLab Context Switcher - Usage Documentation

## Overview

The GitLab Context Switcher is a Python tool designed to seamlessly manage multiple GitLab contexts (personal/work) within the same git repository. It automates the process of switching between different GitLab instances, managing git remotes, and handling authentication.

## Core Concepts

### Contexts
A **context** represents a complete GitLab environment including:
- Git remote configuration
- GitLab CLI (glab) authentication
- Repository access permissions
- User identity

### Supported Contexts
- **Personal**: Your personal GitLab account/instance
- **Work**: Your organization's GitLab account/instance

## Installation

### Method 1: Package Installation
```bash
pip install gitlab-switch
gitlab-switch --help
```

### Method 2: Direct Usage
```bash
git clone https://github.com/yourusername/gitlab-switch.git
cd gitlab-switch
pip install -r requirements.txt
python gitlab_switch.py --help
```

### Method 3: Development Installation
```bash
git clone https://github.com/yourusername/gitlab-switch.git
cd gitlab-switch
pip install -e .
gitlab-switch --help
```

## Configuration

### 1. SSH Setup

Configure SSH hosts in `~/.ssh/config`:

```ssh-config
# Personal GitLab
Host gitlab-personal
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
    AddKeysToAgent yes
    UseKeychain yes

# Work GitLab
Host gitlab-work
    HostName gitlab.com  # or your-company.gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    AddKeysToAgent yes
    UseKeychain yes
```

### 2. Environment Variables

Create a `.env` file (copy from `.env.example`):

```env
# GitLab Personal Access Tokens
PERSONAL_GLAB_TOKEN=glpat-your-personal-token-here
WORK_GLAB_TOKEN=glpat-your-work-token-here
```

#### Token Generation
1. Go to GitLab → Settings → Access Tokens
2. Create token with scopes:
   - `api` - Full API access
   - `read_user` - Read user information  
   - `read_repository` - Read repository content
   - `write_repository` - Write repository content

### 3. Context Configuration

Edit the `CONTEXTS` dictionary in `gitlab_switch.py`:

```python
CONTEXTS: Dict[str, Dict[str, str]] = {
    "personal": {
        "remote_name": "origin",           # Git remote name
        "remote_url": "git@gitlab-personal:username/repo.git",
        "glab_host": "gitlab-personal",    # SSH host from config  
        "glab_user": "your-username",      # GitLab username
        "token_env_var": "PERSONAL_GLAB_TOKEN",
        "repo_path": "username/repo",      # GitLab project path
        "description": "Personal GitLab (username/repo)"
    },
    "work": {
        "remote_name": "work",
        "remote_url": "git@gitlab-work:org/repo.git",
        "glab_host": "gitlab-work", 
        "glab_user": "work-username",
        "token_env_var": "WORK_GLAB_TOKEN",
        "repo_path": "org/repo",
        "description": "Work GitLab (org/repo)"
    }
}
```

## Usage

### Basic Commands

```bash
# Switch to personal GitLab context
gitlab-switch personal

# Switch to work GitLab context
gitlab-switch work

# Check current status and configuration
gitlab-switch status

# Setup both remotes initially  
gitlab-switch --setup
```

### Command-line Options

```bash
usage: gitlab_switch.py [-h] [--setup] [context]

Switch between GitLab contexts (personal/work)

positional arguments:
  context     Context to switch to or status to check

optional arguments:
  -h, --help  show this help message and exit
  --setup     Setup both remotes initially

Examples:
  gitlab_switch.py personal     # Switch to personal GitLab
  gitlab_switch.py work        # Switch to work GitLab  
  gitlab_switch.py status      # Show current status
  gitlab_switch.py --setup     # Setup both remotes initially
```

## Workflow

### Typical Usage Flow

1. **Initial Setup**:
   ```bash
   gitlab-switch --setup
   ```

2. **Daily Work**:
   ```bash
   # Morning: Switch to work context
   gitlab-switch work
   git pull work main
   # ... work on features ...
   git push work feature-branch
   
   # Evening: Switch to personal context
   gitlab-switch personal
   git pull origin main
   # ... personal projects ...
   git push origin personal-feature
   ```

3. **Status Checking**:
   ```bash
   gitlab-switch status
   ```

### Context Switching Process

When you run `gitlab-switch [context]`, the tool:

1. **Validates Context**: Ensures the requested context exists in configuration
2. **Updates Git Remote**: Sets or updates the git remote URL for the context
3. **Clears Authentication**: Logs out from all glab CLI sessions for clean state
4. **Authenticates**: Logs into glab CLI using the context-specific token
5. **Verifies Access**: Confirms repository access and user identity
6. **Sets Upstream**: Configures branch tracking for current branch
7. **Saves State**: Stores the current context in `.gitlab-context.json`
8. **Reports Status**: Shows final configuration and next steps

## Advanced Usage

### Custom Contexts

Add additional contexts by extending the configuration:

```python
CONTEXTS["staging"] = {
    "remote_name": "staging",
    "remote_url": "git@gitlab-staging:staging/repo.git", 
    "glab_host": "gitlab-staging",
    "glab_user": "staging-user",
    "token_env_var": "STAGING_GLAB_TOKEN", 
    "repo_path": "staging/repo",
    "description": "Staging GitLab"
}
```

### Integration with Scripts

```bash
#!/bin/bash
# deployment.sh - Switch context before deployment

set -e

echo "Switching to work context..."
if gitlab-switch work; then
    echo "✅ Context switched successfully"
    
    # Deploy to work environment
    git push work main
    glab mr create --title "Deploy v$(date +%Y%m%d)"
    
else
    echo "❌ Failed to switch context"
    exit 1
fi
```

### Automation

```bash
# Add to your shell profile (.bashrc, .zshrc)
alias gls='gitlab-switch status'
alias glp='gitlab-switch personal' 
alias glw='gitlab-switch work'

# Function to switch context and pull latest
glpull() {
    local context=${1:-personal}
    if gitlab-switch "$context"; then
        git pull "$(git remote)" main
    fi
}
```

## Troubleshooting

### Common Issues

#### 1. No Token Found
```
⚠️  No token found in environment variable PERSONAL_GLAB_TOKEN
```

**Solution**:
- Check `.env` file exists in project directory
- Verify token variable names match configuration
- Ensure tokens are valid and not expired

#### 2. Authentication Failed
```
❌ Failed to authenticate to gitlab-personal
```

**Solution**:
- Verify token has required scopes (api, read_user, read_repository, write_repository)
- Check token hasn't expired
- Ensure glab CLI is installed: `brew install glab`

#### 3. Repository Access Denied
```
⚠️  Cannot access repository username/repo
```

**Solution**:
- Verify `repo_path` matches actual GitLab project path
- Check user has access to the repository
- Ensure `glab_user` matches the token owner

#### 4. SSH Connection Issues
```
ssh: connect to host gitlab-personal port 22: Connection refused
```

**Solution**:
- Test SSH connections manually:
  ```bash
  ssh -T git@gitlab-personal
  ssh -T git@gitlab-work
  ```
- Verify SSH keys are added to GitLab accounts
- Check `~/.ssh/config` configuration
- Ensure SSH keys have proper permissions: `chmod 600 ~/.ssh/id_ed25519_*`

### Debug Commands

```bash
# Test individual components
ssh -T git@gitlab-personal
ssh -T git@gitlab-work

# Check glab authentication 
glab auth status --hostname gitlab-personal
glab auth status --hostname gitlab-work

# Verify repository access
glab repo view username/repo --host gitlab-personal
glab repo view org/repo --host gitlab-work

# Check git remotes
git remote -v

# View current context
cat .gitlab-context.json
```

### Verbose Debugging

```bash
# Enable git tracing
GIT_TRACE=1 gitlab-switch personal

# Enable glab debug mode
export GLAB_DEBUG=1
gitlab-switch work
```

## File Structure

```
gitlab-switch/
├── gitlab-switch.py      # Main script
├── README.md            # Comprehensive documentation  
├── LICENSE              # MIT license
├── setup.py             # Package installation
├── requirements.txt     # Python dependencies
├── .env.example         # Environment template
├── .claude/
│   ├── gitlab-switch    # Executable wrapper
│   └── commands/
│       └── gitlab/
│           └── gitlab-switch.md  # Command documentation
└── docs/
    └── gitlab-switch.md # Usage documentation
```

## Security Considerations

### Token Security
- Store tokens in `.env` file (never commit to git)
- Use Personal Access Tokens, not passwords
- Set appropriate token scopes (minimal required permissions)
- Rotate tokens regularly
- Consider using different tokens for different projects

### SSH Key Security  
- Use separate SSH keys for personal/work accounts
- Protect private keys with proper file permissions (`600`)
- Add keys to SSH agent for convenience
- Use strong passphrases for key encryption

### Best Practices
- Add `.env` to `.gitignore`
- Never log token values
- Clear authentication state between switches
- Verify repository access after context switch
- Use descriptive context names and documentation

## Contributing

### Development Setup

```bash
git clone https://github.com/yourusername/gitlab-switch.git
cd gitlab-switch
python -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows
pip install -e .
pip install -r requirements.txt
```

### Testing Changes

```bash
# Test basic functionality
python gitlab-switch.py --help
python gitlab-switch.py status

# Test context switching (requires configuration)
python gitlab-switch.py personal
python gitlab-switch.py work
```

### Submitting Changes

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Make changes and test thoroughly
4. Commit changes: `git commit -m 'Add amazing feature'`
5. Push branch: `git push origin feature/amazing-feature`
6. Open Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.