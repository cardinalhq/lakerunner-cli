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

cat <<EOF

Next steps:
  1. Make sure lakerunner-cli is on your PATH.
  2. Export LAKERUNNER_QUERY_URL and LAKERUNNER_API_KEY.
  3. In Claude Code, type /${SKILL_NAME} to invoke the skill.

Uninstall with: rm -rf "${TARGET_DIR}"
EOF
