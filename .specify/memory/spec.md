# Feature Specification: Thanos Multi-Cluster Monitoring Infrastructure with kubeadm

**Feature Branch**: `001-thanos-multi-cluster`
**Created**: 2025-10-13
**Updated**: 2025-10-14 (Changed to 4 independent kubeadm clusters)
**Status**: Draft - Architecture Updated
**Input**: Thanos Multi-Cluster Monitoring Infrastructure

## User Scenarios & Testing *(mandatory)*

### User Story 0 - Kubernetes Cluster Installation with kubeadm (Priority: P0)

Infrastructure operator installs and configures 4 independent Kubernetes clusters using kubeadm, one per node (192.168.101.194, 196, 197, 198), where each node runs both control plane and worker components as a single-node cluster.

**Why this priority**: This is the absolute first step. Four independent single-node Kubernetes clusters are required to create a distributed monitoring infrastructure with Thanos multi-cluster aggregation.

**Independent Test**: Can be fully tested by SSH-ing to each node, running kubeadm installation commands, verifying cluster status with `kubectl get nodes` on each cluster independently, confirming each node is Ready.

**Acceptance Scenarios**:

1. **Given** operator has SSH access to all four nodes with credentials `bsh / 123qwe`, **When** operator initializes kubeadm on node 194, **Then** cluster-01 control plane starts successfully and `kubectl get nodes` shows node 194 Ready
2. **Given** operator repeats kubeadm init on nodes 196, 197, 198, **When** operator verifies each cluster independently, **Then** all 4 single-node clusters show Ready status with role "control-plane,worker"
3. **Given** all clusters are operational, **When** operator deploys test pod on each cluster, **Then** pods run successfully on their respective nodes
4. **Given** clusters are operational, **When** operator checks network connectivity between clusters, **Then** all clusters can reach each other and the S3 endpoint

---

### User Story 1 - Per-Cluster Prometheus Deployment (Priority: P1)

Infrastructure operator deploys Prometheus on each of the 4 independent clusters (cluster-01 through cluster-04) with Thanos Sidecar for metrics collection and S3 upload.

**Why this priority**: After Kubernetes clusters are ready, Prometheus on each cluster ensures local metrics collection. Each cluster operates independently with its own Prometheus instance.

**Independent Test**: Can be fully tested by deploying Prometheus on each cluster, verifying metrics collection locally, confirming Thanos Sidecar uploads blocks to S3 with unique cluster labels.

**Acceptance Scenarios**:

1. **Given** 4 Kubernetes clusters are running, **When** operator deploys Prometheus on cluster-01 (node 194), **Then** Prometheus collects metrics from cluster-01 resources and Thanos Sidecar uploads to S3 with label `cluster: "cluster-01"`
2. **Given** operator repeats deployment on clusters 02-04, **When** operator verifies each Prometheus independently, **Then** all 4 Prometheus instances collect metrics from their respective clusters
3. **Given** Prometheus is operational on all clusters, **When** one cluster fails, **Then** other clusters continue collecting metrics without interruption (cluster autonomy)
4. **Given** Prometheus is configured with Thanos Sidecar on all clusters, **When** operator checks S3 bucket, **Then** metric blocks from all 4 clusters are uploaded with unique cluster labels

---

### User Story 2 - Central Thanos Query and Multi-Cluster Aggregation (Priority: P2)

Infrastructure operator deploys Thanos Query, Query Frontend, and Store Gateway on cluster-01 (central cluster) to provide global view of metrics from all 4 clusters with S3-backed long-term storage.

**Why this priority**: Thanos Query provides the unified interface to query metrics across all 4 independent clusters, aggregates data, and enables querying historical data from S3.

**Independent Test**: Can be tested by deploying Thanos components on cluster-01, querying through Thanos Query, verifying aggregation of metrics from all 4 clusters, and confirming historical query from S3.

**Acceptance Scenarios**:

1. **Given** Prometheus with Thanos Sidecar is running on all 4 clusters, **When** operator deploys Thanos Query on cluster-01 with StoreAPI endpoints configured for all 4 Sidecars, **Then** Thanos Query discovers all Prometheus instances across all clusters and aggregates their metrics
2. **Given** Thanos Query is operational, **When** operator queries a metric, **Then** Thanos aggregates data from all 4 clusters (cluster-01, cluster-02, cluster-03, cluster-04) and returns unified time series with cluster labels
3. **Given** Thanos Store Gateway is deployed on cluster-01, **When** operator queries metrics older than Prometheus retention (2h), **Then** Store Gateway retrieves data from S3 and Thanos Query returns historical results from all clusters
4. **Given** Thanos Query Frontend is configured, **When** operator runs query spanning long time range across all clusters, **Then** Query Frontend splits query into smaller chunks and parallelizes execution for better performance

---

### User Story 3 - Per-Cluster Log Collection and Central Storage (Priority: P3)

Infrastructure operator deploys OpenSearch on cluster-01 (central) and Fluent-bit agents on all 4 clusters to collect and forward logs from all Kubernetes pods to central OpenSearch with S3-backed retention.

**Why this priority**: Log aggregation enhances observability but is not critical for core metrics monitoring. Can be deployed after monitoring infrastructure is stable.

**Independent Test**: Can be tested by deploying OpenSearch on cluster-01, configuring Fluent-bit on all 4 clusters, verifying log ingestion from pods across all clusters, and confirming S3 snapshot functionality.

**Acceptance Scenarios**:

1. **Given** OpenSearch cluster is deployed on cluster-01, **When** operator checks cluster health, **Then** OpenSearch is operational and ready to receive logs
2. **Given** Fluent-bit is deployed as DaemonSet on all 4 clusters, **When** pods emit logs on any cluster, **Then** Fluent-bit collects and forwards logs to central OpenSearch on cluster-01 within 30 seconds
3. **Given** OpenSearch contains log data from all clusters, **When** operator creates S3 snapshot, **Then** snapshot is successfully stored in S3 bucket with logs from all 4 clusters
4. **Given** OpenSearch is configured with 14-day local retention and 180-day S3 retention, **When** logs exceed retention periods, **Then** logs older than 14 days are moved to S3 and logs older than 180 days are deleted from S3

---

### User Story 4 - Infrastructure Storage and Ingress Provisioning (Priority: P1)

Infrastructure operator deploys Longhorn distributed storage and NGINX Ingress controller on each of the 4 clusters to provide persistent storage and external access to monitoring interfaces.

**Why this priority**: This is foundational infrastructure required before deploying any monitoring components. Storage and ingress are blocking dependencies for each cluster.

**Independent Test**: Can be tested by deploying Longhorn and NGINX Ingress on each cluster independently, creating test PersistentVolumeClaim, verifying volume provisioning, and confirming ingress routing to test service.

**Acceptance Scenarios**:

1. **Given** 4 Kubernetes clusters are running, **When** operator deploys Longhorn storage class on each cluster, **Then** Longhorn components are running and storage class is available on all clusters
2. **Given** Longhorn is operational on all clusters, **When** operator creates PersistentVolumeClaim on any cluster, **Then** volume is provisioned and bound within 60 seconds on that cluster
3. **Given** NGINX Ingress is deployed on all clusters, **When** operator creates Ingress resource for test service, **Then** service is accessible via ingress hostname (*.k8s-cluster-01.miribit.lab, *.k8s-cluster-02.miribit.lab, etc.)
4. **Given** Longhorn is configured with S3 backup target on all clusters, **When** operator creates volume backup, **Then** backup is successfully stored in S3 from each cluster

---

### User Story 5 - Unified Multi-Cluster Monitoring Dashboard Access (Priority: P3)

Operations team accesses centralized Grafana dashboard on cluster-01 to view metrics from all 4 clusters, query historical data, and monitor system health across the entire infrastructure.

**Why this priority**: This is the end-user experience that ties everything together. Requires all other stories to be complete for full functionality.

**Independent Test**: Can be tested by accessing Grafana UI on cluster-01, running sample queries across all 4 clusters, viewing pre-configured dashboards, and verifying data from all clusters and time ranges (recent + historical from S3).

**Acceptance Scenarios**:

1. **Given** Prometheus with Thanos Sidecar is operational on all 4 clusters, **When** operator accesses Grafana at grafana.k8s-cluster-01.miribit.lab, **Then** dashboards display metrics from all 4 clusters (cluster-01, cluster-02, cluster-03, cluster-04)
2. **Given** operator is viewing Grafana, **When** operator queries historical metrics beyond 2-hour Prometheus retention, **Then** Thanos Query retrieves data from S3 and displays results from all clusters
3. **Given** operator is viewing dashboards, **When** operator selects cluster filter, **Then** dashboards show metrics only from selected cluster (cluster-01, cluster-02, cluster-03, or cluster-04)
4. **Given** monitoring stack is deployed, **When** operator views Thanos health dashboard, **Then** dashboard shows sidecar upload status, query performance, S3 connectivity for all 4 clusters

---

### Edge Cases

- What happens when kubeadm init fails on a node during single-node cluster setup?
- How does system handle complete cluster failure (one of the 4 clusters goes down)?
- What happens when S3 endpoint becomes unreachable during metric upload? (Alert sent to operator for manual intervention)
- What happens when multiple alerts fire simultaneously from different clusters? (Alertmanager groups and sends consolidated notifications)
- How does system handle Thanos Query failures on cluster-01 while other clusters continue collecting metrics?
- What happens when operator deploys configuration changes to one cluster?
- How does system handle node/cluster failures with respect to cluster autonomy?
- What happens when Prometheus local retention fills up before Thanos Sidecar uploads blocks?
- What happens when network partition isolates one cluster from others?
- What happens when OpenSearch on cluster-01 goes down but other clusters continue generating logs?
- How does system handle rolling updates to Prometheus on each cluster without data loss?
- What happens when clocks are skewed between different clusters?
- How does Thanos Query handle temporary unavailability of one or more cluster Sidecars (StoreAPI endpoints)?
- What happens when Fluent-bit on one cluster cannot reach central OpenSearch on cluster-01?
- How does system handle DNS resolution failures for cluster-specific hostnames?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-000**: System MUST install 4 independent Kubernetes clusters using kubeadm on nodes (192.168.101.194, 196, 197, 198) with containerd runtime, where each node functions as a single-node cluster with both control-plane and worker roles
- **FR-001**: System MUST deploy all components using Kustomize with Helm chart inflation (no direct `helm install` commands allowed)
- **FR-002**: System MUST provision persistent storage via Longhorn storage class on each independent cluster
- **FR-003**: System MUST configure Cilium CNI with Ingress controller for external access to Grafana, Prometheus, and OpenSearch interfaces on each cluster
- **FR-003a**: System MUST configure ingress hostnames using pattern: *.k8s-cluster-01.miribit.lab (node 194), *.k8s-cluster-02.miribit.lab (node 196), *.k8s-cluster-03.miribit.lab (node 197), *.k8s-cluster-04.miribit.lab (node 198)
- **FR-003b**: System MUST configure Cilium LoadBalancer IP Pools: cluster-01 (192.168.101.210), cluster-02 (192.168.101.211), cluster-03 (192.168.101.212), cluster-04 (192.168.101.213)
- **FR-003c**: System MUST configure Cilium L2 Announcement Policy for LoadBalancer IP advertisement on all clusters
- **FR-004**: System MUST deploy Prometheus Operator on each of the 4 clusters with 2-hour local metric retention and 30-second scrape interval
- **FR-005**: System MUST deploy Thanos Sidecar alongside Prometheus on each cluster to upload metric blocks to S3 with external labels identifying the source cluster (cluster: "cluster-01", "cluster-02", "cluster-03", "cluster-04")
- **FR-006**: System MUST deploy Thanos Query, Query Frontend, Store Gateway, Compactor, and Ruler components on cluster-01 (central) for multi-cluster metric aggregation
- **FR-007**: System MUST configure S3 storage backend with endpoint s3.minio.miribit.lab:80 (Console: http://console.minio.miribit.lab) and credentials (access_key: Kl8u9VGxT4KA8TxlLEfO, secret_key: U9KVRsMZlHJtiToriOxXfl9uPAXqFjqAI1ZdRCOz)
- **FR-007b**: System MUST use bucket name "thanos-bucket" for metric storage, "opensearch-logs" for log snapshots, and "longhorn-backups" for volume backups
- **FR-007c**: System MUST configure S3 client with insecure: true and insecure_skip_verify: true for HTTP connections without TLS
- **FR-007a**: System MUST store S3 credentials in Kubernetes Secrets and reference them in Thanos and OpenSearch configurations
- **FR-008**: System MUST deploy OpenSearch on cluster-01 (central) to receive logs from all 4 clusters
- **FR-009**: System MUST deploy Fluent-bit as DaemonSet on all 4 clusters to collect pod logs and forward to central OpenSearch on cluster-01
- **FR-009a**: System MUST configure OpenSearch to retain logs locally for 14 days, then move to S3 snapshots
- **FR-009b**: System MUST configure S3 lifecycle policy to delete log snapshots after 180 days
- **FR-010**: System MUST configure Prometheus ServiceMonitors on each cluster for all monitoring components (Thanos, Fluent-bit, Longhorn, Cilium)
- **FR-011**: System MUST configure Grafana on cluster-01 with dashboards for Thanos health, multi-cluster Prometheus status, OpenSearch cluster health, Longhorn storage, and Cilium network monitoring across all clusters
- **FR-011a**: System MUST configure Grafana datasource pointing to Thanos Query endpoint for unified multi-cluster metric queries
- **FR-012**: System MUST configure alerts for S3 connectivity loss, Thanos Sidecar upload failures, Prometheus scrape failures, and disk pressure warnings on each cluster
- **FR-012a**: System MUST configure Alertmanager on each cluster to send notifications to operators via configured channels (email, webhook, or Slack)
- **FR-012b**: System MUST NOT implement automated remediation actions; all alert responses require manual operator intervention
- **FR-013**: System MUST prohibit local storage (hostPath, emptyDir) for persistent data; all metric and log persistence uses S3
- **FR-014**: System MUST ensure each cluster operates independently (single cluster failure does not impact other clusters)
- **FR-015**: System MUST configure Thanos Query on cluster-01 to query all 4 cluster Sidecars via StoreAPI
- **FR-016**: System MUST configure RBAC policies following principle of least privilege for all service accounts on each cluster
- **FR-017**: System MUST configure Network Policies to restrict pod-to-pod communication on each cluster and allow cross-cluster communication for Fluent-bit→OpenSearch and Thanos Query→Sidecars
- **FR-018**: System MUST externalize all environment-specific configuration via ConfigMaps, Secrets, or Kustomize overlays
- **FR-019**: System MUST use base/overlay pattern: base configs for shared settings, overlays per cluster (cluster-01, cluster-02, cluster-03, cluster-04)
- **FR-020**: System MUST support deployment command: `kustomize build <path> --enable-helm | kubectl apply -f - -n <namespace>` on each cluster independently

### Key Entities

- **Kubernetes Cluster**: Independent single-node Kubernetes cluster (cluster-01 on node 194, cluster-02 on node 196, cluster-03 on node 197, cluster-04 on node 198)
- **Kubernetes Node**: Physical/virtual machine running a single-node cluster with both control-plane and worker components (192.168.101.194, 196, 197, 198)
- **Prometheus Instance**: Prometheus deployment on each cluster with Thanos Sidecar for metrics collection
- **Metric Block**: 2-hour chunks of Prometheus time series data uploaded to S3 by Thanos Sidecar
- **External Label**: Label added by Thanos Sidecar to identify source cluster (cluster: "cluster-01", region: "central" for cluster-01; cluster: "cluster-XX", region: "edge" for others)
- **StoreAPI Endpoint**: gRPC endpoint (port 10901) exposing metrics data from each cluster's Prometheus Sidecar to Thanos Query on cluster-01
- **LoadBalancer Service**: Cilium L2-announced LoadBalancer exposing Thanos Sidecar StoreAPI from edge clusters (IPs: 211, 212, 213) to central cluster
- **Log Entry**: Structured log line collected by Fluent-bit from any cluster and forwarded to central OpenSearch on cluster-01
- **S3 Bucket**: Object storage container for persistent metrics, logs, and backups (thanos-bucket, opensearch-logs, longhorn-backups)
- **Storage Volume**: Longhorn-provisioned persistent volume for component state on each cluster
- **Service Monitor**: Prometheus Operator custom resource defining scrape targets for metrics collection on each cluster
- **Dashboard**: Grafana visualization on cluster-01 showing metrics from all 4 clusters with Thanos aggregation
- **Alert Rule**: Prometheus alert definition triggering on specific metric conditions on each cluster
- **Ingress Route**: Cilium Ingress routing rule for external access to services on each cluster (*.k8s-cluster-XX.miribit.lab)
- **IP Pool**: Cilium LoadBalancer IP Pool defining available IP addresses for LoadBalancer services on each cluster

## Clarifications

### Session 2025-10-13

- Q: What is the log retention period for OpenSearch (local) and S3 archive? → A: 14일 로컬 보관 후 S3 이동, S3에서 180일 후 삭제
- Q: Which container runtime should be used? → A: containerd runtime
- Q: How should the system respond when alerts are triggered? → A: Alert 발생 시 Alertmanager를 통해 오퍼레이터에게 알림만 전송 (수동 대응)
- Q: What hostname pattern should be used for ingress access to monitoring UIs? → A: *.k8s-cluster-01.miribit.lab, *.k8s-cluster-02.miribit.lab, *.k8s-cluster-03.miribit.lab, *.k8s-cluster-04.miribit.lab
- Q: What scrape interval should Prometheus use for collecting metrics? → A: 30초
- Q: What are the S3 storage endpoint and credentials? → A: S3 endpoint: s3.minio.miribit.lab:80, Console: http://console.minio.miribit.lab, access_key: Kl8u9VGxT4KA8TxlLEfO, secret_key: U9KVRsMZlHJtiToriOxXfl9uPAXqFjqAI1ZdRCOz
- Q: What CNI should be used? → A: Cilium CNI with kubeProxyReplacement, L2 announcements for LoadBalancer services
- Q: What IP addresses are assigned for LoadBalancer services? → A: cluster-01: 192.168.101.210, cluster-02: 192.168.101.211, cluster-03: 192.168.101.212, cluster-04: 192.168.101.213

### Session 2025-10-14

- Q: Should we use Minikube or kubeadm for cluster deployment? → A: kubeadm으로 변경 (Minikube에서는 실제환경과 차이가 커서)
- Q: How many nodes/clusters should be deployed? → A: 4개 독립 클러스터 (192.168.101.194, 196, 197, 198)
- Q: Should nodes form a single cluster or separate clusters? → A: 각 노드는 독립적인 단일 노드 클러스터로 구성
- Q: How should clusters be organized? → A: 4개 독립 클러스터로 멀티 클러스터 구성, cluster-01이 중앙 클러스터로 Thanos Query 및 OpenSearch 배포
- Q: What ingress hostname pattern should be used? → A: *.k8s-cluster-01.miribit.lab, *.k8s-cluster-02.miribit.lab, *.k8s-cluster-03.miribit.lab, *.k8s-cluster-04.miribit.lab

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-000**: Operators can install 4 independent kubeadm clusters on all 4 nodes within 40 minutes using documented procedures
- **SC-001**: Operators can deploy complete monitoring infrastructure to all 4 clusters within 90 minutes using documented procedures (after cluster installation)
- **SC-002**: System retains metrics for unlimited duration via S3 storage while maintaining 2-hour local retention for query performance on each cluster
- **SC-003**: Thanos Query on cluster-01 aggregates metrics from all 4 clusters in unified Grafana dashboards
- **SC-004**: Operators can query historical metrics from any cluster covering any time range stored in S3
- **SC-005**: System continues metrics collection when one cluster fails (cluster autonomy validation)
- **SC-006**: Log collection captures logs from all pods across all 4 clusters with less than 30-second ingestion delay to central OpenSearch
- **SC-007**: System detects and alerts on S3 connectivity failures within 5 minutes of occurrence on each cluster
- **SC-008**: Storage provisioning responds to PersistentVolumeClaim requests within 60 seconds on each cluster
- **SC-009**: Grafana dashboards on cluster-01 load and display data from all 4 clusters within 5 seconds under normal load
- **SC-010**: System supports concurrent queries from multiple operators without performance degradation
- **SC-011**: OpenSearch on cluster-01 maintains operational health status and receives logs from all 4 clusters
- **SC-012**: System survives single cluster failure without data loss in other clusters (cluster independence validation)
- **SC-013**: Deployment configurations are version-controlled and reproducible across all clusters
- **SC-014**: Zero manual deployment steps required; all operations use declarative Kustomize configurations per cluster
- **SC-015**: Thanos Query successfully aggregates metrics from all 4 clusters with cluster-specific external labels
- **SC-016**: Each cluster operates independently with its own control plane and etcd

## Assumptions *(optional)*

- All 4 nodes are running Linux OS (Ubuntu 22.04+ or RHEL 8+) with containerd runtime available
- Nodes have network connectivity to each other and to MinIO S3 endpoint at s3.minio.miribit.lab:80
- Nodes have internet connectivity for downloading Kubernetes binaries, kubeadm, Helm charts, and container images
- MinIO S3 storage is deployed at s3.minio.miribit.lab:80 and accessible with credentials (access_key: Kl8u9VGxT4KA8TxlLEfO, secret_key: U9KVRsMZlHJtiToriOxXfl9uPAXqFjqAI1ZdRCOz)
- Cilium CNI v1.18.2 is installed on all clusters with kubeProxyReplacement and L2 announcement capabilities
- Each node has sufficient resources (minimum 4 CPU, 16GB RAM, 100GB disk per node recommended)
- Kustomize 4.5+, kubectl, and kubeadm are installed on operator workstation
- SSH access to nodes uses credentials `bsh / 123qwe` (to be rotated post-deployment)
- All Helm charts sourced from ArtifactHub (kube-prometheus-stack, opensearch, fluent-bit, longhorn, nginx-ingress)
- DNS records configured for: grafana.k8s-cluster-01.miribit.lab → 192.168.101.210, s3.minio.miribit.lab → 172.16.203.1, console.minio.miribit.lab → 172.16.203.1
- LoadBalancer IPs 192.168.101.210-213 are allocated for ingress services across all clusters
- Korean language documentation is required for operational procedures
- Each node runs an independent single-node Kubernetes cluster (control-plane + worker on same node)
- Clusters do not form a multi-node cluster; they are separate independent clusters
- Thanos provides cross-cluster metric aggregation via S3 and StoreAPI
- OpenSearch on cluster-01 receives logs from Fluent-bit agents on all 4 clusters
- Network connectivity between clusters is required for Thanos Query→Sidecars and Fluent-bit→OpenSearch

## Dependencies *(optional)*

- MinIO S3 storage at s3.minio.miribit.lab:80 (externally managed)
- Linux OS with containerd runtime on all target nodes
- kubectl, kubeadm, kubelet binaries available for cluster management
- Cilium CNI v1.18.2+ with L2 announcement support
- Helm v3.10+ for chart templating (used via kustomize --enable-helm)
- Kustomize v5.0+ with Helm chart inflation support
- Network connectivity between all nodes (192.168.101.194, 196-198) and MinIO endpoint (s3.minio.miribit.lab:80)
- Sufficient disk space on each node for Longhorn storage provisioning (minimum 100GB per node)
- Helm charts availability from ArtifactHub (internet connectivity or internal mirror)
- open-iscsi and nfs-common packages installed on all nodes for Longhorn requirements

## Out of Scope *(optional)*

- MinIO S3 storage deployment and configuration (assumed to be externally managed at s3.minio.miribit.lab:80)
- Base Linux OS installation and configuration on nodes
- containerd runtime installation and configuration
- kubeadm, kubectl, kubelet binary installation (documented in deployment guide but not automated)
- Cilium CNI installation (documented in deployment guide as part of cluster bootstrap)
- DNS record setup for *.k8s-cluster-01.miribit.lab and s3.minio.miribit.lab (assumed to be pre-configured)
- open-iscsi and nfs-common package installation (documented but not automated)
- TLS certificate provisioning and management for HTTPS ingress
- Authentication and authorization for Grafana/Prometheus/OpenSearch UI access (basic auth assumed initially)
- Multi-tenancy isolation between different application teams
- Service mesh or advanced networking between clusters (basic pod-to-pod communication assumed)
- Advanced Thanos downsampling configuration (basic compaction included)
- Custom Prometheus exporters for application-specific metrics
- Log parsing and transformation beyond basic Fluent-bit forwarding
- Backup scheduling and retention automation (manual backup process acceptable)
- Disaster recovery automation and testing procedures
- Performance tuning and capacity planning for production scale
- Cost optimization for S3 storage lifecycle policies
- Node-level security hardening (firewall, SELinux, etc.)
- Cross-cluster service discovery beyond Thanos and OpenSearch
- Federation of multiple Thanos Query instances (single Thanos Query on cluster-01 only)
