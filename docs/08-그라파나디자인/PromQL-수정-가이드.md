# DataOps Dashboard PromQL 수정 가이드

## 📋 문제 요약

현재 배포된 대시보드는 **Spark, Airflow, Trino, Kafka, Iceberg 등의 빅데이터 애플리케이션 메트릭**을 사용하도록 설계되어 있으나, 실제 클러스터에는 이러한 애플리케이션이 배포되지 않았습니다.

현재 수집되는 메트릭은 **Kubernetes 기본 메트릭**만 포함됩니다:
- `kube_*` - kube-state-metrics에서 수집
- `container_*` - cadvisor에서 수집
- `node_*` - node-exporter에서 수집
- `machine_*` - node-exporter에서 수집
- 기타 Prometheus, Grafana, Alertmanager 메트릭

---

## 🔧 해결 방안

### 옵션 1: 빅데이터 애플리케이션 배포 (권장)

대시보드가 의도한 대로 작동하려면 다음 애플리케이션을 배포해야 합니다:

#### 필요한 애플리케이션 및 ServiceMonitor

| 애플리케이션 | Helm Chart | Prometheus Exporter |
|------------|-----------|---------------------|
| **Apache Spark** | `bitnami/spark` | Spark Metrics System (자체 내장) |
| **Apache Airflow** | `apache-airflow/airflow` | StatsD → Prometheus Exporter |
| **Trino** | `trino/trino` | JMX Exporter (자체 내장) |
| **Apache Kafka** | `bitnami/kafka` | Kafka Exporter 또는 JMX Exporter |
| **Apache Iceberg** | - | Custom metrics from Spark/Trino |
| **Hive Metastore** | `bitsensor/hive-metastore` | JMX Exporter |

#### 배포 예시: Spark with Metrics

```bash
# Spark Helm 설치 (Prometheus metrics 활성화)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install spark bitnami/spark \
  --namespace spark \
  --create-namespace \
  --set metrics.enabled=true \
  --set master.extraEnvVars[0].name=SPARK_METRICS_CONF \
  --set master.extraEnvVars[0].value=/opt/bitnami/spark/conf/metrics.properties

# ServiceMonitor 생성
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spark-metrics
  namespace: spark
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: spark
  endpoints:
  - port: metrics
    interval: 30s
EOF
```

---

### 옵션 2: Kubernetes 메트릭 기반 대시보드로 수정

빅데이터 애플리케이션 없이 Kubernetes 모니터링에 집중한 대시보드로 변경합니다.

## 📊 수정된 PromQL - 실제 사용 가능한 메트릭

### 1. **Portal Dashboard (00-portal-e2e.yaml)**

#### ✅ 현재 상태 - 수정 필요 없음
Portal 대시보드의 Health Card들은 **미래 배포를 위한 플레이스홀더**이므로 현재 데이터가 없어도 정상입니다.

---

### 2. **Deployment Pipeline Dashboard (01-deployment-pipeline.yaml)**

#### ❌ Jenkins 메트릭 → ✅ ArgoCD 메트릭으로 대체

**문제 PromQL:**
```promql
# Jenkins는 배포되지 않음
sum(rate(jenkins_job_success_total[1h])) / sum(rate(jenkins_job_total[1h])) * 100
```

**수정된 PromQL:**
```promql
# ArgoCD Sync Success Rate
sum(rate(argocd_app_sync_total{phase="Succeeded"}[1h])) /
sum(rate(argocd_app_sync_total[1h])) * 100

# ArgoCD Sync Duration p95
histogram_quantile(0.95,
  sum(rate(argocd_app_sync_duration_seconds_bucket[5m])) by (le)
)

# Out of Sync Applications
count(argocd_app_info{sync_status="OutOfSync"})

# Failed Syncs
count(argocd_app_info{health_status="Degraded"})
```

**대시보드 수정 필요 패널:**
- `Jenkins Build Success Rate` → `ArgoCD Sync Success Rate`
- `Build Duration p95` → `ArgoCD Sync Duration p95`
- `Jenkins Build Queue Length` → `Out of Sync Applications`

---

### 3. **Application Health Dashboard (02-application-health.yaml)**

#### ✅ 수정 필요 없음 - 모든 메트릭 정상

이 대시보드는 Kubernetes 기본 메트릭만 사용하므로 정상 작동합니다:

```promql
# Pod Running Rate
count(kube_pod_status_phase{phase="Running"}) /
count(kube_pod_status_phase) * 100

# CrashLoopBackOff Pods
count(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"})

# Pod Restart Count
sum(rate(kube_pod_container_status_restarts_total[5m]))

# Service Availability
sum(up{job=~".*"}) / count(up{job=~".*"}) * 100
```

---

### 4. **Resource Capacity Dashboard (03-resource-capacity.yaml)**

#### ⚠️ 일부 메트릭 수정 필요

**문제 PromQL (machine_cpu_cores 사용):**
```promql
# 현재 (정상 작동)
sum(machine_cpu_cores)
```

**Storage 메트릭 - 실제 메트릭으로 수정:**

```promql
# ❌ 기존: Isilon/Ceph 메트릭 (존재하지 않음)
sum(rate(isilon_node_disk_ops_total[5m]))
sum(rate(ceph_osd_op_r[5m]) + rate(ceph_osd_op_w[5m]))

# ✅ 수정: Node 디스크 IOPS
sum(rate(node_disk_reads_completed_total[5m]) + rate(node_disk_writes_completed_total[5m]))

# ✅ 수정: PVC 사용량 (StorageClass별)
sum(kubelet_volume_stats_used_bytes) by (persistentvolumeclaim, storageclass) /
sum(kubelet_volume_stats_capacity_bytes) by (persistentvolumeclaim, storageclass) * 100
```

**Network Bandwidth - 정상 작동:**
```promql
# RX Bandwidth (Mbps)
sum(rate(node_network_receive_bytes_total{device!~"lo|veth.*"}[5m])) * 8 / 1000000

# TX Bandwidth (Mbps)
sum(rate(node_network_transmit_bytes_total{device!~"lo|veth.*"}[5m])) * 8 / 1000000
```

---

### 5. **Workload Performance Dashboard (04-workload-performance.yaml)**

#### ❌ 전체 수정 필요 - 빅데이터 메트릭 존재하지 않음

이 대시보드는 **Spark, Airflow, Trino가 배포되어야** 작동합니다.

**대체 옵션: Kubernetes Workload 모니터링**

```promql
# ✅ Deployment Replica Status
kube_deployment_status_replicas_available /
kube_deployment_spec_replicas

# ✅ StatefulSet Replica Status
kube_statefulset_status_replicas_ready /
kube_statefulset_replicas

# ✅ Job Success Rate
sum(kube_job_status_succeeded) /
(sum(kube_job_status_succeeded) + sum(kube_job_status_failed)) * 100

# ✅ Job Completion Time
avg(kube_job_status_completion_time - kube_job_status_start_time)

# ✅ CronJob Last Success
time() - kube_cronjob_status_last_successful_time
```

---

### 6. **Data Pipeline Dashboard (05-data-pipeline.yaml)**

#### ❌ 전체 수정 필요 - Kafka, Iceberg, S3 메트릭 없음

이 대시보드는 **데이터 파이프라인 애플리케이션이 배포되어야** 작동합니다.

**대체 옵션: 네트워크 및 스토리지 I/O 모니터링**

```promql
# ✅ Container Network I/O
sum(rate(container_network_receive_bytes_total[5m])) by (namespace)
sum(rate(container_network_transmit_bytes_total[5m])) by (namespace)

# ✅ Container Filesystem I/O
sum(rate(container_fs_reads_bytes_total[5m])) by (namespace)
sum(rate(container_fs_writes_bytes_total[5m])) by (namespace)

# ✅ PVC Usage Growth Rate
rate(kubelet_volume_stats_used_bytes[1h])
```

---

### 7. **Optimization & Troubleshooting Dashboard (06-optimization-troubleshooting.yaml)**

#### ⚠️ 일부 수정 필요

대부분의 메트릭은 정상 작동하지만 몇 가지 수정 필요:

**Resource Efficiency Score - 정상:**
```promql
(
  (sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) /
   sum(kube_pod_container_resource_requests{resource="cpu"})) * 50 +
  (sum(container_memory_working_set_bytes{container!=""}) /
   sum(kube_pod_container_resource_requests{resource="memory"})) * 50
)
```

**CPU Throttling Rate - 정상:**
```promql
sum(rate(container_cpu_cfs_throttled_periods_total[5m])) by (namespace) /
sum(rate(container_cpu_cfs_periods_total[5m])) by (namespace) * 100
```

**OOM Kill Events - 정상:**
```promql
sum(increase(kube_pod_container_status_terminated_reason{reason="OOMKilled"}[5m])) by (namespace)
```

**❌ Slow Query Analysis (Trino) - 삭제 또는 비활성화 필요**

Trino가 없으므로 이 패널은 데이터가 없습니다.

---

## 🚀 권장 조치

### 즉시 수정 가능한 대시보드:
- ✅ **Application Health** - 수정 불필요
- ✅ **Resource Capacity** - 일부 Storage 메트릭만 수정
- ✅ **Optimization & Troubleshooting** - 대부분 정상, Trino 패널만 비활성화

### 빅데이터 애플리케이션 배포 후 작동:
- ❌ **Deployment Pipeline** - ArgoCD로 대체 가능
- ❌ **Workload Performance** - Spark/Airflow/Trino 필요
- ❌ **Data Pipeline** - Kafka/Iceberg 필요

---

## 📝 단계별 수정 프로세스

### Step 1: 즉시 작동하는 대시보드 확인

```bash
# Grafana에서 확인
curl -s http://grafana.k8s-cluster-01.miribit.lab/d/dataops-health-v4
curl -s http://grafana.k8s-cluster-01.miribit.lab/d/dataops-resource-v4
curl -s http://grafana.k8s-cluster-01.miribit.lab/d/dataops-optimization-v4
```

### Step 2: 빅데이터 애플리케이션 배포 계획

```bash
# 1. Spark 배포
helm install spark bitnami/spark -n spark --create-namespace --set metrics.enabled=true

# 2. Airflow 배포
helm install airflow apache-airflow/airflow -n airflow --create-namespace --set metrics.enabled=true

# 3. Trino 배포
helm install trino trino/trino -n trino --create-namespace

# 4. Kafka 배포
helm install kafka bitnami/kafka -n kafka --create-namespace
```

### Step 3: ServiceMonitor 생성

각 애플리케이션별로 Prometheus가 메트릭을 수집하도록 ServiceMonitor 생성이 필요합니다.

---

## 🔍 메트릭 확인 방법

### Prometheus에서 사용 가능한 메트릭 확인:

```bash
# 모든 메트릭 나열
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  wget -q -O- 'http://localhost:9090/api/v1/label/__name__/values' | jq -r '.data[]'

# Kubernetes 메트릭만 필터
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  wget -q -O- 'http://localhost:9090/api/v1/label/__name__/values' | \
  jq -r '.data[]' | grep -E '^(kube_|container_|node_)'

# 특정 메트릭 쿼리 테스트
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  wget -q -O- 'http://localhost:9090/api/v1/query?query=up'
```

### Grafana Explore에서 테스트:

1. Grafana UI 접속: http://grafana.k8s-cluster-01.miribit.lab
2. 좌측 메뉴 → Explore
3. PromQL 쿼리 입력 후 Run Query

---

## 📚 참고 자료

### Prometheus Exporter 목록:
- **Spark Metrics**: https://spark.apache.org/docs/latest/monitoring.html
- **Airflow StatsD**: https://airflow.apache.org/docs/apache-airflow/stable/logging-monitoring/metrics.html
- **Trino JMX**: https://trino.io/docs/current/admin/jmx.html
- **Kafka Exporter**: https://github.com/danielqsj/kafka_exporter

### ServiceMonitor 예시:
- https://github.com/prometheus-operator/kube-prometheus/tree/main/manifests

---

## ✅ 체크리스트

- [ ] Application Health Dashboard 확인 (정상 작동 예상)
- [ ] Resource Capacity Dashboard Storage 메트릭 수정
- [ ] Optimization Dashboard에서 Trino 패널 비활성화
- [ ] 빅데이터 애플리케이션 배포 계획 수립
- [ ] ServiceMonitor 생성 및 메트릭 수집 확인
- [ ] 대시보드 전체 재검증

---

**작성일**: 2025-11-07
**작성자**: Claude (Anthropic)
