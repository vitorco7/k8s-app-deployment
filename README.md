# k8s-app-deployment

Production-grade Kubernetes deployment case study for a TypeScript/Express API using MariaDB.

This repository focuses on:
- Containerization and release flow
- Kubernetes manifests with high-availability scheduling constraints
- Terraform-based local cluster provisioning (Minikube)
- Operational runbook-style documentation for quick local evaluation

## Interviewer Quick Start (Recommended Path)

If you only want to run the project locally and validate the API, use this path.

### 1) Prerequisites

Install these tools first:
- Docker
- Minikube
- kubectl
- Terraform `>= 1.6`
- GNU Make

Recommended machine capacity for default cluster settings:
- At least `8 vCPU` and `16 GB RAM` available to Docker/Minikube

Why: the default Terraform config creates `1 control-plane + 3 worker nodes`, each worker sized to `2 CPU / 4 GB`.

### 2) Clone the repository

```bash
git clone <your-repo-url>
cd k8s-app-deployment
```

### 3) Create required local files (not committed to git)

These files are intentionally ignored by git and must exist locally before deployment:

```bash
cp k8s/app/secret.env.example k8s/app/secret.env
cp k8s/mysql/secret.env.example k8s/mysql/secret.env
cp k8s/app/registry-credentials.json.example k8s/app/registry-credentials.json
```

Then edit values:
- Ensure `k8s/app/secret.env` and `k8s/mysql/secret.env` use matching DB credentials.
- Add `TYPEORM_SYNCHRONIZE=true` to `k8s/app/secret.env` for first local run.
- For `publish`/`release`, set real Docker Hub credentials in `k8s/app/registry-credentials.json`.

Minimal working local example:

```dotenv
# k8s/app/secret.env
TYPEORM_USERNAME=app
TYPEORM_PASSWORD=changeme
TYPEORM_SYNCHRONIZE=true
```

```dotenv
# k8s/mysql/secret.env
MYSQL_ROOT_PASSWORD=changeme-root
MYSQL_DATABASE=app
MYSQL_USER=app
MYSQL_PASSWORD=changeme
```

### 4) Deploy

```bash
make deploy
```

What this does:
- Provisions/recreates Minikube through Terraform (`init -> plan -> apply`)
- Applies Kubernetes manifests via Kustomize
- Waits for deployment rollout

Important behavior:
- `make deploy` recreates the Minikube profile defined in Terraform (default profile: `minikube`).

### 5) Validate cluster and workloads

```bash
kubectl get nodes
kubectl -n k8s-app get pods -o wide
kubectl -n k8s-app get ingress
kubectl -n k8s-app get svc
```

### 6) Call the API

Option A (no hosts file changes):

```bash
curl -i -H "Host: api.k8s-app.local" "http://$(minikube ip)/posts"
```

Option B (friendlier URL):

```bash
echo "$(minikube ip) api.k8s-app.local" | sudo tee -a /etc/hosts
curl -i http://api.k8s-app.local/posts
```

Create a sample post:

```bash
curl -i \
  -H "Host: api.k8s-app.local" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"title":"hello","text":"from interview run","categories":[{"name":"demo"}]}' \
  "http://$(minikube ip)/posts"
```

## 5-Minute Demo Script (Interviewer)

Use this when you want a fast, deterministic walkthrough during evaluation.

Assumption:
- Prerequisites are installed and local secret files are already created from the examples.

Note:
- First run on a cold machine can take longer than 5 minutes because Minikube image pulls and cluster startup may take extra time.

### 1) Tool sanity check

```bash
docker --version
minikube version
kubectl version --client
terraform version
make --version
```

Expected:
- All commands return a version successfully.

If this fails:
- Install the missing tool and re-run this block.

### 2) Deploy everything

```bash
make deploy
```

Expected:
- Terraform `init/plan/apply` completes.
- Kubernetes rollout finishes with no errors.

If this fails:
- Re-check required local files:
  - `k8s/app/secret.env`
  - `k8s/mysql/secret.env`
  - `k8s/app/registry-credentials.json`
- Check `kubectl config current-context` and `minikube status`.

### 3) Confirm cluster health

```bash
kubectl get nodes
kubectl -n k8s-app get pods -o wide
kubectl -n k8s-app get ingress
kubectl -n k8s-app get svc
```

Expected:
- Nodes are `Ready`.
- App and mysql pods are `Running` (or app may be briefly `ContainerCreating` during image pull).
- Ingress `app` exists.

If this fails:
- `kubectl -n k8s-app describe pod <failing-pod>`
- `kubectl -n k8s-app logs <failing-pod> --all-containers`

### 4) Functional API check (GET + POST + GET)

```bash
MINIKUBE_IP="$(minikube ip)"

curl -sS -i -H "Host: api.k8s-app.local" "http://${MINIKUBE_IP}/posts"

curl -sS -i \
  -H "Host: api.k8s-app.local" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"title":"interview-demo","text":"hello from demo","categories":[{"name":"demo"}]}' \
  "http://${MINIKUBE_IP}/posts"

curl -sS -i -H "Host: api.k8s-app.local" "http://${MINIKUBE_IP}/posts"
```

Expected:
- First GET returns `200` with an array (possibly empty).
- POST returns `200` with created object including `id`.
- Final GET returns the inserted post.

If this fails:
- Confirm ingress host header is present (`Host: api.k8s-app.local`).
- Check app logs:
  - `kubectl -n k8s-app logs deployment/app --tail=100`

### 5) High-availability evidence (quick proof)

```bash
kubectl get nodes --show-labels | grep topology.kubernetes.io/zone
kubectl -n k8s-app get pods -l app.kubernetes.io/name=app -o wide
```

Expected:
- Worker nodes show `topology.kubernetes.io/zone` labels.
- App pods are spread across multiple nodes (subject to current cluster capacity).

### 6) Optional cleanup

```bash
make terraform-destroy
```

Expected:
- Minikube profile is removed cleanly.

## Project Overview

### Compact Architecture Diagram

```mermaid
flowchart LR
  U[Interviewer curl/postman] -->|Host: api.k8s-app.local| ING[NGINX Ingress]
  ING --> SVC[Service app (ClusterIP:80)]
  SVC --> APP[Deployment app (9 pods / 3 zones)]
  APP --> DB[(MariaDB StatefulSet + PVC)]

  M[make deploy/release] --> OPS[Terraform + kubectl apply -k]
  OPS --> K8S[Minikube cluster (1 control-plane + 3 workers)]
  K8S --> ING
  K8S --> APP
  K8S --> DB
```

### API

Endpoints:
- `GET /posts`
- `GET /posts/:id`
- `POST /posts`

Application stack:
- Node.js + Express
- TypeORM
- MariaDB

### Kubernetes architecture

- Namespace: `k8s-app`
- App deployment:
  - `9` replicas
  - `topologySpreadConstraints` across zones and hostnames
  - `PodDisruptionBudget` with `minAvailable: 2`
  - non-root runtime security context
- Database:
  - MariaDB `StatefulSet` with `1` replica and persistent volume claim
- Traffic:
  - `Ingress` host: `api.k8s-app.local`
  - App service type: `ClusterIP` on port `80` to pod `3000`

### Infrastructure provisioning

Terraform provisions a local Minikube environment and applies zone labels used by scheduling constraints.

Default zones:
- `zone-a`
- `zone-b`
- `zone-c`

## Makefile Commands

Primary commands:
- `make deploy`: deploy current version from `k8s/kustomization.yaml`
- `make publish`: build image, push tags, bump `newTag` in kustomization
- `make release`: full pipeline (`publish + deploy`)

Dry-run helpers:
- `make deploy-dry`
- `make publish-dry`
- `make release-dry`

Compatibility aliases:
- `make run` -> alias for `make deploy`
- `make build` -> alias for `make publish`

Version helpers:
- `make version`
- `make publish V=1.0.3`
- `make release V=1.0.3`

Cleanup:
- `make terraform-destroy`
- `make stop-pods`

## Release Flow Notes

`make publish` expects the image name in `k8s/kustomization.yaml` to match `IMAGE_REPOSITORY`.

Defaults:
- `IMAGE_REPOSITORY=vco7/k8s-app-deployment`
- `KUSTOMIZATION_FILE=k8s/kustomization.yaml`

If you want to publish to a different repository:
1. Update the image `name` in `k8s/kustomization.yaml`
2. Run `make publish IMAGE_REPOSITORY=<your-user>/<your-repo> V=<version>`

## Configuration and Files

Required local files:
- `k8s/app/secret.env`
- `k8s/mysql/secret.env`
- `k8s/app/registry-credentials.json`

Template files:
- `k8s/app/secret.env.example`
- `k8s/mysql/secret.env.example`
- `k8s/app/registry-credentials.json.example`

Common overrides:
- `IMAGE_REPOSITORY`
- `DOCKERFILE_PATH`
- `TERRAFORM_DIR`
- `K8S_DIR`
- `KUSTOMIZATION_FILE`
- `NAMESPACE`
- `DEPLOYMENT_NAME`
- `VERSION` (or shorthand `V`)

## Troubleshooting

`curl localhost:3000` fails after Kubernetes deploy:
- Expected in this setup.
- The k8s entrypoint is ingress host `api.k8s-app.local`, not host port `3000`.
- Use `curl -H "Host: api.k8s-app.local" "http://$(minikube ip)/posts"`.

Pods stuck in `ImagePullBackOff`:
- Check `k8s/app/registry-credentials.json` exists and is valid.
- If using a private image, ensure credentials/token are correct.

App pod running but `/posts` errors with DB/table issues:
- Ensure app and mysql credentials match across both secret files.
- Ensure `TYPEORM_SYNCHRONIZE=true` is set for first local bootstrap.

Insufficient resources / scheduling failures:
- Increase Docker/Minikube CPU and memory allocation.
- Verify node labels and pod distribution:

```bash
kubectl get nodes --show-labels | grep topology.kubernetes.io/zone
kubectl -n k8s-app get pods -l app.kubernetes.io/name=app -o wide
```

## Repository Structure (High Level)

- `src/`: API source code (Express + TypeORM)
- `Dockerfiles/app/dockerfile.yaml`: multi-stage production image build
- `k8s/`: Kubernetes manifests and kustomization
- `terraform/`: local cluster provisioning and node zone labeling
- `Makefile`: deployment/release entrypoint

## Known Trade-offs

- MariaDB runs as a single replica StatefulSet (not multi-zone HA database).
- Terraform-driven deploy recreates Minikube profile for deterministic local runs, which can be destructive to an existing profile with the same name.
- `publish/release` assume container-registry push permissions.

## Optional Non-Kubernetes Local Mode

A simple container-compose path is also available for local app debugging:

```bash
docker compose up -d
curl -i http://localhost:3000/posts
```

Use this mode only for quick app-level debugging; the primary evaluation path is Kubernetes via `make deploy`.
