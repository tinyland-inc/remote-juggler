#!/usr/bin/env bash
# Push Dockerfiles, configs, and workspace files to each agent repo.
#
# Usage: ./push-to-forks.sh [--dry-run] [ironclaw|picoclaw|hexstrike-ai]
#
# Prerequisites:
#   - gh CLI authenticated to tinyland-inc org
#   - GITHUB_TOKEN unset (or org-scoped): GITHUB_TOKEN= ./push-to-forks.sh
#
# What this does for each repo:
#   1. Clones the repo's main branch into a temp dir
#   2. Copies the Dockerfile + config files into the right locations
#   3. Creates a deploy branch, commits, pushes, creates PR, and merges
#   4. Cleans up temp dir and remote branch
#
# Note: Agent repos are standalone (not GitHub forks). Main is the primary branch.
# All changes flow through PRs for full auditability.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIG_DIR="$(pwd)"
DRY_RUN="${DRY_RUN:-}"
REPOS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    ironclaw|picoclaw|hexstrike-ai) REPOS+=("$1"); shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Default: all repos
if [[ ${#REPOS[@]} -eq 0 ]]; then
  REPOS=(ironclaw picoclaw hexstrike-ai)
fi

push_repo() {
  local agent="$1"
  local repo="tinyland-inc/${agent}"
  local src_dir="${SCRIPT_DIR}/${agent}"
  local tmp_dir repo_dir
  local branch_name="deploy/config-sync-$(date +%Y%m%d-%H%M%S)"

  echo "==> Processing ${repo}"

  if [[ ! -d "${src_dir}" ]]; then
    echo "    ERROR: ${src_dir} does not exist"
    return 1
  fi

  tmp_dir=$(mktemp -d)
  repo_dir="${tmp_dir}/repo"

  # Clone the repo's main branch
  echo "    Cloning ${repo}..."
  gh repo clone "${repo}" "${repo_dir}" -- --branch main --depth 1 --single-branch 2>/dev/null

  # Copy config files into tinyland/ subdir, replace Dockerfile
  mkdir -p "${repo_dir}/tinyland"
  cp "${src_dir}/Dockerfile" "${repo_dir}/Dockerfile"

  case "${agent}" in
    ironclaw)
      cp "${src_dir}/openclaw.json" "${repo_dir}/tinyland/openclaw.json"
      if [[ -d "${src_dir}/workspace" ]]; then
        rm -rf "${repo_dir}/tinyland/workspace"
        cp -r "${src_dir}/workspace" "${repo_dir}/tinyland/workspace"
      fi
      ;;
    picoclaw)
      cp "${src_dir}/config.json" "${repo_dir}/tinyland/config.json"
      cp "${src_dir}/entrypoint.sh" "${repo_dir}/tinyland/entrypoint.sh"
      chmod +x "${repo_dir}/tinyland/entrypoint.sh"
      if [[ -d "${src_dir}/workspace" ]]; then
        rm -rf "${repo_dir}/tinyland/workspace"
        cp -r "${src_dir}/workspace" "${repo_dir}/tinyland/workspace"
      fi
      ;;
    hexstrike-ai)
      # Copy Flask server wrapper (bridges adapter to security tools)
      if [[ -f "${src_dir}/hexstrike_server.py" ]]; then
        cp "${src_dir}/hexstrike_server.py" "${repo_dir}/hexstrike_server.py"
      fi
      if [[ -d "${src_dir}/workspace" ]]; then
        rm -rf "${repo_dir}/tinyland/workspace"
        cp -r "${src_dir}/workspace" "${repo_dir}/tinyland/workspace"
      fi
      ;;
  esac

  # Sync workflows (always overwrite to keep in sync)
  local workflows_src="${SCRIPT_DIR}/../fork-workflows"
  if [[ -d "${workflows_src}" ]]; then
    mkdir -p "${repo_dir}/.github/workflows"
    for wf in ghcr.yml upstream-sync.yml; do
      if [[ -f "${workflows_src}/${wf}" ]]; then
        sed "s/REPO_NAME: ironclaw/REPO_NAME: ${agent}/" "${workflows_src}/${wf}" > "${repo_dir}/.github/workflows/${wf}"
      fi
    done
  fi

  # Force-add tinyland/ dir (some repos gitignore config.json)
  if [[ -d "${repo_dir}/tinyland" ]]; then
    git -C "${repo_dir}" add -f "${repo_dir}/tinyland/"
  fi
  git -C "${repo_dir}" add "${repo_dir}/Dockerfile"

  # Stage hexstrike_server.py if it was copied
  if [[ -f "${repo_dir}/hexstrike_server.py" ]]; then
    git -C "${repo_dir}" add "${repo_dir}/hexstrike_server.py"
  fi

  # Stage .github/workflows if they were added/modified
  if [[ -d "${repo_dir}/.github/workflows" ]]; then
    git -C "${repo_dir}" add -f "${repo_dir}/.github/workflows/"
  fi

  # Check for changes
  if git -C "${repo_dir}" diff --cached --quiet; then
    echo "    No changes to push for ${agent}"
    rm -rf "${tmp_dir}"
    return 0
  fi
  echo "    Changes staged:"
  git -C "${repo_dir}" --no-pager diff --cached --stat

  if [[ -n "${DRY_RUN}" ]]; then
    echo "    [DRY RUN] Would create PR on ${repo} from ${branch_name}"
    rm -rf "${tmp_dir}"
    return 0
  fi

  # Create deploy branch, commit, push, PR, merge
  git -C "${repo_dir}" checkout -b "${branch_name}"

  git -C "${repo_dir}" \
    -c user.name="rj-agent-bot[bot]" \
    -c user.email="rj-agent-bot[bot]@users.noreply.github.com" \
    -c commit.gpgsign=false \
    commit -m "feat: sync config, workspace, and workflows

Syncs Dockerfile, config, workspace bootstrap files, and
GitHub workflows from RemoteJuggler deploy/fork-dockerfiles."

  echo "    Pushing ${branch_name}..."
  git -C "${repo_dir}" push origin "${branch_name}"

  echo "    Creating PR..."
  local pr_url
  pr_url=$(gh pr create \
    --repo "${repo}" \
    --base main \
    --head "${branch_name}" \
    --title "deploy: sync config, workspace, and workflows" \
    --body "Automated sync from RemoteJuggler \`deploy/fork-dockerfiles/${agent}/\`.

Changes include Dockerfile, agent config, workspace bootstrap files,
skills, and GitHub workflows.

Pushed by \`push-to-forks.sh\` via \`rj-agent-bot[bot]\`." 2>/dev/null | grep -o 'https://[^ ]*')

  echo "    PR created: ${pr_url}"

  echo "    Merging PR..."
  gh pr merge "${pr_url}" --merge --delete-branch
  echo "    Merged and branch cleaned up"

  rm -rf "${tmp_dir}"
}

for agent in "${REPOS[@]}"; do
  push_repo "${agent}"
  echo ""
done

echo "Done. Verify GHCR builds at:"
for agent in "${REPOS[@]}"; do
  echo "  https://github.com/tinyland-inc/${agent}/actions"
done
