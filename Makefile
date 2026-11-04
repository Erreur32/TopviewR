# Usage : make build | test | scan | buildx | push   (REGISTRY=ghcr.io/erreur32 make push)
BTOP_VERSION ?= $(shell sed -n 's/^ARG BTOP_VERSION=//p' Dockerfile | head -1)
DATE         := $(shell date -u +%Y%m%d)
REGISTRY     ?= ghcr.io/erreur32
IMAGE        ?= $(REGISTRY)/btop-web
LOCAL        ?= btop-web:dev
PLATFORMS    ?= linux/amd64,linux/arm64
BUILD_ARGS    = --build-arg VERSION=$(BTOP_VERSION)-$(DATE) \
                --build-arg REVISION=$(shell git rev-parse --short HEAD 2>/dev/null || echo local) \
                --build-arg CREATED=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)

.PHONY: build test scan buildx push
build:  ## image locale, architecture de la machine
	docker build --pull $(BUILD_ARGS) -t $(LOCAL) .

test: build
	./tests/test.sh $(LOCAL)

scan: build  ## failles CRITICAL et HIGH corrigeables
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest \
		image --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 $(LOCAL)

buildx:  ## multi-arch sans push (vérifie que tout compile)
	docker buildx build --pull --platform $(PLATFORMS) $(BUILD_ARGS) .

push:
	docker buildx build --pull --platform $(PLATFORMS) $(BUILD_ARGS) --sbom=true --provenance=true \
		-t $(IMAGE):latest -t $(IMAGE):$(BTOP_VERSION) -t $(IMAGE):$(BTOP_VERSION)-$(DATE) --push .
