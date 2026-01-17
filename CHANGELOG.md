# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-15

### Added
- Initial release of GitLab Context Switcher
- Support for switching between personal and work GitLab contexts
- Automatic git remote management
- Token-based glab CLI authentication
- Branch upstream tracking configuration
- Context state persistence in `.gitlab-context.json`
- Comprehensive error handling and validation
- SSH host configuration support
- Repository access verification
- Status command for checking current configuration
- Setup command for initial remote configuration
- Environment variable based token management
- Claude command wrapper for easy execution
- Complete documentation and usage examples

### Features
- **Context Management**: Switch between personal/work GitLab instances
- **Authentication**: Automatic token-based glab CLI authentication
- **Git Integration**: Seamless git remote and upstream branch management
- **State Persistence**: Remembers last used context across sessions
- **Verification**: Confirms authentication and repository access
- **Flexibility**: Configurable contexts via Python dictionary
- **Security**: Environment variable based token storage
- **CLI Interface**: Simple command-line interface with status reporting

### Documentation
- Comprehensive README.md with setup and usage instructions
- Detailed docs/gitlab-switch.md for advanced usage
- Claude command documentation in .claude/commands/
- Example configuration files and environment templates
- Troubleshooting guide with common issues and solutions

### Package Structure
- Pip installable package with entry points
- MIT license for open source usage
- Modern Python packaging with pyproject.toml
- Support for Python 3.8+ with type hints
- Proper .gitignore for security (excludes .env files)

## [Unreleased]

### Planned Features
- Support for GitLab CE/EE instances
- Configuration file based context management
- Multi-repository context switching
- Integration with popular development tools
- Shell completion support
- Enhanced logging and debugging options