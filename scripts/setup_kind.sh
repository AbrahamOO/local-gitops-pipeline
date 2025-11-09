#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-gitops-lab}
KIND_CONFIG=${KIND_CONFIG:-}
ARGOCD_VERSION=${ARGOCD_VERSION:-stable}

log() {
  echo "[setup_kind] $*"
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required binary '$1' not found in PATH" >&2
    exit 1
  fi
}

require kind
require kubectl

if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  log "Creating kind cluster '$CLUSTER_NAME'"
  if [[ -n "$KIND_CONFIG" && -f "$KIND_CONFIG" ]]; then
    kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG" --wait 120s
  else
    kind create cluster --name "$CLUSTER_NAME" --wait 120s
  fi
else
  log "kind cluster '$CLUSTER_NAME' already exists; skipping creation"
fi

kubectl cluster-info --context "kind-$CLUSTER_NAME" >/dev/null

if ! kubectl get namespace argocd >/dev/null 2>&1; then
  log "Creating argocd namespace"
  kubectl create namespace argocd
else
  log "Namespace argocd already exists"
fi

INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
log "Applying ArgoCD manifests from ${INSTALL_URL}"
kubectl apply -n argocd -f "$INSTALL_URL"

log "Waiting for ArgoCD deployments"
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=5m
kubectl -n argocd rollout status deploy/argocd-redis --timeout=5m || true
kubectl -n argocd rollout status deploy/argocd-dex-server --timeout=5m
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m

log "ArgoCD is ready. Port-forward with:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
log "Retrieve the initial admin password with:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
