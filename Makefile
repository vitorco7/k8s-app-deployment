SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

IMAGE_REPOSITORY ?= vco7/k8s-app-deployment

override DOCKERFILE_PATH := Dockerfiles/app/dockerfile.yaml
override TERRAFORM_DIR := terraform
override K8S_DIR := k8s
override KUSTOMIZATION_FILE := $(K8S_DIR)/kustomization.yaml
override NAMESPACE := k8s-app
override DEPLOYMENT_NAME := app

.PHONY: help run release version destroy

help:
	@echo "Commands:"
	@echo "  make run                Configure local k8s (Terraform + Minikube) and deploy app"
	@echo "  make release            Bump patch version, build + push image, update kustomization, then run"
	@echo "  make version            Show current release version (and next patch)"
	@echo "  make destroy            Run terraform destroy for local infrastructure"
	@echo "  make help               Show this help"
	@echo ""
	@echo "Optional overrides:"
	@echo "  IMAGE_REPOSITORY=$(IMAGE_REPOSITORY)"

run:
	@set -euo pipefail; \
	for tool in kubectl terraform minikube; do \
		command -v "$$tool" >/dev/null 2>&1 || { echo "[make] ERROR: $$tool is required"; exit 1; }; \
	done; \
	for required in "$(TERRAFORM_DIR)/main.tf" "$(KUSTOMIZATION_FILE)" "$(K8S_DIR)/app/secret.env" "$(K8S_DIR)/mysql/secret.env" "$(K8S_DIR)/app/registry-credentials.json"; do \
		[[ -f "$$required" ]] || { echo "[make] ERROR: Missing $$required"; exit 1; }; \
	done; \
	minikube_status="$$(minikube status --format='{{.Host}}|{{.Kubelet}}|{{.APIServer}}' 2>/dev/null || true)"; \
	if [[ "$$minikube_status" != "Running|Running|Running" ]]; then \
		echo "[make] Minikube is not running. Starting minikube..."; \
		minikube start; \
	else \
		echo "[make] Minikube is already running."; \
	fi; \
	echo "[make] Running Terraform workflow (init -> plan -> apply)"; \
	terraform -chdir="$(TERRAFORM_DIR)" init; \
	terraform -chdir="$(TERRAFORM_DIR)" plan; \
	terraform -chdir="$(TERRAFORM_DIR)" apply; \
	echo "[make] Waiting for all nodes to be Ready..."; \
	kubectl wait --for=condition=Ready nodes --all --timeout=120s; \
	echo "[make] Applying Kubernetes manifests"; \
	kubectl apply -k "$(K8S_DIR)"; \
	kubectl -n "$(NAMESPACE)" rollout status "deployment/$(DEPLOYMENT_NAME)" --timeout=180s; \
	echo "[make] Deployment finished successfully."

release:
	@set -euo pipefail; \
	for tool in docker awk sed grep; do \
		command -v "$$tool" >/dev/null 2>&1 || { echo "[make] ERROR: $$tool is required"; exit 1; }; \
	done; \
	for required in "$(DOCKERFILE_PATH)" "$(KUSTOMIZATION_FILE)"; do \
		[[ -f "$$required" ]] || { echo "[make] ERROR: Missing $$required"; exit 1; }; \
	done; \
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
		echo "[make] ERROR: Could not find newTag for $(IMAGE_REPOSITORY) in $(KUSTOMIZATION_FILE)"; \
		exit 1; \
	}; \
	[[ "$$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]] || { \
		echo "[make] ERROR: Current newTag '$$current_version' is not semantic version (x.y.z)."; \
		echo "[make] Set a semantic version in $(KUSTOMIZATION_FILE) and retry."; \
		exit 1; \
	}; \
	IFS='.' read -r major minor patch <<< "$$current_version"; \
	target_version="$$major.$$minor.$$((patch + 1))"; \
	echo "[make] Current release version: $$current_version"; \
	echo "[make] Releasing next patch version: $$target_version"; \
	[[ "$$target_version" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$$ ]] || { \
		echo "[make] ERROR: Invalid Docker tag '$$target_version'"; \
		exit 1; \
	}; \
	image_escaped="$$(printf '%s' "$(IMAGE_REPOSITORY)" | sed -e 's/[][\\/.*^$$+?|(){}-]/\\&/g')"; \
	grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$image_escaped[[:space:]]*$$" "$(KUSTOMIZATION_FILE)" || { \
		echo "[make] ERROR: Image '$(IMAGE_REPOSITORY)' not found in $(KUSTOMIZATION_FILE)"; \
		exit 1; \
	}; \
	echo "[make] Building image $(IMAGE_REPOSITORY):$$target_version"; \
	docker build \
		--file "$(DOCKERFILE_PATH)" \
		--target production \
		--tag "$(IMAGE_REPOSITORY):$$target_version" \
		--tag "$(IMAGE_REPOSITORY):latest" \
		.; \
	echo "[make] Pushing Docker tags"; \
	docker push "$(IMAGE_REPOSITORY):$$target_version"; \
	docker push "$(IMAGE_REPOSITORY):latest"; \
	sed -i -E "/^[[:space:]]*-[[:space:]]*name:[[:space:]]*$$image_escaped[[:space:]]*$$/{n;s/^([[:space:]]*newTag:[[:space:]]*).*/\\1$$target_version/;}" "$(KUSTOMIZATION_FILE)"; \
	echo "[make] Updated $(KUSTOMIZATION_FILE) with newTag=$$target_version"; \
	$(MAKE) --no-print-directory run

version:
	@set -euo pipefail; \
	command -v awk >/dev/null 2>&1 || { echo "[make] ERROR: awk is required"; exit 1; }; \
	[[ -f "$(KUSTOMIZATION_FILE)" ]] || { echo "[make] ERROR: Missing $(KUSTOMIZATION_FILE)"; exit 1; }; \
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
		echo "[make] ERROR: Could not find newTag for $(IMAGE_REPOSITORY) in $(KUSTOMIZATION_FILE)"; \
		exit 1; \
	}; \
	echo "[make] Current release version: $$current_version"; \
	if [[ "$$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$$ ]]; then \
		IFS='.' read -r major minor patch <<< "$$current_version"; \
		echo "[make] Next patch release: $$major.$$minor.$$((patch + 1))"; \
	fi

destroy:
	@set -euo pipefail; \
	command -v terraform >/dev/null 2>&1 || { echo "[make] ERROR: terraform is required"; exit 1; }; \
	[[ -f "$(TERRAFORM_DIR)/main.tf" ]] || { echo "[make] ERROR: Missing $(TERRAFORM_DIR)/main.tf"; exit 1; }; \
	echo "[make] Running terraform destroy in $(TERRAFORM_DIR)"; \
	terraform -chdir="$(TERRAFORM_DIR)" destroy; \
	echo "[make] Terraform destroy complete."
