# Fish completion for remote-juggler
# Install to ~/.config/fish/completions/remote-juggler.fish

# Disable file completion by default
complete -c remote-juggler -f

# Options
complete -c remote-juggler -l help -d "Show help message"
complete -c remote-juggler -l version -d "Show version"
complete -c remote-juggler -l verbose -d "Enable verbose output"
complete -c remote-juggler -l debug -d "Enable debug output"
complete -c remote-juggler -l mode -d "Operation mode" -xa "cli mcp acp"
complete -c remote-juggler -l configPath -d "Override config file path" -r
complete -c remote-juggler -l useKeychain -d "Enable/disable keychain"
complete -c remote-juggler -l gpgSign -d "Enable/disable GPG signing"
complete -c remote-juggler -l provider -d "Filter by provider" -xa "gitlab github bitbucket all"

# Commands
complete -c remote-juggler -n "__fish_use_subcommand" -a "list" -d "List all configured identities"
complete -c remote-juggler -n "__fish_use_subcommand" -a "detect" -d "Detect identity for current repository"
complete -c remote-juggler -n "__fish_use_subcommand" -a "switch" -d "Switch to specified identity"
complete -c remote-juggler -n "__fish_use_subcommand" -a "to" -d "Alias for switch"
complete -c remote-juggler -n "__fish_use_subcommand" -a "validate" -d "Test SSH/API connectivity"
complete -c remote-juggler -n "__fish_use_subcommand" -a "status" -d "Show current identity status"
complete -c remote-juggler -n "__fish_use_subcommand" -a "config" -d "Configuration management"
complete -c remote-juggler -n "__fish_use_subcommand" -a "token" -d "Token management"
complete -c remote-juggler -n "__fish_use_subcommand" -a "gpg" -d "GPG signing management"
complete -c remote-juggler -n "__fish_use_subcommand" -a "debug" -d "Debug utilities"
complete -c remote-juggler -n "__fish_use_subcommand" -a "keys" -d "KeePassXC credential authority"
complete -c remote-juggler -n "__fish_use_subcommand" -a "kdbx" -d "Alias for keys"
complete -c remote-juggler -n "__fish_use_subcommand" -a "pin" -d "HSM PIN management"
complete -c remote-juggler -n "__fish_use_subcommand" -a "yubikey" -d "YubiKey management"
complete -c remote-juggler -n "__fish_use_subcommand" -a "yk" -d "Alias for yubikey"
complete -c remote-juggler -n "__fish_use_subcommand" -a "trusted-workstation" -d "Trusted workstation mode"
complete -c remote-juggler -n "__fish_use_subcommand" -a "tws" -d "Alias for trusted-workstation"
complete -c remote-juggler -n "__fish_use_subcommand" -a "security-mode" -d "Set security mode"
complete -c remote-juggler -n "__fish_use_subcommand" -a "setup" -d "Run setup wizard"
complete -c remote-juggler -n "__fish_use_subcommand" -a "unseal-pin" -d "Unseal HSM PIN"
complete -c remote-juggler -n "__fish_use_subcommand" -a "verify" -d "Verify GPG keys"

# Config subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from config" -a "show" -d "Display configuration"
complete -c remote-juggler -n "__fish_seen_subcommand_from config" -a "add" -d "Add new identity"
complete -c remote-juggler -n "__fish_seen_subcommand_from config" -a "edit" -d "Edit existing identity"
complete -c remote-juggler -n "__fish_seen_subcommand_from config" -a "remove" -d "Remove identity"
complete -c remote-juggler -n "__fish_seen_subcommand_from config" -a "import" -d "Import from SSH config"
complete -c remote-juggler -n "__fish_seen_subcommand_from config" -a "sync" -d "Sync managed blocks"
complete -c remote-juggler -n "__fish_seen_subcommand_from config" -a "init" -d "Initialize config"

# Token subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from token" -a "set" -d "Store token in keychain"
complete -c remote-juggler -n "__fish_seen_subcommand_from token" -a "get" -d "Retrieve token"
complete -c remote-juggler -n "__fish_seen_subcommand_from token" -a "clear" -d "Remove token"
complete -c remote-juggler -n "__fish_seen_subcommand_from token" -a "verify" -d "Test all credentials"
complete -c remote-juggler -n "__fish_seen_subcommand_from token" -a "check-expiry" -d "Check token expiration"
complete -c remote-juggler -n "__fish_seen_subcommand_from token" -a "renew" -d "Renew token"

# GPG subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from gpg" -a "status" -d "Show GPG configuration"
complete -c remote-juggler -n "__fish_seen_subcommand_from gpg" -a "configure" -d "Configure GPG for identity"
complete -c remote-juggler -n "__fish_seen_subcommand_from gpg" -a "verify" -d "Check provider registration"

# Debug subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from debug" -a "ssh-config" -d "Show parsed SSH config"
complete -c remote-juggler -n "__fish_seen_subcommand_from debug" -a "git-config" -d "Show parsed gitconfig"
complete -c remote-juggler -n "__fish_seen_subcommand_from debug" -a "keychain" -d "Test keychain access"
complete -c remote-juggler -n "__fish_seen_subcommand_from debug" -a "hsm" -d "Debug HSM/TPM connectivity"

# Keys (KeePassXC) subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "init" -d "Initialize credential store"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "status" -d "Show store status"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "search" -d "Fuzzy search credentials"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "resolve" -d "Search and retrieve credential"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "get" -d "Get credential by title"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "store" -d "Store new credential"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "delete" -d "Delete credential"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "list" -d "List all credentials"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "ingest" -d "Ingest from env vars"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "crawl" -d "Crawl .env files"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "discover" -d "Auto-discover credentials"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx" -a "export" -d "Export credentials"

# PIN subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from pin" -a "store" -d "Store HSM PIN"
complete -c remote-juggler -n "__fish_seen_subcommand_from pin" -a "clear" -d "Clear stored PIN"
complete -c remote-juggler -n "__fish_seen_subcommand_from pin" -a "status" -d "Check PIN status"

# YubiKey subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from yubikey yk" -a "info" -d "Show YubiKey info"
complete -c remote-juggler -n "__fish_seen_subcommand_from yubikey yk" -a "set-pin-policy" -d "Set PIN caching policy"
complete -c remote-juggler -n "__fish_seen_subcommand_from yubikey yk" -a "set-touch" -d "Set touch requirement"
complete -c remote-juggler -n "__fish_seen_subcommand_from yubikey yk" -a "configure-trusted" -d "Configure for trusted mode"
complete -c remote-juggler -n "__fish_seen_subcommand_from yubikey yk" -a "diagnostics" -d "Run diagnostics"

# Trusted workstation subcommands
complete -c remote-juggler -n "__fish_seen_subcommand_from trusted-workstation tws" -a "enable" -d "Enable trusted mode"
complete -c remote-juggler -n "__fish_seen_subcommand_from trusted-workstation tws" -a "disable" -d "Disable trusted mode"
complete -c remote-juggler -n "__fish_seen_subcommand_from trusted-workstation tws" -a "status" -d "Show trusted mode status"
complete -c remote-juggler -n "__fish_seen_subcommand_from trusted-workstation tws" -a "verify" -d "Verify configuration"

# Security mode values
complete -c remote-juggler -n "__fish_seen_subcommand_from security-mode" -a "standard" -d "Standard security"
complete -c remote-juggler -n "__fish_seen_subcommand_from security-mode" -a "trusted_workstation" -d "Trusted workstation mode"
complete -c remote-juggler -n "__fish_seen_subcommand_from security-mode" -a "hardware_only" -d "Hardware-only mode"

# Keys options
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx; and __fish_seen_subcommand_from search" -l field -d "Search field" -xa "title username url notes"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx; and __fish_seen_subcommand_from search list export" -l group -d "Filter by group"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx; and __fish_seen_subcommand_from search list export" -l json -d "JSON output"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx; and __fish_seen_subcommand_from store" -l username -d "Associated username"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx; and __fish_seen_subcommand_from store" -l url -d "Associated URL"
complete -c remote-juggler -n "__fish_seen_subcommand_from keys kdbx; and __fish_seen_subcommand_from export" -l format -d "Output format" -xa "env json shell"

# Identity name completion for commands that need it
function __remote_juggler_identities
    remote-juggler list 2>/dev/null | grep -E '^  - ' | sed 's/^  - //'
end

complete -c remote-juggler -n "__fish_seen_subcommand_from switch to validate" -a "(__remote_juggler_identities)"
complete -c remote-juggler -n "__fish_seen_subcommand_from config; and __fish_seen_subcommand_from edit remove" -a "(__remote_juggler_identities)"
complete -c remote-juggler -n "__fish_seen_subcommand_from token; and __fish_seen_subcommand_from set get clear renew" -a "(__remote_juggler_identities)"
complete -c remote-juggler -n "__fish_seen_subcommand_from gpg; and __fish_seen_subcommand_from configure" -a "(__remote_juggler_identities)"
