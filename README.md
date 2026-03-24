# k8s-app-deployment
Case study for app deployment with kubernetes

## Deploy

Use only `Makefile` as the deployment entrypoint:

```bash
make deploy
```

Run only build and publish pipeline (no deploy):

```bash
make publish
```

Run the full pipeline (build + publish + version bump + deploy):

```bash
make release
```

Build or release with manual override:

```bash
make publish V=1.0.2
make release V=1.0.2
```

Check current and next version from `k8s/kustomization.yaml`:

```bash
make version
```

Preview options:

```bash
make publish-dry
make deploy-dry
make release-dry
make publish DRY_RUN=true
make deploy DRY_RUN=true
make deploy --dry
```

Notes:
- `make deploy` deploys the current version already present in `k8s/kustomization.yaml`.
- `make publish` reads current `newTag` in `k8s/kustomization.yaml` for `vco7/k8s-app-deployment`, increments patch (`1.0.1 -> 1.0.2`), builds/pushes image, and updates tag in `k8s/kustomization.yaml` (without deploying).
- `make release` runs `make publish` and then `make deploy`.
- `make publish-dry` / `make deploy-dry` / `make release-dry` / `make publish DRY_RUN=true` / `make deploy DRY_RUN=true` are the recommended previews.
- `make deploy --dry` is GNU Make raw output (recipe text only), so it can look noisy and include fallback error branches that are not actually executed.
- Compatibility aliases: `make run` = `make deploy`, `make build` = `make publish`.

`make deploy` does:
- Runs Terraform workflow in `terraform/` (`init`, `plan`, `apply`)
- Applies manifests with `kubectl apply -k k8s/`
- Waits for rollout completion (`deployment/app` in `k8s-app` namespace)

`make publish` does:
- Builds the app image from `Dockerfiles/app/dockerfile.yaml` (`production` target)
- Pushes `<version>` and `latest` tags to Docker Hub
- Updates `k8s/kustomization.yaml` (`images[].newTag`)

`make release` does:
- Runs `make publish`
- Runs `make deploy` (Terraform + Kubernetes deployment)

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
- `VERSION` (optional manual override for `make publish` / `make release`)
- `V` (short alias for `VERSION`, useful with `make publish V=...` / `make release V=...`)
