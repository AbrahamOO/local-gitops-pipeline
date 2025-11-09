## local-gitops-pipeline — developer guide

This repository is a small local GitOps demo: a Helm chart (`helm/myapp`) deployed by ArgoCD using manifests in `manifests/`.

## Goal

Get the app running locally via ArgoCD and a local Docker registry. This README documents two reliable ways to make images available to the cluster so ArgoCD can deploy them successfully.

## Overview of common failure

When you push an image to a registry running on your host (for example via `docker compose` mapping the registry to `localhost:5001->5000`), Kubernetes nodes inside a VM (Docker Desktop, colima, etc.) cannot always reach `localhost:5001` the same way your host OS does. You will see ImagePullBackOff and errors like:

    Failed to pull image "localhost:5001/myapp:latest": Head "https://172.18.0.2:5000/v2/myapp/manifests/latest": dial tcp 172.18.0.2:5000: connect: connection refused

## Two good solutions

A) Quick local fix — import the image into the cluster node(s)
B) Long-term/friendly fix — push the image to a registry reachable by the cluster (remote or host-accessible) and update the Git repo so ArgoCD can pull it

## A) Quick local fix — import image into the cluster (recommended for local development)

This is fast and works offline. Approach depends on your cluster type.

1. If you use kind (Kubernetes IN Docker):

- Build and tag the image locally:

```bash
docker build -t localhost:5001/myapp:latest ./app
```

- Load the image into the kind cluster:

```bash
kind load docker-image localhost:5001/myapp:latest --name <cluster-name>
```

- Re-deploy or refresh ArgoCD application (or patch the deployment image temporarily):

```bash
kubectl -n gitops rollout restart deployment/myapp
kubectl -n argocd get applications
```

2. If you use Docker Desktop Kubernetes (or the cluster runs inside a VM / containerd):

- You can often push to `host.docker.internal:<port>` if your registry is listening on the host. However, some runtimes insist on HTTPS for IP addresses and will reject plain HTTP.
- Reliable local method: save the image and import into the node's containerd.

Example: save and import via a privileged helper pod (works when you can't access node container directly):

```bash
# save locally
docker save localhost:5001/myapp:latest -o myapp.tar

# create a temporary pod that has host access to /var/run/docker.sock (cluster-admin required)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
	name: containerd-importer
	namespace: kube-system
spec:
	hostPID: true
	hostNetwork: true
	hostIPC: true
	containers:
	- name: importer
		image: docker.io/library/busybox:1.36.1
		command: ["sleep","3600"]
		securityContext:
			privileged: true
		volumeMounts:
		- name: dockersock
			mountPath: /var/run/docker.sock
	volumes:
	- name: dockersock
		hostPath:
			path: /var/run/docker.sock
EOF

# copy the tar to the pod
kubectl cp myapp.tar kube-system/containerd-importer:/tmp/myapp.tar

# inside the pod you could use ctr (if available) or scp the file into the node and run containerd ctr import
# (This step varies by cluster; if you want I can run the exact commands for your environment.)
```

After importing, restart the deployment:

```bash
kubectl -n gitops rollout restart deployment/myapp
kubectl -n gitops get pods -w
```

## B) Long-term / shareable fix — push image to a reachable registry and update Git

This is what CI and multi-developer environments use.

1. Push to Docker Hub (example):

```bash
docker tag localhost:5001/myapp:latest YOUR_DOCKERHUB_USER/myapp:latest
docker push YOUR_DOCKERHUB_USER/myapp:latest
```

Then update `helm/myapp/values.yaml` to point to `YOUR_DOCKERHUB_USER/myapp` (set tag as `latest` or a specific sha) and commit/push so ArgoCD picks it up.

2. Use GitHub Container Registry (GHCR) or GitHub Packages or any other private registry.

3. Use the local registry but make sure the cluster is configured to allow insecure HTTP for that registry IP:port (containerd config tweak). This requires modifying the container runtime config for the cluster nodes (different per platform: Docker Desktop, kind, k3d, etc.).

## Concrete `helm/myapp/values.yaml` guidance

Make the image repository configurable. Current file (`helm/myapp/values.yaml`) should look like:

```yaml
replicaCount: 1
image:
	repository: localhost:5001/myapp
	tag: latest
service:
	port: 8000
```

If you decide to push to Docker Hub, change `repository` to `youruser/myapp` and commit. ArgoCD will reconcile the deployment automatically.

## Troubleshooting checklist

- If you see ImagePullBackOff, run:

```bash
kubectl -n gitops describe pod <pod-name>
```

Look for DNS/connection errors or TLS/HTTP errors in the events.

- If the registry is HTTP and the node refuses TLS, look into configuring the container runtime (containerd) to allow the registry as insecure.

- If you prefer I handle this for you, I can (with your permission):
  - load the image into the node(s) now so the pods become Ready (fast local fix), or
  - update the Helm values in Git and push the image to GHCR/DockerHub and update the repo so ArgoCD deploys from a public registry.

## Next steps I can take now

- Import the current image into the cluster nodes so ArgoCD deployment becomes Ready (I can run the exact containerd import method for Docker Desktop; confirm and I’ll proceed).
- Or update `helm/myapp/values.yaml` and push to Git if you want the GitOps repo to reflect the change.

---

If you'd like, tell me which of the following to do now:

- (1) I should import the image into your cluster nodes (quick), or
- (2) I should push the image to Docker Hub/GHCR and update the repo (shareable), or
- (3) I should change `values.yaml` to use `172.18.0.2:5000/myapp` and commit (not recommended unless containerd is configured to allow HTTP).

I'll proceed after you pick one.
