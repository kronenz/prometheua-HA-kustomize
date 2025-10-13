# Tasks: Thanos Multi-Cluster Monitoring Infrastructure

**Feature Branch**: `001-thanos-multi-cluster`
**Input**: Design documents from `/root/specs/001-thanos-multi-cluster/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files/nodes, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US0, US1, US2...)
- Include exact file paths and commands in descriptions

## Path Conventions
- Infrastructure deployment: `thanos-multi-cluster/deploy/base/` and `deploy/overlays/cluster-{196,197,198}-{central,edge}/`
- Scripts: `thanos-multi-cluster/scripts/`
- Documentation: `thanos-multi-cluster/docs/`

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Initialize repository structure and development environment

- [x] T001 Create project directory structure `thanos-multi-cluster/` with subdirectories: `deploy/`, `scripts/`, `docs/`, `tests/`
- [x] T002 [P] Create base kustomization directories: `deploy/base/{longhorn,nginx-ingress,kube-prometheus-stack,thanos,opensearch,fluent-bit}/`
- [x] T003 [P] Create overlay directories: `deploy/overlays/{cluster-196-central,cluster-197-edge,cluster-198-edge}/`
- [x] T004 [P] Initialize Git repository and add `.gitignore` (exclude secrets, kubeconfig files)
- [x] T005 [P] Create README.md with project overview and quick links to documentation

---

## Phase 2: Foundational (Blocking Prerequisites for All User Stories)

**Purpose**: Prerequisites that MUST complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T006 Create S3 bucket `thanos` in MinIO at https://172.20.40.21:30001 using credentials minio/minio123 (script created: scripts/s3/create-buckets.sh)
- [x] T007 Create S3 bucket `opensearch-logs` in MinIO for log snapshots (script created: scripts/s3/create-buckets.sh)
- [x] T008 Create S3 bucket `longhorn-backups` in MinIO for volume backups (script created: scripts/s3/create-buckets.sh)
- [ ] T009 Verify S3 connectivity from all node IPs (192.168.101.196-198) using curl: `curl -k https://172.20.40.21:30001/minio/health/live`
- [ ] T010 Verify DNS wildcard records resolve: `*.mkube-196.miribit.lab → 192.168.101.196`, same for 197/198

**Checkpoint**: Foundation ready - S3 buckets exist, DNS resolves, nodes can reach S3. User story implementation can now begin.

---

## Phase 3: User Story 0 - Minikube Installation (Priority: P0) 🎯 FIRST

**Goal**: Install Minikube with containerd driver on all three nodes to create independent Kubernetes clusters

**Independent Test**: SSH to each node, run `minikube status`, verify Running. Deploy test pod, verify schedules successfully.

### Implementation for User Story 0

- [x] T011 [P] [US0] Create Minikube installation script `scripts/install-minikube.sh` with containerd driver, 4 CPU, 16GB RAM configuration (script created: scripts/minikube/install-minikube.sh)
- [ ] T012 [P] [US0] SSH to node 192.168.101.196, run `scripts/install-minikube.sh`, verify `minikube status` returns Running
- [ ] T013 [P] [US0] SSH to node 192.168.101.197, run `scripts/install-minikube.sh`, verify `minikube status` returns Running
- [ ] T014 [P] [US0] SSH to node 192.168.101.198, run `scripts/install-minikube.sh`, verify `minikube status` returns Running
- [ ] T015 [US0] Validate all clusters: `kubectl get nodes` on all clusters show Ready status
- [ ] T016 [US0] Deploy test pod on each cluster to verify scheduling works

**Checkpoint**: Minikube installed on all 3 nodes. All clusters operational. User Story 0 complete.

---

## Phase 4: User Story 4 - Infrastructure Storage Provisioning (Priority: P1)

**Goal**: Deploy Longhorn storage class and NGINX Ingress controller on all clusters for persistent storage and external access

**Independent Test**: Create test PVC on each cluster, verify provisions in <60s. Create test Ingress, verify routes to backend.

### Implementation for User Story 4

- [x] T017 [P] [US4] Create Longhorn base kustomization: `deploy/base/longhorn/kustomization.yaml` with helmCharts pointing to longhorn/longhorn chart v1.5.3
- [x] T018 [P] [US4] Create Longhorn base values.yaml with defaultReplicaCount=1, backupTarget=s3://longhorn-backups@us-east-1/
- [x] T019 [P] [US4] Create Longhorn S3 secret template (created in overlays: `deploy/overlays/cluster-*/longhorn/longhorn-s3-secret.yaml`)
- [x] T020 [P] [US4] Create NGINX Ingress base kustomization: `deploy/base/ingress-nginx/kustomization.yaml` with ingress-nginx/ingress-nginx chart v4.8.3
- [x] T021 [P] [US4] Create NGINX Ingress base values.yaml with controller.hostNetwork=true, controller.kind=DaemonSet
- [x] T022 [P] [US4] Create cluster-196 overlay for Longhorn: `deploy/overlays/cluster-196-central/longhorn/kustomization.yaml`
- [x] T023 [P] [US4] Create cluster-197 overlay for Longhorn: `deploy/overlays/cluster-197-edge/longhorn/kustomization.yaml`
- [x] T024 [P] [US4] Create cluster-198 overlay for Longhorn: `deploy/overlays/cluster-198-edge/longhorn/kustomization.yaml`
- [x] T025 [P] [US4] Create cluster-196 overlay for NGINX Ingress: `deploy/overlays/cluster-196-central/ingress-nginx/kustomization.yaml`
- [x] T026 [P] [US4] Create cluster-197 overlay for NGINX Ingress: `deploy/overlays/cluster-197-edge/ingress-nginx/kustomization.yaml`
- [x] T027 [P] [US4] Create cluster-198 overlay for NGINX Ingress: `deploy/overlays/cluster-198-edge/ingress-nginx/kustomization.yaml`
- [ ] T028 [P] [US4] Deploy Longhorn to cluster 196: `kustomize build deploy/overlays/cluster-196-central/longhorn --enable-helm | kubectl apply -f - -n longhorn-system`
- [ ] T029 [P] [US4] Deploy Longhorn to cluster 197: `kustomize build deploy/overlays/cluster-197-edge/longhorn --enable-helm | kubectl apply -f - -n longhorn-system`
- [ ] T030 [P] [US4] Deploy Longhorn to cluster 198: `kustomize build deploy/overlays/cluster-198-edge/longhorn --enable-helm | kubectl apply -f - -n longhorn-system`
- [ ] T031 [US4] Wait for Longhorn pods Ready on all clusters: `kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=180s`
- [ ] T032 [P] [US4] Deploy NGINX Ingress to cluster 196: `kustomize build deploy/overlays/cluster-196-central/nginx-ingress --enable-helm | kubectl apply -f - -n ingress-nginx`
- [ ] T033 [P] [US4] Deploy NGINX Ingress to cluster 197: `kustomize build deploy/overlays/cluster-197-edge/nginx-ingress --enable-helm | kubectl apply -f - -n ingress-nginx`
- [ ] T034 [P] [US4] Deploy NGINX Ingress to cluster 198: `kustomize build deploy/overlays/cluster-198-edge/nginx-ingress --enable-helm | kubectl apply -f - -n ingress-nginx`
- [ ] T035 [US4] Wait for NGINX Ingress pods Ready on all clusters: `kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=120s`
- [ ] T036 [P] [US4] Test Longhorn provisioning on cluster 196: Create test PVC, verify binds in <60s
- [ ] T037 [P] [US4] Test Longhorn provisioning on cluster 197: Create test PVC, verify binds in <60s
- [ ] T038 [P] [US4] Test Longhorn provisioning on cluster 198: Create test PVC, verify binds in <60s
- [ ] T039 [US4] Test NGINX Ingress routing on cluster 196: Create test Ingress, curl test service via hostname
- [ ] T040 [US4] Configure Longhorn S3 backup targets on all clusters via Longhorn UI or kubectl patch

**Checkpoint**: Longhorn and NGINX Ingress deployed on all 3 clusters. Storage class available. Ingress controller routing. User Story 4 complete.

---

## Phase 5: User Story 1 - Central Cluster Deployment (Priority: P1)

**Goal**: Deploy Prometheus, Grafana, Alertmanager, Thanos Query, and Thanos Store Gateway on central cluster (196) for metric aggregation

**Independent Test**: Access Grafana at grafana.mkube-196.miribit.lab, verify Thanos Query datasource, query sample metrics.

### Implementation for User Story 1

- [ ] T041 [US1] Create Thanos S3 secret for cluster 196: `kubectl create secret generic thanos-s3-secret --from-literal=objstore.yml=... -n monitoring`
- [x] T042 [P] [US1] Create kube-prometheus-stack base kustomization (created as `deploy/base/prometheus/kustomization.yaml`)
- [x] T043 [P] [US1] Create kube-prometheus-stack base values.yaml: prometheus.retention=2h, prometheus.scrapeInterval=30s, grafana.enabled=true
- [x] T044 [P] [US1] Create Thanos base kustomization: `deploy/base/thanos/kustomization.yaml` (plain YAML, no Helm chart)
- [x] T045 [P] [US1] Create Thanos Query deployment (created as `deploy/base/thanos/thanos-query.yaml`)
- [x] T046 [P] [US1] Create Thanos Store Gateway deployment (created as `deploy/base/thanos/thanos-store.yaml`)
- [x] T047 [P] [US1] Create Thanos additional components (created Compactor: `deploy/base/thanos/thanos-compactor.yaml`, Ruler: `deploy/base/thanos/thanos-ruler.yaml`)
- [x] T048 [US1] Create cluster-196 overlay for kube-prometheus-stack (created as `deploy/overlays/cluster-196-central/prometheus/kustomization.yaml`)
- [x] T049 [US1] Create cluster-196 Grafana ingress patch (included in prometheus values-patch.yaml)
- [x] T050 [US1] Create cluster-196 Prometheus ingress patch (included in Thanos Query ingress)
- [x] T051 [US1] Create cluster-196 Thanos overlay (included in prometheus overlay with Query/Store/Compactor/Ruler)
- [ ] T052 [US1] Deploy kube-prometheus-stack to cluster 196: `kustomize build deploy/overlays/cluster-196-central/kube-prometheus-stack --enable-helm | kubectl apply -f - -n monitoring`
- [ ] T053 [US1] Wait for Prometheus pods Ready: `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=180s`
- [ ] T054 [US1] Deploy Thanos components to cluster 196: `kustomize build deploy/overlays/cluster-196-central/thanos | kubectl apply -f - -n monitoring`
- [ ] T055 [US1] Wait for Thanos Query pods Ready (2 replicas): `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=thanos-query -n monitoring --timeout=120s`
- [ ] T056 [P] [US1] Create Grafana dashboards ConfigMap: `deploy/base/kube-prometheus-stack/dashboards/` with Thanos Overview, Prometheus Federation dashboards
- [ ] T057 [P] [US1] Create ServiceMonitor for Thanos Query: `deploy/base/thanos/servicemonitor-query.yaml`
- [ ] T058 [P] [US1] Create ServiceMonitor for Thanos Store Gateway: `deploy/base/thanos/servicemonitor-store.yaml`
- [ ] T059 [US1] Configure Grafana datasource pointing to Thanos Query: Patch kube-prometheus-stack values to add Thanos datasource
- [ ] T060 [US1] Create PrometheusRule for S3 connectivity alerts: `deploy/base/kube-prometheus-stack/alerts/s3-connectivity.yaml`
- [ ] T061 [US1] Create PrometheusRule for Thanos Sidecar upload failures: `deploy/base/kube-prometheus-stack/alerts/thanos-sidecar.yaml`
- [ ] T062 [US1] Create PrometheusRule for Prometheus scrape failures: `deploy/base/kube-prometheus-stack/alerts/prometheus-scrapes.yaml`
- [ ] T063 [US1] Create PrometheusRule for disk pressure warnings: `deploy/base/kube-prometheus-stack/alerts/disk-pressure.yaml`
- [ ] T064 [US1] Configure Alertmanager notification channels (webhook/email/Slack) in kube-prometheus-stack values.yaml
- [ ] T065 [US1] Verify Grafana accessible at https://grafana.mkube-196.miribit.lab
- [ ] T066 [US1] Verify Prometheus targets all Up in Prometheus UI
- [ ] T067 [US1] Verify Thanos Query endpoint responding: `curl http://thanos-query.monitoring.svc:9090/-/healthy`
- [ ] T068 [US1] Test Thanos Query federation: Query a metric, verify Thanos Query aggregates (even though only 196 exists for now)

**Checkpoint**: Central cluster monitoring stack fully deployed. Grafana accessible. Thanos Query operational. Alerts configured. User Story 1 complete.

---

## Phase 6: User Story 2 - Distributed Edge Cluster Deployment (Priority: P2)

**Goal**: Deploy Prometheus with Thanos Sidecar on edge clusters (197, 198) to collect local metrics and upload to S3

**Independent Test**: Verify Prometheus on 197/198 scrapes local targets. Verify Thanos Sidecar uploads blocks to S3. Verify Thanos Query on 196 aggregates metrics from all clusters.

### Implementation for User Story 2

- [ ] T069 [P] [US2] Create Thanos S3 secret for cluster 197: `kubectl create secret generic thanos-s3-secret --from-literal=objstore.yml=... -n monitoring`
- [ ] T070 [P] [US2] Create Thanos S3 secret for cluster 198: `kubectl create secret generic thanos-s3-secret --from-literal=objstore.yml=... -n monitoring`
- [ ] T071 [P] [US2] Create cluster-197 overlay for kube-prometheus-stack: `deploy/overlays/cluster-197-edge/kube-prometheus-stack/kustomization.yaml`
- [ ] T072 [P] [US2] Create cluster-198 overlay for kube-prometheus-stack: `deploy/overlays/cluster-198-edge/kube-prometheus-stack/kustomization.yaml`
- [ ] T073 [P] [US2] Create Thanos Sidecar patch for cluster 197: `deploy/overlays/cluster-197-edge/thanos-sidecar-patch.yaml` to inject Sidecar container into Prometheus pod
- [ ] T074 [P] [US2] Create Thanos Sidecar patch for cluster 198: `deploy/overlays/cluster-198-edge/thanos-sidecar-patch.yaml` to inject Sidecar container into Prometheus pod
- [ ] T075 [P] [US2] Create Grafana ingress for cluster 197: `deploy/overlays/cluster-197-edge/ingress-grafana.yaml` with hostname grafana.mkube-197.miribit.lab
- [ ] T076 [P] [US2] Create Grafana ingress for cluster 198: `deploy/overlays/cluster-198-edge/ingress-grafana.yaml` with hostname grafana.mkube-198.miribit.lab
- [ ] T077 [P] [US2] Deploy kube-prometheus-stack to cluster 197: `kustomize build deploy/overlays/cluster-197-edge/kube-prometheus-stack --enable-helm | kubectl apply -f - -n monitoring`
- [ ] T078 [P] [US2] Deploy kube-prometheus-stack to cluster 198: `kustomize build deploy/overlays/cluster-198-edge/kube-prometheus-stack --enable-helm | kubectl apply -f - -n monitoring`
- [ ] T079 [US2] Wait for Prometheus pods Ready on cluster 197 (with Thanos Sidecar): `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=180s`
- [ ] T080 [US2] Wait for Prometheus pods Ready on cluster 198 (with Thanos Sidecar): `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=180s`
- [ ] T081 [US2] Verify Thanos Sidecar container running in Prometheus pod on cluster 197: `kubectl get pod prometheus-0 -n monitoring -o jsonpath='{.spec.containers[*].name}'` includes thanos-sidecar
- [ ] T082 [US2] Verify Thanos Sidecar container running in Prometheus pod on cluster 198: Same as T081 for cluster 198
- [ ] T083 [US2] Check Thanos Sidecar logs on cluster 197 for S3 upload activity: `kubectl logs prometheus-0 -c thanos-sidecar -n monitoring --tail=50`
- [ ] T084 [US2] Check Thanos Sidecar logs on cluster 198 for S3 upload activity: Same as T083 for cluster 198
- [ ] T085 [US2] Update Thanos Query on cluster 196 to add store endpoints for cluster 197/198 Sidecars: Patch Thanos Query args with `--store=dnssrv+_grpc._tcp.thanos-sidecar-197...` and 198
- [ ] T086 [US2] Verify Thanos Query on 196 can query metrics from cluster 197: Run PromQL query with `cluster="197"` label
- [ ] T087 [US2] Verify Thanos Query on 196 can query metrics from cluster 198: Run PromQL query with `cluster="198"` label
- [ ] T088 [US2] Verify Thanos Query deduplicates metrics across all 3 clusters: Query without cluster filter, verify aggregation works
- [ ] T089 [US2] Wait 2+ hours and verify Thanos Sidecar uploads metric blocks to S3 from cluster 197
- [ ] T090 [US2] Wait 2+ hours and verify Thanos Sidecar uploads metric blocks to S3 from cluster 198
- [ ] T091 [US2] Verify Thanos Store Gateway on 196 can read blocks from S3 uploaded by edge clusters

**Checkpoint**: Edge clusters 197 and 198 operational. Thanos Sidecars uploading to S3. Thanos Query aggregating all 3 clusters. User Story 2 complete.

---

## Phase 7: User Story 3 - Unified Log Collection and Storage (Priority: P3)

**Goal**: Deploy OpenSearch 3-node cluster and Fluent-bit DaemonSets to collect, aggregate, and store logs with S3-backed retention

**Independent Test**: Deploy test pod, verify logs appear in OpenSearch within 30s. Verify OpenSearch creates S3 snapshots. Verify 14-day local / 180-day S3 retention.

### Implementation for User Story 3

- [x] T092 [P] [US3] Create OpenSearch base kustomization: `deploy/base/opensearch/kustomization.yaml` with opensearch-project-helm-charts/opensearch chart v2.17.0
- [x] T093 [P] [US3] Create OpenSearch base values.yaml: replicas=1 per cluster (total 3 nodes), masterService pointing to shared service, replication factor 2
- [x] T094 [P] [US3] Create OpenSearch S3 secret: `deploy/base/opensearch/s3-secret.yaml` with MinIO credentials
- [x] T095 [P] [US3] Create OpenSearch S3 snapshot repository ConfigMap (included in s3-secret.yaml)
- [x] T096 [P] [US3] Create OpenSearch ISM policy ConfigMap: `deploy/base/opensearch/ism-policy.yaml` for 14-day local retention, snapshot then delete
- [x] T097 [P] [US3] Create Fluent-bit base kustomization: `deploy/base/fluent-bit/kustomization.yaml` with fluent/fluent-bit chart v0.43.0
- [x] T098 [P] [US3] Create Fluent-bit base values.yaml: DaemonSet, outputs to OpenSearch endpoints, filters for Kubernetes metadata
- [x] T099 [US3] Create cluster-196 overlay for OpenSearch: `deploy/overlays/cluster-196-central/opensearch/kustomization.yaml`
- [x] T100 [US3] Create cluster-197 overlay for OpenSearch: `deploy/overlays/cluster-197-edge/opensearch/kustomization.yaml`
- [x] T101 [US3] Create cluster-198 overlay for OpenSearch: `deploy/overlays/cluster-198-edge/opensearch/kustomization.yaml`
- [ ] T102 [P] [US3] Deploy OpenSearch to cluster 196: `kustomize build deploy/overlays/cluster-196-central/opensearch --enable-helm | kubectl apply -f - -n logging`
- [ ] T103 [P] [US3] Deploy OpenSearch to cluster 197: `kustomize build deploy/overlays/cluster-197-edge/opensearch --enable-helm | kubectl apply -f - -n logging`
- [ ] T104 [P] [US3] Deploy OpenSearch to cluster 198: `kustomize build deploy/overlays/cluster-198-edge/opensearch --enable-helm | kubectl apply -f - -n logging`
- [ ] T105 [US3] Wait for OpenSearch pods Ready on all clusters: `kubectl wait --for=condition=ready pod -l app=opensearch -n logging --timeout=300s`
- [ ] T106 [US3] Form OpenSearch 3-node cluster: Configure discovery.seed_hosts in OpenSearch config to include all 3 node IPs
- [ ] T107 [US3] Verify OpenSearch cluster health: `curl http://opensearch.logging.svc:9200/_cluster/health` shows green with 3 nodes
- [ ] T108 [US3] Register S3 snapshot repository in OpenSearch: `PUT _snapshot/s3-logs-repository` with MinIO config
- [ ] T109 [US3] Apply ISM policy to log indices: `PUT _index_template/logs-template` with ISM policy_id (requires running OpenSearch cluster)
- [x] T110 [P] [US3] Create ServiceMonitor for OpenSearch (included in values.yaml extraObjects)
- [x] T111 [P] [US3] Create cluster-196 overlay for Fluent-bit: `deploy/overlays/cluster-196-central/fluent-bit/kustomization.yaml`
- [x] T112 [P] [US3] Create cluster-197 overlay for Fluent-bit: `deploy/overlays/cluster-197-edge/fluent-bit/kustomization.yaml`
- [x] T113 [P] [US3] Create cluster-198 overlay for Fluent-bit: `deploy/overlays/cluster-198-edge/fluent-bit/kustomization.yaml`
- [ ] T114 [P] [US3] Deploy Fluent-bit to cluster 196: `kustomize build deploy/overlays/cluster-196-central/fluent-bit --enable-helm | kubectl apply -f - -n logging`
- [ ] T115 [P] [US3] Deploy Fluent-bit to cluster 197: `kustomize build deploy/overlays/cluster-197-edge/fluent-bit --enable-helm | kubectl apply -f - -n logging`
- [ ] T116 [P] [US3] Deploy Fluent-bit to cluster 198: `kustomize build deploy/overlays/cluster-198-edge/fluent-bit --enable-helm | kubectl apply -f - -n logging`
- [ ] T117 [US3] Verify Fluent-bit DaemonSet running on all nodes: `kubectl get ds fluent-bit -n logging` shows all nodes
- [ ] T118 [P] [US3] Create ServiceMonitor for Fluent-bit: `deploy/base/fluent-bit/servicemonitor.yaml` scraping port 2020
- [ ] T119 [US3] Create test pod, verify logs appear in OpenSearch within 30s: `kubectl run test-logger --image=busybox -- sh -c "while true; do echo test log; sleep 1; done"`
- [ ] T120 [US3] Query OpenSearch for test logs: `curl http://opensearch.logging.svc:9200/logs-*/_search?q=test`
- [ ] T121 [US3] Create OpenSearch ingress for cluster 196: hostname opensearch.mkube-196.miribit.lab
- [ ] T122 [US3] Test OpenSearch S3 snapshot: Trigger manual snapshot, verify appears in S3 bucket opensearch-logs
- [ ] T123 [US3] Configure S3 lifecycle policy on MinIO for 180-day retention: Delete objects in opensearch-logs/ older than 180 days
- [ ] T124 [US3] Verify ISM policy triggers after 14 days (or adjust for testing): Check logs-* indices get snapshotted and deleted locally

**Checkpoint**: OpenSearch 3-node cluster green. Fluent-bit collecting logs from all clusters. Logs searchable in OpenSearch. S3 snapshots working. User Story 3 complete.

---

## Phase 8: User Story 5 - Unified Monitoring Dashboard Access (Priority: P3)

**Goal**: Configure and validate centralized Grafana dashboards to view metrics from all clusters, query historical data, and monitor system health

**Independent Test**: Access Grafana on 196, view dashboards showing data from all 3 clusters, query historical metrics >2h from S3, test cluster filtering.

### Implementation for User Story 5

- [ ] T125 [US5] Verify Grafana datasource "Thanos Query" is configured and working: Grafana UI → Configuration → Data Sources
- [ ] T126 [P] [US5] Create Grafana dashboard "Thanos Overview": `deploy/base/kube-prometheus-stack/dashboards/thanos-overview.json` with panels for Sidecar upload status, Query performance, Store Gateway latency, S3 connectivity
- [ ] T127 [P] [US5] Create Grafana dashboard "Prometheus Federation": `deploy/base/kube-prometheus-stack/dashboards/prometheus-federation.json` with panels for scrape success rate per cluster, target health
- [ ] T128 [P] [US5] Create Grafana dashboard "OpenSearch Cluster Health": `deploy/base/kube-prometheus-stack/dashboards/opensearch-health.json` with panels for node status, shard allocation, index health, snapshot status
- [ ] T129 [P] [US5] Create Grafana dashboard "Longhorn Storage": `deploy/base/kube-prometheus-stack/dashboards/longhorn-storage.json` with panels for volume usage, backup status, replica health
- [ ] T130 [P] [US5] Create Grafana dashboard "NGINX Ingress Traffic": `deploy/base/kube-prometheus-stack/dashboards/nginx-ingress.json` with panels for request rate, latency, error rate per hostname
- [ ] T131 [US5] Import all dashboards to Grafana: Add dashboard ConfigMaps to kube-prometheus-stack kustomization
- [ ] T132 [US5] Test Grafana query across all clusters: Run query without cluster filter, verify shows metrics from 196, 197, 198
- [ ] T133 [US5] Test Grafana cluster filter: Add cluster variable to dashboards, test filtering to show only cluster 196 data
- [ ] T134 [US5] Test Grafana historical query: Query metric older than 2 hours (after waiting for blocks to upload), verify Thanos retrieves from S3
- [ ] T135 [US5] Verify "Thanos Overview" dashboard shows all Sidecars uploading successfully
- [ ] T136 [US5] Verify "Prometheus Federation" dashboard shows all targets Up across all clusters
- [ ] T137 [US5] Verify "OpenSearch Cluster Health" dashboard shows green status with 3 nodes
- [ ] T138 [US5] Verify "Longhorn Storage" dashboard shows volume usage per cluster
- [ ] T139 [US5] Verify "NGINX Ingress Traffic" dashboard shows traffic to grafana.mkube-{196,197,198}.miribit.lab hostnames
- [ ] T140 [US5] Test alert firing: Trigger a test alert (e.g., stop a Prometheus target), verify alert fires in Alertmanager
- [ ] T141 [US5] Verify Alertmanager notification: Confirm alert notification sent to configured channel (email/webhook/Slack)
- [ ] T142 [US5] Validate no automated remediation actions occur (FR-012b): Verify alerts only notify, no auto-restart or auto-fix

**Checkpoint**: All Grafana dashboards operational. Multi-cluster queries working. Historical queries from S3 working. Cluster filtering working. Alerts firing and notifying. User Story 5 complete.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, cleanup, and final validation across all user stories

- [ ] T143 [P] Create architecture diagram in docs/architecture.md with Mermaid syntax showing 3 clusters, Thanos components, data flows (metrics to S3, logs to OpenSearch), network topology
- [ ] T144 [P] Write deployment guide in docs/deployment.md (Korean) with step-by-step instructions: prerequisites, S3 setup, DNS setup, deployment order, validation per component
- [ ] T145 [P] Write operations runbook in docs/operations.md (Korean) with troubleshooting common issues: pod CrashLoopBackOff, S3 upload failures, OpenSearch cluster red, ingress not routing
- [ ] T146 [P] Verify quickstart.md executes successfully: Follow quickstart.md on fresh cluster 196, measure time (<15 minutes), ensure all checks pass
- [ ] T147 [P] Create validation script `scripts/validate-deployment.sh` that checks: all pods Running, all targets Up, Grafana accessible, Thanos Query healthy, OpenSearch green
- [ ] T148 [P] Create backup script `scripts/backup-s3.sh` to verify S3 buckets contain data: list objects in thanos/, opensearch-logs/, longhorn-backups/
- [ ] T149 [P] Create rollback script `scripts/rollback-cluster.sh` to delete all monitoring resources: `kubectl delete ns monitoring logging longhorn-system ingress-nginx`
- [ ] T150 Perform end-to-end validation: Run validation script on all 3 clusters, verify 100% pass rate
- [ ] T151 Document known limitations in README.md: Minikube single-node per cluster, no TLS on ingress, basic auth only, no Thanos Compactor
- [ ] T152 Create PR checklist in docs/pr-checklist.md: kustomize build validates, no hardcoded secrets, S3 integration present, Korean documentation updated
- [ ] T153 Review all configurations for constitutional compliance: No helm install commands, all persistent data in S3, Kustomize-only deployment, RBAC configured
- [ ] T154 Final cleanup: Remove any test resources, ensure no secrets in Git, verify .gitignore covers all sensitive files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Story 0 (Phase 3)**: Depends on Foundational - BLOCKS all other stories
- **User Story 4 (Phase 4)**: Depends on US0 completion - BLOCKS US1, US2
- **User Story 1 (Phase 5)**: Depends on US4 completion - Independent of US2
- **User Story 2 (Phase 6)**: Depends on US4 completion, enhanced by US1 (Thanos Query)
- **User Story 3 (Phase 7)**: Depends on US0, US4 - Independent of US1, US2
- **User Story 5 (Phase 8)**: Depends on US1, US2, US3 - Final integration validation
- **Polish (Phase 9)**: Depends on all user stories complete

### User Story Dependencies

```
Foundational (S3 buckets, DNS)
   ↓
US0: Minikube (P0) ← BLOCKS ALL
   ↓
US4: Storage/Ingress (P1) ← BLOCKS US1, US2, US3
   ├→ US1: Central Cluster (P1) - Independent
   ├→ US2: Edge Clusters (P2) - Can start after US4, enhanced by US1
   └→ US3: Log Collection (P3) - Independent
        ↓
   US5: Unified Dashboard (P3) ← Requires US1, US2, US3
   ↓
Polish & Documentation
```

### Parallel Opportunities

**Within Phase 3 (US0 - Minikube)**:
- T012, T013, T014 can run in parallel (install on 3 nodes simultaneously)

**Within Phase 4 (US4 - Infrastructure)**:
- T017-T021: Create base configs in parallel
- T022-T027: Create overlays in parallel
- T028-T030: Deploy Longhorn to 3 clusters in parallel
- T032-T034: Deploy NGINX to 3 clusters in parallel
- T036-T038: Test PVC provisioning on 3 clusters in parallel

**Within Phase 5 (US1 - Central Cluster)**:
- T042-T047: Create base configs in parallel
- T056-T058: Create ServiceMonitors in parallel
- T060-T063: Create alert rules in parallel

**Within Phase 6 (US2 - Edge Clusters)**:
- T069-T070: Create secrets in parallel
- T071-T074: Create overlays/patches in parallel
- T075-T076: Create ingress in parallel
- T077-T078: Deploy to clusters 197/198 in parallel

**Within Phase 7 (US3 - Logging)**:
- T092-T098: Create base configs in parallel
- T102-T104: Deploy OpenSearch to 3 clusters in parallel
- T114-T116: Deploy Fluent-bit to 3 clusters in parallel

**Within Phase 8 (US5 - Dashboards)**:
- T126-T130: Create dashboard JSONs in parallel

**Within Phase 9 (Polish)**:
- T143-T149: Create documentation and scripts in parallel

---

## Parallel Example: User Story 4 (Infrastructure)

```bash
# Launch Longhorn deployment on all 3 clusters simultaneously:
Task T028: "Deploy Longhorn to cluster 196"
Task T029: "Deploy Longhorn to cluster 197"
Task T030: "Deploy Longhorn to cluster 198"

# Then wait for all to complete before proceeding
Task T031: "Wait for Longhorn pods Ready on all clusters"

# Launch NGINX deployment on all 3 clusters simultaneously:
Task T032: "Deploy NGINX to cluster 196"
Task T033: "Deploy NGINX to cluster 197"
Task T034: "Deploy NGINX to cluster 198"
```

---

## Implementation Strategy

### MVP First (User Story 0 + 4 + 1 Only)

1. Complete Phase 1: Setup (T001-T005)
2. Complete Phase 2: Foundational (T006-T010) - CRITICAL: blocks all stories
3. Complete Phase 3: User Story 0 - Minikube (T011-T016)
4. Complete Phase 4: User Story 4 - Infrastructure (T017-T040)
5. Complete Phase 5: User Story 1 - Central Cluster (T041-T068)
6. **STOP and VALIDATE**: Access Grafana on 196, verify metrics from 196, verify Thanos components healthy
7. Deploy/demo if ready

This gives you a working monitoring stack on the central cluster with foundation for expansion.

### Incremental Delivery

1. Complete Setup + Foundational + US0 → All clusters ready
2. Add US4 → Storage and ingress available
3. Add US1 → Central monitoring operational (MVP!)
4. Add US2 → Edge clusters added, multi-cluster federation working
5. Add US3 → Log collection added, full observability
6. Add US5 → Unified dashboards, complete system
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational + US0 + US4 together (foundation)
2. Once US4 done:
   - Developer A: User Story 1 (Central Cluster)
   - Developer B: User Story 2 (Edge Clusters) - starts US1 done for Thanos Query config
   - Developer C: User Story 3 (Logging) - independent
3. Once US1, US2, US3 complete:
   - Team collaborates on US5 (Unified Dashboard validation)
4. Team completes Polish & Documentation together

---

## Notes

- [P] tasks = different nodes or independent components
- [Story] label (US0, US1, etc.) maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Constitution compliance: No helm install, all configs in Git, S3 for persistence, Kustomize deployment only
- Korean documentation required for operations guides
- Mermaid diagrams required for architecture docs
- S3 credentials (minio/minio123) MUST be in Secrets, not hardcoded in configs
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence

---

**Total Tasks**: 154
**MVP Tasks (US0+US4+US1)**: 68 (44% of total)
**Parallel Opportunities**: 47 tasks marked [P] (31% can run concurrently)
