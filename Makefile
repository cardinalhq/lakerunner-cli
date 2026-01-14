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

TARGETS=test local
PLATFORM=linux/amd64,linux/arm64
BUILDX=docker buildx build --pull --platform ${PLATFORM}
IMAGE_PREFIX=public.ecr.aws/cardinalhq.io/
IMAGE_TAG=latest-dev

#
# Build targets.  Adding to these will cause magic to occur.
#

# These are targets for "make local"
BINARIES = lakerunner-cli

# These are the targets for Docker images, used both for the multi-arch and
# single (local) Docker builds.
# Dockerfiles should have a target that ends in -image, e.g. agent-image.
IMAGE_TARGETS = lakerunner-cli

#
# Below here lies magic...
#

# Due to the way we build, we will make the universe no matter which files
# actually change.  With the many targets, this is just so much easier,
# and it also ensures the Docker images have identical timestamp-based tags.
all_deps := $(shell find main.go cmd internal -name '*.go' | grep -v _test) Makefile

#
# Default target.
#

.PHONY: all
all: ${TARGETS}

# name of the buildx builder we’ll always (re)create
BUILDER := lakerunner-cli-builder

# convenience recipe to always start with a clean builder
define with_builder
	@docker buildx rm $(BUILDER) >/dev/null 2>&1 || true; \
	docker buildx create --name $(BUILDER) --driver docker-container --use --bootstrap; \
	trap 'docker buildx rm $(BUILDER) >/dev/null 2>&1' EXIT; \
	$(1)
endef

#
# Generate all the things.
#
.PHONY: generate
generate:
	go generate ./...

#
# Install development tools
#
tools/golangci-lint tools/license-eye tools/goreleaser:
	./scripts/install-tools.sh

#
# Run pre-commit checks
#
check: test license-check lint

license-check: tools/license-eye
	./tools/license-eye header check

lint: tools/golangci-lint
	./tools/golangci-lint run --timeout 15m --config .golangci.yaml

#
# Build locally, mostly for development speed.
#
.PHONY: local
local: $(addprefix bin/,$(BINARIES))

bin/lakerunner-cli: ${all_deps}
	@[ -d bin ] || mkdir bin
	go build -o $@ main.go

#
# Multi-architecture image builds
#
.PHONY: images
images: test-only tools/goreleaser
	$(call with_builder, ./tools/goreleaser release --clean)

#
# Build binaries for all platforms
#
.PHONY: binaries
binaries: test-only tools/goreleaser
	./tools/goreleaser release --clean --config .goreleaser-release.yaml --skip=docker

#
# Test targets
#

.PHONY: test
test: generate test-only

.PHONY: test-only
test-only:
	go test -race ./...


#
# promode to prod
#

.PHONY: promote-to-prod
promote-to-prod:
	crane cp ${IMAGE_PREFIX}lakerunner-cli:${IMAGE_TAG} ${IMAGE_PREFIX}lakerunner-cli:latest

#
# Clean the world.
#

.PHONY: clean
clean:
	rm -f bin/*

.PHONY: really-clean
really-clean: clean
