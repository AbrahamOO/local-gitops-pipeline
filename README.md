## Run GitOps Locally with Argo CD, Kind, and FastAPI

Think of this repository as your classroom lab. You will:

- Package a FastAPI service with Helm.
- Let Argo CD keep a Kind cluster in sync with your Git history.
- Prove the CI/CD story end-to-end, including local GitHub Actions runs via `act`.

Throughout this guide substitute **`YOUR_GITHUB_USERNAME`** wherever you see that placeholder (for example, the GHCR repo path).

---

### 1. Prepare your toolbox

| Tool    | Why you need it                     | Quick check                   |
| ------- | ----------------------------------- | ----------------------------- |
| Docker  | Builds/pushes images, backs Kind    | `docker ps`                   |
| Kind    | Spins up the Kubernetes lab env     | `kind version`                |
| kubectl | Talks to the cluster                | `kubectl version --client`    |
| Helm    | Renders our chart                   | `helm version`                |
| Act     | Replays GitHub Actions locally      | `act --version`               |
| Git     | Version control                     | `git --version`               |

Install missing tools (Homebrew/Chocolatey or your distro’s package manager work). Start Docker Desktop before you move on.

---

### 2. Clone this repository

If you have not cloned the code yet, run:

```bash
git clone <repository-url>
cd local-gitops-pipeline
```

> Working on the FastAPI app outside of Docker? Create a virtual environment and install dependencies:
>
> ```bash
> python3 -m venv .venv
> source .venv/bin/activate
> pip install -r app/requirements.txt
> uvicorn app.main:app --reload
> ```

### 3. Open the project folder

```
File → Open Folder → local-gitops-pipeline
```

Open the VS Code terminal (`Ctrl + \``). Every command below assumes you run it from the repository root.

---

### 4. Bootstrap Kind and Argo CD

```bash
bash scripts/setup_kind.sh
```

The script:

1. Ensures a Kind cluster named `gitops-lab` exists.
2. Installs the official Argo CD manifests into the `argocd` namespace.
3. Waits until every Argo component is Ready.

Need a different cluster name or Argo version?

```bash
CLUSTER_NAME=dev-gitops ARGOCD_VERSION=v2.11.3 bash scripts/setup_kind.sh
```

---

### 5. Log into Argo CD

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open <http://localhost:8080> and sign in:

- **Username:** `admin`
- **Password:**

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d && echo
  ```

Leave this port-forward running if you want to monitor syncs.

---

### 6. Build/push the app image (local registry path)

```bash
docker compose up -d
docker build -t localhost:5000/myapp:latest ./app
docker push localhost:5000/myapp:latest
```

Edit `helm/myapp/values.yaml` so it points to the registry you just used:

```yaml
image:
  repository: localhost:5000/myapp
  tag: latest
  digest: ""
```

> Need to stay completely offline? Run `scripts/load-image-into-kind.sh`. It loads the freshly built image straight into Kind so Kubernetes never tries to reach a registry (make sure `image.digest` remains empty).

---

### 7. Register the app with Argo CD

```bash
kubectl apply -k manifests/
```

This creates the `gitops` namespace and an Argo CD `Application` pointing to `helm/myapp` in this repository (`main` branch). You should now see `myapp` listed in the Argo CD UI.

---

### 8. Sync and verify

In the Argo CD dashboard: **myapp → Sync**. Argo will clone this repo, render the Helm chart, and apply it to the `gitops` namespace.

Watch the rollout from the terminal:

```bash
kubectl get pods -n gitops
```

You are looking for `READY 1/1` and `STATUS Running`.

---

### 9. Reach the FastAPI service

The service name follows the `<release>-<chart>` pattern (`myapp-myapp`). Port-forward it:

```bash
kubectl port-forward svc/myapp-myapp -n gitops 8000:8000
curl http://localhost:8000
```

Expected response:

```json
{"message":"Hello from <pod-name> - GitOps works!"}
```

---

### 10. Reproduce the CI workflow with `act`

GitHub’s hosted runners already have everything we need, but running the workflow locally requires a compatible image. Build it once:

```bash
docker buildx build --platform linux/amd64 -t local/act-ubuntu:amd64 \
  -f docker/act-runner/Dockerfile . --load
```

Then run:

```bash
act push --job build --container-architecture linux/amd64 \
  -P ubuntu-latest=local/act-ubuntu:amd64 --pull=false
```

What happens:

1. Docker image build and smoke test (FastAPI container must respond on port 8000).
2. `helm lint` validation of the chart.
3. No GHCR publishing locally (the workflow short-circuits when the actor is `nektos/act`), but on GitHub the workflow builds multi-arch images, pushes to `ghcr.io/YOUR_GH_USERNAME/myapp`, updates `helm/myapp/values.yaml` with the new tag + digest, and opens a pull request.

---

### 11. Practice the GitOps loop

1. Modify `app/main.py` (change the greeting text, add a new endpoint—anything visible).
2. Rebuild/push the image (or run `scripts/load-image-into-kind.sh`).
3. Wait ~60 seconds. Argo CD sees the new artifact, rolls out a fresh Deployment, and your curl output updates automatically.

---

### 12. Frequently asked questions

**Q: Do I have to use `localhost:5000`?**  
A: No. Point `helm/myapp/values.yaml` to any registry you control (Docker Hub, GHCR, Harbor, etc.). Just remember to push the image there and, if needed, configure imagePullSecrets.

**Q: Where do I set `YOUR_GITHUB_USERNAME`?**  
A: Search the repo for that placeholder (values file, manifests, README). Replace it with your actual account before committing.

**Q: Can I skip Kind and run this on another cluster?**  
A: Yes, as long as kubectl context points to a cluster where you have admin rights. Reuse the Argo CD install steps, but be sure to update any load balancer or ingress settings to match your environment.

**Q: Why does `act` insist on `linux/amd64`?**  
A: GitHub-hosted runners for Ubuntu jobs are amd64. Matching that architecture locally avoids surprises with multi-arch Docker builds and platform-specific binaries.

---

### 13. Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `ErrImagePull` / `ImagePullBackOff` | Cluster cannot reach your registry | Push to GHCR/Docker Hub, allow insecure registry in Kind config, or run `scripts/load-image-into-kind.sh`. |
| Argo CD `SyncError: namespace "gitops" not found` | You deleted the namespace | Re-run `kubectl apply -k manifests/`. |
| Port-forward fails with `service "myapp" not found` | Helm named the service `myapp-myapp` | Use `kubectl port-forward svc/myapp-myapp -n gitops 8000:8000`. |
| `act` complains about missing runner image | Build the provided runner (`docker/act-runner/Dockerfile`) and pass `-P ubuntu-latest=local/act-ubuntu:amd64 --pull=false`. |
| GHCR rejects pushes with 403 | Package is private and the cluster lacks credentials | Either make the GHCR package public or create an imagePullSecret in the `gitops` namespace. |

Helpful reset commands:

```bash
kind delete cluster --name gitops-lab
kubectl delete application myapp -n argocd --ignore-not-found
kubectl delete namespace gitops --ignore-not-found
```

---

### 14. Command cheat sheet

```bash
# Build + push app
docker build -t localhost:5000/myapp:latest ./app
docker push localhost:5000/myapp:latest

# Load image into Kind instead of pushing
scripts/load-image-into-kind.sh

# Apply Argo resources
kubectl apply -k manifests/

# Watch resources
kubectl get app -n argocd
kubectl get pods -n gitops -w
```

---

### 15. Keep exploring

1. Wire Argo CD notifications (Slack, Teams, or Discord).
2. Add Prometheus + Grafana via Helm for visibility.
3. Create `manifests/dev`, `manifests/staging`, `manifests/prod` overlays and drive environment promotion with Git branches.
4. Extend `.github/workflows/ci.yml` with Trivy, Hadolint, or policy checks.
5. Build a `.devcontainer/` so new contributors land in a fully provisioned environment.

You now have a complete local GitOps playground—experiment freely and teach others how Git, Kubernetes, and CI/CD fit together. Happy shipping!
