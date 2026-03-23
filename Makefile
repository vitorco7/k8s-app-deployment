SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

IMAGE_REPOSITORY ?= vco7/k8s-app-deployment
DOCKERFILE_PATH ?= Dockerfiles/app/dockerfile.yaml
K8S_DIR ?= k8s
KUSTOMIZATION_FILE ?= $(K8S_DIR)/kustomization.yaml
NAMESPACE ?= k8s-app
DEPLOYMENT_NAME ?= app
VERSION ?= dev-$(shell date +%Y%m%d%H%M%S)

.PHONY: help run run-dry dry check-tools check-files check-version

help:
	@echo "Targets:"
	@echo "  make run                   Deploy using VERSION (default: generated timestamp tag)"
	@echo "  make run VERSION=1.0.3     Deploy a specific version"
	@echo "  make run-dry               Shortcut to: make run --dry"
	@echo "  make run --dry             Preview commands without executing"
	@echo ""
	@echo "Variables you can override:"
	@echo "  IMAGE_REPOSITORY=$(IMAGE_REPOSITORY)"
	@echo "  DOCKERFILE_PATH=$(DOCKERFILE_PATH)"
	@echo "  K8S_DIR=$(K8S_DIR)"
	@echo "  KUSTOMIZATION_FILE=$(KUSTOMIZATION_FILE)"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  DEPLOYMENT_NAME=$(DEPLOYMENT_NAME)"
	@echo "  VERSION=$(VERSION)"

run: check-version check-tools check-files
	@echo "[make] Deploying version $(VERSION)"
	@docker build \
		--file "$(DOCKERFILE_PATH)" \
		--target production \
		--tag "$(IMAGE_REPOSITORY):$(VERSION)" \
		--tag "$(IMAGE_REPOSITORY):latest" \
		.
	@docker push "$(IMAGE_REPOSITORY):$(VERSION)"
	@docker push "$(IMAGE_REPOSITORY):latest"
	@IMAGE_REPOSITORY_ESCAPED="$$(printf '%s' "$(IMAGE_REPOSITORY)" | sed -e 's/[][\\/.*^$$+?|(){}-]/\\&/g')"; \
	grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$IMAGE_REPOSITORY_ESCAPED[[:space:]]*$$" "$(KUSTOMIZATION_FILE)" || { \
		echo "[make] ERROR: Image '$(IMAGE_REPOSITORY)' not found in $(KUSTOMIZATION_FILE)"; \
		exit 1; \
	}; \
	sed -i -E "/^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$IMAGE_REPOSITORY_ESCAPED[[:space:]]*$$/{n;s/^([[:space:]]*newTag:[[:space:]]*).*/\\1$(VERSION)/;}" "$(KUSTOMIZATION_FILE)"
	@kubectl apply -k "$(K8S_DIR)"
	@kubectl -n "$(NAMESPACE)" rollout status "deployment/$(DEPLOYMENT_NAME)" --timeout=180s
	@echo "[make] Deployment finished successfully."

run-dry:
	@$(MAKE) --no-print-directory --dry-run run VERSION="$(VERSION)"

dry: run-dry

check-tools:
	@command -v docker >/dev/null 2>&1 || { echo "[make] ERROR: docker is required"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "[make] ERROR: kubectl is required"; exit 1; }
	@command -v sed >/dev/null 2>&1 || { echo "[make] ERROR: sed is required"; exit 1; }
	@command -v grep >/dev/null 2>&1 || { echo "[make] ERROR: grep is required"; exit 1; }

check-files:
	@test -f "$(DOCKERFILE_PATH)" || { echo "[make] ERROR: Missing $(DOCKERFILE_PATH)"; exit 1; }
	@test -f "$(KUSTOMIZATION_FILE)" || { echo "[make] ERROR: Missing $(KUSTOMIZATION_FILE)"; exit 1; }
	@test -f "$(K8S_DIR)/app/secret.env" || { echo "[make] ERROR: Missing $(K8S_DIR)/app/secret.env"; exit 1; }
	@test -f "$(K8S_DIR)/mysql/secret.env" || { echo "[make] ERROR: Missing $(K8S_DIR)/mysql/secret.env"; exit 1; }
	@test -f "$(K8S_DIR)/app/registry-credentials.json" || { echo "[make] ERROR: Missing $(K8S_DIR)/app/registry-credentials.json"; exit 1; }

check-version:
	@[[ "$(VERSION)" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$$ ]] || { \
		echo "[make] ERROR: Invalid VERSION='$(VERSION)'"; \
		echo "[make] Expected Docker tag format: [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}"; \
		exit 1; \
	}
