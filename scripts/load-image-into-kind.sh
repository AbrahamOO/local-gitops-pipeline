#!/usr/bin/env bash
set -euo pipefail
# make script executable
# Usage: ./scripts/load-image-into-kind.sh [kind-cluster-name]
# Default cluster name: gitops-lab-control-plane

CLUSTER_NAME=${1:-gitops-lab-control-plane}

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VALUES_FILE="$ROOT_DIR/helm/myapp/values.yaml"
APP_DIR="$ROOT_DIR/app"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH" >&2
  exit 2
fi
if ! command -v kind >/dev/null 2>&1; then
  echo "kind not found in PATH" >&2
  exit 2
fi

if [ ! -f "$VALUES_FILE" ]; then
  echo "values file not found: $VALUES_FILE" >&2
  exit 2
fi

# Extract repository and tag from values.yaml
REPO=$(sed -n 's/^\s*repository:\s*\(.*\)/\1/p' "$VALUES_FILE" | head -n1 | tr -d '"')
TAG=$(sed -n 's/^\s*tag:\s*\(.*\)/\1/p' "$VALUES_FILE" | head -n1 | tr -d '"')

if [ -z "$REPO" ]; then
  echo "Could not determine image.repository from $VALUES_FILE" >&2
  exit 2
fi
if [ -z "$TAG" ]; then
  echo "Could not determine image.tag from $VALUES_FILE; defaulting to 'latest'" >&2
  TAG=latest
fi

IMAGE="${REPO}:${TAG}"

echo "Building image $IMAGE from $APP_DIR"
docker build -t "$IMAGE" "$APP_DIR"

echo "Loading image into kind cluster '$CLUSTER_NAME'"
kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

echo "Image loaded into kind. If your Helm values point to $IMAGE, ArgoCD should be able to deploy it from the node-local image store." 
