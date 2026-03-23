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

Preview options:

```bash
make run-dry
make run --dry
```

What it does:
- Builds the app image from `Dockerfiles/app/dockerfile.yaml` (`production` target)
- Pushes `<version>` and `latest` tags to Docker Hub
- Updates `k8s/kustomization.yaml` (`images[].newTag`)
- Applies manifests with `kubectl apply -k k8s/`
- Waits for rollout completion (`deployment/app` in `k8s-app` namespace)

Required local files:
- `k8s/app/secret.env`
- `k8s/mysql/secret.env`
- `k8s/app/registry-credentials.json`

Optional environment overrides:
- `IMAGE_REPOSITORY` (default: `vco7/k8s-app-deployment`)
- `DOCKERFILE_PATH` (default: `Dockerfiles/app/dockerfile.yaml`)
- `K8S_DIR` (default: `k8s`)
- `KUSTOMIZATION_FILE` (default: `k8s/kustomization.yaml`)
- `NAMESPACE` (default: `k8s-app`)
- `DEPLOYMENT_NAME` (default: `app`)
- `VERSION` (default: generated timestamp tag)
