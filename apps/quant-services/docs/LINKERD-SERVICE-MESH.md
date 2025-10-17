# Linkerd Service Mesh Integration for Quant Services

## Overview

This directory contains patches to enable Linkerd service mesh integration for all quant services in the dev-lab environment. The service mesh provides:

- **Automatic mTLS** between all services
- **Traffic metrics and observability** via Linkerd dashboard
- **Traffic policies** for enhanced security  
- **Load balancing** and **circuit breaking**
- **Distributed tracing** capabilities

## Patch Files

### 1. linkerd-namespace-injection.yaml
**Purpose**: Enables automatic Linkerd sidecar injection for all pods in the `quant-services` namespace.

**What it does**:
- Adds `linkerd.io/inject: enabled` annotation to the namespace
- Configures proxy resource limits and requests
- Sets up proper labels for mesh integration

**Applied automatically** - No manual intervention needed.

### 2. linkerd-service-mesh-advanced.yaml  
**Purpose**: Template for advanced per-service mesh configuration.

**Use cases**:
- Services needing custom proxy resource limits
- Services with admin ports that should skip mesh
- Services requiring specific traffic policies

**Usage**: Apply selectively by targeting specific HelmRelease names.

### 3. linkerd-observability.yaml
**Purpose**: Enhanced monitoring and observability for meshed services.

**Features**:
- Prometheus metrics scraping configuration
- Health check setup compatible with mesh
- Service monitoring annotations

**Usage**: Apply to services that expose metrics or need enhanced monitoring.

## Current Configuration

### Basic Setup (Active)
```yaml
# Applied automatically via kustomization.yaml
patches:
  - path: patches/linkerd-namespace-injection.yaml
    target:
      kind: Namespace
      name: quant-services
```

### Optional Advanced Configuration
To apply advanced mesh features to specific services, add to kustomization.yaml:

```yaml
patches:
  # Advanced configuration for specific services
  - path: patches/linkerd-service-mesh-advanced.yaml
    target:
      kind: HelmRelease
      name: dash-ws  # Example: Apply to dash-ws service
      namespace: quant-services
      
  # Observability for services with metrics
  - path: patches/linkerd-observability.yaml
    target:
      kind: HelmRelease
      name: betticker-ws  # Example: Apply to betticker-ws
      namespace: quant-services
```

## Service Mesh Benefits for Quant Services

### 1. Security
- **Automatic mTLS**: All inter-service communication encrypted
- **Zero-trust networking**: Services authenticated by default
- **Traffic policies**: Fine-grained access control

### 2. Observability  
- **Live traffic metrics**: Request rates, latencies, success rates
- **Service topology**: Visual map of service dependencies
- **Distributed tracing**: Request flow across services

### 3. Reliability
- **Automatic retries**: Failed requests retried transparently
- **Circuit breaking**: Failing services isolated automatically
- **Load balancing**: Traffic distributed optimally

### 4. Traffic Management
- **Traffic splitting**: A/B testing and canary deployments
- **Fault injection**: Chaos engineering capabilities
- **Rate limiting**: Protection against traffic spikes

## Verification

### 1. Check Namespace Injection
```bash
kubectl get namespace quant-services -o yaml
# Should show linkerd.io/inject: enabled annotation
```

### 2. Verify Pod Injection
```bash
kubectl get pods -n quant-services
# Pods should show 2/2 ready (app container + linkerd proxy)
```

### 3. Check Linkerd Dashboard
```bash
linkerd dashboard &
# Navigate to http://localhost:50750
# Check quant-services namespace for meshed services
```

### 4. View Service Metrics
```bash
linkerd stat deploy -n quant-services
# Shows success rates, request rates, and latencies
```

## Monitoring Integration

### Grafana Dashboards
The service mesh automatically provides:
- **Linkerd Top Line**: Overall mesh health
- **Linkerd Service**: Per-service metrics  
- **Linkerd Workload**: Per-workload detailed metrics

### Prometheus Metrics
Available metrics include:
- `request_total`: Total requests
- `response_latency_ms`: Response latencies
- `tcp_open_total`: TCP connections
- `tcp_open_connections`: Current open connections

## Traffic Policies

### Example: Restrict Database Access
```yaml
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: database-server
  namespace: quant-services
spec:
  podSelector:
    matchLabels:
      app: postgresql
  port: 5432
---
apiVersion: policy.linkerd.io/v1beta1  
kind: ServerAuthorization
metadata:
  name: database-access
  namespace: quant-services
spec:
  server:
    name: database-server
  requiredRoutes:
  - pathRegex: "/.*"
    methods: ["GET", "POST"]
  client:
    meshTLS:
      serviceAccounts:
      - name: adh-consumer
      - name: dash-ws
```

## Troubleshooting

### Pod Not Getting Injected
1. Check namespace annotation: `kubectl get ns quant-services -o yaml`
2. Verify Linkerd control plane: `linkerd check`
3. Check injection override: Look for `linkerd.io/inject: disabled` on pods

### Service Not Showing in Mesh
1. Verify pod has sidecar: `kubectl describe pod <pod-name> -n quant-services`
2. Check service discovery: `linkerd endpoints <service-name> -n quant-services`
3. Review service configuration

### Metrics Not Available
1. Confirm proxy metrics port: `kubectl port-forward <pod> 4191:4191`
2. Check Prometheus configuration
3. Verify service annotations

## Performance Considerations

### Resource Usage
- **CPU overhead**: ~10-20m per pod for proxy
- **Memory overhead**: ~50-100Mi per pod for proxy  
- **Network latency**: ~1-2ms additional latency

### Optimization
- Tune proxy resource limits based on service load
- Use traffic policies to reduce unnecessary mesh hops
- Configure appropriate timeout values

## Integration with Existing Services

The mesh is designed to work transparently with existing quant services:
- **No code changes required**
- **Existing health checks preserved**
- **Current monitoring still functional**
- **Database connections unaffected**

Services continue to function exactly as before, with added mesh benefits.