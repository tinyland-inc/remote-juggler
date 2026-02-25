#!/usr/bin/env bash
# Push tinyland branch Dockerfiles and configs to each fork repo.
#
# Usage: ./push-to-forks.sh [--dry-run] [ironclaw|picoclaw|hexstrike-ai]
#
# Prerequisites:
#   - gh CLI authenticated to tinyland-inc org
#   - GITHUB_TOKEN unset (or org-scoped): GITHUB_TOKEN= ./push-to-forks.sh
#
# What this does for each fork:
#   1. Clones the fork's tinyland branch into a temp dir
#   2. Copies the Dockerfile + config files into the right locations
#   3. Commits and pushes to tinyland branch
#   4. Cleans up temp dir

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIG_DIR="$(pwd)"
DRY_RUN="${DRY_RUN:-}"
FORKS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    ironclaw|picoclaw|hexstrike-ai) FORKS+=("$1"); shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Default: all forks
if [[ ${#FORKS[@]} -eq 0 ]]; then
  FORKS=(ironclaw picoclaw hexstrike-ai)
fi

push_fork() {
  local fork="$1"
  local repo="tinyland-inc/${fork}"
  local src_dir="${SCRIPT_DIR}/${fork}"
  local tmp_dir repo_dir

  echo "==> Processing ${repo} (tinyland branch)"

  if [[ ! -d "${src_dir}" ]]; then
    echo "    ERROR: ${src_dir} does not exist"
    return 1
  fi

  tmp_dir=$(mktemp -d)
  repo_dir="${tmp_dir}/repo"

  # Clone the repo — try tinyland branch first, fall back to default branch
  echo "    Cloning ${repo}..."
  if gh repo clone "${repo}" "${repo_dir}" -- --branch tinyland --depth 1 --single-branch 2>/dev/null; then
    echo "    Using existing tinyland branch"
  else
    echo "    tinyland branch not found, cloning default branch and creating tinyland..."
    gh repo clone "${repo}" "${repo_dir}" -- --depth 1 2>/dev/null
    git -C "${repo_dir}" checkout -b tinyland
  fi

  # Copy config files into tinyland/ subdir, replace Dockerfile
  mkdir -p "${repo_dir}/tinyland"
  cp "${src_dir}/Dockerfile" "${repo_dir}/Dockerfile"

  case "${fork}" in
    ironclaw)
      cp "${src_dir}/openclaw.json" "${repo_dir}/tinyland/openclaw.json"
      ;;
    picoclaw)
      cp "${src_dir}/config.json" "${repo_dir}/tinyland/config.json"
      cp "${src_dir}/entrypoint.sh" "${repo_dir}/tinyland/entrypoint.sh"
      chmod +x "${repo_dir}/tinyland/entrypoint.sh"
      ;;
    hexstrike-ai)
      # HexStrike has no upstream Dockerfile — ours is the only one.
      ;;
  esac

  # Ensure GHCR and upstream-sync workflows exist
  local workflows_src="${SCRIPT_DIR}/../fork-workflows"
  if [[ -d "${workflows_src}" ]]; then
    mkdir -p "${repo_dir}/.github/workflows"
    for wf in ghcr.yml upstream-sync.yml; do
      if [[ -f "${workflows_src}/${wf}" ]] && [[ ! -f "${repo_dir}/.github/workflows/${wf}" ]]; then
        echo "    Adding ${wf} workflow"
        sed "s/FORK_NAME: ironclaw/FORK_NAME: ${fork}/" "${workflows_src}/${wf}" > "${repo_dir}/.github/workflows/${wf}"
      fi
    done
  fi

  # Force-add tinyland/ dir (some repos gitignore config.json)
  if [[ -d "${repo_dir}/tinyland" ]]; then
    git -C "${repo_dir}" add -f "${repo_dir}/tinyland/"
  fi
  git -C "${repo_dir}" add "${repo_dir}/Dockerfile"

  # Check for changes
  if git -C "${repo_dir}" diff --cached --quiet; then
    echo "    No changes to push for ${fork}"
    rm -rf "${tmp_dir}"
    return 0
  fi
  echo "    Changes staged:"
  git -C "${repo_dir}" --no-pager diff --cached --stat

  if [[ -n "${DRY_RUN}" ]]; then
    echo "    [DRY RUN] Would commit and push to ${repo}:tinyland"
    rm -rf "${tmp_dir}"
    return 0
  fi

  git -C "${repo_dir}" \
    -c user.name="rj-agent-bot[bot]" \
    -c user.email="rj-agent-bot[bot]@users.noreply.github.com" \
    -c commit.gpgsign=false \
    commit -m "feat: add tinyland Dockerfile with RemoteJuggler config

Adds Dockerfile for GHCR builds on the tinyland branch.
Includes baked-in config for Aperture API routing and
adapter sidecar integration."

  git -C "${repo_dir}" push origin tinyland
  echo "    Pushed to ${repo}:tinyland"

  rm -rf "${tmp_dir}"
}

for fork in "${FORKS[@]}"; do
  push_fork "${fork}"
  echo ""
done

echo "Done. Verify GHCR builds at:"
for fork in "${FORKS[@]}"; do
  echo "  https://github.com/tinyland-inc/${fork}/actions"
done
