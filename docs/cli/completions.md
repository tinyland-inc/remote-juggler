---
title: "Shell Completions"
description: "Shell completion scripts for bash, zsh, and fish with command and identity auto-completion."
category: "cli"
llm_priority: 4
keywords:
  - completions
  - bash
  - zsh
  - fish
  - shell
---

# Shell Completions

RemoteJuggler supports shell completion for bash, zsh, and fish.

## Bash

Add to `~/.bashrc`:

```bash
# RemoteJuggler completion
_remote_juggler_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Top-level commands
    local commands="list detect switch to validate status config token gpg debug help version"

    # Config subcommands
    local config_commands="show add edit remove import sync init"

    # Token subcommands
    local token_commands="set get clear verify"

    # GPG subcommands
    local gpg_commands="status configure verify"

    # Debug subcommands
    local debug_commands="ssh-config git-config keychain"

    case "$prev" in
        remote-juggler)
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            ;;
        config)
            COMPREPLY=($(compgen -W "$config_commands" -- "$cur"))
            ;;
        token)
            COMPREPLY=($(compgen -W "$token_commands" -- "$cur"))
            ;;
        gpg)
            COMPREPLY=($(compgen -W "$gpg_commands" -- "$cur"))
            ;;
        debug)
            COMPREPLY=($(compgen -W "$debug_commands" -- "$cur"))
            ;;
        switch|to|validate|set|get|clear|configure|edit|remove)
            # Complete with identity names
            local identities=$(remote-juggler list 2>/dev/null | awk 'NR>2 {print $1}' | tr -d '*')
            COMPREPLY=($(compgen -W "$identities" -- "$cur"))
            ;;
        --provider)
            COMPREPLY=($(compgen -W "gitlab github bitbucket all" -- "$cur"))
            ;;
        --mode)
            COMPREPLY=($(compgen -W "cli mcp acp" -- "$cur"))
            ;;
    esac
}

complete -F _remote_juggler_completions remote-juggler
```

## Zsh

Add to `~/.zshrc`:

```zsh
# RemoteJuggler completion
_remote_juggler() {
    local -a commands config_commands token_commands gpg_commands debug_commands

    commands=(
        'list:List all configured identities'
        'detect:Detect identity for current repository'
        'switch:Switch to a different identity'
        'to:Alias for switch'
        'validate:Test SSH/API connectivity'
        'status:Show current identity status'
        'config:Configuration management'
        'token:Token/credential management'
        'gpg:GPG signing configuration'
        'debug:Debug commands'
        'help:Show help message'
        'version:Show version'
    )

    config_commands=(
        'show:Display configuration'
        'add:Add new identity'
        'edit:Edit existing identity'
        'remove:Remove identity'
        'import:Import from SSH config'
        'sync:Synchronize managed blocks'
        'init:Initialize configuration'
    )

    token_commands=(
        'set:Store token in Keychain'
        'get:Retrieve token'
        'clear:Remove token'
        'verify:Test all credentials'
    )

    gpg_commands=(
        'status:Show GPG configuration'
        'configure:Configure GPG for identity'
        'verify:Check provider registration'
    )

    debug_commands=(
        'ssh-config:Show parsed SSH configuration'
        'git-config:Show parsed gitconfig'
        'keychain:Test Keychain access'
    )

    _arguments -C \
        '--mode=[Operation mode]:mode:(cli mcp acp)' \
        '--verbose[Enable verbose output]' \
        '--help[Show help]' \
        '--configPath=[Config file path]:path:_files' \
        '--useKeychain[Enable Keychain]' \
        '--gpgSign[Enable GPG signing]' \
        '--provider=[Filter by provider]:provider:(gitlab github bitbucket all)' \
        '1:command:->command' \
        '*::arg:->args'

    case $state in
        command)
            _describe 'command' commands
            ;;
        args)
            case $words[1] in
                config)
                    _describe 'config command' config_commands
                    ;;
                token)
                    _describe 'token command' token_commands
                    ;;
                gpg)
                    _describe 'gpg command' gpg_commands
                    ;;
                debug)
                    _describe 'debug command' debug_commands
                    ;;
                switch|to|validate)
                    local identities=(${(f)"$(remote-juggler list 2>/dev/null | awk 'NR>2 {print $1}' | tr -d '*')"})
                    _describe 'identity' identities
                    ;;
            esac
            ;;
    esac
}

compdef _remote_juggler remote-juggler
```

## Fish

Create `~/.config/fish/completions/remote-juggler.fish`:

```fish
# RemoteJuggler completions for fish

# Top-level commands
complete -c remote-juggler -f -n '__fish_use_subcommand' -a list -d 'List all configured identities'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a detect -d 'Detect identity for current repository'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a switch -d 'Switch to a different identity'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a to -d 'Alias for switch'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a validate -d 'Test SSH/API connectivity'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a status -d 'Show current identity status'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a config -d 'Configuration management'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a token -d 'Token/credential management'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a gpg -d 'GPG signing configuration'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a debug -d 'Debug commands'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a help -d 'Show help message'
complete -c remote-juggler -f -n '__fish_use_subcommand' -a version -d 'Show version'

# Config subcommands
complete -c remote-juggler -f -n '__fish_seen_subcommand_from config' -a show -d 'Display configuration'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from config' -a add -d 'Add new identity'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from config' -a edit -d 'Edit existing identity'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from config' -a remove -d 'Remove identity'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from config' -a import -d 'Import from SSH config'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from config' -a sync -d 'Synchronize managed blocks'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from config' -a init -d 'Initialize configuration'

# Token subcommands
complete -c remote-juggler -f -n '__fish_seen_subcommand_from token' -a set -d 'Store token in Keychain'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from token' -a get -d 'Retrieve token'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from token' -a clear -d 'Remove token'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from token' -a verify -d 'Test all credentials'

# GPG subcommands
complete -c remote-juggler -f -n '__fish_seen_subcommand_from gpg' -a status -d 'Show GPG configuration'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from gpg' -a configure -d 'Configure GPG for identity'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from gpg' -a verify -d 'Check provider registration'

# Debug subcommands
complete -c remote-juggler -f -n '__fish_seen_subcommand_from debug' -a ssh-config -d 'Show parsed SSH configuration'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from debug' -a git-config -d 'Show parsed gitconfig'
complete -c remote-juggler -f -n '__fish_seen_subcommand_from debug' -a keychain -d 'Test Keychain access'

# Global options
complete -c remote-juggler -l mode -xa 'cli mcp acp' -d 'Operation mode'
complete -c remote-juggler -l verbose -d 'Enable verbose output'
complete -c remote-juggler -l help -d 'Show help'
complete -c remote-juggler -l configPath -r -d 'Config file path'
complete -c remote-juggler -l useKeychain -d 'Enable Keychain'
complete -c remote-juggler -l gpgSign -d 'Enable GPG signing'
complete -c remote-juggler -l provider -xa 'gitlab github bitbucket all' -d 'Filter by provider'

# Identity completions for switch/to/validate
function __fish_remote_juggler_identities
    remote-juggler list 2>/dev/null | awk 'NR>2 {print $1}' | tr -d '*'
end

complete -c remote-juggler -f -n '__fish_seen_subcommand_from switch to validate' -a '(__fish_remote_juggler_identities)'
```

## Usage

After adding completion scripts, restart your shell or source the file:

```bash
# Bash
source ~/.bashrc

# Zsh
source ~/.zshrc

# Fish
source ~/.config/fish/completions/remote-juggler.fish
```

Test completions:

```bash
remote-juggler <TAB>         # Shows commands
remote-juggler switch <TAB>  # Shows identity names
remote-juggler --mode=<TAB>  # Shows mode options
```
