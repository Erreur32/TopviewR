# Usage: make build | test | build-nvidia | test-nvidia | scan | buildx | push   (REGISTRY=ghcr.io/erreur32 make push)
BTOP_VERSION ?= $(shell sed -n 's/^ARG BTOP_VERSION=//p' Dockerfile | head -1)
DATE         := $(shell date -u +%Y%m%d)
REGISTRY     ?= ghcr.io/erreur32
IMAGE        ?= $(REGISTRY)/topviewr
LOCAL        ?= topviewr:dev
PLATFORMS    ?= linux/amd64,linux/arm64
BUILD_ARGS    = --build-arg VERSION=$(BTOP_VERSION)-$(DATE) \
                --build-arg REVISION=$(shell git rev-parse --short HEAD 2>/dev/null || echo local) \
                --build-arg CREATED=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)

.PHONY: build test scan buildx push build-nvidia test-nvidia
build:  ## local image, host architecture
	docker build --pull $(BUILD_ARGS) -t $(LOCAL) .

test: build
	./tests/test.sh $(LOCAL)

build-nvidia:  ## Debian variant (NVIDIA), host architecture
	docker build --pull $(BUILD_ARGS) -f Dockerfile.nvidia -t $(LOCAL)-nvidia .

test-nvidia: build-nvidia
	./tests/test.sh $(LOCAL)-nvidia

scan: build  ## fixable CRITICAL and HIGH vulnerabilities
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest \
		image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 $(LOCAL)

buildx:  ## multi-arch without push (checks that everything builds)
	docker buildx build --pull --platform $(PLATFORMS) $(BUILD_ARGS) .

push:
	docker buildx build --pull --platform $(PLATFORMS) $(BUILD_ARGS) --sbom=true --provenance=true \
		-t $(IMAGE):latest -t $(IMAGE):$(BTOP_VERSION) -t $(IMAGE):$(BTOP_VERSION)-$(DATE) --push .
