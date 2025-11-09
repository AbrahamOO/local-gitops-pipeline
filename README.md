## local-gitops-pipeline — end-to-end lab

Deploy a FastAPI app to a Kind cluster that is kept in sync by Argo CD, and prove the same workflow through GitHub Actions locally via `act`.

---

## 1. Prerequisites

| Tool    | Purpose                    | Verify                         |
| ------- | -------------------------- | ------------------------------ |
| Docker  | Containers + registry      | `docker ps`                    |
| Kind    | Local Kubernetes cluster   | `kind version`                 |
| kubectl | Kubernetes CLI             | `kubectl version --client`     |
| Helm    | Package app as a chart     | `helm version`                 |
| Act     | Run GitHub Actions locally | `act --version`                |
| Git     | Repo management            | `git --version`                |

Install any missing tool via Homebrew/Chocolatey (or your package manager). Docker Desktop must be running before you interact with Kind.

---

## 2. Open the project

```text
File → Open Folder → local-gitops-pipeline
```

Open a VS Code terminal (`Ctrl + \``) inside this folder for all subsequent commands.

---

## 3. Create the Kind cluster and install Argo CD

```bash
bash scripts/setup_kind.sh
```

What happens:

1. A Kind cluster named `gitops-lab` is created (idempotent, reruns are safe).
2. The script installs the publicly maintained Argo CD manifest into the `argocd` namespace.
3. All Argo CD pods roll out and are verified before the script exits.

Need custom settings? Override via environment variables:

```bash
CLUSTER_NAME=dev-gitops ARGOCD_VERSION=v2.11.3 bash scripts/setup_kind.sh
```

---

## 4. Access the Argo CD dashboard

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Browse to <http://localhost:8080> and sign in with:

- Username: `admin`
- Password:

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
  ```

---

## 5. Start (optional but recommended) local registry

```bash
docker compose up -d
```

This exposes a registry on `localhost:5000`. Build and push the sample app into it:

```bash
docker build -t localhost:5000/myapp:latest ./app
docker push localhost:5000/myapp:latest
```

Tell Helm/Argo CD to use the image by editing `helm/myapp/values.yaml`:

```yaml
image:
  repository: localhost:5000/myapp
  tag: latest
  digest: ""
```

*Tip:* If you only need a very fast local iteration loop, run `scripts/load-image-into-kind.sh`. It builds the image and uses `kind load docker-image ...` so Kubernetes can start the pod without touching a registry. (The script exits if `image.digest` is pinned.)

---

## 6. Register the application with Argo CD

```bash
kubectl apply -k manifests/
```

This creates the `gitops` namespace plus an `Application` CR that points to `helm/myapp` in this repo. In the Argo CD UI you should now see the `myapp` entry.

---

## 7. Sync and deploy

In the Argo CD UI, open `myapp` → `Sync`. The controller will:

1. Pull this repo (`main` branch).
2. Render the Helm chart with the current `values.yaml`.
3. Apply it into the `gitops` namespace.

Inspect the rollout:

```bash
kubectl get pods -n gitops
```

Expected:

```
NAME                     READY   STATUS    RESTARTS   AGE
myapp-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

---

## 8. Access the FastAPI service

Port-forward the ClusterIP service:

```bash
kubectl port-forward svc/myapp -n gitops 8000:8000
```

Now:

```bash
curl localhost:8000
# {"message":"Hello from <pod-name> - GitOps works!"}
```

---

## 9. Run the CI workflow locally with Act

The `ci.yml` workflow builds the Docker image, smoke-tests it, and runs `helm lint`. Modern GitHub actions expect Node 20+ **and** Docker CLI availability, so we ship a tiny runner definition in `docker/act-runner/Dockerfile`. Build an amd64 copy (so the container matches GitHub’s architecture) once:

```bash
docker buildx build --platform linux/amd64 -t local/act-ubuntu:amd64 \
  -f docker/act-runner/Dockerfile . --load
```

Then run the workflow:

```bash
act push --job build --container-architecture linux/amd64 \
  -P ubuntu-latest=local/act-ubuntu:amd64 --pull=false
```

Notes:

- The first command builds the runner image (~250 MB). Subsequent `act` runs reuse it.
- On Apple Silicon, the `--container-architecture linux/amd64` flag is mandatory so Docker emulates the GitHub runner architecture.
- `--pull=false` tells `act` to use the local runner image instead of trying to pull it from Docker Hub.
- The `publish-ghcr.yml` workflow automatically skips under `act` because the actor is `nektos/act`. On GitHub it will push to GHCR and open a PR that updates `helm/myapp/values.yaml` with the new tag + digest.

---

## 10. Change the app and watch Argo CD reconcile

Edit `app/main.py`:

```python
return {"message": f"Hello from {hostname} - GitOps is ALIVE!"}
```

Rebuild and push:

```bash
docker build -t localhost:5000/myapp:latest ./app
docker push localhost:5000/myapp:latest
```

Within ~60 seconds (depending on your auto-sync interval) Argo CD notices the new tag/digest, updates the Deployment, and restarts the pod. Refresh `curl localhost:8000` to confirm the new text.

---

## 11. Troubleshooting

- `ImagePullBackOff` after pointing to `localhost:5000`: make sure you either (a) ran `scripts/load-image-into-kind.sh` or (b) `docker push`ed to the registry that the chart references. Kind nodes cannot reach `localhost` on your host; loading the image into Kind solves it.
- Forgot the Argo CD password? Re-run the command in section 4; the secret is recreated only when the namespace is deleted.
- Want to start fresh? `kind delete cluster --name gitops-lab`.

---

## 12. Next steps

1. Wire Argo CD notifications (Slack/Discord).
2. Add Prometheus + Grafana via Helm for observability.
3. Create per-environment overlays (`manifests/dev|staging|prod`).
4. Add a Trivy scan stage to `.github/workflows/ci.yml`.
5. Ship a `.devcontainer/` with kubectl, helm, kind, act pre-installed for teammates.
