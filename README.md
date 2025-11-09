# Local GitOps Pipeline with ArgoCD + Kind

This project demonstrates a zero-cost local GitOps CI/CD setup using:
- Kind (Kubernetes in Docker)
- ArgoCD (GitOps controller)
- GitHub Actions (CI)
- Helm charts for deployment

## Prerequisites
- Docker Desktop
- Kind
- kubectl
- Helm
- Act (for running GitHub Actions locally)
- VS Code

## Setup
```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/local-gitops-pipeline.git
cd local-gitops-pipeline
bash scripts/setup_kind.sh
```

Access ArgoCD UI:
- URL: http://localhost:8080
- Username: admin
- Password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Then add your repo in ArgoCD → watch the app sync automatically.

## Test Pipeline Locally
```bash
act push
```

Validate Deployment:
```bash
kubectl get pods -n gitops
kubectl port-forward svc/myapp -n gitops 8000:8000
curl localhost:8000
```
Expected output:
```json
{"message":"Hello from <pod-name> - GitOps works!"}
```
