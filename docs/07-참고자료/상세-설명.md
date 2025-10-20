╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
║                    Thanos HA Monitoring Infrastructure with kubeadm                           ║
║                    4-Node Kubernetes Cluster + External MinIO S3                              ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                External Access Layer                                        │
│                                                                                             │
│  End Users  ────────►  DNS: *.k8s.miribit.lab (192.168.1.1)                               │
│  Operators  ────────►  DNS: *.minio.miribit.lab (192.168.1.1)                             │
│                                                                                             │
│  External URLs:                                                                             │
│    https://grafana.k8s.miribit.lab         → Grafana UI                                   │
│    https://prometheus.k8s.miribit.lab      → Prometheus UI                                │
│    https://thanos-query.k8s.miribit.lab    → Thanos Query UI                             │
│    https://opensearch.k8s.miribit.lab      → OpenSearch Dashboards                        │
│                                                                                             │
│    http://console.minio.miribit.lab        → MinIO Console (External)                     │
│    http://s3.minio.miribit.lab             → MinIO S3 API (External)                      │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              Kubernetes Cluster - Ingress Layer                             │
│  ┌──────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  NGINX Ingress Controller (Multiple Replicas)                                        │  │
│  │                                                                                        │  │
│  │  Routes:                                                                              │  │
│  │    grafana.k8s.miribit.lab      →  svc/grafana:80         (monitoring namespace)    │  │
│  │    prometheus.k8s.miribit.lab   →  svc/prometheus:9090    (monitoring namespace)    │  │
│  │    thanos-query.k8s.miribit.lab →  svc/thanos-query:9090  (monitoring namespace)    │  │
│  │    opensearch.k8s.miribit.lab   →  svc/opensearch:9200    (logging namespace)       │  │
│  └──────────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                          Kubernetes Cluster (4-Node HA Configuration)                      │
│                                                                                             │
│  ┌──────────────────────────┐  ┌──────────────────────────┐  ┌───────────────────────────┐│
│  │   Node 194               │  │   Node 196               │  │   Node 197                ││
│  │   192.168.101.194        │  │   192.168.101.196        │  │   192.168.101.197         ││
│  │   (Control+Worker)       │  │   (Control+Worker)       │  │   (Control+Worker)        ││
│  │                          │  │                          │  │                           ││
│  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ ││
│  │ │ Control Plane        │ │  │ │ Control Plane        │ │  │ │ Control Plane        │ ││
│  │ │  • kube-apiserver    │ │  │ │  • kube-apiserver    │ │  │ │  • kube-apiserver    │ ││
│  │ │  • kube-scheduler    │ │  │ │  • kube-scheduler    │ │  │ │  • kube-scheduler    │ ││
│  │ │  • kube-controller   │ │  │ │  • kube-controller   │ │  │ │  • kube-controller   │ ││
│  │ │  • etcd (member 1/4) │ │  │ │  • etcd (member 2/4) │ │  │ │  • etcd (member 3/4) │ ││
│  │ └──────────────────────┘ │  │ └──────────────────────┘ │  │ └──────────────────────┘ ││
│  │                          │  │                          │  │                           ││
│  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ ││
│  │ │ monitoring namespace │ │  │ │ monitoring namespace │ │  │ │ monitoring namespace │ ││
│  │ │                      │ │  │ │                      │ │  │ │                      │ ││
│  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ ││
│  │ │ │ Prometheus-0     │ │ │  │ │ │ Prometheus-1     │ │ │  │ │ │ Thanos Query-0   │ ││
│  │ │ │ StatefulSet      │ │ │  │ │ │ StatefulSet      │ │ │  │ │ │ Deployment       │ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │                  │ ││
│  │ │ │ External Labels: │ │ │  │ │ │ External Labels: │ │ │  │ │ │ StoreAPI Clients:│ ││
│  │ │ │  replica: "A"    │ │ │  │ │ │  replica: "B"    │ │ │  │ │ │  • Prom-0 Sidecar│ ││
│  │ │ │  cluster: "ha"   │ │ │  │ │ │  cluster: "ha"   │ │ │  │ │ │  • Prom-1 Sidecar│ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │  • Store Gateway │ ││
│  │ │ │ ┌──────────────┐ │ │ │  │ │ │ ┌──────────────┐ │ │ │  │ │ │                  │ ││
│  │ │ │ │Thanos Sidecar│ │ │ │  │ │ │ │Thanos Sidecar│ │ │ │  │ │ │ Deduplication:   │ ││
│  │ │ │ │              │ │ │ │  │ │ │ │              │ │ │ │  │ │ │  by replica label│ ││
│  │ │ │ │StoreAPI:19091│ │ │ │  │ │ │ │StoreAPI:19091│ │ │ │  │ │ │                  │ ││
│  │ │ │ └──────┬───────┘ │ │ │  │ │ │ └──────┬───────┘ │ │ │  │ │ └──────────────────┘ ││
│  │ │ │        │ upload  │ │ │  │ │ │        │ upload  │ │ │  │ │                      │ ││
│  │ │ │        │ 2h      │ │ │  │ │ │        │ 2h      │ │ │  │ │ ┌──────────────────┐ ││
│  │ │ │        │ blocks  │ │ │  │ │ │        │ blocks  │ │ │  │ │ │ Grafana          │ ││
│  │ │ │        ▼         │ │ │  │ │ │        ▼         │ │ │  │ │ │                  │ ││
│  │ │ │   [S3 API]      │ │ │  │ │ │   [S3 API]      │ │ │  │ │ │ Datasource:      │ ││
│  │ │ │   s3.minio      │ │ │  │ │ │   s3.minio      │ │ │  │ │ │  → Thanos Query  │ ││
│  │ │ │   .miribit.lab  │ │ │  │ │ │   .miribit.lab  │ │ │  │ │ └──────────────────┘ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │                      │ ││
│  │ │ │ PVC: 10Gi        │ │ │  │ │ │ PVC: 10Gi        │ │ │  │ │ ┌──────────────────┐ ││
│  │ │ │ Retention: 2h    │ │ │  │ │ │ Retention: 2h    │ │ │  │ │ │ Alertmanager     │ ││
│  │ │ │ Scrape: 30s      │ │ │  │ │ │ Scrape: 30s      │ │ │  │ │ └──────────────────┘ ││
│  │ │ └──────────────────┘ │ │  │ │ └──────────────────┘ │ │  │ │                      │ ││
│  │ │                      │ │  │ │                      │ │  │ │ ┌──────────────────┐ ││
│  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ │ │  │ │ │ Thanos Compactor │ ││
│  │ │ │ Thanos Store     │ │ │  │ │ │ Thanos Ruler     │ │ │  │ │ │                  │ ││
│  │ │ │ Gateway          │ │ │  │ │ │                  │ │ │  │ │ │ Compact blocks   │ ││
│  │ │ │                  │ │ │  │ │ │ Alert Rules      │ │ │  │ │ │ from S3          │ ││
│  │ │ │ Query S3 blocks  │ │ │  │ │ │ → Alertmanager   │ │ │  │ │ │                  │ ││
│  │ │ │   ▲              │ │ │  │ │ └──────────────────┘ │ │  │ │ │ Read/Write S3    │ ││
│  │ │ │   │ read         │ │ │  │ │                      │ │ │  │ │ └────┬───────────┘ ││
│  │ │ │   │ blocks       │ │ │  │ │                      │ │ │  │ │      │             │ ││
│  │ │ │   [S3 API]       │ │ │  │ │                      │ │ │  │ │      ▼             │ ││
│  │ │ │   s3.minio       │ │ │  │ │                      │ │ │  │ │ [S3 API]          │ ││
│  │ │ │   .miribit.lab   │ │ │  │ │                      │ │ │  │ │                    │ ││
│  │ │ │                  │ │ │  │ │                      │ │ │  │ │                    │ ││
│  │ │ │ StoreAPI:19091   │ │ │  │ │                      │ │ │  │ │                    │ ││
│  │ │ └──────────────────┘ │ │  │ │                      │ │ │  │ └──────────────────┘ ││
│  │ └──────────────────────┘ │  │ └──────────────────────┘ │  │ └──────────────────────┘ ││
│  │                          │  │                          │  │                           ││
│  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ ││
│  │ │ logging namespace    │ │  │ │ logging namespace    │ │  │ │ logging namespace    │ ││
│  │ │                      │ │  │ │                      │ │  │ │                      │ ││
│  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ ││
│  │ │ │ OpenSearch-0     │ │ │  │ │ │ OpenSearch-1     │ │ │  │ │ │ OpenSearch-2     │ ││
│  │ │ │ Data Node        │ │ │  │ │ │ Data Node        │ │ │  │ │ │ Data Node        │ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │                  │ ││
│  │ │ │ Replication: 2   │ │ │  │ │ │ Replication: 2   │ │ │  │ │ │ Replication: 2   │ ││
│  │ │ │ Retention: 14d   │ │ │  │ │ │ Retention: 14d   │ │ │  │ │ │ Retention: 14d   │ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │                  │ ││
│  │ │ │ ISM Policy:      │ │ │  │ │ │ ISM Policy:      │ │ │  │ │ │ ISM Policy:      │ ││
│  │ │ │  14d → S3        │ │ │  │ │ │  14d → S3        │ │ │  │ │ │  14d → S3        │ ││
│  │ │ │  snapshot        │ │ │  │ │ │  snapshot        │ │ │  │ │ │  snapshot        │ ││
│  │ │ │     ▼            │ │ │  │ │ │     ▼            │ │ │  │ │ │     ▼            │ ││
│  │ │ │  [S3 API]        │ │ │  │ │ │  [S3 API]        │ │ │  │ │ │  [S3 API]        │ ││
│  │ │ │  opensearch-     │ │ │  │ │ │  opensearch-     │ │ │  │ │ │  opensearch-     │ ││
│  │ │ │  snapshots       │ │ │  │ │ │  snapshots       │ │ │  │ │ │  snapshots       │ ││
│  │ │ │  bucket          │ │ │  │ │ │  bucket          │ │ │  │ │ │  bucket          │ ││
│  │ │ └──────────────────┘ │ │  │ │ └──────────────────┘ │ │  │ │ └──────────────────┘ ││
│  │ │                      │ │  │ │                      │ │  │ │                      │ ││
│  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ ││
│  │ │ │ Fluent-bit       │ │ │  │ │ │ Fluent-bit       │ │ │  │ │ │ Fluent-bit       │ ││
│  │ │ │ DaemonSet pod    │ │ │  │ │ │ DaemonSet pod    │ │ │  │ │ │ DaemonSet pod    │ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │                  │ ││
│  │ │ │ Collect all pod  │ │ │  │ │ │ Collect all pod  │ │ │  │ │ │ Collect all pod  │ ││
│  │ │ │ logs on Node 194 │ │ │  │ │ │ logs on Node 196 │ │ │  │ │ │ logs on Node 197 │ ││
│  │ │ │     │            │ │ │  │ │ │     │            │ │ │  │ │ │     │            │ ││
│  │ │ │     └──────►OpenSearch Cluster                  │ │ │  │ │ │     └──────►     │ ││
│  │ │ └──────────────────┘ │ │  │ │ └──────────────────┘ │ │  │ │ └──────────────────┘ ││
│  │ └──────────────────────┘ │  │ └──────────────────────┘ │  │ └──────────────────────┘ ││
│  │                          │  │                          │  │                           ││
│  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ │  │ ┌──────────────────────┐ ││
│  │ │longhorn-system ns    │ │  │ │longhorn-system ns    │ │  │ │longhorn-system ns    │ ││
│  │ │                      │ │  │ │                      │ │ │  │ │                      │ ││
│  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ │ │  │ │ ┌──────────────────┐ ││
│  │ │ │ Longhorn Manager │ │ │  │ │ │ Longhorn Manager │ │ │  │ │ │ Longhorn Manager │ ││
│  │ │ │ + Engine         │ │ │  │ │ │ + Engine         │ │ │  │ │ │ + Engine         │ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │                  │ ││
│  │ │ │ StorageClass:    │ │ │  │ │ │ StorageClass:    │ │ │  │ │ │ StorageClass:    │ ││
│  │ │ │  longhorn        │ │ │  │ │ │  longhorn        │ │ │  │ │ │  longhorn        │ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │                  │ ││
│  │ │ │ Replication: 3   │ │ │  │ │ │ Replication: 3   │ │ │  │ │ │ Replication: 3   │ ││
│  │ │ │                  │ │ │  │ │ │                  │ │ │  │ │ │                  │ ││
│  │ │ │ S3 Backup:       │ │ │  │ │ │ S3 Backup:       │ │ │  │ │ │ S3 Backup:       │ ││
│  │ │ │  Manual trigger  │ │ │  │ │ │  Manual trigger  │ │ │  │ │ │  Manual trigger  │ ││
│  │ │ │     ▼            │ │ │  │ │ │     ▼            │ │ │  │ │ │     ▼            │ ││
│  │ │ │  [S3 API]        │ │ │  │ │ │  [S3 API]        │ │ │  │ │ │  [S3 API]        │ ││
│  │ │ │  longhorn-backup │ │ │  │ │ │  longhorn-backup │ │ │  │ │ │  longhorn-backup │ ││
│  │ │ │  bucket          │ │ │  │ │ │  bucket          │ │ │  │ │ │  bucket          │ ││
│  │ │ └──────────────────┘ │ │  │ │ └──────────────────┘ │ │  │ │ └──────────────────┘ ││
│  │ └──────────────────────┘ │  │ └──────────────────────┘ │  │ └──────────────────────┘ ││
│  └──────────────────────────┘  └──────────────────────────┘  └───────────────────────────┘│
│                                                                                             │
│  ┌──────────────────────────┐                                                              │
│  │   Node 198               │                                                              │
│  │   192.168.101.198        │                                                              │
│  │   (Control+Worker)       │                                                              │
│  │                          │                                                              │
│  │ ┌──────────────────────┐ │                                                              │
│  │ │ Control Plane        │ │                                                              │
│  │ │  • etcd (member 4/4) │ │   etcd Quorum: 3/4 nodes (tolerates 1 failure)             │
│  │ └──────────────────────┘ │                                                              │
│  │                          │                                                              │
│  │ ┌──────────────────────┐ │                                                              │
│  │ │ monitoring namespace │ │                                                              │
│  │ │ ┌──────────────────┐ │ │                                                              │
│  │ │ │ Thanos Query-1   │ │ │                                                              │
│  │ │ │ (HA Replica)     │ │ │                                                              │
│  │ │ │                  │ │ │   Pod Anti-Affinity ensures:                                │
│  │ │ │ Load Balancing   │ │ │   - Prometheus replicas on different nodes                 │
│  │ │ │ with Query-0     │ │ │   - Thanos Query replicas on different nodes               │
│  │ │ └──────────────────┘ │ │                                                              │
│  │ └──────────────────────┘ │                                                              │
│  │                          │                                                              │
│  │ ┌──────────────────────┐ │                                                              │
│  │ │ logging namespace    │ │                                                              │
│  │ │ ┌──────────────────┐ │ │                                                              │
│  │ │ │ Fluent-bit       │ │ │                                                              │
│  │ │ │ DaemonSet pod    │ │ │                                                              │
│  │ │ └──────────────────┘ │ │                                                              │
│  │ └──────────────────────┘ │                                                              │
│  │                          │                                                              │
│  │ ┌──────────────────────┐ │                                                              │
│  │ │longhorn-system ns    │ │                                                              │
│  │ │ ┌──────────────────┐ │ │                                                              │
│  │ │ │ Longhorn Manager │ │ │                                                              │
│  │ │ └──────────────────┘ │ │                                                              │
│  │ └──────────────────────┘ │                                                              │
│  └──────────────────────────┘                                                              │
│                                                                                             │
│         All S3 connections go to: http://s3.minio.miribit.lab                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            │ HTTPS/S3 API
                                            ▼
╔═════════════════════════════════════════════════════════════════════════════════════════════╗
║                          MinIO S3 Storage (External Infrastructure)                        ║
║                          Deployed separately, managed externally                            ║
╚═════════════════════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    MinIO Cluster                                            │
│                                                                                             │
│  Access Information:                                                                        │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  S3 API Endpoint:  http://s3.minio.miribit.lab                                     │   │
│  │  Console Endpoint: http://console.minio.miribit.lab                                │   │
│  │  Access Key:       minio                                                            │   │
│  │  Secret Key:       minio123                                                         │   │
│  │  Region:           us-east-1 (default)                                              │   │
│  │  DNS Server:       192.168.1.1 (resolves *.minio.miribit.lab)                      │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                             │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐  ┌─────────────────┐ │
│  │    Bucket: thanos-bucket     │  │ Bucket: opensearch-snapshots │  │Bucket: longhorn-│ │
│  │    (Metrics Storage)         │  │    (Log Snapshots)           │  │backup           │ │
│  │                              │  │                              │  │(Volume Backups) │ │
│  │ ┌──────────────────────────┐ │  │ ┌──────────────────────────┐ │  │┌───────────────┐│ │
│  │ │ Object Structure:        │ │  │ │ Object Structure:        │ │  ││ Object        ││ │
│  │ │                          │ │  │ │                          │ │  ││ Structure:    ││ │
│  │ │ /01HXXXXXXXXXXXXX/       │ │  │ │ /snapshots/              │ │  ││               ││ │
│  │ │   meta.json              │ │  │ │   snapshot-2024-01-15/   │ │  ││ /backups/     ││ │
│  │ │   chunks/                │ │  │ │     manifest.json        │ │  ││   volume-abc/ ││ │
│  │ │     000001               │ │  │ │     index-0              │ │  ││     backup.cfg││ │
│  │ │     000002               │ │  │ │     index-1              │ │  ││     volume.img││ │
│  │ │   index                  │ │  │ │   snapshot-2024-01-16/   │ │  ││               ││ │
│  │ │                          │ │  │ │     ...                  │ │  ││ Manual        ││ │
│  │ │ /01HYYYYYYYYYYYY/        │ │  │ │                          │ │  ││ Trigger Only  ││ │
│  │ │   meta.json              │ │  │ │ Retention: 180 days      │ │  ││               ││ │
│  │ │   chunks/                │ │  │ │ Lifecycle: Auto-delete   │ │  ││               ││ │
│  │ │   index                  │ │  │ │            after 180d    │ │  ││               ││ │
│  │ │                          │ │  │ │                          │ │  ││               ││ │
│  │ │ External Labels in meta: │ │  │ │ Automated by:            │ │  ││               ││ │
│  │ │   replica: "A" | "B"     │ │  │ │  - OpenSearch ISM Policy │ │  ││               ││ │
│  │ │   cluster: "ha"          │ │  │ │  - Triggers at 14d       │ │  ││               ││ │
│  │ │                          │ │  │ │                          │ │  ││               ││ │
│  │ │ Block Size: ~100MB-2GB   │ │  │ │ Snapshot Size: varies    │ │  ││Backup Size:   ││ │
│  │ │ Retention: Unlimited     │ │  │ │                          │ │  ││varies         ││ │
│  │ │                          │ │  │ │                          │ │  ││               ││ │
│  │ └──────────────────────────┘ │  │ └──────────────────────────┘ │  │└───────────────┘│ │
│  │                              │  │                              │  │                 │ │
│  │ ┌──────────────────────────┐ │  │ ┌──────────────────────────┐ │  │┌───────────────┐│ │
│  │ │ Uploaded by:             │ │  │ │ Uploaded by:             │ │  ││ Uploaded by:  ││ │
│  │ │  • Thanos Sidecar        │ │  │ │  • OpenSearch            │ │  ││ • Longhorn    ││ │
│  │ │    (every 2 hours)       │ │  │ │    (ISM policy: 14d)     │ │  ││   Backup      ││ │
│  │ │  • From Prometheus-0     │ │  │ │  • From all OS nodes     │ │  ││   (manual)    ││ │
│  │ │  • From Prometheus-1     │ │  │ │                          │ │  ││               ││ │
│  │ │                          │ │  │ │ Accessed by:             │ │  ││ Accessed by:  ││ │
│  │ │ Compacted by:            │ │  │ │  • OpenSearch restore    │ │  ││ • Longhorn    ││ │
│  │ │  • Thanos Compactor      │ │  │ │  • Manual investigation  │ │  ││   restore     ││ │
│  │ │    (merges blocks)       │ │  │ │                          │ │  ││               ││ │
│  │ │                          │ │  │ │ Configuration:           │ │  ││Configuration: ││ │
│  │ │ Queried by:              │ │  │ │  opensearch.yml:         │ │  ││ longhorn-     ││ │
│  │ │  • Thanos Store Gateway  │ │  │ │    s3.client.default:    │ │  ││ s3-secret.yaml││ │
│  │ │  • Thanos Query          │ │  │ │      endpoint: s3.minio  │ │  ││   endpoint:   ││ │
│  │ │    (via Store Gateway)   │ │  │ │      access_key: minio   │ │  ││   s3.minio... ││ │
│  │ │  • Grafana               │ │  │ │      secret_key: ***     │ │  ││   accessKey:  ││ │
│  │ │    (via Thanos Query)    │ │  │ │                          │ │  ││   minio       ││ │
│  │ │                          │ │  │ │ Secret: opensearch-s3-   │ │  ││   secretKey:  ││ │
│  │ │ Configuration:           │ │  │ │         secret           │ │  ││   minio123    ││ │
│  │ │  Secret: thanos-s3-config│ │  │ │         (logging ns)     │ │  ││               ││ │
│  │ │  objstore.yml:           │ │  │ └──────────────────────────┘ │  │└───────────────┘│ │
│  │ │    type: S3              │ │  │                              │  │                 │ │
│  │ │    config:               │ │  │                              │  │                 │ │
│  │ │      bucket: thanos-     │ │  │                              │  │                 │ │
│  │ │              bucket      │ │  │                              │  │                 │ │
│  │ │      endpoint: s3.minio  │ │  │                              │  │                 │ │
│  │ │                .miribit  │ │  │                              │  │                 │ │
│  │ │                .lab      │ │  │                              │  │                 │ │
│  │ │      access_key: minio   │ │  │                              │  │                 │ │
│  │ │      secret_key: minio123│ │  │                              │  │                 │ │
│  │ │      insecure: false     │ │  │                              │  │                 │ │
│  │ └──────────────────────────┘ │  │                              │  │                 │ │
│  │                              │  │                              │  │                 │ │
│  │ Total Objects: ~1000+/day    │  │ Total Snapshots: ~30         │  │ Total Backups:  │ │
│  │ (depends on metric volume)   │  │ (one per day, 14d rolling)   │  │ Ad-hoc only     │ │
│  └──────────────────────────────┘  └──────────────────────────────┘  └─────────────────┘ │
│                                                                                             │
│  S3 Security:                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  • Bucket Policy: Private (no public access)                                       │   │
│  │  • Access: Authenticated requests only (access_key + secret_key)                   │   │
│  │  • Encryption: Server-side encryption recommended (SSE-S3 or SSE-KMS)              │   │
│  │  • Versioning: Optional (enable for data protection)                               │   │
│  │  • Lifecycle Rules: Configured per bucket (180d for logs, unlimited for metrics)   │   │
│  │  • Network: Accessible from Kubernetes nodes via DNS resolution                    │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                             │
│  Kubernetes Secrets containing S3 credentials:                                              │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  • monitoring/thanos-s3-config          (for Thanos components)                    │   │
│  │  • logging/opensearch-s3-secret         (for OpenSearch snapshots)                 │   │
│  │  • longhorn-system/longhorn-s3-secret   (for Longhorn backups)                     │   │
│  └────────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


╔═════════════════════════════════════════════════════════════════════════════════════════════╗
║                              Detailed Data Flow - Metrics Path                              ║
╚═════════════════════════════════════════════════════════════════════════════════════════════╝

Step 1: Collection (every 30 seconds)
──────────────────────────────────────
  Kubernetes Resources (Pods, Services, Nodes)
          │
          │ /metrics endpoint scraping
          ▼
  ┌─────────────────────────────────────────┐
  │  Prometheus Replica A (Node 194)        │
  │  Prometheus Replica B (Node 196)        │
  │                                         │
  │  Both scrape same targets:              │
  │   - node-exporter (all nodes)           │
  │   - kube-state-metrics                  │
  │   - kubelet                             │
  │   - Thanos components                   │
  │   - OpenSearch                          │
  │   - Longhorn                            │
  │   - Custom exporters                    │
  │                                         │
  │  Local TSDB storage: 2 hours            │
  └─────────────────────────────────────────┘

Step 2: Labeling & Upload (every 2 hours)
──────────────────────────────────────────
  ┌────────────────────────┐    ┌────────────────────────┐
  │ Thanos Sidecar (Prom A)│    │ Thanos Sidecar (Prom B)│
  │                        │    │                        │
  │ Adds external labels:  │    │ Adds external labels:  │
  │   replica: "A"         │    │   replica: "B"         │
  │   cluster: "ha"        │    │   cluster: "ha"        │
  │                        │    │                        │
  │ Every 2h:              │    │ Every 2h:              │
  │  1. Read TSDB block    │    │  1. Read TSDB block    │
  │  2. Add external labels│    │  2. Add external labels│
  │  3. Upload to S3       │    │  3. Upload to S3       │
  │     thanos-bucket      │    │     thanos-bucket      │
  │                        │    │                        │
  │ S3 Object:             │    │ S3 Object:             │
  │  /01HXX.../meta.json   │    │  /01HYY.../meta.json   │
  │  /01HXX.../chunks/*    │    │  /01HYY.../chunks/*    │
  │  /01HXX.../index       │    │  /01HYY.../index       │
  └────────────────────────┘    └────────────────────────┘
          │                              │
          │                              │
          └──────────────┬───────────────┘
                         │
                         ▼
        ┌────────────────────────────────────┐
        │   MinIO S3: thanos-bucket          │
        │                                    │
        │   Blocks from Replica A:           │
        │     01HXXX... (replica: A)         │
        │     01HXXY... (replica: A)         │
        │                                    │
        │   Blocks from Replica B:           │
        │     01HYYY... (replica: B)         │
        │     01HYYZ... (replica: B)         │
        │                                    │
        │   Same metrics, different replicas │
        │   Timestamps slightly different    │
        └────────────────────────────────────┘

Step 3: Compaction (periodic)
──────────────────────────────
  ┌────────────────────────────────────┐
  │   Thanos Compactor (Node 196)      │
  │                                    │
  │   Reads from S3:                   │
  │    1. Find blocks in same time     │
  │       range                        │
  │    2. Merge multiple 2h blocks     │
  │       → larger blocks (4h, 8h...)  │
  │    3. Apply downsampling           │
  │       (optional)                   │
  │    4. Write compacted block to S3  │
  │    5. Delete source blocks         │
  │                                    │
  │   Benefits:                        │
  │    • Reduced storage               │
  │    • Faster queries                │
  │    • Less S3 API calls             │
  └────────────────────────────────────┘

Step 4: Query (real-time + historical)
───────────────────────────────────────
  User → Grafana → Thanos Query
                       │
                       │ StoreAPI gRPC
                       ▼
  ┌────────────────────────────────────────────────┐
  │  Thanos Query (HA: Query-0, Query-1)           │
  │                                                │
  │  Query sources (all via StoreAPI):             │
  │   1. Prometheus-0 Sidecar → Recent 2h          │
  │   2. Prometheus-1 Sidecar → Recent 2h          │
  │   3. Thanos Store Gateway → Historical (S3)    │
  │                                                │
  │  Deduplication:                                │
  │   • Group by: metric name + timestamp          │
  │   • Compare: replica label                     │
  │   • Keep: First replica (A before B)           │
  │   • Result: Single time series                 │
  │                                                │
  │  Example:                                      │
  │   Input:                                       │
  │    node_cpu{replica="A"} 0.5 @timestamp        │
  │    node_cpu{replica="B"} 0.5 @timestamp        │
  │   Output (deduplicated):                       │
  │    node_cpu{cluster="ha"} 0.5 @timestamp       │
  └────────────────────────────────────────────────┘
          │
          │ PromQL result
          ▼
  ┌────────────────────────────────────────────────┐
  │             Grafana Dashboard                  │
  │                                                │
  │  Shows unified view:                           │
  │   • Recent metrics (2h): from both Prometheus  │
  │   • Historical metrics: from S3 via Store      │
  │   • All deduplicated automatically             │
  │   • No gaps in data                            │
  └────────────────────────────────────────────────┘


╔═════════════════════════════════════════════════════════════════════════════════════════════╗
║                              Detailed Data Flow - Logs Path                                 ║
╚═════════════════════════════════════════════════════════════════════════════════════════════╝

Step 1: Collection (continuous streaming)
──────────────────────────────────────────
  All Pods (stdout/stderr) on all nodes
          │
          │ /var/log/pods/*/*.log
          ▼
  ┌─────────────────────────────────────────┐
  │  Fluent-bit DaemonSet                   │
  │  (one pod per node, 4 total)            │
  │                                         │
  │  Node 194: Collects logs from all pods │
  │  Node 196: Collects logs from all pods │
  │  Node 197: Collects logs from all pods │
  │  Node 198: Collects logs from all pods │
  │                                         │
  │  Enrichment:                            │
  │   • Add Kubernetes metadata             │
  │   • Add node name                       │
  │   • Parse JSON logs                     │
  │   • Buffer: 5MB per stream              │
  └─────────────────────────────────────────┘
          │
          │ Forward (HTTP/TCP)
          │ Target: opensearch:9200
          │ Latency: < 30 seconds
          ▼

Step 2: Indexing (< 30s latency)
──────────────────────────────────
  ┌────────────────────────────────────────────┐
  │  OpenSearch Cluster (3 data nodes)         │
  │                                            │
  │  Index Pattern: logs-YYYY.MM.DD            │
  │  Replication: 2 (each shard x2)            │
  │                                            │
  │  OpenSearch-0 (Node 194):                  │
  │    Primary shards: 0, 3, 6...              │
  │    Replica shards: 1, 4, 7...              │
  │                                            │
  │  OpenSearch-1 (Node 196):                  │
  │    Primary shards: 1, 4, 7...              │
  │    Replica shards: 2, 5, 8...              │
  │                                            │
  │  OpenSearch-2 (Node 197):                  │
  │    Primary shards: 2, 5, 8...              │
  │    Replica shards: 0, 3, 6...              │
  │                                            │
  │  Local Retention: 14 days                  │
  └────────────────────────────────────────────┘
          │
          │ ISM (Index State Management) Policy
          │ Triggers at 14 days
          ▼

Step 3: Snapshot to S3 (after 14 days)
───────────────────────────────────────
  ┌────────────────────────────────────────────┐
  │  OpenSearch ISM Policy                     │
  │                                            │
  │  Policy "hot-warm-delete":                 │
  │   • hot: 0-14 days (queryable)             │
  │   • snapshot: day 14 (copy to S3)          │
  │   • delete: day 14 (delete local index)    │
  │                                            │
  │  Snapshot Repository Config:               │
  │    type: s3                                │
  │    bucket: opensearch-snapshots            │
  │    endpoint: s3.minio.miribit.lab          │
  │    base_path: /snapshots                   │
  │    compress: true                          │
  │    chunk_size: 100mb                       │
  │                                            │
  │  Snapshot naming:                          │
  │    snapshot-2024-01-15-logs-*              │
  └────────────────────────────────────────────┘
          │
          │ S3 PUT operations
          ▼
  ┌────────────────────────────────────────────┐
  │  MinIO S3: opensearch-snapshots            │
  │                                            │
  │  /snapshots/                               │
  │    snapshot-2024-01-15-logs-*/             │
  │      manifest.json                         │
  │      metadata-<uuid>.dat                   │
  │      index-<N>                             │
  │      indices/                              │
  │        <index-uuid>/                       │
  │          shards/                           │
  │            0/                              │
  │              index-<uuid>                  │
  │              __<uuid>                      │
  │                                            │
  │  Lifecycle Policy:                         │
  │    • Transition: None (direct storage)     │
  │    • Expiration: 180 days                  │
  │    • Action: Delete object                 │
  │                                            │
  │  S3 Lifecycle Rule:                        │
  │    <LifecycleConfiguration>                │
  │      <Rule>                                │
  │        <ID>delete-old-snapshots</ID>       │
  │        <Prefix>snapshots/</Prefix>         │
  │        <Status>Enabled</Status>            │
  │        <Expiration>                        │
  │          <Days>180</Days>                  │
  │        </Expiration>                       │
  │      </Rule>                               │
  │    </LifecycleConfiguration>               │
  └────────────────────────────────────────────┘

Step 4: Query & Restore
────────────────────────
  Recent logs (0-14 days):
    User → OpenSearch Dashboards → OpenSearch Cluster
           Direct query from local indices
           Response time: < 1 second

  Historical logs (14-180 days):
    User → OpenSearch Dashboards → Restore snapshot
           1. Select snapshot from S3
           2. Restore to temporary index
           3. Query restored index
           4. Delete temporary index
           Response time: minutes (restore) + seconds (query)


╔═════════════════════════════════════════════════════════════════════════════════════════════╗
║                                  S3 Credential Management                                   ║
╚═════════════════════════════════════════════════════════════════════════════════════════════╝

Kubernetes Secrets (Base64 encoded):
────────────────────────────────────

1. monitoring/thanos-s3-config (Secret)
   ────────────────────────────────────
   apiVersion: v1
   kind: Secret
   metadata:
     name: thanos-s3-config
     namespace: monitoring
   type: Opaque
   stringData:
     objstore.yml: |
       type: S3
       config:
         bucket: thanos-bucket
         endpoint: s3.minio.miribit.lab
         access_key: minio
         secret_key: minio123
         insecure: false

   Used by:
     • Thanos Sidecar (both replicas)
     • Thanos Store Gateway
     • Thanos Compactor
     • Thanos Ruler

2. logging/opensearch-s3-secret (Secret)
   ─────────────────────────────────────
   apiVersion: v1
   kind: Secret
   metadata:
     name: opensearch-s3-secret
     namespace: logging
   type: Opaque
   stringData:
     access_key: minio
     secret_key: minio123
     endpoint: s3.minio.miribit.lab
     bucket: opensearch-snapshots

   Used by:
     • OpenSearch (all 3 nodes)
     • Snapshot repository configuration

3. longhorn-system/longhorn-s3-secret (Secret)
   ───────────────────────────────────────────
   apiVersion: v1
   kind: Secret
   metadata:
     name: longhorn-s3-secret
     namespace: longhorn-system
   type: Opaque
   stringData:
     AWS_ACCESS_KEY_ID: minio
     AWS_SECRET_ACCESS_KEY: minio123
     AWS_ENDPOINTS: http://s3.minio.miribit.lab
     VIRTUAL_HOSTED_STYLE: "false"

   Used by:
     • Longhorn Manager (all nodes)
     • Backup operations (manual trigger)


╔═════════════════════════════════════════════════════════════════════════════════════════════╗
║                                    Storage Capacity Planning                                ║
╚═════════════════════════════════════════════════════════════════════════════════════════════╝

MinIO S3 Buckets - Estimated Storage Requirements:
───────────────────────────────────────────────────

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Bucket: thanos-bucket                                                                   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Metrics Volume:                                                                         │
│   • Prometheus replicas: 2                                                              │
│   • Scrape interval: 30s                                                                │
│   • Active series: ~100,000 (estimated)                                                 │
│   • Samples per scrape: 100,000                                                         │
│   • Samples per hour: 100,000 × 120 (2 per minute) = 12,000,000                        │
│   • Block size (2h): ~500MB per replica                                                 │
│   • Blocks per day: 12 × 2 replicas = 24 blocks                                        │
│   • Daily raw storage: ~12 GB/day (before compaction)                                  │
│   • Daily after compaction: ~6 GB/day (50% reduction)                                  │
│   • Monthly storage: ~180 GB                                                            │
│   • Yearly storage: ~2.2 TB                                                             │
│   • Retention: Unlimited (adjust based on capacity)                                     │
│                                                                                         │
│ Recommended S3 allocation: 5 TB (2-3 years of metrics)                                  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Bucket: opensearch-snapshots                                                            │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Logs Volume:                                                                            │
│   • Pods: ~100 (estimated)                                                              │
│   • Logs per pod: ~1 KB/s average                                                       │
│   • Total logs: 100 KB/s = 8.6 GB/day                                                   │
│   • Snapshot compression: 50% (4.3 GB/day compressed)                                   │
│   • Retention: 180 days                                                                 │
│   • Total storage: 4.3 GB × 180 = 774 GB                                                │
│   • Peak storage: ~1 TB (with overhead)                                                 │
│                                                                                         │
│ Recommended S3 allocation: 2 TB (safety margin + growth)                                │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Bucket: longhorn-backup                                                                 │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ Volume Backups:                                                                         │
│   • PVCs: ~20 (Prometheus, OpenSearch, Grafana, etc.)                                  │
│   • Average PVC size: 10 GB                                                             │
│   • Total PVC storage: 200 GB                                                           │
│   • Backup frequency: Manual (ad-hoc)                                                   │
│   • Backup retention: Manual management                                                 │
│   • Estimated backups: 5 copies × 200 GB = 1 TB                                         │
│                                                                                         │
│ Recommended S3 allocation: 1 TB                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Total MinIO S3 Storage Required                                                         │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│   thanos-bucket:           5 TB                                                         │
│   opensearch-snapshots:    2 TB                                                         │
│   longhorn-backup:         1 TB                                                         │
│   ─────────────────────────────                                                         │
│   Total:                   8 TB                                                         │
│                                                                                         │
│ Recommended MinIO deployment: 10-15 TB (with growth headroom)                           │
└─────────────────────────────────────────────────────────────────────────────────────────┘


╔═════════════════════════════════════════════════════════════════════════════════════════════╗
║                                  Network Connectivity Matrix                                ║
╚═════════════════════════════════════════════════════════════════════════════════════════════╝

Source Component          │ Destination            │ Protocol │ Port  │ Purpose
──────────────────────────┼────────────────────────┼──────────┼───────┼─────────────────────
Prometheus (all replicas) │ Kubernetes API         │ HTTPS    │ 6443  │ Service discovery
Prometheus (all replicas) │ node-exporter          │ HTTP     │ 9100  │ Metrics scraping
Prometheus (all replicas) │ kube-state-metrics     │ HTTP     │ 8080  │ Metrics scraping
Thanos Sidecar (all)      │ s3.minio.miribit.lab   │ HTTP     │ 80    │ Upload blocks
Thanos Query (all)        │ Thanos Sidecar         │ gRPC     │ 19091 │ StoreAPI queries
Thanos Query (all)        │ Thanos Store Gateway   │ gRPC     │ 19091 │ StoreAPI queries
Thanos Store Gateway      │ s3.minio.miribit.lab   │ HTTP     │ 80    │ Read blocks
Thanos Compactor          │ s3.minio.miribit.lab   │ HTTP     │ 80    │ Read/write blocks
Grafana                   │ Thanos Query           │ HTTP     │ 9090  │ PromQL queries
Fluent-bit (all nodes)    │ OpenSearch cluster     │ HTTP     │ 9200  │ Forward logs
OpenSearch (all nodes)    │ s3.minio.miribit.lab   │ HTTP     │ 80    │ Snapshot upload
Longhorn (all nodes)      │ s3.minio.miribit.lab   │ HTTP     │ 80    │ Backup upload
NGINX Ingress             │ All services           │ HTTP     │ varies│ External access
Users (external)          │ NGINX Ingress          │ HTTPS    │ 443   │ Dashboard access
Users (external)          │ console.minio...       │ HTTP     │ 80    │ MinIO console
Operators (external)      │ Kubernetes API         │ HTTPS    │ 6443  │ kubectl access

DNS Resolution:
───────────────
  All Kubernetes nodes:    192.168.1.1 (nameserver)
  Resolves:                *.minio.miribit.lab → MinIO cluster
                           *.k8s.miribit.lab → NGINX Ingress
이 상세한 아키텍처 다이어그램은 다음을 포함합니다:
MinIO S3 상세 정보:
3개의 버킷 (thanos-bucket, opensearch-snapshots, longhorn-backup)
각 버킷의 객체 구조 및 용도
접속 정보 (endpoint, credentials)
업로드/쿼리 흐름
Kubernetes Secrets:
각 컴포넌트별 S3 인증 정보 관리
Secret 구조 및 사용처
데이터 플로우:
메트릭: Prometheus → Thanos Sidecar → S3 → Store Gateway → Query
로그: Fluent-bit → OpenSearch → S3 스냅샷
외부 레이블을 통한 중복 제거 메커니즘
스토리지 용량 계획:
각 버킷별 예상 용량
보존 정책 (메트릭: 무제한, 로그: 180일)
네트워크 연결성:
모든 컴포넌트 간 통신 프로토콜 및 포트
S3 API 엔드포인트로의 연결