SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

IMAGE_REPOSITORY ?= vco7/k8s-app-deployment
DOCKERFILE_PATH ?= Dockerfiles/app/dockerfile.yaml
TERRAFORM_DIR ?= terraform
K8S_DIR ?= k8s
KUSTOMIZATION_FILE ?= $(K8S_DIR)/kustomization.yaml
NAMESPACE ?= k8s-app
DEPLOYMENT_NAME ?= app
VERSION ?=
V ?=
DRY_RUN ?= false

ifneq ($(strip $(V)),)
VERSION := $(V)
endif

.PHONY: help run release release-dry run-dry dry version check-tools check-files check-version

help:
	@echo "Targets:"
	@echo "  make run VERSION=1.0.3     Deploy a specific version (required)"
	@echo "  make release               Auto bump patch version from kustomization and deploy"
	@echo "  make release V=1.0.3       Override release version manually"
	@echo "  make version               Show current and next patch version from kustomization"
	@echo "  make run-dry VERSION=1.0.3 Dry run for explicit version"
	@echo "  make release-dry           Dry run with automatic patch bump"
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
	@echo "  VERSION=$(if $(strip $(VERSION)),$(VERSION),<empty>)"

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

release:
	@set -euo pipefail; \
	target_version="$(VERSION)"; \
	if [[ -z "$$target_version" ]]; then \
		current_version="$$(awk -v image="$(IMAGE_REPOSITORY)" '\
			BEGIN { match_image=0 } \
			/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ { \
				line=$$0; \
				sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line); \
				sub(/[[:space:]]*$$/, "", line); \
				match_image=(line==image); \
				next; \
			} \
			match_image && /^[[:space:]]*newTag:[[:space:]]*/ { \
				tag=$$0; \
				sub(/^[[:space:]]*newTag:[[:space:]]*/, "", tag); \
				sub(/[[:space:]]*$$/, "", tag); \
				print tag; \
				exit; \
			}' "$(KUSTOMIZATION_FILE)")"; \
		[[ -n "$$current_version" ]] || { \
			echo "[make] ERROR: Could not find current newTag for $(IMAGE_REPOSITORY) in $(KUSTOMIZATION_FILE)"; \
			exit 1; \
		}; \
		[[ "$$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]] || { \
			echo "[make] ERROR: Current tag '$$current_version' is not semantic version (x.y.z)."; \
			echo "[make] Set one manually in $(KUSTOMIZATION_FILE) or run: make release V=1.0.0"; \
			exit 1; \
		}; \
		IFS='.' read -r major minor patch <<< "$$current_version"; \
		target_version="$$major.$$minor.$$((patch + 1))"; \
		echo "[make] Current version: $$current_version"; \
		echo "[make] Next patch version: $$target_version"; \
	else \
		echo "[make] Using manual release version: $$target_version"; \
	fi; \
	$(MAKE) --no-print-directory run VERSION="$$target_version" DRY_RUN="$(DRY_RUN)"

release-dry:
	@$(MAKE) --no-print-directory release DRY_RUN=true VERSION="$(VERSION)"

run-dry:
	@$(MAKE) --no-print-directory run DRY_RUN=true VERSION="$(VERSION)"

dry: run-dry

version: check-files
	@set -euo pipefail; \
	current_version="$$(awk -v image="$(IMAGE_REPOSITORY)" '\
		BEGIN { match_image=0 } \
		/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ { \
			line=$$0; \
			sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line); \
			sub(/[[:space:]]*$$/, "", line); \
			match_image=(line==image); \
			next; \
		} \
		match_image && /^[[:space:]]*newTag:[[:space:]]*/ { \
			tag=$$0; \
			sub(/^[[:space:]]*newTag:[[:space:]]*/, "", tag); \
			sub(/[[:space:]]*$$/, "", tag); \
			print tag; \
			exit; \
		}' "$(KUSTOMIZATION_FILE)")"; \
	[[ -n "$$current_version" ]] || { \
		echo "[make] ERROR: Could not find current newTag for $(IMAGE_REPOSITORY) in $(KUSTOMIZATION_FILE)"; \
		exit 1; \
	}; \
	echo "[make] Current version: $$current_version"; \
	if [[ "$$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]]; then \
		IFS='.' read -r major minor patch <<< "$$current_version"; \
		echo "[make] Next patch version: $$major.$$minor.$$((patch + 1))"; \
	else \
		echo "[make] Current version is not semantic (x.y.z), so next patch cannot be calculated automatically."; \
	fi

check-tools:
	@command -v docker >/dev/null 2>&1 || { echo "[make] ERROR: docker is required"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "[make] ERROR: kubectl is required"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "[make] ERROR: terraform is required"; exit 1; }
	@command -v minikube >/dev/null 2>&1 || { echo "[make] ERROR: minikube is required"; exit 1; }
	@command -v awk >/dev/null 2>&1 || { echo "[make] ERROR: awk is required"; exit 1; }
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
	@[[ -n "$(VERSION)" ]] || { \
		echo "[make] ERROR: VERSION is required for 'make run'."; \
		echo "[make] Use: make run VERSION=1.0.2"; \
		echo "[make] Or use: make release (auto-increment patch from $(KUSTOMIZATION_FILE))"; \
		exit 1; \
	}
	@[[ "$(VERSION)" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$$ ]] || { \
		echo "[make] ERROR: Invalid VERSION='$(VERSION)'"; \
		echo "[make] Expected Docker tag format: [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}"; \
		exit 1; \
	}
