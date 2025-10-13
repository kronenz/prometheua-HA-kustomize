<!--
Sync Impact Report:
- Version change: Initial → 1.0.0
- Principles added:
  * I. Infrastructure as Code (IaC) First
  * II. Multi-Cluster Architecture
  * III. S3-Backed Storage (NON-NEGOTIABLE)
  * IV. Kustomize-Helm Integration
  * V. Observability & Monitoring
- Sections added:
  * Deployment Constraints
  * Documentation Requirements
- Templates requiring updates:
  * ✅ plan-template.md - Constitution Check section now references IaC, distributed systems, S3 storage
  * ✅ spec-template.md - User stories should align with multi-cluster deployment scenarios
  * ✅ tasks-template.md - Tasks should include Kubernetes/Helm/Kustomize deployment steps
- Follow-up TODOs:
  * S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY variables to be provided during deployment
  * Ratification date set to today as initial constitution
-->

# Thanos Multi-Cluster Monitoring Constitution

## Core Principles

### I. Infrastructure as Code (IaC) First

All infrastructure and application deployments MUST be defined as code using Kustomize and Helm charts. Manual deployments are prohibited.

**Rules:**
- Every component MUST have a declarative configuration in YAML
- Helm `install` command is FORBIDDEN; use only `kustomize build . --enable-helm | kubectl apply -f - -n <namespace>`
- All configurations MUST be version-controlled
- Changes require code review and approval before deployment
- Environment-specific values MUST be externalized (ConfigMaps, Secrets, or kustomization overlays)

**Rationale:** Ensures reproducibility, auditability, disaster recovery capability, and prevents configuration drift across clusters.

### II. Multi-Cluster Architecture

The system operates as a distributed multi-cluster architecture with centralized query capabilities.

**Rules:**
- Node 192.168.101.196 is the CENTRAL cluster hosting Thanos Query, Query Frontend, and aggregation components
- Nodes 192.168.101.197 and 192.168.101.198 are DISTRIBUTED clusters with local Prometheus + Thanos Sidecars
- Each cluster MUST be independently operational (autonomy principle)
- Central cluster failure MUST NOT impact local cluster monitoring capabilities
- All clusters MUST share a common object storage backend (S3)
- Load balancing MUST distribute query load across available Thanos Query instances

**Rationale:** Provides scalability, fault tolerance, and overcomes single Prometheus instance limitations (retention, cardinality, high availability).

### III. S3-Backed Storage (NON-NEGOTIABLE)

Local storage (hostPath, emptyDir) is PROHIBITED for persistent metrics and logs. All persistent data MUST reside in S3-compatible object storage.

**Rules:**
- Prometheus local retention: maximum 2 hours (for query performance only)
- Long-term metrics storage: Thanos S3 buckets via Thanos Sidecar/Store Gateway
- Log storage: OpenSearch with S3 snapshots for retention
- Fluent-bit MUST NOT use local disk buffering; use memory or S3 direct shipping
- S3 credentials MUST be managed via Kubernetes Secrets
- S3 endpoint, bucket names, and access keys MUST be parameterized (not hardcoded)

**Rationale:** Eliminates single points of failure, enables unlimited retention, ensures data durability, and simplifies backup/restore operations.

### IV. Kustomize-Helm Integration

Helm charts from ArtifactHub MUST be consumed through Kustomize helmCharts feature for unified configuration management.

**Rules:**
- Primary configuration via `values.yaml` within kustomization directories
- Unavoidable customizations (non-Helm resources) go in `kustomization.yaml` resources section
- Each component (kube-prometheus-stack, OpenSearch, Fluent-bit, Longhorn, NGINX Ingress) has dedicated kustomization directory
- Base/overlay pattern: base configurations for shared settings, overlays per cluster (196, 197, 198)
- Deployment command standard: `kustomize build <path> --enable-helm | kubectl apply -f - -n <namespace>`

**Rationale:** Combines Helm ecosystem benefits with Kustomize's patching and overlay capabilities; ensures consistency and simplifies multi-environment management.

### V. Observability & Monitoring

All components MUST emit structured logs, metrics, and traces where applicable. Monitoring the monitoring stack is mandatory.

**Rules:**
- Prometheus ServiceMonitors for all deployable components (including Thanos, OpenSearch, Fluent-bit)
- Fluent-bit MUST collect logs from all pods (including kube-system)
- OpenSearch MUST have retention policies configured (align with S3 lifecycle policies)
- Grafana dashboards for: Thanos health, Prometheus federation status, OpenSearch cluster health, Longhorn storage health, NGINX Ingress traffic
- Alerts for: S3 connectivity loss, Thanos Sidecar upload failures, Prometheus scrape failures, disk pressure (pre-eviction warning)

**Rationale:** Proactive issue detection, troubleshooting capability, capacity planning, and operational transparency.

## Deployment Constraints

### Technology Stack (Mandatory)

- **Kubernetes Distribution:** Minikube (single-node clusters per host)
- **Storage Class:** Longhorn (distributed block storage across local disks, with S3 backup targets)
- **Ingress Controller:** NGINX Ingress Controller
- **Monitoring Stack:** kube-prometheus-stack (Prometheus Operator + Grafana + Alertmanager) + Thanos
- **Logging Stack:** OpenSearch + Fluent-bit (Fluent-d only if OpenSearch ingestion requires transformation)
- **Object Storage:** MinIO S3 (or compatible provider, externally managed)
- **Deployment Tool:** Kustomize 4.5+ with Helm chart inflation

### Node Access & Security

- SSH access: `bsh / 123qwe` (credentials MUST be rotated post-deployment and managed via secrets management tool in production)
- RBAC policies MUST follow principle of least privilege
- ServiceAccounts for each component with explicit role bindings
- Network Policies to restrict inter-pod communication (logging → OpenSearch, sidecars → S3, Thanos Query → Store Gateways)

### Load Distribution

- Thanos Query: Minimum 2 replicas with anti-affinity (spread across central + one distributed node if resources allow)
- Prometheus: 1 instance per cluster (Operator manages HA if configured)
- OpenSearch: 3-node cluster (1 per host) with shard replication factor 2
- NGINX Ingress: 1 controller per cluster with HostNetwork or LoadBalancer (Minikube limitation workaround)

## Documentation Requirements

All documentation MUST be written in Korean with detailed explanations and MUST include Mermaid diagrams for architecture visualization.

**Mandatory Documents:**

1. **Architecture Overview (`docs/architecture.md`)**
   - Mermaid diagram showing: 3 clusters, Thanos components placement, data flow (metrics, logs), S3 integration
   - Component interaction diagram: Prometheus → Thanos Sidecar → S3, Thanos Query → Store Gateway, Fluent-bit → OpenSearch
   - Network topology: Ingress routing, internal service mesh

2. **Deployment Guide (`docs/deployment.md`)**
   - Step-by-step per-node installation (Korean)
   - Pre-requisites checklist (Minikube, kubectl, kustomize versions)
   - Environment variable configuration (S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY, S3_SECRET_KEY)
   - Deployment order: 1. Longhorn → 2. NGINX Ingress → 3. kube-prometheus-stack → 4. Thanos → 5. OpenSearch → 6. Fluent-bit
   - Validation steps per component (health checks, sample queries)

3. **Operations Runbook (`docs/operations.md`)**
   - Troubleshooting common issues (Korean)
   - Backup and restore procedures
   - Scaling procedures (adding new clusters)
   - Alert response playbooks

4. **Quickstart (`docs/quickstart.md`)**
   - 15-minute minimal viable deployment for testing
   - Sample dashboards and queries
   - Verification checklist

**Diagram Requirements:**
- Use Mermaid syntax (graph TD, sequenceDiagram, C4Context where appropriate)
- Include all 3 nodes explicitly labeled (196-central, 197-edge, 198-edge)
- Show data persistence paths (emphemeral vs. S3)
- Color-code by concern: monitoring (blue), logging (green), storage (orange), ingress (purple)

## Governance

**Authority:** This constitution supersedes all other practices, conventions, or undocumented decisions.

**Amendment Process:**
1. Proposed change documented with rationale (why current principle insufficient)
2. Impact analysis on existing deployments and documentation
3. Approval from infrastructure lead
4. Version bump per semantic versioning (MAJOR.MINOR.PATCH)
5. Migration plan for existing clusters (if breaking change)
6. Documentation updates in lockstep with constitution change

**Compliance:**
- All pull requests MUST reference constitution principles in design decisions
- Code reviews MUST verify: no local storage, Kustomize-only deployment, S3 integration present
- Complexity violations (e.g., additional proprietary component) MUST be justified in plan.md Complexity Tracking table
- Quarterly audits to verify deployed state matches IaC definitions

**Versioning Policy:**
- **MAJOR**: Breaking changes (e.g., removing Prometheus Operator, switching to Loki)
- **MINOR**: New principles or technology additions (e.g., adding service mesh requirement)
- **PATCH**: Clarifications, documentation fixes, non-functional improvements

**Development Guidance:**
- Use `CLAUDE.md` in project root for agent-specific runtime instructions
- Use `.specify/memory/constitution.md` (this file) for governance and non-negotiable principles

**Version**: 1.0.0 | **Ratified**: 2025-10-13 | **Last Amended**: 2025-10-13
