# Implementation Plan: Thanos Multi-Cluster Monitoring Infrastructure

**Branch**: `001-thanos-multi-cluster` | **Date**: 2025-10-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/root/specs/001-thanos-multi-cluster/spec.md`

## Summary

Deploy a distributed Thanos-based monitoring infrastructure across 3 Minikube clusters (nodes 196, 197, 198) with centralized metric aggregation, S3-backed unlimited retention, and comprehensive observability. The system includes Prometheus for metrics collection, Thanos for multi-cluster aggregation, OpenSearch+Fluent-bit for log management, Longhorn for storage, and NGINX Ingress for external access. All components are deployed via Kustomize+Helm following IaC principles with Korean documentation and Mermaid architecture diagrams.

## Technical Context

**Language/Version**: YAML (Kustomize manifests), Bash (installation scripts), Korean (documentation)
**Primary Dependencies**:
- Kubernetes: Minikube with containerd driver
- Monitoring: kube-prometheus-stack (Prometheus Operator, Grafana, Alertmanager), Thanos (Query, Sidecar, Store Gateway)
- Logging: OpenSearch 2.x, Fluent-bit 2.x
- Storage: Longhorn 1.5+, MinIO S3 (external at https://172.20.40.21:30001)
- Ingress: NGINX Ingress Controller
- Deployment: Kustomize 4.5+, Helm charts from ArtifactHub

**Storage**:
- Local: Longhorn distributed block storage (2-hour Prometheus retention, 14-day OpenSearch retention)
- Remote: MinIO S3 at https://172.20.40.21:30001 (unlimited metrics, 180-day logs)

**Testing**:
- Contract tests: Kubernetes manifest validation (kubeval, kustomize build verification)
- Integration tests: Health check scripts per component, end-to-end query validation
- Smoke tests: Quickstart.md validation script

**Target Platform**:
- 3x Linux nodes (192.168.101.196-198) running Minikube single-node clusters
- Node 196: Central cluster (Thanos Query aggregation)
- Nodes 197-198: Edge clusters (local Prometheus + Thanos Sidecar)

**Project Type**: Infrastructure (Kubernetes multi-cluster deployment)

**Performance Goals**:
- Metrics: 30-second scrape interval, <5 second Grafana dashboard load
- Logs: <30 second ingestion latency from pod to OpenSearch
- Storage: 60 second PVC provisioning via Longhorn
- Deployment: 15 minutes Minikube installation, 60 minutes full stack deployment

**Constraints**:
- No manual deployments (IaC only via Kustomize)
- No local persistent storage (S3 only for metrics/logs)
- No helm install command (Kustomize helmCharts only)
- DNS: *.mkube-{196,197,198}.miribit.lab
- Resources: Minimum 4 CPU, 16GB RAM per node

**Scale/Scope**:
- 3 Kubernetes clusters (1 per node)
- ~15 monitoring components across all clusters
- OpenSearch 3-node cluster with replication factor 2
- Thanos Query: 2 replicas with anti-affinity

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Infrastructure as Code (IaC) First

**Status**: ✅ COMPLIANT

**Verification**:
- All components defined in Kustomize YAML manifests
- Helm charts consumed via `kustomize build --enable-helm` only
- Git version control for all configurations
- Environment-specific values externalized via Kustomize overlays (base/ + overlays/{196,197,198}/)

**Implementation**:
- FR-001: Kustomize with Helm chart inflation
- FR-018: ConfigMaps, Secrets, overlays for environment-specific config
- FR-019: Base/overlay pattern for 3 clusters
- FR-020: Standardized deployment command

### Principle II: Multi-Cluster Architecture

**Status**: ✅ COMPLIANT

**Verification**:
- Node 196: Central cluster (Thanos Query, Query Frontend, Store Gateway)
- Nodes 197-198: Edge clusters (Prometheus, Thanos Sidecar)
- Independent operation: Each cluster has local Prometheus + Grafana
- Shared S3 backend: All Thanos components use MinIO at 172.20.40.21:30001

**Implementation**:
- FR-006: Central cluster Thanos components on node 196
- FR-005: Edge cluster Thanos Sidecars on nodes 197-198
- FR-014: Independent cluster operation requirement
- FR-015: Thanos Query 2 replicas with anti-affinity

### Principle III: S3-Backed Storage (NON-NEGOTIABLE)

**Status**: ✅ COMPLIANT

**Verification**:
- Prometheus: 2-hour local retention only (FR-004)
- Thanos: All metric blocks uploaded to S3 via Sidecar (FR-005, FR-007)
- OpenSearch: 14-day local, 180-day S3 snapshots (FR-009a, FR-009b)
- Longhorn: S3 backup target configured (User Story 4)
- No hostPath or emptyDir for persistent data (FR-013)

**Implementation**:
- FR-007: S3 endpoint https://172.20.40.21:30001, credentials minio/minio123
- FR-007a: S3 credentials in Kubernetes Secrets
- FR-013: Explicit prohibition of local storage

### Principle IV: Kustomize-Helm Integration

**Status**: ✅ COMPLIANT

**Verification**:
- Helm charts from ArtifactHub consumed via Kustomize helmCharts feature
- Each component (kube-prometheus-stack, opensearch, fluent-bit, longhorn, nginx-ingress) has dedicated kustomization directory
- values.yaml files for primary configuration
- kustomization.yaml resources section for non-Helm resources

**Structure**:
```
deploy/
├── base/
│   ├── longhorn/
│   ├── nginx-ingress/
│   ├── kube-prometheus-stack/
│   ├── thanos/
│   ├── opensearch/
│   └── fluent-bit/
└── overlays/
    ├── cluster-196-central/
    ├── cluster-197-edge/
    └── cluster-198-edge/
```

**Implementation**:
- FR-001, FR-019: Base/overlay pattern
- FR-020: `kustomize build . --enable-helm | kubectl apply -f - -n <namespace>`

### Principle V: Observability & Monitoring

**Status**: ✅ COMPLIANT

**Verification**:
- Prometheus ServiceMonitors for all components (FR-010)
- Grafana dashboards: Thanos health, Prometheus federation, OpenSearch, Longhorn, NGINX (FR-011)
- Alerts: S3 connectivity, Thanos Sidecar failures, Prometheus scrapes, disk pressure (FR-012)
- Fluent-bit collects all pod logs (FR-009)
- Alertmanager notifications to operators (FR-012a, FR-012b)

**Implementation**:
- FR-010: ServiceMonitors for self-monitoring
- FR-011: Pre-configured Grafana dashboards
- FR-012, FR-012a, FR-012b: Alerting infrastructure with manual intervention

### Documentation Requirements

**Status**: ✅ COMPLIANT

**Deliverables**:
1. `docs/architecture.md`: Mermaid diagrams (3 clusters, data flows, network topology)
2. `docs/deployment.md`: Step-by-step Korean guide with deployment order
3. `docs/operations.md`: Korean troubleshooting and runbooks
4. `docs/quickstart.md`: 15-minute validation script

**Mermaid Diagrams Required**:
- Multi-cluster architecture (3 nodes, components per node)
- Data flow: Prometheus → Thanos Sidecar → S3, Thanos Query → Store Gateway
- Log flow: Pods → Fluent-bit → OpenSearch → S3
- Network topology: Ingress (*.mkube-{node}.miribit.lab) → Services

### Gate Result: ✅ PASS

No constitutional violations detected. All 5 core principles are satisfied by the design.

## Project Structure

### Documentation (this feature)

```
specs/001-thanos-multi-cluster/
├── spec.md                  # Feature specification (complete)
├── plan.md                  # This file (in progress)
├── research.md              # Phase 0 output (pending)
├── data-model.md            # Phase 1 output (pending)
├── quickstart.md            # Phase 1 output (pending)
├── contracts/               # Phase 1 output (pending)
│   ├── minikube-install.md
│   ├── longhorn-deployment.md
│   ├── nginx-ingress-deployment.md
│   ├── kube-prometheus-stack.md
│   ├── thanos-deployment.md
│   ├── opensearch-deployment.md
│   └── fluent-bit-deployment.md
└── tasks.md                 # Phase 2 output (/tasks command)
```

### Source Code (repository root)

```
thanos-multi-cluster/
├── deploy/
│   ├── base/
│   │   ├── longhorn/
│   │   │   ├── kustomization.yaml
│   │   │   └── values.yaml
│   │   ├── nginx-ingress/
│   │   │   ├── kustomization.yaml
│   │   │   └── values.yaml
│   │   ├── kube-prometheus-stack/
│   │   │   ├── kustomization.yaml
│   │   │   ├── values.yaml
│   │   │   └── servicemonitors/
│   │   ├── thanos/
│   │   │   ├── kustomization.yaml
│   │   │   ├── query.yaml
│   │   │   ├── store-gateway.yaml
│   │   │   ├── sidecar-config.yaml
│   │   │   └── s3-secret.yaml
│   │   ├── opensearch/
│   │   │   ├── kustomization.yaml
│   │   │   ├── values.yaml
│   │   │   └── snapshot-repository.yaml
│   │   └── fluent-bit/
│   │       ├── kustomization.yaml
│   │       └── values.yaml
│   └── overlays/
│       ├── cluster-196-central/
│       │   ├── kustomization.yaml
│       │   ├── ingress-hostnames.yaml
│       │   ├── thanos-query-patch.yaml
│       │   └── grafana-datasources.yaml
│       ├── cluster-197-edge/
│       │   ├── kustomization.yaml
│       │   ├── ingress-hostnames.yaml
│       │   └── thanos-sidecar-patch.yaml
│       └── cluster-198-edge/
│           ├── kustomization.yaml
│           ├── ingress-hostnames.yaml
│           └── thanos-sidecar-patch.yaml
├── scripts/
│   ├── install-minikube.sh
│   ├── deploy-cluster.sh
│   ├── validate-deployment.sh
│   └── backup-s3.sh
├── docs/
│   ├── architecture.md
│   ├── deployment.md
│   ├── operations.md
│   └── quickstart.md
└── tests/
    ├── validate-manifests.sh
    ├── health-checks/
    └── integration/
```

**Structure Decision**: Infrastructure deployment pattern with base/overlay structure for multi-cluster Kubernetes configuration management. Follows Kustomize best practices for managing multiple similar environments with shared base configurations.

## Complexity Tracking

*No constitutional violations detected. This section is empty.*

## Phase 0: Outline & Research

### Research Tasks

1. **Minikube + containerd Integration**
   - Research: Best practices for Minikube with containerd driver
   - Research: Resource requirements and performance characteristics
   - Research: Networking setup for multi-cluster scenarios

2. **Thanos Multi-Cluster Architecture**
   - Research: Thanos Sidecar vs Receiver patterns
   - Research: Thanos Store Gateway configuration for S3
   - Research: Thanos Query load balancing and federation
   - Research: Thanos Compactor necessity (deferred to future)

3. **Kustomize + Helm Integration**
   - Research: helmCharts feature in Kustomize 4.5+
   - Research: Best practices for values.yaml management in Kustomize
   - Research: Overlay strategies for multi-cluster deployments

4. **OpenSearch S3 Snapshot Configuration**
   - Research: OpenSearch snapshot repository setup for MinIO
   - Research: ISM (Index State Management) policies for 14-day retention
   - Research: S3 lifecycle policies for 180-day retention

5. **Longhorn Multi-Cluster Setup**
   - Research: Longhorn installation on Minikube
   - Research: Longhorn S3 backup target configuration
   - Research: Longhorn volume replication across single-node clusters

6. **DNS and Ingress Configuration**
   - Research: NGINX Ingress on Minikube with HostNetwork
   - Research: Wildcard DNS setup for *.mkube-{node}.miribit.lab
   - Research: Ingress path routing for multiple services

7. **Security: RBAC and Network Policies**
   - Research: Least-privilege ServiceAccounts for each component
   - Research: Network Policies for pod-to-pod communication restrictions
   - Research: Kubernetes Secrets management for S3 credentials

### Research Agents Dispatched

```bash
Task 1: "Research Minikube containerd driver best practices for multi-node monitoring cluster deployment"
Task 2: "Research Thanos multi-cluster architecture patterns with S3 storage and independent cluster operation"
Task 3: "Research Kustomize 4.5+ helmCharts feature with base/overlay pattern for 3 cluster environments"
Task 4: "Research OpenSearch S3 snapshot repository configuration with MinIO and ISM retention policies"
Task 5: "Research Longhorn installation on Minikube with S3 backup targets"
Task 6: "Research NGINX Ingress on Minikube with wildcard DNS and multiple service routing"
Task 7: "Research Kubernetes RBAC least-privilege patterns and Network Policies for monitoring stack"
```

### Output: research.md

Will contain consolidated findings for all 7 research areas with:
- Decisions made
- Rationale for each choice
- Alternatives considered and rejected
- Configuration recommendations

## Phase 1: Design & Contracts

*Prerequisites: research.md complete*

### 1. Data Model (`data-model.md`)

**Entities from Feature Spec**:

1. **Cluster**
   - Fields: name (196-central/197-edge/198-edge), ip_address, role (central/edge)
   - Relationships: Has many Components, Has one Minikube instance
   - Validation: IP must match 192.168.101.{196,197,198}

2. **Metric Block**
   - Fields: prometheus_instance, start_time, end_time, s3_path, size_bytes
   - Relationships: Uploaded by Thanos Sidecar, Stored in S3 Bucket
   - State transitions: Collected → Uploaded → Available in Store Gateway

3. **Log Entry**
   - Fields: timestamp, pod_name, namespace, log_level, message, cluster_source
   - Relationships: Collected by Fluent-bit, Stored in OpenSearch Index
   - Lifecycle: Emitted → Collected → Indexed → Snapshotted (14d) → Deleted (180d)

4. **S3 Bucket**
   - Fields: endpoint (https://172.20.40.21:30001), access_key (minio), secret_key (minio123)
   - Relationships: Stores Metric Blocks, Stores Log Snapshots, Stores Longhorn Backups
   - Validation: Endpoint must be reachable, credentials must be valid

5. **Storage Volume**
   - Fields: pvc_name, size, storage_class (longhorn), status, cluster
   - Relationships: Provisioned by Longhorn, Backed up to S3
   - State transitions: Pending → Bound → Backing Up → Backed Up

6. **Service Monitor**
   - Fields: name, namespace, selector, endpoints, scrape_interval (30s)
   - Relationships: Defines scrape targets for Prometheus
   - Validation: Selector must match existing services

7. **Dashboard**
   - Fields: name, datasource (Prometheus/Thanos), panels, variables (cluster filter)
   - Relationships: Deployed to Grafana, Queries Thanos Query endpoint
   - Validation: Must include cluster label for filtering

8. **Alert Rule**
   - Fields: name, expression, severity, duration, annotations
   - Relationships: Evaluated by Prometheus, Fired to Alertmanager
   - Lifecycle: Pending → Firing → Resolved

9. **Ingress Route**
   - Fields: hostname (grafana.mkube-{node}.miribit.lab), service_name, service_port
   - Relationships: Managed by NGINX Ingress Controller
   - Validation: Hostname must match pattern *.mkube-{196,197,198}.miribit.lab

### 2. API Contracts (`contracts/`)

Since this is infrastructure deployment (not application APIs), contracts are deployment contracts:

**Contract 1: `minikube-install.md`**
- Input: Node IP, CPU allocation (4+), RAM allocation (16GB+), driver (containerd)
- Output: Minikube cluster with kubectl access, Ready node status
- Validation: `minikube status` returns Running, `kubectl get nodes` shows Ready

**Contract 2: `longhorn-deployment.md`**
- Input: Minikube cluster context, S3 backup target config
- Output: Longhorn storage class available, system pods Running
- Validation: `kubectl get storageclass longhorn` exists, test PVC provisions in <60s

**Contract 3: `nginx-ingress-deployment.md`**
- Input: Cluster context, HostNetwork configuration
- Output: NGINX Ingress Controller Running, LoadBalancer/HostPort accessible
- Validation: Test Ingress routes to backend service successfully

**Contract 4: `kube-prometheus-stack.md`**
- Input: Cluster context, retention (2h), scrape interval (30s), S3 secret
- Output: Prometheus Operator, Prometheus, Grafana, Alertmanager Running
- Validation: Prometheus UI accessible, targets Up, Grafana dashboards loaded

**Contract 5: `thanos-deployment.md`**
- Input: Cluster context, role (central/edge), S3 config
- Output:
  - Central: Thanos Query (2 replicas), Store Gateway Running
  - Edge: Thanos Sidecar attached to Prometheus
- Validation: Thanos Query returns metrics from S3, Sidecar uploads blocks

**Contract 6: `opensearch-deployment.md`**
- Input: 3-node cluster info, S3 snapshot repo config, retention (14d local, 180d S3)
- Output: OpenSearch 3-node cluster, green health, snapshot repo registered
- Validation: Cluster health green, ISM policy active, test snapshot succeeds

**Contract 7: `fluent-bit-deployment.md`**
- Input: Cluster context, OpenSearch endpoints
- Output: Fluent-bit DaemonSet on all nodes, logs flowing to OpenSearch
- Validation: Test log appears in OpenSearch within 30s

### 3. Quickstart (`quickstart.md`)

15-minute validation script for MVP deployment:

```markdown
# Thanos Multi-Cluster Quickstart (15분)

## 사전 준비 (5분)
1. Node 196 SSH 접속: `ssh bsh@192.168.101.196` (password: 123qwe)
2. Minikube 설치 확인: `minikube version`
3. MinIO S3 접근 확인: `curl -k https://172.20.40.21:30001/minio/health/live`

## 배포 (8분)
1. Minikube 시작: `minikube start --driver=containerd --cpus=4 --memory=16384`
2. Longhorn 배포: `kustomize build deploy/overlays/cluster-196-central/longhorn | kubectl apply -f -`
3. Prometheus 배포: `kustomize build deploy/overlays/cluster-196-central/kube-prometheus-stack | kubectl apply -f -`
4. Grafana 접속: `https://grafana.mkube-196.miribit.lab`

## 검증 (2분)
1. Pod 상태: `kubectl get pods -n monitoring` (모두 Running 확인)
2. Prometheus targets: Prometheus UI → Status → Targets (모두 Up 확인)
3. Grafana 대시보드: "Thanos Overview" 대시보드에서 메트릭 확인
4. S3 업로드: `kubectl logs -n monitoring prometheus-0 thanos-sidecar` (upload success 확인)

## 성공 기준
- ✅ 모든 pods Running 상태
- ✅ Prometheus targets 100% Up
- ✅ Grafana 대시보드 데이터 표시
- ✅ Thanos Sidecar S3 업로드 성공
```

### 4. Agent Context Update

Will execute after Phase 1 design is complete:
```bash
.specify/scripts/bash/update-agent-context.sh claude
```

Updates `CLAUDE.md` with:
- Active Technologies: Kubernetes, Minikube, Kustomize, Helm, Thanos, Prometheus, OpenSearch, Fluent-bit, Longhorn, NGINX Ingress
- Commands: `kustomize build --enable-helm`, `kubectl apply`, `minikube start`
- Recent Changes: Added Thanos multi-cluster monitoring with S3 storage

## Phase 2: Task Planning Approach

*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:

### User Story 0: Minikube Installation (P0)
- Tasks per node (196, 197, 198):
  - T001 [P]: Install Minikube on node 196
  - T002 [P]: Install Minikube on node 197
  - T003 [P]: Install Minikube on node 198
  - T004: Validate all Minikube clusters are operational

### User Story 4: Infrastructure Storage Provisioning (P1)
- Tasks per cluster:
  - T005 [P]: Deploy Longhorn on cluster 196
  - T006 [P]: Deploy Longhorn on cluster 197
  - T007 [P]: Deploy Longhorn on cluster 198
  - T008 [P]: Deploy NGINX Ingress on cluster 196
  - T009 [P]: Deploy NGINX Ingress on cluster 197
  - T010 [P]: Deploy NGINX Ingress on cluster 198
  - T011: Configure S3 backup targets for Longhorn
  - T012: Validate storage and ingress deployment

### User Story 1: Central Cluster Deployment (P1)
- Tasks:
  - T013: Create S3 Secret for Thanos on cluster 196
  - T014: Deploy kube-prometheus-stack on cluster 196
  - T015: Deploy Thanos Query and Store Gateway on cluster 196
  - T016: Configure Grafana datasources pointing to Thanos Query
  - T017: Deploy Grafana dashboards (Thanos, Prometheus, OpenSearch, Longhorn, NGINX)
  - T018: Configure Alertmanager notification channels
  - T019: Validate central cluster monitoring stack

### User Story 2: Edge Cluster Deployment (P2)
- Tasks per edge cluster:
  - T020 [P]: Create S3 Secret for Thanos on cluster 197
  - T021 [P]: Create S3 Secret for Thanos on cluster 198
  - T022 [P]: Deploy kube-prometheus-stack with Thanos Sidecar on cluster 197
  - T023 [P]: Deploy kube-prometheus-stack with Thanos Sidecar on cluster 198
  - T024: Verify Thanos Sidecar uploads to S3 from cluster 197
  - T025: Verify Thanos Sidecar uploads to S3 from cluster 198
  - T026: Verify Thanos Query on 196 aggregates metrics from all clusters

### User Story 3: Log Collection (P3)
- Tasks:
  - T027 [P]: Deploy OpenSearch node on cluster 196
  - T028 [P]: Deploy OpenSearch node on cluster 197
  - T029 [P]: Deploy OpenSearch node on cluster 198
  - T030: Form OpenSearch 3-node cluster
  - T031: Configure S3 snapshot repository in OpenSearch
  - T032: Configure ISM policy for 14-day local retention
  - T033: Configure S3 lifecycle policy for 180-day retention
  - T034 [P]: Deploy Fluent-bit on cluster 196
  - T035 [P]: Deploy Fluent-bit on cluster 197
  - T036 [P]: Deploy Fluent-bit on cluster 198
  - T037: Validate log collection end-to-end

### User Story 5: Unified Dashboard (P3)
- Tasks:
  - T038: Configure Grafana to query all clusters via Thanos Query
  - T039: Test historical queries beyond 2-hour Prometheus retention
  - T040: Test cluster filtering in dashboards
  - T041: Validate alert firing and Alertmanager notifications

### Documentation Tasks
- T042 [P]: Generate architecture.md with Mermaid diagrams
- T043 [P]: Generate deployment.md in Korean
- T044 [P]: Generate operations.md runbooks in Korean
- T045: Validate quickstart.md executes successfully

**Ordering Strategy**:
1. P0 (Minikube) blocks all others
2. P1 (Storage/Ingress) blocks P1 (Central) and P2 (Edge)
3. P1 (Central) and P2 (Edge) can proceed in parallel after infrastructure
4. P3 (Logging, Dashboard) depends on P1 and P2 completion
5. Documentation can proceed in parallel with implementation

**Parallelism Markers**:
- [P] indicates tasks that can run concurrently (different nodes or independent components)
- Sequential tasks within each user story maintain dependencies

**Estimated Output**: 45 numbered, ordered tasks in tasks.md with clear dependencies and parallel execution opportunities.

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation

*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md with 45 numbered tasks)
**Phase 4**: Implementation (execute tasks.md sequentially by priority, parallelize [P] tasks)
**Phase 5**: Validation (run quickstart.md, verify all success criteria from spec.md)

## Progress Tracking

*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command) - research.md created
- [x] Phase 1: Design complete (/plan command) - data-model.md, contracts/, quickstart.md created
- [x] Phase 2: Task planning complete (/plan command - describe approach only) - 45 tasks outlined
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS (all 5 principles compliant)
- [x] Post-Design Constitution Check: PASS (no new violations introduced)
- [x] All NEEDS CLARIFICATION resolved (none identified)
- [x] Complexity deviations documented (none - no violations)

---
*Based on Constitution v1.0.0 - See `.specify/memory/constitution.md`*
