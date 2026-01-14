#!/bin/bash
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

set -euo pipefail

# Tool versions - update these to change versions across the project
GOLANGCI_LINT_VERSION="v2.4.0"
LICENSE_EYE_VERSION="latest"
GORELEASER_VERSION="v2.12.0"

# Project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$PROJECT_ROOT/tools"

echo "Installing development tools to $TOOLS_DIR..."

# Create tools directory if it doesn't exist
mkdir -p "$TOOLS_DIR"

# Install tools with pinned versions to project-local tools directory
echo "Installing golangci-lint $GOLANGCI_LINT_VERSION..."
GOBIN="$TOOLS_DIR" go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$GOLANGCI_LINT_VERSION"

echo "Installing license-eye $LICENSE_EYE_VERSION..."
GOBIN="$TOOLS_DIR" go install "github.com/apache/skywalking-eyes/cmd/license-eye@$LICENSE_EYE_VERSION"

echo "Installing goreleaser $GORELEASER_VERSION..."
GOBIN="$TOOLS_DIR" go install "github.com/goreleaser/goreleaser/v2@$GORELEASER_VERSION"

echo ""
echo "Installation complete. Installed tools:"
ls -la "$TOOLS_DIR"
