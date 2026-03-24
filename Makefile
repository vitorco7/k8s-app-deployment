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

.PHONY: help deploy publish release deploy-dry publish-dry release-dry run build run-dry build-dry dry version stop-pods terraform-destroy check-run-tools check-release-tools check-run-files check-release-files check-version

help:
	@echo "Targets:"
	@echo "  make deploy                Deploy current version (terraform + kubernetes)"
	@echo "  make publish               Build + publish + version bump (no deploy)"
	@echo "  make release               Full pipeline: build + publish + version bump + deploy"
	@echo "  make publish V=1.0.3       Override publish version manually"
	@echo "  make release V=1.0.3       Override release/publish version manually"
	@echo "  make version               Show current and next patch version from kustomization"
	@echo "  make publish-dry           Dry run for build + publish + version bump"
	@echo "  make deploy-dry            Dry run for terraform + kubernetes deployment"
	@echo "  make release-dry           Dry run for the full release pipeline"
	@echo "  make deploy DRY_RUN=true   Same as deploy-dry"
	@echo "  make publish DRY_RUN=true  Same as publish-dry"
	@echo "  make deploy --dry          Raw GNU Make preview (prints recipe text only)"
	@echo "  make run                   Alias of deploy"
	@echo "  make build                 Alias of publish"
	@echo "  make stop-pods             Scale all deployments in namespace to 0 replicas"
	@echo "  make terraform-destroy     Run terraform destroy in the terraform directory"
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

deploy: check-run-tools check-run-files
	@set -euo pipefail; \
	dry_run="$(DRY_RUN)"; \
	run_cmd() { \
		if [[ "$$dry_run" == "true" ]]; then \
			printf '[make][dry-run] %s\n' "$$*"; \
		else \
			"$$@"; \
		fi; \
	}; \
	ensure_minikube_running() { \
		if [[ "$$dry_run" == "true" ]]; then \
			echo "[make][dry-run] Check minikube status before applying manifests"; \
			printf '[make][dry-run] %s\n' "minikube status --format={{.Host}}|{{.Kubelet}}|{{.APIServer}}"; \
			printf '[make][dry-run] %s\n' "minikube start"; \
			return 0; \
		fi; \
		minikube_status="$$(minikube status --format='{{.Host}}|{{.Kubelet}}|{{.APIServer}}' 2>/dev/null || true)"; \
		if [[ "$$minikube_status" != "Running|Running|Running" ]]; then \
			echo "[make] Minikube is not running. Starting minikube..."; \
			minikube start; \
		else \
			echo "[make] Minikube is already running."; \
		fi; \
	}; \
	echo "[make] Running Terraform workflow (init -> plan -> apply)"; \
	run_cmd terraform -chdir="$(TERRAFORM_DIR)" init; \
	run_cmd terraform -chdir="$(TERRAFORM_DIR)" plan; \
	run_cmd terraform -chdir="$(TERRAFORM_DIR)" apply; \
	ensure_minikube_running; \
	echo "[make] Waiting for all nodes to be Ready..."; \
	if [[ "$$dry_run" == "true" ]]; then \
		printf '[make][dry-run] %s\n' "kubectl wait --for=condition=Ready nodes --all --timeout=120s"; \
	else \
		kubectl wait --for=condition=Ready nodes --all --timeout=120s; \
	fi; \
	echo "[make] Applying Kubernetes manifests"; \
	run_cmd kubectl apply -k "$(K8S_DIR)"; \
	run_cmd kubectl -n "$(NAMESPACE)" rollout status "deployment/$(DEPLOYMENT_NAME)" --timeout=180s; \
	if [[ "$$dry_run" == "true" ]]; then \
		echo "[make] Dry-run finished. No changes were applied."; \
	else \
		echo "[make] Deployment finished successfully."; \
	fi

run: deploy

publish: check-release-tools check-release-files
	@set -euo pipefail; \
	dry_run="$(DRY_RUN)"; \
	run_cmd() { \
		if [[ "$$dry_run" == "true" ]]; then \
			printf '[make][dry-run] %s\n' "$$*"; \
		else \
			"$$@"; \
		fi; \
	}; \
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
			echo "[make] Set one manually in $(KUSTOMIZATION_FILE) or run: make publish V=1.0.0"; \
			exit 1; \
		}; \
		IFS='.' read -r major minor patch <<< "$$current_version"; \
		target_version="$$major.$$minor.$$((patch + 1))"; \
		echo "[make] Current version: $$current_version"; \
		echo "[make] Next patch version: $$target_version"; \
	else \
		echo "[make] Using manual publish version: $$target_version"; \
	fi; \
	[[ "$$target_version" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$$ ]] || { \
		echo "[make] ERROR: Invalid publish version '$$target_version'"; \
		echo "[make] Expected Docker tag format: [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}"; \
		exit 1; \
	}; \
	IMAGE_REPOSITORY_ESCAPED="$$(printf '%s' "$(IMAGE_REPOSITORY)" | sed -e 's/[][\\/.*^$$+?|(){}-]/\\&/g')"; \
	grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$IMAGE_REPOSITORY_ESCAPED[[:space:]]*$$" "$(KUSTOMIZATION_FILE)" || { \
		echo "[make] ERROR: Image '$(IMAGE_REPOSITORY)' not found in $(KUSTOMIZATION_FILE)"; \
		exit 1; \
	}; \
	echo "[make] Building and publishing image $$target_version"; \
	run_cmd docker build \
		--file "$(DOCKERFILE_PATH)" \
		--target production \
		--tag "$(IMAGE_REPOSITORY):$$target_version" \
		--tag "$(IMAGE_REPOSITORY):latest" \
		.; \
	run_cmd docker push "$(IMAGE_REPOSITORY):$$target_version"; \
	run_cmd docker push "$(IMAGE_REPOSITORY):latest"; \
	run_cmd sed -i -E "/^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$IMAGE_REPOSITORY_ESCAPED[[:space:]]*$$/{n;s/^([[:space:]]*newTag:[[:space:]]*).*/\\1$$target_version/;}" "$(KUSTOMIZATION_FILE)"; \
	if [[ "$$dry_run" == "true" ]]; then \
		echo "[make] Build dry-run finished. No changes were applied."; \
	else \
		echo "[make] Build pipeline finished successfully."; \
	fi

build: publish

release:
	@set -euo pipefail; \
	dry_run="$(DRY_RUN)"; \
	echo "[make] Starting full release pipeline (publish + deploy)"; \
	$(MAKE) --no-print-directory publish DRY_RUN="$$dry_run" VERSION="$(VERSION)"; \
	$(MAKE) --no-print-directory deploy DRY_RUN="$$dry_run"

publish-dry:
	@$(MAKE) --no-print-directory publish DRY_RUN=true VERSION="$(VERSION)"

build-dry: publish-dry

release-dry:
	@$(MAKE) --no-print-directory release DRY_RUN=true VERSION="$(VERSION)"

deploy-dry:
	@$(MAKE) --no-print-directory deploy DRY_RUN=true

run-dry: deploy-dry

dry: deploy-dry

version: check-release-tools check-release-files
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

stop-pods: check-run-tools
	@set -euo pipefail; \
	echo "[make] Scaling all deployments and statefulsets in namespace '$(NAMESPACE)' to 0 replicas"; \
	kubectl -n "$(NAMESPACE)" scale deployment --all --replicas=0; \
	kubectl -n "$(NAMESPACE)" scale statefulset --all --replicas=0; \
	echo "[make] All deployments and statefulsets scaled down."

terraform-destroy:
	@command -v terraform >/dev/null 2>&1 || { echo "[make] ERROR: terraform is required"; exit 1; }
	@test -f "$(TERRAFORM_DIR)/main.tf" || { echo "[make] ERROR: Missing $(TERRAFORM_DIR)/main.tf"; exit 1; }
	@set -euo pipefail; \
	echo "[make] Running terraform destroy in $(TERRAFORM_DIR)"; \
	terraform -chdir="$(TERRAFORM_DIR)" destroy; \
	echo "[make] Terraform destroy complete."

check-run-tools:
	@command -v kubectl >/dev/null 2>&1 || { echo "[make] ERROR: kubectl is required"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "[make] ERROR: terraform is required"; exit 1; }
	@command -v minikube >/dev/null 2>&1 || { echo "[make] ERROR: minikube is required"; exit 1; }

check-release-tools:
	@command -v docker >/dev/null 2>&1 || { echo "[make] ERROR: docker is required"; exit 1; }
	@command -v awk >/dev/null 2>&1 || { echo "[make] ERROR: awk is required"; exit 1; }
	@command -v sed >/dev/null 2>&1 || { echo "[make] ERROR: sed is required"; exit 1; }
	@command -v grep >/dev/null 2>&1 || { echo "[make] ERROR: grep is required"; exit 1; }

check-run-files:
	@test -f "$(TERRAFORM_DIR)/main.tf" || { echo "[make] ERROR: Missing $(TERRAFORM_DIR)/main.tf"; exit 1; }
	@test -f "$(KUSTOMIZATION_FILE)" || { echo "[make] ERROR: Missing $(KUSTOMIZATION_FILE)"; exit 1; }
	@test -f "$(K8S_DIR)/app/secret.env" || { echo "[make] ERROR: Missing $(K8S_DIR)/app/secret.env"; exit 1; }
	@test -f "$(K8S_DIR)/mysql/secret.env" || { echo "[make] ERROR: Missing $(K8S_DIR)/mysql/secret.env"; exit 1; }
	@test -f "$(K8S_DIR)/app/registry-credentials.json" || { echo "[make] ERROR: Missing $(K8S_DIR)/app/registry-credentials.json"; exit 1; }

check-release-files:
	@test -f "$(DOCKERFILE_PATH)" || { echo "[make] ERROR: Missing $(DOCKERFILE_PATH)"; exit 1; }
	@test -f "$(KUSTOMIZATION_FILE)" || { echo "[make] ERROR: Missing $(KUSTOMIZATION_FILE)"; exit 1; }

check-version:
	@[[ -n "$(VERSION)" ]] || { echo "[make] ERROR: VERSION is required for check-version"; exit 1; }
	@[[ "$(VERSION)" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$$ ]] || { \
		echo "[make] ERROR: Invalid VERSION='$(VERSION)'"; \
		echo "[make] Expected Docker tag format: [A-Za-z0-9_][A-Za-z0-9_.-]{0,127}"; \
		exit 1; \
	}
