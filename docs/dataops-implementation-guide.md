# DataOps 플랫폼 모니터링 시스템 구현 가이드

## 📋 목차

1. [개요](#개요)
2. [사전 요구사항](#사전-요구사항)
3. [Phase 1: 메트릭 수집 인프라](#phase-1-메트릭-수집-인프라)
4. [Phase 2: 대시보드 개발](#phase-2-대시보드-개발)
5. [Phase 3: 알림 및 SLO](#phase-3-알림-및-slo)
6. [Phase 4: 최적화](#phase-4-최적화)
7. [트러블슈팅](#트러블슈팅)

---

## 🎯 개요

이 문서는 빅데이터 DataOps 플랫폼의 End-to-End 모니터링 시스템을 구현하기 위한
단계별 가이드입니다.

### 시스템 범위

```
[사용자] → Portal
         ↓
[GitOps] → Bitbucket → Jenkins → ArgoCD
         ↓
[App]    → Spark, Airflow, Trino
         ↓
[Data]   → Iceberg → S3, Hive Metastore
         ↓
[Storage]→ S3/MinIO, Oracle, Isilon, Ceph
```

### 목표

- ✅ 6개 계층 모니터링
- ✅ End-to-End 추적
- ✅ 99.9% 가용성 보장
- ✅ MTTD < 5분, MTTR < 30분

---

## 🔧 사전 요구사항

### 필수 컴포넌트

| 컴포넌트 | 버전 | 용도 |
|----------|------|------|
| Kubernetes | 1.25+ | 컨테이너 오케스트레이션 |
| Prometheus | 2.45+ | 메트릭 수집 |
| Thanos | 0.32+ | 장기 저장 및 멀티클러스터 |
| Grafana | 10.0+ | 시각화 |
| kube-prometheus-stack | 55.0+ | Operator 기반 배포 |

### 권한 요구사항

```yaml
# ServiceAccount 권한
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: dataops-monitoring
rules:
  # Prometheus 메트릭 수집
  - apiGroups: [""]
    resources: ["nodes", "services", "endpoints", "pods"]
    verbs: ["get", "list", "watch"]

  # Custom Resources
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["*"]
    verbs: ["*"]

  # Application 메트릭
  - apiGroups: ["sparkoperator.k8s.io"]
    resources: ["sparkapplications"]
    verbs: ["get", "list", "watch"]
```

---

## 📊 Phase 1: 메트릭 수집 인프라

### 1.1 Prometheus Operator 배포

```bash
# Helm Repository 추가
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Values 파일 생성
cat > dataops-prometheus-values.yaml <<EOF
prometheus:
  prometheusSpec:
    # 리소스 설정
    resources:
      requests:
        cpu: 2000m
        memory: 8Gi
      limits:
        cpu: 4000m
        memory: 16Gi

    # 스토리지 설정
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          resources:
            requests:
              storage: 50Gi

    # External Labels
    externalLabels:
      cluster: dataops-prod
      environment: production
      platform: dataops

    # ServiceMonitor 자동 검색
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

    # Thanos Sidecar (선택사항)
    thanos:
      image: quay.io/thanos/thanos:v0.32.0
      objectStorageConfig:
        name: thanos-s3-config
        key: objstore.yml

    # Remote Write (Thanos Receiver 사용 시)
    remoteWrite:
      - url: http://thanos-receive.monitoring.svc:19291/api/v1/receive
        queueConfig:
          capacity: 10000
          maxShards: 10

grafana:
  enabled: true
  adminPassword: admin123

  # Datasource 설정
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Thanos Query
          type: prometheus
          url: http://thanos-query.monitoring.svc:9090
          isDefault: true

  # Dashboard 자동 로드
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
      provider:
        allowUiUpdates: true

# Alert Manager
alertmanager:
  enabled: true
  config:
    route:
      receiver: 'default'
      routes:
        - match:
            severity: critical
          receiver: pagerduty
        - match:
            severity: high
          receiver: slack
    receivers:
      - name: 'default'
      - name: 'pagerduty'
        pagerduty_configs:
          - service_key: '<YOUR_KEY>'
      - name: 'slack'
        slack_configs:
          - channel: '#dataops-ops'
            api_url: '<SLACK_WEBHOOK_URL>'
EOF

# 배포
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f dataops-prometheus-values.yaml
```

### 1.2 ServiceMonitor 생성

#### Spark Applications

```yaml
# spark-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spark-applications
  namespace: monitoring
  labels:
    app: spark
spec:
  selector:
    matchLabels:
      spark-role: driver
  namespaceSelector:
    matchNames:
      - spark-jobs
      - data-processing
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
      relabelings:
        # Spark App ID
        - sourceLabels: [__meta_kubernetes_pod_label_spark_app_id]
          targetLabel: spark_app_id
          action: replace

        # Executor ID
        - sourceLabels: [__meta_kubernetes_pod_label_spark_executor_id]
          targetLabel: executor_id
          action: replace

        # Job Name
        - sourceLabels: [__meta_kubernetes_pod_annotation_spark_job_name]
          targetLabel: job_name
          action: replace
```

#### Airflow

```yaml
# airflow-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: airflow-statsd
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: airflow-statsd-exporter
  endpoints:
    - port: metrics
      interval: 30s
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_label_dag_id]
          targetLabel: dag_id
```

#### Trino

```yaml
# trino-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: trino
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: trino
      component: coordinator
  endpoints:
    - port: http
      interval: 30s
      path: /v1/metrics
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_label_trino_cluster]
          targetLabel: cluster_name
```

### 1.3 JMX Exporter 배포

#### Spark Driver/Executor

```yaml
# spark-jmx-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: spark-jmx-config
  namespace: spark-jobs
data:
  jmx-exporter-config.yaml: |
    lowercaseOutputName: true
    lowercaseOutputLabelNames: true
    rules:
      # JVM 메모리
      - pattern: java.lang<type=Memory><>HeapMemoryUsage\.(\w+)
        name: jvm_memory_heap_$1
        type: GAUGE

      # GC
      - pattern: java.lang<name=(\w+), type=GarbageCollector><>CollectionCount
        name: jvm_gc_collection_count
        labels:
          gc: $1
        type: COUNTER

      - pattern: java.lang<name=(\w+), type=GarbageCollector><>CollectionTime
        name: jvm_gc_collection_time_seconds
        labels:
          gc: $1
        type: COUNTER
        valueFactor: 0.001

      # Spark Executor
      - pattern: metrics<name=executor\.(\w+)\.(\w+)><>Value
        name: spark_executor_$1_$2
        type: GAUGE

      # Spark Driver
      - pattern: metrics<name=driver\.(\w+)\.(\w+)><>Value
        name: spark_driver_$1_$2
        type: GAUGE
```

```yaml
# spark-application-with-jmx.yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: example-spark-app
  namespace: spark-jobs
spec:
  driver:
    javaOptions: |
      -javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent.jar=8090:/opt/jmx_exporter/config.yaml
    volumeMounts:
      - name: jmx-config
        mountPath: /opt/jmx_exporter
  executor:
    javaOptions: |
      -javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent.jar=8090:/opt/jmx_exporter/config.yaml
    volumeMounts:
      - name: jmx-config
        mountPath: /opt/jmx_exporter
  volumes:
    - name: jmx-config
      configMap:
        name: spark-jmx-config
```

### 1.4 Custom Exporters

#### Iceberg Table Metrics Exporter

```python
# iceberg_exporter.py
from prometheus_client import start_http_server, Gauge, Counter
import time
from pyiceberg.catalog import load_catalog

# Metrics
table_size = Gauge('iceberg_table_size_bytes', 'Table size in bytes', ['database', 'table'])
table_files = Gauge('iceberg_table_files_count', 'Number of data files', ['database', 'table'])
table_snapshots = Gauge('iceberg_table_snapshots_count', 'Number of snapshots', ['database', 'table'])
table_last_update = Gauge('iceberg_table_last_update_timestamp', 'Last update timestamp', ['database', 'table'])

def collect_iceberg_metrics():
    catalog = load_catalog('hive', uri='thrift://hive-metastore:9083')

    for database in catalog.list_namespaces():
        for table_name in catalog.list_tables(database):
            table = catalog.load_table(f"{database}.{table_name}")

            # Table 크기
            total_size = sum(file.file_size_in_bytes for file in table.scan().plan_files())
            table_size.labels(database=database, table=table_name).set(total_size)

            # 파일 개수
            file_count = len(list(table.scan().plan_files()))
            table_files.labels(database=database, table=table_name).set(file_count)

            # Snapshot 개수
            snapshot_count = len(table.history())
            table_snapshots.labels(database=database, table=table_name).set(snapshot_count)

            # 마지막 업데이트
            if table.history():
                last_update = table.history()[-1].timestamp_ms / 1000
                table_last_update.labels(database=database, table=table_name).set(last_update)

if __name__ == '__main__':
    start_http_server(8000)
    while True:
        collect_iceberg_metrics()
        time.sleep(300)  # 5분마다 수집
```

```dockerfile
# Dockerfile
FROM python:3.9-slim

RUN pip install prometheus-client pyiceberg[hive]

COPY iceberg_exporter.py /app/
WORKDIR /app

CMD ["python", "iceberg_exporter.py"]
```

```yaml
# iceberg-exporter-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: iceberg-exporter
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: iceberg-exporter
  template:
    metadata:
      labels:
        app: iceberg-exporter
    spec:
      containers:
        - name: exporter
          image: dataops/iceberg-exporter:v1.0
          ports:
            - containerPort: 8000
              name: metrics
          env:
            - name: HIVE_METASTORE_URI
              value: "thrift://hive-metastore:9083"
---
apiVersion: v1
kind: Service
metadata:
  name: iceberg-exporter
  namespace: monitoring
  labels:
    app: iceberg-exporter
spec:
  ports:
    - port: 8000
      name: metrics
  selector:
    app: iceberg-exporter
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: iceberg-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: iceberg-exporter
  endpoints:
    - port: metrics
      interval: 5m
```

### 1.5 Recording Rules 설정

```yaml
# dataops-recording-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dataops-recording-rules
  namespace: monitoring
spec:
  groups:
    - name: dataops_platform
      interval: 30s
      rules:
        # 전체 플랫폼 가용성
        - record: dataops:platform:availability
          expr: |
            avg(up{job=~"spark.*|airflow.*|trino.*"})

        # 리소스 사용률
        - record: dataops:cluster:cpu_usage_ratio
          expr: |
            1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))

        - record: dataops:cluster:memory_usage_ratio
          expr: |
            1 - (
              sum(node_memory_MemAvailable_bytes) /
              sum(node_memory_MemTotal_bytes)
            )

    - name: dataops_spark
      interval: 1m
      rules:
        # Spark Job 성공률
        - record: dataops:spark:success_rate_24h
          expr: |
            sum(increase(spark_job_succeeded_total[24h])) /
            (
              sum(increase(spark_job_succeeded_total[24h])) +
              sum(increase(spark_job_failed_total[24h]))
            )

        # Spark Executor 평균 메모리 사용률
        - record: dataops:spark:executor_memory_usage_avg
          expr: |
            avg(spark_executor_memory_used_bytes / spark_executor_memory_total_bytes)

        # Spark GC 시간 비율
        - record: dataops:spark:gc_time_ratio
          expr: |
            rate(jvm_gc_collection_time_seconds_total{job="spark"}[5m]) /
            rate(jvm_gc_collection_time_seconds_total{job="spark"}[5m] offset 5m)

    - name: dataops_airflow
      interval: 1m
      rules:
        # Airflow DAG 성공률
        - record: dataops:airflow:dag_success_rate_24h
          expr: |
            sum(increase(airflow_dag_succeeded[24h])) /
            sum(increase(airflow_dag_total[24h]))

        # Airflow Scheduler 지연
        - record: dataops:airflow:scheduler_lag_seconds
          expr: |
            time() - airflow_scheduler_heartbeat

    - name: dataops_trino
      interval: 1m
      rules:
        # Trino Query 성공률
        - record: dataops:trino:query_success_rate_24h
          expr: |
            sum(increase(trino_execution_query_completed{status="FINISHED"}[24h])) /
            sum(increase(trino_execution_query_completed[24h]))

        # Trino Worker 가용률
        - record: dataops:trino:worker_availability
          expr: |
            trino_cluster_active_workers / trino_cluster_total_workers

    - name: dataops_storage
      interval: 5m
      rules:
        # S3 에러율
        - record: dataops:s3:error_rate
          expr: |
            sum(rate(s3_errors_total[5m])) /
            sum(rate(s3_requests_total[5m]))

        # Iceberg 작은 파일 비율
        - record: dataops:iceberg:small_files_ratio
          expr: |
            sum(iceberg_table_files_count{size_category="small"}) /
            sum(iceberg_table_files_count)

        # 스토리지 용량 예측 (7일 후)
        - record: dataops:storage:capacity_forecast_7d
          expr: |
            predict_linear(
              sum(kubelet_volume_stats_used_bytes{persistentvolumeclaim=~".*dataops.*"})[7d:1h],
              7 * 24 * 3600
            )
```

---

## 📈 Phase 2: 대시보드 개발

### 2.1 ConfigMap으로 대시보드 배포

모든 대시보드는 ConfigMap으로 관리하여 GitOps 방식으로 배포합니다.

```bash
# 대시보드 디렉토리 구조
deploy-new/overlays/cluster-01-central/kube-prometheus-stack/dashboards/dataops/
├── 00-dataops-main-navigation.yaml           # 메인 네비게이션
├── 01-dataops-gitops-pipeline.yaml          # GitOps 배포 파이프라인
├── 02-dataops-resource-capacity.yaml        # 리소스 가용량
├── 03-dataops-workload-execution.yaml       # 워크로드 실행
├── 04-dataops-data-pipeline.yaml            # 데이터 파이프라인
├── 05-dataops-optimization.yaml             # 최적화 & 트러블슈팅
└── 06-dataops-e2e-analytics.yaml            # E2E 분석
```

### 2.2 kustomization.yaml에 추가

```yaml
# kustomization.yaml
resources:
  # ... 기존 리소스들

  # DataOps 대시보드
  - dashboards/dataops/00-dataops-main-navigation.yaml
  - dashboards/dataops/01-dataops-gitops-pipeline.yaml
  - dashboards/dataops/02-dataops-resource-capacity.yaml
  - dashboards/dataops/03-dataops-workload-execution.yaml
  - dashboards/dataops/04-dataops-data-pipeline.yaml
  - dashboards/dataops/05-dataops-optimization.yaml
  - dashboards/dataops/06-dataops-e2e-analytics.yaml
```

### 2.3 배포

```bash
# ConfigMap 생성
kubectl apply -k deploy-new/overlays/cluster-01-central/kube-prometheus-stack/

# Grafana Pod 재시작 (자동 로드)
kubectl rollout restart deployment -n monitoring kube-prometheus-stack-grafana

# 대시보드 로드 확인
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=50
```

---

## 🚨 Phase 3: 알림 및 SLO

### 3.1 Alert Rules 설정

```yaml
# dataops-alert-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dataops-alert-rules
  namespace: monitoring
spec:
  groups:
    - name: dataops_critical
      interval: 1m
      rules:
        # 플랫폼 다운
        - alert: DataOpsPlatformDown
          expr: dataops:platform:availability < 0.95
          for: 2m
          labels:
            severity: critical
            component: platform
          annotations:
            summary: "DataOps 플랫폼 가용성 저하 ({{ $value | humanizePercentage }})"
            description: "전체 플랫폼 가용성이 95% 미만입니다."

        # OOM Kill 빈발
        - alert: OOMKillFrequent
          expr: |
            sum(increase(kube_pod_container_status_terminated_reason{
              reason="OOMKilled",
              namespace=~"spark.*|airflow.*|trino.*"
            }[10m])) > 3
          for: 5m
          labels:
            severity: critical
            component: infrastructure
          annotations:
            summary: "OOM Kill 빈번 발생 ({{ $value }}회/10분)"

        # Spark Job 대량 실패
        - alert: SparkJobFailureSpike
          expr: |
            (
              sum(increase(spark_job_failed_total[10m])) /
              sum(increase(spark_job_total[10m]))
            ) > 0.2
          for: 5m
          labels:
            severity: critical
            component: spark
          annotations:
            summary: "Spark Job 실패율 급증 ({{ $value | humanizePercentage }})"

    - name: dataops_high
      interval: 2m
      rules:
        # 리소스 부족
        - alert: CPUCapacityLow
          expr: dataops:cluster:cpu_usage_ratio > 0.85
          for: 10m
          labels:
            severity: high
            component: infrastructure
          annotations:
            summary: "CPU 용량 부족 ({{ $value | humanizePercentage }})"

        - alert: MemoryCapacityLow
          expr: dataops:cluster:memory_usage_ratio > 0.90
          for: 10m
          labels:
            severity: high
            component: infrastructure
          annotations:
            summary: "메모리 용량 부족 ({{ $value | humanizePercentage }})"

        # 스토리지 부족
        - alert: StorageCapacityLow
          expr: |
            (
              sum(kubelet_volume_stats_used_bytes{namespace=~"spark.*|airflow.*|trino.*"}) /
              sum(kubelet_volume_stats_capacity_bytes{namespace=~"spark.*|airflow.*|trino.*"})
            ) > 0.85
          for: 15m
          labels:
            severity: high
            component: storage
          annotations:
            summary: "스토리지 용량 부족 ({{ $value | humanizePercentage }})"

        # Iceberg 작은 파일 많음
        - alert: IcebergSmallFilesHigh
          expr: dataops:iceberg:small_files_ratio > 0.5
          for: 1h
          labels:
            severity: high
            component: iceberg
          annotations:
            summary: "Iceberg 작은 파일 비율 높음 ({{ $value | humanizePercentage }})"
            description: "Compaction 필요"

    - name: dataops_medium
      interval: 5m
      rules:
        # Slow Query
        - alert: TrinoSlowQueriesHigh
          expr: |
            count(
              trino_query_wall_time_seconds > 600
              and
              trino_query_state == "RUNNING"
            ) > 5
          for: 10m
          labels:
            severity: medium
            component: trino
          annotations:
            summary: "Trino 슬로우 쿼리 다수 ({{ $value }}개)"

        # Airflow Scheduler 지연
        - alert: AirflowSchedulerLag
          expr: dataops:airflow:scheduler_lag_seconds > 60
          for: 5m
          labels:
            severity: medium
            component: airflow
          annotations:
            summary: "Airflow Scheduler 지연 ({{ $value }}초)"
```

### 3.2 SLO 정의

```yaml
# dataops-slo.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dataops-slo
  namespace: monitoring
spec:
  groups:
    - name: dataops_slo_availability
      interval: 1m
      rules:
        # SLO: 99.9% 가용성
        - record: dataops:slo:availability:target
          expr: 0.999

        # SLI: 실제 가용성
        - record: dataops:slo:availability:sli
          expr: dataops:platform:availability

        # Error Budget
        - record: dataops:slo:availability:error_budget
          expr: |
            1 - (
              (1 - dataops:slo:availability:sli) /
              (1 - dataops:slo:availability:target)
            )

        # Burn Rate (1시간 윈도우)
        - record: dataops:slo:availability:burn_rate_1h
          expr: |
            (
              1 - avg_over_time(dataops:platform:availability[1h])
            ) / (1 - 0.999)

        # Burn Rate (6시간 윈도우)
        - record: dataops:slo:availability:burn_rate_6h
          expr: |
            (
              1 - avg_over_time(dataops:platform:availability[6h])
            ) / (1 - 0.999)

    - name: dataops_slo_latency
      interval: 1m
      rules:
        # SLO: P95 레이턴시 < 1시간
        - record: dataops:slo:latency:target_seconds
          expr: 3600

        # SLI: 실제 P95 레이턴시
        - record: dataops:slo:latency:sli_seconds
          expr: |
            histogram_quantile(0.95,
              sum(rate(spark_job_duration_seconds_bucket[5m])) by (le)
            )

    - name: dataops_slo_alerts
      interval: 1m
      rules:
        # Error Budget 빠른 소진 알림
        - alert: ErrorBudgetBurnRateCritical
          expr: |
            (
              dataops:slo:availability:burn_rate_1h > 14.4
              and
              dataops:slo:availability:burn_rate_6h > 6
            )
          for: 2m
          labels:
            severity: critical
            slo: availability
          annotations:
            summary: "Error Budget 빠른 소진 (1시간 내 5% 소진 예상)"

        - alert: ErrorBudgetBurnRateHigh
          expr: |
            (
              dataops:slo:availability:burn_rate_1h > 7
              and
              dataops:slo:availability:burn_rate_6h > 3
            )
          for: 15m
          labels:
            severity: high
            slo: availability
          annotations:
            summary: "Error Budget 소진 경고 (6시간 내 10% 소진 예상)"

        # Error Budget 소진 임박
        - alert: ErrorBudgetExhausted
          expr: dataops:slo:availability:error_budget < 0.1
          for: 5m
          labels:
            severity: critical
            slo: availability
          annotations:
            summary: "Error Budget 소진 임박 ({{ $value | humanizePercentage }} 남음)"
```

---

## ⚡ Phase 4: 최적화

### 4.1 Recording Rule 최적화

자주 사용되는 복잡한 쿼리를 Recording Rule로 사전 계산:

```yaml
# 대시보드에서 자주 사용하는 쿼리를 Recording Rule로 변환
- record: dataops:spark:active_jobs_by_namespace
  expr: sum(spark_job_active_count) by (namespace, spark_app_id)

- record: dataops:resource:node_allocatable_ratio
  expr: |
    sum(kube_node_status_allocatable{resource="cpu"}) /
    sum(kube_node_status_capacity{resource="cpu"})
```

### 4.2 대시보드 쿼리 최적화

```
Before:
sum(rate(spark_job_duration_seconds_sum[5m])) by (namespace) /
sum(rate(spark_job_duration_seconds_count[5m])) by (namespace)

After (Recording Rule 사용):
dataops:spark:job_duration_avg_by_namespace
```

### 4.3 Retention 정책 최적화

```yaml
# Prometheus retention
retention: 15d  # Raw 데이터 15일

# Thanos downsampling
- resolution: 5m
  retention: 90d

- resolution: 1h
  retention: 1y
```

---

## 🔍 트러블슈팅

### 메트릭이 수집되지 않을 때

```bash
# 1. Prometheus Targets 확인
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090/targets

# 2. ServiceMonitor 확인
kubectl get servicemonitor -n monitoring

# 3. Service Label 확인
kubectl get svc -n <namespace> --show-labels

# 4. Pod Label 확인
kubectl get pods -n <namespace> --show-labels
```

### 대시보드가 로드되지 않을 때

```bash
# 1. ConfigMap 확인
kubectl get cm -n monitoring -l grafana_dashboard=1

# 2. Sidecar 로그 확인
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard

# 3. Grafana 재시작
kubectl rollout restart deployment -n monitoring kube-prometheus-stack-grafana
```

### 알림이 발송되지 않을 때

```bash
# 1. AlertManager 상태 확인
kubectl get alertmanager -n monitoring

# 2. Alert Rule 확인
kubectl get prometheusrule -n monitoring

# 3. AlertManager UI 확인
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# http://localhost:9093
```

---

## 📚 다음 단계

1. **Phase 1 완료 후**: 메트릭 수집 검증
2. **Phase 2 완료 후**: 대시보드 사용자 테스트
3. **Phase 3 완료 후**: 알림 테스트 (실제 장애 시뮬레이션)
4. **Phase 4 완료 후**: 성능 벤치마크

---

**문서 버전**: v1.0
**마지막 업데이트**: 2025-11-05
**작성자**: DataOps Platform Team
