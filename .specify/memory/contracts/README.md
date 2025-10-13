# Deployment Contracts

This directory contains deployment contracts for each component of the Thanos Multi-Cluster Monitoring Infrastructure.

## Contract Structure

Each contract defines:
- **Input**: Required configuration and prerequisites
- **Output**: Expected deployment state
- **Validation**: How to verify successful deployment
- **Rollback**: How to undo the deployment

## Contracts List

1. **minikube-install.md**: Minikube installation with containerd driver
2. **longhorn-deployment.md**: Longhorn storage class deployment
3. **nginx-ingress-deployment.md**: NGINX Ingress Controller deployment
4. **kube-prometheus-stack.md**: Prometheus Operator + Grafana + Alertmanager
5. **thanos-deployment.md**: Thanos Query/Sidecar/Store Gateway deployment
6. **opensearch-deployment.md**: OpenSearch 3-node cluster deployment
7. **fluent-bit-deployment.md**: Fluent-bit log collection deployment

## Deployment Order

The contracts MUST be executed in this order to satisfy dependencies:

```
P0: Minikube (on all nodes in parallel)
  ↓
P1: Longhorn + NGINX Ingress (on all clusters in parallel)
  ↓
P1: kube-prometheus-stack (central cluster 196)
  ↓
P1: Thanos Query/Store (on central cluster 196)
  ↓
P2: kube-prometheus-stack + Thanos Sidecar (edge clusters 197/198 in parallel)
  ↓
P3: OpenSearch (3 nodes, form cluster)
  ↓
P3: Fluent-bit (on all clusters in parallel)
```

## Validation Commands

Quick validation script for all contracts:

```bash
# Minikube
minikube status --profile cluster-196
kubectl get nodes

# Longhorn
kubectl get storageclass longhorn
kubectl get pods -n longhorn-system

# NGINX Ingress
kubectl get pods -n ingress-nginx
kubectl get ing -A

# Prometheus
kubectl get promethe uses -n monitoring
kubectl get pods -n monitoring | grep prometheus

# Thanos
kubectl get pods -n monitoring | grep thanos
curl http://thanos-query.monitoring.svc:9090/-/healthy

# OpenSearch
kubectl get pods -n logging | grep opensearch
curl http://opensearch.logging.svc:9200/_cluster/health

# Fluent-bit
kubectl get ds -n logging fluent-bit
kubectl logs -n logging -l app=fluent-bit --tail=10
```

## Contract Templates

Each contract follows this template:

```markdown
# Component Deployment Contract: [Name]

## Input

### Prerequisites
- [What must exist before this deployment]

### Configuration
- [Required configuration parameters]

### Secrets
- [Required secrets and credentials]

## Output

### Expected Resources
- [List of Kubernetes resources created]

### Health Indicators
- [How to verify component health]

## Validation

### Automated Tests
```bash
# [Commands to verify deployment]
```

### Manual Checks
- [UI/API checks to perform]

## Rollback

```bash
# [Commands to undo this deployment]
```

## Troubleshooting

Common issues and solutions:
- [Issue 1]: [Solution]
- [Issue 2]: [Solution]
```
