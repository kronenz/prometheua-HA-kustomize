# Research: Thanos Multi-Cluster Monitoring Infrastructure

**Date**: 2025-10-13
**Feature**: 001-thanos-multi-cluster
**Purpose**: Research and validate technical decisions for multi-cluster monitoring deployment

## 1. Minikube + containerd Integration

### Decision
Use Minikube with containerd runtime driver for all 3 nodes with 4 CPU and 16GB RAM allocation.

### Rationale
- **Production Alignment**: containerd is the standard container runtime in production Kubernetes (CRI-O alternative), providing better alignment for later migration
- **Resource Efficiency**: containerd has lower overhead than Docker (no dockerd layer)
- **Longhorn Compatibility**: Longhorn 1.5+ fully supports containerd via CSI
- **Thanos Compatibility**: Thanos containers work identically with containerd
- **Minikube Support**: Stable since Minikube 1.25+

### Alternatives Considered
- **Docker driver**: Rejected - heavier resource footprint, deprecated in Kubernetes 1.24+
- **none driver** (bare metal): Rejected - requires direct host modification, harder to tear down/rebuild
- **podman driver**: Rejected - less mature, potential rootless complications with Longhorn

### Configuration Recommendations
```bash
minikube start \
  --driver=containerd \
  --cpus=4 \
  --memory=16384 \
  --disk-size=100g \
  --kubernetes-version=v1.28.0 \
  --container-runtime=containerd \
  --extra-config=kubelet.max-pods=110
```

**Network Plugin**: Use CNI (default), no special configuration needed for multi-cluster since clusters are independent.

---

## 2. Thanos Multi-Cluster Architecture

### Decision
Use Thanos Sidecar pattern on edge clusters (197, 198) with centralized Query/Store Gateway on central cluster (196).

### Rationale
- **Sidecar vs Receiver**: Sidecar chosen because:
  - Simpler deployment (no remote write configuration changes)
  - Better alignment with existing Prometheus Operator
  - Local scraping continues even if S3 unavailable (queues blocks)
- **Central Query Pattern**: Single Thanos Query on 196 with 2 replicas provides:
  - Unified query interface for all clusters
  - Load balancing via replicas
  - Deduplication across clusters
- **Store Gateway**: Enables querying historical data beyond 2h Prometheus retention from S3

### Alternatives Considered
- **Thanos Receiver**: Rejected - requires remote write, adds complexity, single point of failure for writes
- **Query per cluster**: Rejected - requires federation, no global deduplication
- **Thanos Compactor**: Deferred to future - downsampling not critical for MVP

### Architecture Diagram
```
Edge Cluster 197/198:          Central Cluster 196:
┌─────────────────┐            ┌──────────────────┐
│ Prometheus      │            │ Thanos Query (x2)│◄─── Grafana
│   └─Sidecar─────┼────┐       │                  │
└─────────────────┘    │       │ Store Gateway    │
                       │       └──────────────────┘
                       │              ▲
                       │              │
                       ▼              │
                  ┌────────────────────┐
                  │   MinIO S3         │
                  │ 172.20.40.21:30001 │
                  └────────────────────┘
```

### Configuration Recommendations
**Thanos Sidecar** (edge clusters):
```yaml
--objstore.config:
  type: S3
  config:
    bucket: thanos
    endpoint: 172.20.40.21:30001
    access_key: minio
    secret_key: minio123
    insecure: false
--tsdb.path: /prometheus  # Prometheus data dir
--prometheus.url: http://localhost:9090
--reloader.config-file: /etc/prometheus/prometheus.yml
```

**Thanos Query** (central cluster):
```yaml
--store: dnssrv+_grpc._tcp.thanos-sidecar-197.monitoring.svc.cluster.local
--store: dnssrv+_grpc._tcp.thanos-sidecar-198.monitoring.svc.cluster.local
--store: dnssrv+_grpc._tcp.thanos-store-gateway.monitoring.svc.cluster.local
--query.replica-label: prometheus_replica
--query.timeout: 5m
```

---

## 3. Kustomize + Helm Integration

### Decision
Use Kustomize 4.5+ `helmCharts` feature with base/overlay pattern for 3 clusters.

### Rationale
- **Declarative Management**: Helm charts + Kustomize patches in single workflow
- **DRY Principle**: Base configs shared, overlays for cluster-specific values
- **GitOps Ready**: All configs in YAML, no `helm install` commands
- **Version Pinning**: Helm chart versions explicit in kustomization.yaml

### Alternatives Considered
- **Pure Helm**: Rejected - requires `helm install` commands, violates IaC principle
- **Pure Kustomize**: Rejected - would require forking/maintaining Helm charts as raw YAML
- **Helmfile**: Rejected - additional tool dependency, not in constitution

### Directory Structure
```
deploy/
├── base/
│   ├── longhorn/
│   │   ├── kustomization.yaml       # helmCharts: longhorn/longhorn
│   │   └── values.yaml              # Shared values
│   ├── kube-prometheus-stack/
│   │   ├── kustomization.yaml       # helmCharts: prometheus-community/kube-prometheus-stack
│   │   ├── values.yaml
│   │   └── servicemonitors/         # Additional custom resources
│   └── thanos/
│       ├── kustomization.yaml       # Plain Kustomize (no Helm chart for Thanos components)
│       ├── query.yaml
│       ├── store-gateway.yaml
│       └── sidecar-configmap.yaml
└── overlays/
    ├── cluster-196-central/
    │   ├── kustomization.yaml       # bases: ../../base/*, patchesStrategicMerge
    │   ├── ingress-hostnames.yaml   # Patch: grafana.mkube-196.miribit.lab
    │   └── thanos-query-patch.yaml  # Add Thanos Query/Store only on 196
    ├── cluster-197-edge/
    │   ├── kustomization.yaml
    │   ├── ingress-hostnames.yaml   # Patch: grafana.mkube-197.miribit.lab
    │   └── thanos-sidecar-patch.yaml # Enable Sidecar on Prometheus
    └── cluster-198-edge/
        └── (same as 197)
```

### Configuration Recommendations
**Base kustomization.yaml example** (kube-prometheus-stack):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: kube-prometheus-stack
    repo: https://prometheus-community.github.io/helm-charts
    version: 55.5.0
    releaseName: kube-prometheus-stack
    namespace: monitoring
    valuesFile: values.yaml
```

**Overlay kustomization.yaml example** (cluster-196):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base/longhorn
  - ../../base/nginx-ingress
  - ../../base/kube-prometheus-stack
  - ../../base/thanos

patchesStrategicMerge:
  - ingress-hostnames.yaml
  - thanos-query-patch.yaml

namespace: monitoring
```

**Deployment Command**:
```bash
kustomize build deploy/overlays/cluster-196-central --enable-helm | kubectl apply -f - -n monitoring
```

---

## 4. OpenSearch S3 Snapshot Configuration

### Decision
Use OpenSearch native S3 snapshot repository with ISM (Index State Management) for 14-day local retention and S3 lifecycle for 180-day retention.

### Rationale
- **Native Integration**: OpenSearch S3 plugin built-in, no external tools needed
- **ISM Automation**: Declarative policy for automated snapshot + delete on age
- **MinIO Compatibility**: S3-compatible API works identically to AWS S3
- **Cluster-wide**: Snapshot repository shared across 3 OpenSearch nodes

### Alternatives Considered
- **Curator**: Rejected - deprecated by Elastic/OpenSearch in favor of ISM
- **Manual snapshots**: Rejected - violates automation principle
- **Fluent-bit direct to S3**: Rejected - loses search capability, no retention management

### Configuration Recommendations

**Step 1: Register S3 Repository** (one-time setup):
```json
PUT _snapshot/s3-logs-repository
{
  "type": "s3",
  "settings": {
    "bucket": "opensearch-logs",
    "endpoint": "https://172.20.40.21:30001",
    "protocol": "https",
    "path_style_access": true,
    "access_key": "minio",
    "secret_key": "minio123"
  }
}
```

**Step 2: ISM Policy for 14-day Retention**:
```json
PUT _plugins/_ism/policies/logs-retention-policy
{
  "policy": {
    "description": "Snapshot logs after 14 days, delete local indices",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [],
        "transitions": [
          {
            "state_name": "snapshot",
            "conditions": {
              "min_index_age": "14d"
            }
          }
        ]
      },
      {
        "name": "snapshot",
        "actions": [
          {
            "snapshot": {
              "repository": "s3-logs-repository",
              "snapshot": "logs-{{ctx.index}}-{{ctx._timestamp}}"
            }
          },
          {
            "delete": {}
          }
        ]
      }
    ]
  }
}
```

**Step 3: Apply Policy to Indices**:
```json
PUT _index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "plugins.index_state_management.policy_id": "logs-retention-policy"
    }
  }
}
```

**Step 4: S3 Lifecycle (on MinIO side)**:
```xml
<LifecycleConfiguration>
  <Rule>
    <ID>delete-old-snapshots</ID>
    <Filter>
      <Prefix>opensearch-logs/</Prefix>
    </Filter>
    <Status>Enabled</Status>
    <Expiration>
      <Days>180</Days>
    </Expiration>
  </Rule>
</LifecycleConfiguration>
```

---

## 5. Longhorn Multi-Cluster Setup

### Decision
Deploy Longhorn independently on each single-node Minikube cluster with S3 backup target for disaster recovery.

### Rationale
- **CSI Support**: Standard Kubernetes storage via PersistentVolumeClaims
- **Minikube Compatible**: Works on single-node clusters (no replication in this case)
- **S3 Backup**: Enables cluster rebuild from backups
- **No Cross-Cluster Replication**: Each cluster's storage is isolated (matches architecture principle)

### Alternatives Considered
- **Local Path Provisioner**: Rejected - no backup capability, no S3 integration
- **NFS**: Rejected - requires additional infrastructure, single point of failure
- **Rook/Ceph**: Rejected - overkill for single-node clusters, resource-heavy

### Configuration Recommendations

**Longhorn values.yaml**:
```yaml
defaultSettings:
  backupTarget: s3://longhorn-backups@us-east-1/
  backupTargetCredentialSecret: longhorn-s3-secret
  defaultReplicaCount: 1  # Single node, no replication
  storageMinimalAvailablePercentage: 15

persistence:
  defaultClass: true
  defaultClassReplicaCount: 1

csi:
  attacherReplicaCount: 1
  provisionerReplicaCount: 1
  resizerReplicaCount: 1
  snapshotterReplicaCount: 1
```

**S3 Secret** (create in longhorn-system namespace):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-s3-secret
  namespace: longhorn-system
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: minio
  AWS_SECRET_ACCESS_KEY: minio123
  AWS_ENDPOINTS: https://172.20.40.21:30001
  AWS_CERT: ""  # If using self-signed cert, add here
```

**Test PVC**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
```

---

## 6. DNS and Ingress Configuration

### Decision
Use NGINX Ingress Controller with HostNetwork mode on Minikube, relying on external DNS wildcard records for *.mkube-{196,197,198}.miribit.lab.

### Rationale
- **Minikube LoadBalancer Limitation**: Minikube doesn't provide real LoadBalancer, HostNetwork exposes on node IP
- **Wildcard DNS Simplicity**: Single DNS record per cluster (* → node IP)
- **NGINX Ingress Maturity**: Most widely used, well-documented, Helm chart available

### Alternatives Considered
- **NodePort**: Rejected - requires non-standard ports (30000-32767), bad UX
- **MetalLB on Minikube**: Rejected - adds complexity, not needed for 3 static IPs
- **Traefik**: Rejected - less mature Kubernetes integration than NGINX

### Configuration Recommendations

**NGINX Ingress values.yaml**:
```yaml
controller:
  kind: DaemonSet  # Ensure runs on the single node
  hostNetwork: true  # Expose on node IP:80/443
  service:
    type: ClusterIP  # Don't need LoadBalancer with HostNetwork

  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"

  metrics:
    enabled: true
    serviceMonitor:
      enabled: true  # For Prometheus scraping
```

**Ingress Resource Example** (Grafana on cluster 196):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"  # TLS not in scope
spec:
  ingressClassName: nginx
  rules:
    - host: grafana.mkube-196.miribit.lab
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kube-prometheus-stack-grafana
                port:
                  number: 80
```

**DNS Records** (external DNS server):
```
*.mkube-196.miribit.lab.  A  192.168.101.196
*.mkube-197.miribit.lab.  A  192.168.101.197
*.mkube-198.miribit.lab.  A  192.168.101.198
```

**Validation**:
```bash
curl -H "Host: grafana.mkube-196.miribit.lab" http://192.168.101.196/
# Should return Grafana UI HTML
```

---

## 7. Security: RBAC and Network Policies

### Decision
Implement least-privilege ServiceAccounts per component and Network Policies restricting pod-to-pod communication based on constitutional requirements.

### Rationale
- **Defense in Depth**: RBAC + NetworkPolicy = two layers of security
- **Blast Radius Limitation**: Compromised component can't access others
- **Compliance**: Follows principle of least privilege (FR-016)
- **Constitution Requirement**: FR-017 explicitly requires Network Policies

### Alternatives Considered
- **No RBAC** (use default SA): Rejected - violates security best practices
- **Calico instead of default CNI**: Rejected - adds complexity, standard CNI sufficient
- **Service Mesh (Istio/Linkerd)**: Rejected - out of scope, future enhancement

### Configuration Recommendations

**ServiceAccount Example** (Thanos Sidecar):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: thanos-sidecar
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: thanos-sidecar-role
  namespace: monitoring
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["thanos-s3-secret"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: thanos-sidecar-rolebinding
  namespace: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: thanos-sidecar-role
subjects:
  - kind: ServiceAccount
    name: thanos-sidecar
    namespace: monitoring
```

**NetworkPolicy Example** (Fluent-bit → OpenSearch only):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fluent-bit-egress
  namespace: logging
spec:
  podSelector:
    matchLabels:
      app: fluent-bit
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: opensearch
      ports:
        - protocol: TCP
          port: 9200
    - to:  # Allow DNS
        - namespaceSelector:
            matchLabels:
              name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

**NetworkPolicy Example** (Thanos Sidecar → S3 only):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: thanos-sidecar-egress
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: thanos-sidecar
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 172.20.40.21/32  # MinIO S3 endpoint
      ports:
        - protocol: TCP
          port: 30001
    - to:  # Allow DNS
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
```

**S3 Credentials Secret** (Kubernetes Secret, not hardcoded):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-s3-secret
  namespace: monitoring
type: Opaque
stringData:
  objstore.yml: |
    type: S3
    config:
      bucket: thanos
      endpoint: 172.20.40.21:30001
      access_key: minio
      secret_key: minio123
      insecure: false
```

---

## Summary

All 7 research areas have been investigated with concrete decisions:

1. ✅ **Minikube + containerd**: Validated for production alignment and resource efficiency
2. ✅ **Thanos Sidecar Pattern**: Chosen for simplicity and resilience
3. ✅ **Kustomize helmCharts**: Validated for declarative multi-cluster management
4. ✅ **OpenSearch ISM + S3**: Automated retention with 14d local / 180d S3
5. ✅ **Longhorn**: Independent per-cluster with S3 backups
6. ✅ **NGINX Ingress HostNetwork**: Practical solution for Minikube with wildcard DNS
7. ✅ **RBAC + NetworkPolicy**: Least-privilege security per constitution

**No NEEDS CLARIFICATION remaining**. All technical decisions are resolved and documented.

**Ready for Phase 1: Design & Contracts**
