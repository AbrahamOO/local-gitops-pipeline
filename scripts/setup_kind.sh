#!/bin/bash
set -e
echo "Creating Kind cluster..."
kind create cluster --name gitops-lab --wait 60s
echo "Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "Waiting for ArgoCD pods..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=180s
echo "Port-forward ArgoCD UI on localhost:8080"
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
sleep 5
echo "ArgoCD is ready."
