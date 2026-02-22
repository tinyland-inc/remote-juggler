#!/usr/bin/env bash
#
# RemoteJuggler Changelog Generator
#
# Generates release notes from git commits and conventional commit messages.
# Supports multiple output formats: markdown, gitlab, github, plain.
#
# Usage:
#   ./generate-changelog.sh [options]
#   ./generate-changelog.sh --from v1.0.0 --to v2.0.0
#   ./generate-changelog.sh --format github --output RELEASE_NOTES.md
#
set -euo pipefail

# Configuration
REPO_URL="https://github.com/tinyland-inc/remote-juggler"

# Output format templates
declare -A SECTION_HEADERS=(
    ["feat"]="Features"
    ["fix"]="Bug Fixes"
    ["perf"]="Performance"
    ["refactor"]="Refactoring"
    ["docs"]="Documentation"
    ["test"]="Testing"
    ["build"]="Build System"
    ["ci"]="CI/CD"
    ["chore"]="Maintenance"
    ["security"]="Security"
    ["breaking"]="Breaking Changes"
)

# Emoji mapping for GitHub/GitLab style
declare -A SECTION_EMOJI=(
    ["feat"]="✨"
    ["fix"]="🐛"
    ["perf"]="⚡"
    ["refactor"]="♻️"
    ["docs"]="📚"
    ["test"]="🧪"
    ["build"]="🔧"
    ["ci"]="👷"
    ["chore"]="🧹"
    ["security"]="🔒"
    ["breaking"]="💥"
)

# Logging
info() { echo "==> $*" >&2; }
error() { echo "Error: $*" >&2; exit 1; }

usage() {
    cat <<EOF
RemoteJuggler Changelog Generator

Usage:
  $0 [options]

Options:
  --from TAG        Start tag/commit (default: previous tag)
  --to TAG          End tag/commit (default: HEAD)
  --format FORMAT   Output format: markdown, gitlab, github, plain (default: markdown)
  --output FILE     Write to file instead of stdout
  --version VER     Version string for header (default: extracted from --to)
  --date DATE       Release date (default: today)
  --emoji           Include emoji in section headers
  --contributors    Include contributor list
  --stats           Include commit statistics
  --help            Show this help

Conventional Commit Types:
  feat:     New features
  fix:      Bug fixes
  perf:     Performance improvements
  refactor: Code refactoring
  docs:     Documentation changes
  test:     Test additions/changes
  build:    Build system changes
  ci:       CI/CD changes
  chore:    Maintenance tasks
  security: Security fixes

Breaking Changes:
  Commits with "BREAKING CHANGE:" in the body or "!" after the type
  will be highlighted in the Breaking Changes section.

Examples:
  $0 --from v1.5.0 --to v2.0.0 --format github
  $0 --emoji --contributors --output CHANGELOG.md
EOF
}

# Get previous tag
get_previous_tag() {
    local current="${1:-HEAD}"

    if [[ "$current" == "HEAD" ]]; then
        # Get the most recent tag
        git describe --tags --abbrev=0 2>/dev/null || echo ""
    else
        # Get the tag before the specified one
        git describe --tags --abbrev=0 "${current}^" 2>/dev/null || echo ""
    fi
}

# Extract version from tag
extract_version() {
    local tag="$1"
    echo "${tag#v}"
}

# Parse conventional commit message
parse_commit() {
    local message="$1"
    local type="" scope="" subject="" breaking=false

    # Match: type(scope)!: subject or type!: subject or type(scope): subject or type: subject
    if [[ "$message" =~ ^([a-z]+)(\([^)]+\))?(!)?:\ (.+)$ ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[2]}"
        [[ "${BASH_REMATCH[3]}" == "!" ]] && breaking=true
        subject="${BASH_REMATCH[4]}"

        # Remove parentheses from scope
        scope="${scope#(}"
        scope="${scope%)}"
    else
        # Non-conventional commit
        type="other"
        subject="$message"
    fi

    echo "$type|$scope|$subject|$breaking"
}

# Get commits between tags
get_commits() {
    local from="$1"
    local to="$2"

    local range
    if [[ -n "$from" ]]; then
        range="${from}..${to}"
    else
        range="$to"
    fi

    # Format: hash|author|date|subject|body
    git log --pretty=format:"%h|%an|%as|%s|%b" "$range" --no-merges
}

# Generate changelog
generate_changelog() {
    local from="$1"
    local to="$2"
    local format="$3"
    local version="$4"
    local date="$5"
    local use_emoji="$6"
    local show_contributors="$7"
    local show_stats="$8"

    # Collect commits by type
    declare -A commits_by_type
    declare -A breaking_changes
    declare -A contributors
    local total_commits=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        IFS='|' read -r hash author commit_date subject body <<< "$line"

        local parsed
        parsed=$(parse_commit "$subject")
        IFS='|' read -r type scope commit_subject is_breaking <<< "$parsed"

        # Check for breaking change in body
        if [[ "$body" == *"BREAKING CHANGE:"* ]] || [[ "$is_breaking" == "true" ]]; then
            local breaking_desc="$commit_subject"
            if [[ "$body" == *"BREAKING CHANGE:"* ]]; then
                breaking_desc=$(echo "$body" | grep -A1 "BREAKING CHANGE:" | tail -1)
            fi
            breaking_changes["$hash"]="$breaking_desc"
        fi

        # Build commit entry
        local entry="$commit_subject"
        if [[ -n "$scope" ]]; then
            entry="**$scope:** $entry"
        fi
        entry="$entry ([${hash}](${REPO_URL}/-/commit/${hash}))"

        # Add to appropriate section
        commits_by_type["$type"]+="- $entry"$'\n'

        # Track contributors
        contributors["$author"]=1

        ((total_commits++)) || true

    done <<< "$(get_commits "$from" "$to")"

    # Generate output
    local output=""

    # Header
    case "$format" in
        markdown|gitlab|github)
            output+="# ${version}"
            if [[ -n "$date" ]]; then
                output+=" (${date})"
            fi
            output+=$'\n\n'
            ;;
        plain)
            output+="${version}"
            if [[ -n "$date" ]]; then
                output+=" (${date})"
            fi
            output+=$'\n'
            output+="$(printf '=%.0s' {1..60})"$'\n\n'
            ;;
    esac

    # Breaking changes section (always first)
    if [[ ${#breaking_changes[@]} -gt 0 ]]; then
        local header="${SECTION_HEADERS[breaking]}"
        [[ "$use_emoji" == "true" ]] && header="${SECTION_EMOJI[breaking]} $header"

        case "$format" in
            markdown|gitlab|github)
                output+="## $header"$'\n\n'
                ;;
            plain)
                output+="$header"$'\n'
                output+="$(printf -- '-%.0s' {1..40})"$'\n'
                ;;
        esac

        for hash in "${!breaking_changes[@]}"; do
            output+="- ${breaking_changes[$hash]} ([${hash}](${REPO_URL}/-/commit/${hash}))"$'\n'
        done
        output+=$'\n'
    fi

    # Regular sections
    local section_order=("feat" "fix" "perf" "security" "refactor" "docs" "test" "build" "ci" "chore")

    for type in "${section_order[@]}"; do
        if [[ -n "${commits_by_type[$type]:-}" ]]; then
            local header="${SECTION_HEADERS[$type]}"
            [[ "$use_emoji" == "true" ]] && header="${SECTION_EMOJI[$type]} $header"

            case "$format" in
                markdown|gitlab|github)
                    output+="## $header"$'\n\n'
                    ;;
                plain)
                    output+="$header"$'\n'
                    output+="$(printf -- '-%.0s' {1..40})"$'\n'
                    ;;
            esac

            output+="${commits_by_type[$type]}"
            output+=$'\n'
        fi
    done

    # Other commits (non-conventional)
    if [[ -n "${commits_by_type[other]:-}" ]]; then
        case "$format" in
            markdown|gitlab|github)
                output+="## Other Changes"$'\n\n'
                ;;
            plain)
                output+="Other Changes"$'\n'
                output+="$(printf -- '-%.0s' {1..40})"$'\n'
                ;;
        esac
        output+="${commits_by_type[other]}"
        output+=$'\n'
    fi

    # Contributors section
    if [[ "$show_contributors" == "true" ]] && [[ ${#contributors[@]} -gt 0 ]]; then
        case "$format" in
            markdown|gitlab|github)
                output+="## Contributors"$'\n\n'
                ;;
            plain)
                output+="Contributors"$'\n'
                output+="$(printf -- '-%.0s' {1..40})"$'\n'
                ;;
        esac

        for author in "${!contributors[@]}"; do
            output+="- $author"$'\n'
        done
        output+=$'\n'
    fi

    # Statistics
    if [[ "$show_stats" == "true" ]]; then
        local files_changed insertions deletions

        local diffstat
        if [[ -n "$from" ]]; then
            diffstat=$(git diff --shortstat "${from}..${to}" 2>/dev/null || echo "")
        else
            diffstat=$(git diff --shortstat "${to}^..${to}" 2>/dev/null || echo "")
        fi

        case "$format" in
            markdown|gitlab|github)
                output+="## Statistics"$'\n\n'
                output+="- **Commits:** $total_commits"$'\n'
                output+="- **Contributors:** ${#contributors[@]}"$'\n'
                if [[ -n "$diffstat" ]]; then
                    output+="- **Changes:** $diffstat"$'\n'
                fi
                ;;
            plain)
                output+="Statistics"$'\n'
                output+="$(printf -- '-%.0s' {1..40})"$'\n'
                output+="Commits: $total_commits"$'\n'
                output+="Contributors: ${#contributors[@]}"$'\n'
                if [[ -n "$diffstat" ]]; then
                    output+="Changes: $diffstat"$'\n'
                fi
                ;;
        esac
        output+=$'\n'
    fi

    # Footer with links
    case "$format" in
        github)
            output+="---"$'\n\n'
            if [[ -n "$from" ]]; then
                output+="**Full Changelog:** [${from}...${to}](${REPO_URL}/-/compare/${from}...${to})"$'\n'
            fi
            ;;
        gitlab)
            output+="---"$'\n\n'
            if [[ -n "$from" ]]; then
                output+="**Full Changelog:** [${from}...${to}](${REPO_URL}/-/compare/${from}...${to})"$'\n'
            fi
            ;;
    esac

    echo "$output"
}

# Main
main() {
    local from=""
    local to="HEAD"
    local format="markdown"
    local output_file=""
    local version=""
    local date=""
    local use_emoji=false
    local show_contributors=false
    local show_stats=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                from="$2"
                shift 2
                ;;
            --to)
                to="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --version)
                version="$2"
                shift 2
                ;;
            --date)
                date="$2"
                shift 2
                ;;
            --emoji)
                use_emoji=true
                shift
                ;;
            --contributors)
                show_contributors=true
                shift
                ;;
            --stats)
                show_stats=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Validate format
    case "$format" in
        markdown|gitlab|github|plain) ;;
        *) error "Unknown format: $format" ;;
    esac

    # Get default values
    if [[ -z "$from" ]]; then
        from=$(get_previous_tag "$to")
        if [[ -n "$from" ]]; then
            info "Using previous tag: $from"
        fi
    fi

    if [[ -z "$version" ]]; then
        if [[ "$to" != "HEAD" ]]; then
            version=$(extract_version "$to")
        else
            version="Unreleased"
        fi
    fi

    if [[ -z "$date" ]]; then
        if [[ "$to" != "HEAD" ]] && git rev-parse "$to" &>/dev/null; then
            date=$(git log -1 --format=%as "$to")
        else
            date=$(date +%Y-%m-%d)
        fi
    fi

    info "Generating changelog for $version ($from -> $to)"

    # Generate changelog
    local changelog
    changelog=$(generate_changelog "$from" "$to" "$format" "$version" "$date" "$use_emoji" "$show_contributors" "$show_stats")

    # Output
    if [[ -n "$output_file" ]]; then
        echo "$changelog" > "$output_file"
        info "Changelog written to: $output_file"
    else
        echo "$changelog"
    fi
}

main "$@"
