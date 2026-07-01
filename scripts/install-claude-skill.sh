#!/usr/bin/env bash
# Copyright 2025-2026 CardinalHQ, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Installs the lakerunner-cli Claude Code skill into ~/.claude/skills/.
#
# Usage (from a checkout):
#   bash scripts/install-claude-skill.sh
#
# Usage (one-liner, no checkout):
#   curl -fsSL https://raw.githubusercontent.com/cardinalhq/lakerunner-cli/main/scripts/install-claude-skill.sh | bash

set -euo pipefail

SKILL_NAME="lakerunner-cli"
SKILL_URL="https://raw.githubusercontent.com/cardinalhq/lakerunner-cli/main/.claude/skills/${SKILL_NAME}/SKILL.md"

SKILLS_ROOT="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
TARGET_DIR="${SKILLS_ROOT}/${SKILL_NAME}"
TARGET_FILE="${TARGET_DIR}/SKILL.md"

# Prefer the local copy when running from a checkout; otherwise fetch.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SKILL="${SCRIPT_DIR}/../.claude/skills/${SKILL_NAME}/SKILL.md"

mkdir -p "${TARGET_DIR}"

if [[ -f "${LOCAL_SKILL}" ]]; then
  cp "${LOCAL_SKILL}" "${TARGET_FILE}"
  echo "Installed ${SKILL_NAME} skill from local checkout → ${TARGET_FILE}"
else
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required to fetch the skill" >&2
    exit 1
  fi
  curl -fsSL "${SKILL_URL}" -o "${TARGET_FILE}"
  echo "Installed ${SKILL_NAME} skill from ${SKILL_URL} → ${TARGET_FILE}"
fi

# Prompt for credentials so users don't have to look them up separately.
# Both values are deployment-specific — the CLI talks to whatever Lakerunner
# instance the user runs (in-VPC, self-hosted, etc.), so we can't derive them.
prompt_for_creds() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    # Non-interactive (piped install). Skip prompts; fall back to the reminder.
    return 1
  fi

  echo
  echo "Configure Lakerunner credentials for the skill."
  echo "Get these from whoever runs your Lakerunner deployment (or the deployment's"
  echo "own docs/console). Leave blank to skip and set them yourself later."
  echo

  local existing_url="${LAKERUNNER_QUERY_URL:-}"
  local existing_key="${LAKERUNNER_API_KEY:-}"
  local url_prompt="LAKERUNNER_QUERY_URL"
  local key_prompt="LAKERUNNER_API_KEY"
  [[ -n "${existing_url}" ]] && url_prompt+=" [${existing_url}]"
  [[ -n "${existing_key}" ]] && key_prompt+=" [****${existing_key: -4}]"

  local url key
  printf "  %s: " "${url_prompt}"
  IFS= read -r url || return 1
  printf "  %s: " "${key_prompt}"
  # -s hides the key echo; add a newline afterwards.
  IFS= read -rs key || return 1
  echo

  url="${url:-${existing_url}}"
  key="${key:-${existing_key}}"

  if [[ -z "${url}" && -z "${key}" ]]; then
    return 1
  fi

  LR_URL="${url}"
  LR_KEY="${key}"
  return 0
}

persist_creds() {
  local url="$1" key="$2"
  local profile=""
  case "${SHELL:-}" in
    */zsh)  profile="${HOME}/.zshrc" ;;
    */bash) profile="${HOME}/.bashrc" ;;
    */fish) profile="${HOME}/.config/fish/config.fish" ;;
  esac

  echo
  if [[ -z "${profile}" ]]; then
    echo "Couldn't detect a shell profile from \$SHELL=${SHELL:-}. Add these lines yourself:"
    [[ -n "${url}" ]] && echo "  export LAKERUNNER_QUERY_URL=\"${url}\""
    [[ -n "${key}" ]] && echo "  export LAKERUNNER_API_KEY=\"${key}\""
    return
  fi

  printf "Append export lines to %s? [y/N] " "${profile}"
  local answer
  IFS= read -r answer || answer=""
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "Skipped. To set them yourself:"
    [[ -n "${url}" ]] && echo "  export LAKERUNNER_QUERY_URL=\"${url}\""
    [[ -n "${key}" ]] && echo "  export LAKERUNNER_API_KEY=\"${key}\""
    return
  fi

  {
    echo ""
    echo "# Added by lakerunner-cli install-claude-skill.sh"
    if [[ "${profile}" == *config.fish ]]; then
      [[ -n "${url}" ]] && echo "set -gx LAKERUNNER_QUERY_URL \"${url}\""
      [[ -n "${key}" ]] && echo "set -gx LAKERUNNER_API_KEY \"${key}\""
    else
      [[ -n "${url}" ]] && echo "export LAKERUNNER_QUERY_URL=\"${url}\""
      [[ -n "${key}" ]] && echo "export LAKERUNNER_API_KEY=\"${key}\""
    fi
  } >> "${profile}"
  echo "Wrote credentials to ${profile}. Open a new shell (or 'source ${profile}') to pick them up."
}

LR_URL=""
LR_KEY=""
if prompt_for_creds; then
  persist_creds "${LR_URL}" "${LR_KEY}"
  CREDS_DONE=1
else
  CREDS_DONE=0
fi

cat <<EOF

Next steps:
  1. Make sure lakerunner-cli is on your PATH.
EOF

if [[ "${CREDS_DONE}" -eq 0 ]]; then
  cat <<EOF
  2. Set LAKERUNNER_QUERY_URL and LAKERUNNER_API_KEY in your environment
     (values come from your Lakerunner deployment — ask whoever runs it).
  3. In Claude Code, type /${SKILL_NAME} to invoke the skill.
EOF
else
  cat <<EOF
  2. In Claude Code, type /${SKILL_NAME} to invoke the skill.
EOF
fi

cat <<EOF

Uninstall with: rm -rf "${TARGET_DIR}"
EOF
