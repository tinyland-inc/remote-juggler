# Bash completion for remote-juggler
# Source this file or install to /usr/local/etc/bash_completion.d/

_remote_juggler() {
    local cur prev words cword
    _init_completion || return

    local commands="list detect switch to validate status config token gpg debug keys pin yubikey trusted-workstation security-mode setup unseal-pin verify"
    local config_commands="show add edit remove import sync init"
    local token_commands="set get clear verify check-expiry renew"
    local gpg_commands="status configure verify"
    local debug_commands="ssh-config git-config keychain hsm"
    local keys_commands="init status search resolve get store delete list ingest crawl discover export"
    local pin_commands="store clear status"
    local yubikey_commands="info set-pin-policy set-touch configure-trusted diagnostics"
    local tws_commands="enable disable status verify"
    local options="--help --version --mode --verbose --debug --configPath --useKeychain --gpgSign --provider"
    local providers="gitlab github bitbucket all"
    local security_modes="standard trusted_workstation hardware_only"

    case "${prev}" in
        remote-juggler)
            COMPREPLY=( $(compgen -W "${commands} ${options}" -- "${cur}") )
            return
            ;;
        --mode)
            COMPREPLY=( $(compgen -W "cli mcp acp" -- "${cur}") )
            return
            ;;
        --provider)
            COMPREPLY=( $(compgen -W "${providers}" -- "${cur}") )
            return
            ;;
        config)
            COMPREPLY=( $(compgen -W "${config_commands}" -- "${cur}") )
            return
            ;;
        token)
            COMPREPLY=( $(compgen -W "${token_commands}" -- "${cur}") )
            return
            ;;
        gpg)
            COMPREPLY=( $(compgen -W "${gpg_commands}" -- "${cur}") )
            return
            ;;
        debug)
            COMPREPLY=( $(compgen -W "${debug_commands}" -- "${cur}") )
            return
            ;;
        keys|kdbx)
            COMPREPLY=( $(compgen -W "${keys_commands}" -- "${cur}") )
            return
            ;;
        pin)
            COMPREPLY=( $(compgen -W "${pin_commands}" -- "${cur}") )
            return
            ;;
        yubikey|yk)
            COMPREPLY=( $(compgen -W "${yubikey_commands}" -- "${cur}") )
            return
            ;;
        trusted-workstation|tws)
            COMPREPLY=( $(compgen -W "${tws_commands}" -- "${cur}") )
            return
            ;;
        security-mode)
            COMPREPLY=( $(compgen -W "${security_modes}" -- "${cur}") )
            return
            ;;
        switch|to|validate|edit|remove|set|get|clear|configure)
            # Complete with available identity names
            local identities=$(remote-juggler list 2>/dev/null | grep -E "^  - " | sed 's/^  - //')
            COMPREPLY=( $(compgen -W "${identities}" -- "${cur}") )
            return
            ;;
        --field)
            COMPREPLY=( $(compgen -W "title username url notes" -- "${cur}") )
            return
            ;;
        --format)
            COMPREPLY=( $(compgen -W "env json shell" -- "${cur}") )
            return
            ;;
    esac

    # Default completion
    COMPREPLY=( $(compgen -W "${commands} ${options}" -- "${cur}") )
}

complete -F _remote_juggler remote-juggler
