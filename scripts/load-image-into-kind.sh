#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${KIND_CLUSTER:-${1:-gitops-lab}}
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VALUES_FILE="$ROOT_DIR/helm/myapp/values.yaml"
APP_DIR="$ROOT_DIR/app"

log() {
  echo "[load-image] $*"
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "'$1' is required but not installed" >&2
    exit 1
  fi
}

require docker
require kind

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "values file not found: $VALUES_FILE" >&2
  exit 1
fi

read_value() {
  local key=$1
  awk -v look="$key" '
    /^image:/ {inimage=1; next}
    inimage && $1 == look {print $2; exit}
    inimage && NF == 0 {inimage=0}
  ' "$VALUES_FILE" | tr -d '"'
}

REPO=$(read_value "repository:")
TAG=$(read_value "tag:")
DIGEST=$(read_value "digest:")

if [[ -z "$REPO" ]]; then
  echo "Failed to parse image.repository from $VALUES_FILE" >&2
  exit 1
fi
if [[ -z "$TAG" ]]; then
  TAG=latest
fi
if [[ -n "$DIGEST" && "$DIGEST" != "\"\"" ]]; then
  cat <<MSG >&2
image.digest is set to '$DIGEST'. Helm will prefer the digest over the tag, so loading a local image will not have any effect.
Clear the digest field (set it to \"\") or override it with HELM values before rerunning this script.
MSG
  exit 1
fi

IMAGE_REF="${REPO}:${TAG}"

if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "kind cluster '$CLUSTER_NAME' not found. Create it with scripts/setup_kind.sh first." >&2
  exit 1
fi

log "Building Docker image ${IMAGE_REF} from ${APP_DIR}"
docker build -t "$IMAGE_REF" "$APP_DIR"

log "Loading image into kind cluster '$CLUSTER_NAME'"
kind load docker-image "$IMAGE_REF" --name "$CLUSTER_NAME"

log "Loaded $IMAGE_REF into kind. Trigger an ArgoCD sync or run 'kubectl rollout restart deployment/myapp -n gitops' to use the new image."
