# k8s-app-deployment
Case study for app deployment with kubernetes

## Deploy

Use only `Makefile` as the deployment entrypoint:

```bash
make run
```

To deploy a specific version:

```bash
make run VERSION=1.0.2
```

Release alias (same workflow as `run`):

```bash
make release V=1.0.2
```

Check version value and format:

```bash
make version
make version V=1.0.2
```

Preview options:

```bash
make run-dry
make run DRY_RUN=true
make run --dry
```

Notes:
- `make run-dry` / `make run DRY_RUN=true` are the recommended previews.
- `make run --dry` is GNU Make raw output (recipe text only), so it can look noisy and include fallback error branches that are not actually executed.

What it does:
- Builds the app image from `Dockerfiles/app/dockerfile.yaml` (`production` target)
- Pushes `<version>` and `latest` tags to Docker Hub
- Updates `k8s/kustomization.yaml` (`images[].newTag`)
- Runs Terraform workflow in `terraform/`:
  - `terraform init`
  - `terraform plan`
  - `terraform apply`
- Applies manifests with `kubectl apply -k k8s/`
- Waits for rollout completion (`deployment/app` in `k8s-app` namespace)

Required local files:
- `k8s/app/secret.env`
- `k8s/mysql/secret.env`
- `k8s/app/registry-credentials.json`

Optional environment overrides:
- `IMAGE_REPOSITORY` (default: `vco7/k8s-app-deployment`)
- `DOCKERFILE_PATH` (default: `Dockerfiles/app/dockerfile.yaml`)
- `TERRAFORM_DIR` (default: `terraform`)
- `K8S_DIR` (default: `k8s`)
- `KUSTOMIZATION_FILE` (default: `k8s/kustomization.yaml`)
- `NAMESPACE` (default: `k8s-app`)
- `DEPLOYMENT_NAME` (default: `app`)
- `VERSION` (default: generated timestamp tag)
- `V` (short alias for `VERSION`, useful with `make release V=...`)
