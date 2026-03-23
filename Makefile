SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

IMAGE_REPOSITORY ?= vco7/k8s-app-deployment
DOCKERFILE_PATH ?= Dockerfiles/app/dockerfile.yaml
TERRAFORM_DIR ?= terraform
K8S_DIR ?= k8s
KUSTOMIZATION_FILE ?= $(K8S_DIR)/kustomization.yaml
NAMESPACE ?= k8s-app
DEPLOYMENT_NAME ?= app
VERSION ?= dev-$(shell date +%Y%m%d%H%M%S)
V ?=
DRY_RUN ?= false

ifneq ($(strip $(V)),)
VERSION := $(V)
endif

.PHONY: help run release run-dry dry version check-tools check-files check-version

help:
	@echo "Targets:"
	@echo "  make run                   Deploy using VERSION (default: generated timestamp tag)"
	@echo "  make run VERSION=1.0.3     Deploy a specific version"
	@echo "  make release V=1.0.3       Release alias for run (short version variable)"
	@echo "  make version               Show current VERSION and validate format"
	@echo "  make run-dry               Recommended dry run (validates + prints commands)"
	@echo "  make run DRY_RUN=true      Same as run-dry"
	@echo "  make run --dry             Raw GNU Make preview (prints recipe text only)"
	@echo ""
	@echo "Variables you can override:"
	@echo "  IMAGE_REPOSITORY=$(IMAGE_REPOSITORY)"
	@echo "  DOCKERFILE_PATH=$(DOCKERFILE_PATH)"
	@echo "  TERRAFORM_DIR=$(TERRAFORM_DIR)"
	@echo "  K8S_DIR=$(K8S_DIR)"
	@echo "  KUSTOMIZATION_FILE=$(KUSTOMIZATION_FILE)"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  DEPLOYMENT_NAME=$(DEPLOYMENT_NAME)"
	@echo "  VERSION=$(VERSION)"

run: check-version check-tools check-files
	@set -euo pipefail; \
	dry_run="$(DRY_RUN)"; \
	run_cmd() { \
		if [[ "$$dry_run" == "true" ]]; then \
			printf '[make][dry-run] %s\n' "$$*"; \
		else \
			"$$@"; \
		fi; \
	}; \
	echo "[make] Deploying version $(VERSION)"; \
	run_cmd docker build \
		--file "$(DOCKERFILE_PATH)" \
		--target production \
		--tag "$(IMAGE_REPOSITORY):$(VERSION)" \
		--tag "$(IMAGE_REPOSITORY):latest" \
		.; \
	run_cmd docker push "$(IMAGE_REPOSITORY):$(VERSION)"; \
	run_cmd docker push "$(IMAGE_REPOSITORY):latest"; \
	IMAGE_REPOSITORY_ESCAPED="$$(printf '%s' "$(IMAGE_REPOSITORY)" | sed -e 's/[][\\/.*^$$+?|(){}-]/\\&/g')"; \
	grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$IMAGE_REPOSITORY_ESCAPED[[:space:]]*$$" "$(KUSTOMIZATION_FILE)" || { \
		echo "[make] ERROR: Image '$(IMAGE_REPOSITORY)' not found in $(KUSTOMIZATION_FILE)"; \
		exit 1; \
	}; \
	run_cmd sed -i -E "/^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$IMAGE_REPOSITORY_ESCAPED[[:space:]]*$$/{n;s/^([[:space:]]*newTag:[[:space:]]*).*/\\1$(VERSION)/;}" "$(KUSTOMIZATION_FILE)"; \
	echo "[make] Running Terraform workflow (init -> plan -> apply)"; \
	run_cmd terraform -chdir="$(TERRAFORM_DIR)" init; \
	run_cmd terraform -chdir="$(TERRAFORM_DIR)" plan; \
	run_cmd terraform -chdir="$(TERRAFORM_DIR)" apply; \
	echo "[make] Applying Kubernetes manifests"; \
	run_cmd kubectl apply -k "$(K8S_DIR)"; \
	run_cmd kubectl -n "$(NAMESPACE)" rollout status "deployment/$(DEPLOYMENT_NAME)" --timeout=180s; \
	if [[ "$$dry_run" == "true" ]]; then \
		echo "[make] Dry-run finished. No changes were applied."; \
	else \
		echo "[make] Deployment finished successfully."; \
	fi

release: run

run-dry:
	@$(MAKE) --no-print-directory run DRY_RUN=true VERSION="$(VERSION)"

dry: run-dry

version: check-version
	@echo "[make] VERSION=$(VERSION)"

check-tools:
	@command -v docker >/dev/null 2>&1 || { echo "[make] ERROR: docker is required"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "[make] ERROR: kubectl is required"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "[make] ERROR: terraform is required"; exit 1; }
	@command -v minikube >/dev/null 2>&1 || { echo "[make] ERROR: minikube is required"; exit 1; }
	@command -v sed >/dev/null 2>&1 || { echo "[make] ERROR: sed is required"; exit 1; }
	@command -v grep >/dev/null 2>&1 || { echo "[make] ERROR: grep is required"; exit 1; }

check-files:
	@test -f "$(DOCKERFILE_PATH)" || { echo "[make] ERROR: Missing $(DOCKERFILE_PATH)"; exit 1; }
	@test -f "$(TERRAFORM_DIR)/main.tf" || { echo "[make] ERROR: Missing $(TERRAFORM_DIR)/main.tf"; exit 1; }
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
