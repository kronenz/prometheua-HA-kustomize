# Feature Specification: Thanos Multi-Cluster Monitoring Infrastructure

**Feature Branch**: `001-thanos-multi-cluster`
**Created**: 2025-10-13
**Status**: Draft
**Input**: Thanos Multi-Cluster Monitoring Infrastructure

## User Scenarios & Testing *(mandatory)*

### User Story 0 - Minikube Installation on All Nodes (Priority: P0)

Infrastructure operator installs and configures Minikube on all three nodes (192.168.101.196, 192.168.101.197, 192.168.101.198) to create independent Kubernetes clusters.

**Why this priority**: This is the absolute first step. Without Kubernetes clusters running on each node, no monitoring infrastructure can be deployed. This is a blocking prerequisite for all other stories.

**Independent Test**: Can be fully tested by SSH-ing to each node, running Minikube installation commands, verifying cluster status with `kubectl get nodes`, and confirming basic pod deployment works.

**Acceptance Scenarios**:

1. **Given** operator has SSH access to all three nodes with credentials `bsh / 123qwe`, **When** operator runs Minikube installation script on node 196, **Then** Minikube starts successfully and `kubectl get nodes` shows Ready status
2. **Given** Minikube is installed on node 196, **When** operator deploys test pod, **Then** pod schedules and runs successfully
3. **Given** operator installs Minikube on nodes 197 and 198, **When** operator verifies each cluster independently, **Then** all three clusters are operational and isolated from each other
4. **Given** all three Minikube clusters are running, **When** operator checks resource allocation, **Then** each cluster has minimum 4 CPU and 16GB RAM available

---

### User Story 1 - Central Cluster Deployment (Priority: P1)

Infrastructure operator deploys the central monitoring cluster on node 192.168.101.196 that aggregates metrics from all edge clusters and provides a unified query interface.

**Why this priority**: After Kubernetes clusters are ready, this is the foundation of the multi-cluster monitoring architecture. Without the central cluster, there's no aggregation point for distributed metrics.

**Independent Test**: Can be fully tested by deploying to node 196, verifying Thanos Query responds to health checks, and confirming S3 connectivity for historical data retrieval.

**Acceptance Scenarios**:

1. **Given** Minikube is running on node 196, **When** operator deploys central cluster configuration, **Then** Thanos Query, Query Frontend, and Store Gateway components are running and healthy
2. **Given** central cluster is deployed, **When** operator queries Thanos Query endpoint, **Then** system returns available time series data from S3 storage
3. **Given** central cluster is operational, **When** MinIO S3 endpoint (https://172.20.40.21:30001) becomes unavailable, **Then** system logs S3 connectivity errors and sends alerts to operators
4. **Given** central cluster components are running, **When** operator accesses Grafana at grafana.mkube-196.miribit.lab, **Then** dashboards display Thanos health metrics and query performance

---

### User Story 2 - Distributed Edge Cluster Deployment (Priority: P2)

Infrastructure operator deploys edge monitoring clusters on nodes 192.168.101.197 and 192.168.101.198 that collect local metrics and ship them to S3 for central aggregation.

**Why this priority**: Edge clusters provide local monitoring autonomy and feed data to the central cluster. They can be deployed incrementally after central cluster is operational.

**Independent Test**: Can be tested by deploying to nodes 197/198, verifying local Prometheus scrapes metrics, confirming Thanos Sidecar uploads blocks to S3, and validating local Grafana access.

**Acceptance Scenarios**:

1. **Given** Minikube is running on edge nodes 197/198, **When** operator deploys edge cluster configuration, **Then** Prometheus, Thanos Sidecar, and local Grafana are running and healthy
2. **Given** edge cluster is deployed, **When** Prometheus scrapes local targets for 2+ hours, **Then** Thanos Sidecar uploads metric blocks to S3 storage
3. **Given** edge cluster is operational, **When** central cluster is unavailable, **Then** local Prometheus continues collecting metrics and local Grafana remains accessible
4. **Given** edge cluster Thanos Sidecar is configured, **When** S3 upload fails, **Then** system retries uploads and sends alerts to operators

---

### User Story 3 - Unified Log Collection and Storage (Priority: P3)

Infrastructure operator deploys OpenSearch cluster and Fluent-bit agents across all nodes to collect, aggregate, and store logs from all Kubernetes pods with S3-backed retention.

**Why this priority**: Log aggregation enhances observability but is not critical for core metrics monitoring. Can be deployed after monitoring infrastructure is stable.

**Independent Test**: Can be tested by deploying OpenSearch cluster, configuring Fluent-bit on all nodes, verifying log ingestion from sample pods, and confirming S3 snapshot functionality.

**Acceptance Scenarios**:

1. **Given** OpenSearch cluster is deployed across 3 nodes, **When** operator checks cluster health, **Then** all OpenSearch nodes are green with shard replication factor 2
2. **Given** Fluent-bit is deployed as DaemonSet, **When** pods emit logs, **Then** Fluent-bit collects and forwards logs to OpenSearch within 30 seconds
3. **Given** OpenSearch contains log data, **When** operator creates S3 snapshot, **Then** snapshot is successfully stored in S3 bucket
4. **Given** OpenSearch is configured with 14-day local retention and 180-day S3 retention, **When** logs exceed retention periods, **Then** logs older than 14 days are moved to S3 and logs older than 180 days are deleted from S3

---

### User Story 4 - Infrastructure Storage Provisioning (Priority: P1)

Infrastructure operator deploys Longhorn distributed storage and NGINX Ingress controller on all clusters to provide persistent storage and external access to monitoring interfaces.

**Why this priority**: This is foundational infrastructure required before deploying any monitoring components. Storage and ingress are blocking dependencies.

**Independent Test**: Can be tested by deploying Longhorn and NGINX Ingress, creating test PersistentVolumeClaim, verifying volume provisioning, and confirming ingress routing to test service.

**Acceptance Scenarios**:

1. **Given** Minikube is running on all nodes, **When** operator deploys Longhorn storage class, **Then** Longhorn components are running and storage class is available
2. **Given** Longhorn is operational, **When** operator creates PersistentVolumeClaim, **Then** volume is provisioned and bound within 60 seconds
3. **Given** NGINX Ingress is deployed, **When** operator creates Ingress resource for test service, **Then** service is accessible via ingress hostname
4. **Given** Longhorn is configured with S3 backup target, **When** operator creates volume backup, **Then** backup is successfully stored in S3

---

### User Story 5 - Unified Monitoring Dashboard Access (Priority: P3)

Operations team accesses centralized Grafana dashboards to view metrics from all clusters, query historical data, and monitor system health across the entire infrastructure.

**Why this priority**: This is the end-user experience that ties everything together. Requires all other stories to be complete for full functionality.

**Independent Test**: Can be tested by accessing Grafana UI, running sample queries across all clusters, viewing pre-configured dashboards, and verifying data from all time ranges (recent + historical from S3).

**Acceptance Scenarios**:

1. **Given** all clusters are operational, **When** operator accesses central Grafana at grafana.mkube-196.miribit.lab, **Then** dashboards display metrics from all three clusters (196, 197, 198)
2. **Given** operator is viewing Grafana, **When** operator queries historical metrics beyond 2-hour Prometheus retention, **Then** Thanos Query retrieves data from S3 and displays results
3. **Given** operator is viewing dashboards, **When** operator selects cluster filter, **Then** dashboards show metrics only from selected cluster
4. **Given** monitoring stack is deployed, **When** operator views Thanos health dashboard, **Then** dashboard shows sidecar upload status, query performance, and S3 connectivity for all clusters

---

### Edge Cases

- What happens when Minikube installation fails due to insufficient resources?
- How does system handle Minikube cluster restart or node reboot?
- What happens when S3 endpoint becomes unreachable during metric upload? (Alert sent to operator for manual intervention)
- What happens when multiple alerts fire simultaneously? (Alertmanager groups and sends consolidated notifications)
- How does system handle Thanos Query failures while edge clusters continue collecting metrics?
- What happens when operator deploys configuration changes to running clusters?
- How does system handle node failures and automatic pod rescheduling?
- What happens when Prometheus local retention fills up before Thanos Sidecar uploads blocks?
- How does system handle network partitions between clusters?
- What happens when OpenSearch cluster loses quorum (2 of 3 nodes down)?
- How does system handle simultaneous deployment to multiple clusters?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-000**: System MUST install Minikube on all three nodes (192.168.101.196, 192.168.101.197, 192.168.101.198) with containerd driver and minimum 4 CPU and 16GB RAM allocation per cluster
- **FR-001**: System MUST deploy all components using Kustomize with Helm chart inflation (no direct `helm install` commands allowed)
- **FR-002**: System MUST provision persistent storage via Longhorn storage class on all clusters
- **FR-003**: System MUST configure NGINX Ingress controller for external access to Grafana, Prometheus, and OpenSearch interfaces
- **FR-003a**: System MUST configure ingress hostnames using pattern: grafana.mkube-{node}.miribit.lab, prometheus.mkube-{node}.miribit.lab, opensearch.mkube-{node}.miribit.lab where {node} is 196, 197, or 198
- **FR-004**: System MUST deploy Prometheus Operator with 2-hour local metric retention and 30-second scrape interval on each cluster
- **FR-005**: System MUST deploy Thanos Sidecar alongside Prometheus on edge clusters (197, 198) to upload metric blocks to S3
- **FR-006**: System MUST deploy Thanos Query, Query Frontend, and Store Gateway on central cluster (196) for metric aggregation
- **FR-007**: System MUST configure S3 storage backend with endpoint https://172.20.40.21:30001 and credentials (access key: minio, secret key: minio123)
- **FR-007a**: System MUST store S3 credentials in Kubernetes Secrets and reference them in Thanos and OpenSearch configurations
- **FR-008**: System MUST deploy OpenSearch as 3-node cluster (1 per host) with shard replication factor 2
- **FR-009**: System MUST deploy Fluent-bit as DaemonSet on all clusters to collect pod logs
- **FR-009a**: System MUST configure OpenSearch to retain logs locally for 14 days, then move to S3 snapshots
- **FR-009b**: System MUST configure S3 lifecycle policy to delete log snapshots after 180 days
- **FR-010**: System MUST configure Prometheus ServiceMonitors for all monitoring components (Thanos, OpenSearch, Fluent-bit, Longhorn, NGINX Ingress)
- **FR-011**: System MUST configure Grafana dashboards for Thanos health, Prometheus federation, OpenSearch cluster health, Longhorn storage, and NGINX Ingress traffic
- **FR-012**: System MUST configure alerts for S3 connectivity loss, Thanos Sidecar upload failures, Prometheus scrape failures, and disk pressure warnings
- **FR-012a**: System MUST configure Alertmanager to send notifications to operators via configured channels (email, webhook, or Slack)
- **FR-012b**: System MUST NOT implement automated remediation actions; all alert responses require manual operator intervention
- **FR-013**: System MUST prohibit local storage (hostPath, emptyDir) for persistent data; all metric and log persistence uses S3
- **FR-014**: System MUST ensure each cluster operates independently (edge cluster failures do not impact central cluster and vice versa)
- **FR-015**: System MUST configure Thanos Query with minimum 2 replicas with pod anti-affinity rules
- **FR-016**: System MUST configure RBAC policies following principle of least privilege for all service accounts
- **FR-017**: System MUST configure Network Policies to restrict pod-to-pod communication (Fluent-bit→OpenSearch, Thanos Sidecar→S3, Thanos Query→Store Gateway)
- **FR-018**: System MUST externalize all environment-specific configuration via ConfigMaps, Secrets, or Kustomize overlays
- **FR-019**: System MUST use base/overlay pattern: base configs for shared settings, overlays per cluster (196, 197, 198)
- **FR-020**: System MUST support deployment command: `kustomize build <path> --enable-helm | kubectl apply -f - -n <namespace>`

### Key Entities

- **Cluster**: Represents a Minikube Kubernetes cluster on a single node (196-central, 197-edge, 198-edge)
- **Metric Block**: 2-hour chunks of Prometheus time series data uploaded to S3 by Thanos Sidecar
- **Log Entry**: Structured log line collected by Fluent-bit and stored in OpenSearch
- **S3 Bucket**: Object storage container for persistent metrics, logs, and backups
- **Storage Volume**: Longhorn-provisioned persistent volume for component state (non-metrics/logs data)
- **Service Monitor**: Prometheus Operator custom resource defining scrape targets for metrics collection
- **Dashboard**: Grafana visualization showing metrics from one or multiple clusters
- **Alert Rule**: Prometheus alert definition triggering on specific metric conditions
- **Ingress Route**: NGINX Ingress routing rule for external access to internal services

## Clarifications

### Session 2025-10-13

- Q: What is the log retention period for OpenSearch (local) and S3 archive? → A: 14일 로컬 보관 후 S3 이동, S3에서 180일 후 삭제
- Q: Which container runtime driver should Minikube use? → A: containerd driver
- Q: How should the system respond when alerts are triggered? → A: Alert 발생 시 Alertmanager를 통해 오퍼레이터에게 알림만 전송 (수동 대응)
- Q: What hostname pattern should be used for ingress access to monitoring UIs? → A: *.mkube-196.miribit.lab, *.mkube-197.miribit.lab, *.mkube-198.miribit.lab
- Q: What scrape interval should Prometheus use for collecting metrics? → A: 30초
- Q: What are the S3 storage endpoint and credentials? → A: https://172.20.40.21:30001, minio/minio123

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-000**: Operators can install Minikube on all 3 nodes within 15 minutes using documented procedures
- **SC-001**: Operators can deploy complete monitoring infrastructure to all 3 nodes within 60 minutes using documented procedures (after Minikube installation)
- **SC-002**: System retains metrics for unlimited duration via S3 storage while maintaining 2-hour local retention for query performance
- **SC-003**: Central cluster aggregates and displays metrics from all 3 clusters in unified Grafana dashboards
- **SC-004**: Operators can query historical metrics from any cluster covering any time range stored in S3
- **SC-005**: System continues local monitoring operations when central cluster is unavailable (autonomy validation)
- **SC-006**: Log collection captures logs from all pods across all clusters with less than 30-second ingestion delay
- **SC-007**: System detects and alerts on S3 connectivity failures within 5 minutes of occurrence
- **SC-008**: Storage provisioning responds to PersistentVolumeClaim requests within 60 seconds
- **SC-009**: Grafana dashboards load and display data from all clusters within 5 seconds under normal load
- **SC-010**: System supports concurrent queries from multiple operators without performance degradation
- **SC-011**: OpenSearch cluster maintains green health status with shard replication across all 3 nodes
- **SC-012**: System survives single node failure without data loss (replication validation)
- **SC-013**: Deployment configurations are version-controlled and reproducible across environments
- **SC-014**: Zero manual deployment steps required; all operations use declarative Kustomize configurations

## Assumptions *(optional)*

- Nodes are running Linux OS with containerd runtime available
- Nodes have network connectivity to each other and to MinIO S3 endpoint at 172.20.40.21:30001
- Nodes have internet connectivity for downloading Minikube binary and container images
- MinIO S3 storage is deployed at https://172.20.40.21:30001 and accessible with credentials minio/minio123
- Nodes have sufficient resources for assigned components (minimum 4 CPU, 16GB RAM per node recommended)
- Kustomize 4.5+ and kubectl are installed on operator workstation
- SSH access to nodes uses credentials `bsh / 123qwe` (to be rotated post-deployment)
- All Helm charts sourced from ArtifactHub (kube-prometheus-stack, opensearch, fluent-bit, longhorn, nginx-ingress)
- DNS wildcard records configured for *.mkube-196.miribit.lab, *.mkube-197.miribit.lab, *.mkube-198.miribit.lab pointing to respective node IPs
- Korean language documentation is required for operational procedures
- Node 196 is designated as central cluster and has additional capacity for aggregation workload
- Nodes 197 and 198 are designated as edge clusters with identical configurations

## Dependencies *(optional)*

- MinIO S3 storage at https://172.20.40.21:30001 (externally managed)
- Linux OS with containerd runtime on all target nodes
- kubectl binary available for cluster management
- Network connectivity between all nodes (192.168.101.196-198) and MinIO endpoint (172.20.40.21:30001)
- Sufficient disk space on each node for Longhorn storage provisioning
- Helm charts availability from ArtifactHub (internet connectivity or internal mirror)

## Out of Scope *(optional)*

- MinIO S3 storage deployment and configuration (assumed to be externally managed at https://172.20.40.21:30001)
- Base Linux OS installation and configuration on nodes
- containerd runtime installation
- DNS wildcard record setup for *.mkube-{196,197,198}.miribit.lab (assumed to be pre-configured)
- TLS certificate provisioning and management for HTTPS ingress
- Authentication and authorization for Grafana/Prometheus/OpenSearch UI access (basic auth assumed initially)
- Multi-tenancy isolation between different application teams
- Advanced Thanos features (Compactor, Ruler, Downsampling) beyond basic Query/Sidecar/Store
- Custom Prometheus exporters for application-specific metrics
- Log parsing and transformation beyond basic Fluent-bit forwarding
- Backup scheduling and retention automation (manual backup process acceptable)
- Disaster recovery automation and testing procedures
- Performance tuning and capacity planning for production scale
- Cost optimization for S3 storage lifecycle policies
