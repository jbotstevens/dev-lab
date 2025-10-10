# Quant Services Integration for Dev Lab

## Overview

This directory contains the configuration to deploy the quant-services-layer from `amelcocloud/quant-services` into the dev-lab cluster, with automatic image registry patching and tag synchronization to use the local dev-lab registry instead of ECR while preserving upstream image tags.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Dev Lab Cluster                         │
├─────────────────────────────────────────────────────────────┤
│  Local Registry (dev-lab-registry namespace)               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ docker-registry.dev-lab-registry.svc.cluster.local:5000│ │
│  │ - Contains all quant-services images                   │ │
│  │ - Built from amelcocloud/quant-services Dockerfiles   │ │
│  │ - Registry UI available at registry.dev-lab.local     │ │
│  └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  Quant Services (quant-services namespace)                 │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Image patches applied via Kustomize:                   │ │
│  │                                                         │ │
│  │ FROM: 406289901644.dkr.ecr.eu-west-1.amazonaws.com     │ │
│  │ TO:   docker-registry.dev-lab-registry.svc...local:5000│ │
│  │                                                         │ │
│  │ Services:                                               │ │
│  │ - adh-consumer      - rapid-pini-feeder               │ │
│  │ - betticker-ws      - rw-proj-min                     │ │
│  │ - dash-auth         - rw-proj-min-store               │ │
│  │ - dash-ws           - unabated-news-feeder            │ │
│  │ - external-prices   - wnba-reports                    │ │
│  │ - nba-livescores    - news-gather                     │ │
│  └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│  Kafka Infrastructure (included in quant-services-layer)   │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Files Structure

```
apps/quant-services/
├── README.md                          # This file
├── gitrepository.yaml                 # Points to amelcocloud/quant-services
├── kustomization.yaml                 # Main deployment with patches
├── build-and-push.sh                  # Build all services with upstream tags
├── extract-upstream-tags.sh           # Extract tags from upstream HelmReleases  
├── sync-tags.sh                       # Sync build/patch files with upstream tags
├── upstream-tags.yaml                 # Auto-generated tag mappings
├── validate-registry.sh               # Validate images in local registry
└── patches/
    ├── image-registry-patches.yaml    # Strategic merge patches for images
    └── json-patches.yaml              # Alternative JSON patch approach
```

## Image Registry Patching

The system automatically patches all image references:

### Original (ECR):
```yaml
image:
  repository: 406289901644.dkr.ecr.eu-west-1.amazonaws.com/adh-consumer
  tag: 1.0.1
```

### Patched (Local Registry with Upstream Tags):
```yaml
image:
  repository: docker-registry.dev-lab-registry.svc.cluster.local:5000/adh-consumer
  tag: "1.0.0"  # Preserving upstream tag
```

## Tag Synchronization System

The system automatically extracts and uses the same image tags as defined in the upstream HelmReleases from `amelcocloud/quant-services`. This ensures that local development uses exactly the same image versions as production.

### Tag Mapping Process

1. **Extract Upstream Tags**: `./extract-upstream-tags.sh` scans all HelmRelease files
2. **Generate Mappings**: Creates `upstream-tags.yaml` with service → tag mappings
3. **Update Build Script**: Automatically updates `build-and-push.sh` with correct tags
4. **Update Patches**: Updates `image-registry-patches.yaml` to preserve tags
5. **Sync Everything**: `./sync-tags.sh` orchestrates the entire process

### Current Tag Mapping

```yaml
# Auto-extracted from upstream HelmReleases
adh-consumer: "1.0.0"
betticker-ws: "1.0.0"  
dash-auth: "1.0.0"
dash-ws: "1.0.0"
external-prices-gather: "1.0.0"
nba-livescores: "1.0.0"
news-gather: "1.0.0"
rapid-pini-feeder: "1.0.0"
rw-proj-min: "1.0.0"
rw-proj-min-store: "1.0.0"
unabated-news-feeder: "1.0.0"
wnba-reports: "1.0.1"  # Note: Different version
```

## Prerequisites

1. **Dev Lab cluster running** with container registry deployed
2. **Docker** installed and accessible 
3. **kubectl** configured for dev-lab cluster
4. **Access to amelcocloud/quant-services** repository

## Deployment Process

### Step 0: Sync Tags with Upstream (Recommended)

Ensure your local build uses the same tags as upstream HelmReleases:

```bash
# Sync with upstream tags (recommended before building)
./apps/quant-services/sync-tags.sh
```

This will:
- Extract current image tags from amelcocloud/quant-services HelmReleases
- Update build-and-push.sh with the correct tags
- Update image registry patches to preserve tags
- Create upstream-tags.yaml mapping file

### Step 1: Build and Push Images

Build all quant services from source and push to local registry with upstream tags:

```bash
# Run from dev-lab root directory
./apps/quant-services/build-and-push.sh
```

This script will:
- Set up port forwarding to local registry
- Build each service from its Dockerfile using upstream tags
- Tag images with both upstream tags (e.g., 1.0.0) and latest
- Push images to `docker-registry.dev-lab-registry.svc.cluster.local:5000`
- Provide a summary of successful/failed builds

### Step 2: Validate Registry Contents

Check that all required images are available:

```bash
./apps/quant-services/validate-registry.sh
```

This will verify:
- Registry accessibility
- All 12 services are present
- Images have proper tags
- Provide deployment guidance

### Step 3: Deploy Quant Services

Deploy the complete quant-services-layer:

```bash
# Apply the GitRepository and Kustomization
kubectl apply -f apps/quant-services/

# Monitor deployment
kubectl get kustomizations -n flux-system | grep quant
kubectl get pods -n quant-services
```

## How the Patching Works

### 1. **Strategic Merge Patches**
The main approach uses Kustomize strategic merge patches in `patches/image-registry-patches.yaml`:

```yaml
# For each service
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: adh-consumer
spec:
  values:
    image:
      repository: docker-registry.dev-lab-registry.svc.cluster.local:5000/adh-consumer
```

### 2. **Kustomization Integration**
The main `kustomization.yaml` applies patches:

```yaml
patches:
  - path: patches/image-registry-patches.yaml
    target:
      kind: HelmRelease
      namespace: quant-services
```

### 3. **Dependency Management**
Ensures container registry is deployed first:

```yaml
dependsOn:
  - name: dev-lab-infrastructure
```

## Troubleshooting

### Registry Issues

```bash
# Check registry pod
kubectl get pods -n dev-lab-registry

# Check registry service
kubectl get svc -n dev-lab-registry

# Port forward for debugging
kubectl port-forward -n dev-lab-registry service/docker-registry 5000:5000
curl http://localhost:5000/v2/_catalog
```

### Build Issues

```bash
# Check if Dockerfiles exist
ls -la /home/jstevens/git/amelcocloud/quant-services/services/*/Dockerfile

# Manual build for debugging
cd /home/jstevens/git/amelcocloud/quant-services/services/adh-consumer
docker build -t test-image .
```

### Deployment Issues

```bash
# Check Flux kustomization status
kubectl describe kustomization quant-services-layer -n flux-system

# Check HelmRelease status
kubectl get helmreleases -n quant-services

# Check pod status
kubectl get pods -n quant-services
kubectl describe pod <pod-name> -n quant-services
```

## Development Workflow

### Adding New Services

1. **Add Dockerfile** to `amelcocloud/quant-services/services/<service-name>/`
2. **Update build script** by adding service to `SERVICES` array
3. **Add patch** for the new service in `image-registry-patches.yaml`
4. **Rebuild and redeploy**

### Updating Services

1. **Update source code** in `amelcocloud/quant-services`
2. **Rebuild images**: `./build-and-push.sh`
3. **Restart deployments**: `kubectl rollout restart deployment -n quant-services`

### Registry Management

```bash
# Access registry UI
kubectl port-forward -n dev-lab-registry service/docker-registry-ui 8080:80
# Visit http://localhost:8080

# Clean up old images
kubectl exec -n dev-lab-registry deployment/docker-registry -- /bin/registry garbage-collect /etc/docker/registry/config.yml
```

## Configuration Options

### Environment Variables

You can customize the build process with environment variables:

```bash
# Use different registry
export LOCAL_REGISTRY="my-registry:5000"
./build-and-push.sh

# Build specific services only
export SERVICES="adh-consumer dash-auth"
./build-and-push.sh
```

### Image Tags

By default, all images use `latest` tag. You can modify this in the patches or use version-specific builds:

```bash
# Build with specific tag
docker build -t docker-registry.dev-lab-registry.svc.cluster.local:5000/adh-consumer:v1.0.0 .
```

## Security Considerations

1. **Registry Access**: Local registry is accessible within cluster only
2. **Image Scanning**: Consider adding image scanning for security
3. **Network Policies**: Registry is isolated in its own namespace
4. **RBAC**: Flux has minimal required permissions

## Performance Tips

1. **Build Parallelization**: Modify build script to build services in parallel
2. **Image Caching**: Use Docker BuildKit for better build caching
3. **Registry Storage**: Monitor registry storage usage in `/var/lib/registry`
4. **Network**: Use nodePort or ingress for external registry access if needed

## Integration with CI/CD

This setup enables local development and testing of quant-services without requiring ECR access, making it perfect for:
- Development environments
- Testing new features
- Local debugging
- Offline development