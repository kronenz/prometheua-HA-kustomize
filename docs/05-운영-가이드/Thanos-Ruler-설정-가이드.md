# Thanos Ruler 설정 가이드

## 목차
1. [개요](#개요)
2. [Ruler Config 구조](#ruler-config-구조)
3. [Recording Rules 작성](#recording-rules-작성)
4. [Alerting Rules 작성](#alerting-rules-작성)
5. [멀티클러스터 실전 예시](#멀티클러스터-실전-예시)
6. [ConfigMap으로 외부 파일 사용](#configmap으로-외부-파일-사용)
7. [Kustomize를 사용한 Rule 관리](#kustomize를-사용한-rule-관리)
8. [검증 및 테스트](#검증-및-테스트)
9. [필수 Ingress 설정](#필수-ingress-설정)

---

## 개요

Thanos Ruler는 Prometheus Rule 형식을 사용하여 **Recording Rules**와 **Alerting Rules**를 평가하는 컴포넌트입니다.

### 주요 기능
- **Recording Rules**: 자주 사용하는 복잡한 쿼리를 사전 계산하여 새로운 메트릭으로 저장
- **Alerting Rules**: 특정 조건이 만족되면 Alertmanager로 알림 전송
- **멀티클러스터 지원**: 여러 클러스터의 메트릭을 집계하여 규칙 평가

### 아키텍처

```
Thanos Ruler
    ↓ Query (PromQL 평가)
Thanos Query
    ↓ Store API (gRPC)
├── Thanos Receiver (실시간 데이터)
├── Thanos Store Gateway (S3 과거 데이터)
└── Prometheus Agent (엣지 클러스터)

Thanos Ruler
    ↓ Alert (조건 만족 시)
Alertmanager
    ↓ Notification
Slack / Email / PagerDuty
```

---

## Ruler Config 구조

### 기본 구조

```yaml
ruler:
  enabled: true

  config: |-
    groups:
      - name: 그룹이름
        interval: 평가주기
        rules:
          - record: 새로운_메트릭_이름  # Recording Rule
            expr: PromQL 쿼리
            labels:
              추가_레이블: 값

          - alert: 알림이름  # Alerting Rule
            expr: PromQL 조건
            for: 지속시간
            labels:
              severity: critical
            annotations:
              summary: 알림 요약
              description: 상세 설명
```

### 필수 설정 항목

```yaml
ruler:
  enabled: true

  # Alertmanager 설정 (알림 전송 대상)
  alertmanagers:
    - http://alertmanager.monitoring.svc.cluster.local:9093

  # Query 엔드포인트 (규칙 평가 시 쿼리 대상)
  queries:
    - dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local

  # Rule 파일 내용
  config: |-
    groups: []
```

---

## Recording Rules 작성

Recording Rules는 복잡한 쿼리를 사전 계산하여 새로운 메트릭으로 저장합니다.

### 멀티클러스터 메트릭 집계

```yaml
groups:
  - name: multicluster_aggregation
    interval: 30s
    rules:
      # 전체 클러스터의 총 CPU 사용률
      - record: cluster:cpu_usage:total
        expr: sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)
        labels:
          aggregation: cluster

      # 전체 클러스터의 총 메모리 사용량
      - record: cluster:memory_usage:total
        expr: sum(container_memory_working_set_bytes) by (cluster)
        labels:
          aggregation: cluster

      # 클러스터별 노드 수
      - record: cluster:node_count:total
        expr: count(up{job="node-exporter"}) by (cluster)

      # 클러스터별 Pod 수
      - record: cluster:pod_count:total
        expr: count(kube_pod_info) by (cluster)

      # 네임스페이스별 CPU 사용률 (모든 클러스터)
      - record: namespace:cpu_usage:sum
        expr: sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster, namespace)

      # 네임스페이스별 메모리 사용량
      - record: namespace:memory_usage:sum
        expr: sum(container_memory_working_set_bytes) by (cluster, namespace)
```

### SLO(Service Level Objective) 계산

```yaml
groups:
  - name: slo_calculations
    interval: 1m
    rules:
      # 서비스 가용성 (성공률)
      - record: service:availability:5m
        expr: |
          sum(rate(http_requests_total{status!~"5.."}[5m])) by (cluster, namespace, service) /
          sum(rate(http_requests_total[5m])) by (cluster, namespace, service)

      # 서비스 레이턴시 (95th percentile)
      - record: service:latency:p95:5m
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (cluster, namespace, service, le)
          )

      # 서비스 레이턴시 (99th percentile)
      - record: service:latency:p99:5m
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (cluster, namespace, service, le)
          )

      # 에러 버짓 (30일 기준)
      - record: service:error_budget:30d
        expr: |
          1 - (
            sum(increase(http_requests_total{status=~"5.."}[30d])) by (cluster, namespace, service) /
            sum(increase(http_requests_total[30d])) by (cluster, namespace, service)
          )
```

---

## Alerting Rules 작성

Alerting Rules는 특정 조건이 만족되면 Alertmanager로 알림을 전송합니다.

### 클러스터 상태 알림

```yaml
groups:
  - name: cluster_health
    interval: 1m
    rules:
      # 클러스터가 다운된 경우
      - alert: ClusterDown
        expr: up{job="prometheus"} == 0
        for: 5m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "클러스터 {{ $labels.cluster }}가 다운되었습니다"
          description: "클러스터 {{ $labels.cluster }}에서 5분 동안 메트릭이 수신되지 않았습니다."

      # 노드가 다운된 경우
      - alert: NodeDown
        expr: up{job="node-exporter"} == 0
        for: 3m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "노드 {{ $labels.instance }}가 다운되었습니다"
          description: "클러스터 {{ $labels.cluster }}의 노드 {{ $labels.instance }}가 3분 동안 응답하지 않습니다."

      # 높은 CPU 사용률
      - alert: HighCPUUsage
        expr: cluster:cpu_usage:total > 0.8
        for: 10m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "클러스터 {{ $labels.cluster }} CPU 사용률 높음"
          description: "클러스터 {{ $labels.cluster }}의 CPU 사용률이 80%를 10분 동안 초과했습니다. 현재 값: {{ $value | humanizePercentage }}"

      # 높은 메모리 사용률
      - alert: HighMemoryUsage
        expr: |
          (cluster:memory_usage:total /
           sum(kube_node_status_allocatable{resource="memory"}) by (cluster)) > 0.85
        for: 10m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "클러스터 {{ $labels.cluster }} 메모리 사용률 높음"
          description: "클러스터 {{ $labels.cluster }}의 메모리 사용률이 85%를 초과했습니다."

      # 디스크 사용률 높음
      - alert: HighDiskUsage
        expr: |
          (node_filesystem_avail_bytes{mountpoint="/"} /
           node_filesystem_size_bytes{mountpoint="/"}) < 0.2
        for: 5m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "디스크 사용률 높음: {{ $labels.instance }}"
          description: "노드 {{ $labels.instance }}의 디스크 여유 공간이 20% 미만입니다."
```

### Thanos 컴포넌트 상태 알림

```yaml
groups:
  - name: thanos_components
    interval: 1m
    rules:
      # Thanos Receiver가 다운된 경우
      - alert: ThanosReceiverDown
        expr: up{job="thanos-receiver"} == 0
        for: 5m
        labels:
          severity: critical
          component: thanos
        annotations:
          summary: "Thanos Receiver가 다운되었습니다"
          description: "Thanos Receiver 인스턴스 {{ $labels.instance }}가 5분 동안 응답하지 않습니다. Remote Write가 실패할 수 있습니다."

      # Thanos Query가 다운된 경우
      - alert: ThanosQueryDown
        expr: up{job="thanos-query"} == 0
        for: 5m
        labels:
          severity: critical
          component: thanos
        annotations:
          summary: "Thanos Query가 다운되었습니다"
          description: "Thanos Query가 다운되어 Grafana에서 메트릭을 조회할 수 없습니다."

      # Thanos Compactor가 오래 실행되지 않은 경우
      - alert: ThanosCompactorNotRun
        expr: time() - thanos_compact_last_run_timestamp_seconds > 86400
        for: 1h
        labels:
          severity: warning
          component: thanos
        annotations:
          summary: "Thanos Compactor가 24시간 동안 실행되지 않았습니다"
          description: "Thanos Compactor가 24시간 이상 실행되지 않았습니다. S3 블록 압축이 지연되고 있습니다."

      # Thanos Store Gateway가 다운된 경우
      - alert: ThanosStoreDown
        expr: up{job="thanos-store"} == 0
        for: 10m
        labels:
          severity: warning
          component: thanos
        annotations:
          summary: "Thanos Store Gateway가 다운되었습니다"
          description: "Thanos Store Gateway가 다운되어 S3의 과거 데이터를 조회할 수 없습니다."

      # Thanos Ruler가 다운된 경우
      - alert: ThanosRulerDown
        expr: up{job="thanos-ruler"} == 0
        for: 5m
        labels:
          severity: warning
          component: thanos
        annotations:
          summary: "Thanos Ruler가 다운되었습니다"
          description: "Thanos Ruler가 다운되어 Recording Rules와 Alerting Rules가 평가되지 않습니다."
```

### Prometheus Agent (엣지 클러스터) 알림

```yaml
groups:
  - name: prometheus_agent
    interval: 1m
    rules:
      # Remote Write 실패율이 높은 경우
      - alert: HighRemoteWriteFailureRate
        expr: |
          rate(prometheus_remote_storage_failed_samples_total[5m]) /
          rate(prometheus_remote_storage_samples_total[5m]) > 0.05
        for: 10m
        labels:
          severity: warning
          component: prometheus-agent
        annotations:
          summary: "클러스터 {{ $labels.cluster }} Remote Write 실패율 높음"
          description: "클러스터 {{ $labels.cluster }}의 Remote Write 실패율이 5%를 초과했습니다. 현재 실패율: {{ $value | humanizePercentage }}"

      # Remote Write Queue가 가득 찬 경우
      - alert: RemoteWriteQueueFull
        expr: |
          prometheus_remote_storage_queue_highest_sent_timestamp_seconds -
          prometheus_remote_storage_queue_samples_total > 100000
        for: 5m
        labels:
          severity: critical
          component: prometheus-agent
        annotations:
          summary: "클러스터 {{ $labels.cluster }} Remote Write Queue 포화"
          description: "클러스터 {{ $labels.cluster }}의 Remote Write Queue가 가득 차서 메트릭 손실이 발생할 수 있습니다."

      # Prometheus Agent가 다운된 경우
      - alert: PrometheusAgentDown
        expr: up{job="prometheus-agent"} == 0
        for: 5m
        labels:
          severity: critical
          component: prometheus-agent
        annotations:
          summary: "Prometheus Agent가 다운되었습니다"
          description: "클러스터 {{ $labels.cluster }}의 Prometheus Agent가 5분 동안 응답하지 않습니다."

      # Remote Write 지연 증가
      - alert: HighRemoteWriteLatency
        expr: |
          rate(prometheus_remote_storage_queue_duration_seconds_sum[5m]) /
          rate(prometheus_remote_storage_queue_duration_seconds_count[5m]) > 5
        for: 10m
        labels:
          severity: warning
          component: prometheus-agent
        annotations:
          summary: "클러스터 {{ $labels.cluster }} Remote Write 지연 증가"
          description: "Remote Write 평균 지연 시간이 5초를 초과했습니다."
```

### 애플리케이션 성능 알림

```yaml
groups:
  - name: application_performance
    interval: 1m
    rules:
      # HTTP 5xx 오류율이 높은 경우
      - alert: HighHTTP5xxRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m])) by (cluster, namespace, service) /
          sum(rate(http_requests_total[5m])) by (cluster, namespace, service) > 0.05
        for: 5m
        labels:
          severity: warning
          team: dev
        annotations:
          summary: "높은 5xx 오류율: {{ $labels.service }}"
          description: "클러스터 {{ $labels.cluster }}, 네임스페이스 {{ $labels.namespace }}의 서비스 {{ $labels.service }}에서 5xx 오류율이 5%를 초과했습니다."

      # 느린 응답 시간
      - alert: SlowResponseTime
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (cluster, namespace, service, le)
          ) > 1
        for: 10m
        labels:
          severity: warning
          team: dev
        annotations:
          summary: "느린 응답 시간: {{ $labels.service }}"
          description: "클러스터 {{ $labels.cluster }}의 서비스 {{ $labels.service }}의 95th percentile 응답 시간이 1초를 초과했습니다. 현재 값: {{ $value }}s"

      # Pod Restart 빈번함
      - alert: FrequentPodRestarts
        expr: |
          rate(kube_pod_container_status_restarts_total[15m]) > 0.05
        for: 5m
        labels:
          severity: warning
          team: dev
        annotations:
          summary: "Pod 재시작 빈번: {{ $labels.namespace }}/{{ $labels.pod }}"
          description: "클러스터 {{ $labels.cluster }}의 Pod이 15분간 빈번하게 재시작되고 있습니다."
```

---

## 멀티클러스터 실전 예시

### 완전한 설정 예시

```yaml
ruler:
  enabled: true

  # Alertmanager 설정
  alertmanagers:
    - http://alertmanager.monitoring.svc.cluster.local:9093

  # Query 엔드포인트
  queries:
    - dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local

  # Rule 파일 내용
  config: |-
    groups:
      # ============================================================
      # Recording Rules: 멀티클러스터 메트릭 집계
      # ============================================================
      - name: multicluster_aggregation
        interval: 30s
        rules:
          - record: cluster:cpu_usage:total
            expr: sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)

          - record: cluster:memory_usage:total
            expr: sum(container_memory_working_set_bytes) by (cluster)

          - record: cluster:node_count:total
            expr: count(up{job="node-exporter"}) by (cluster)

          - record: cluster:pod_count:total
            expr: count(kube_pod_info) by (cluster)

      # ============================================================
      # Alerting Rules: 클러스터 상태 알림
      # ============================================================
      - name: cluster_health
        interval: 1m
        rules:
          - alert: ClusterDown
            expr: up{job="prometheus"} == 0
            for: 5m
            labels:
              severity: critical
              team: platform
            annotations:
              summary: "클러스터 {{ $labels.cluster }}가 다운되었습니다"
              description: "5분 동안 메트릭이 수신되지 않았습니다."

          - alert: HighCPUUsage
            expr: cluster:cpu_usage:total > 0.8
            for: 10m
            labels:
              severity: warning
              team: platform
            annotations:
              summary: "클러스터 {{ $labels.cluster }} CPU 사용률 높음"
              description: "CPU 사용률: {{ $value | humanizePercentage }}"

      # ============================================================
      # Alerting Rules: Thanos 컴포넌트 상태
      # ============================================================
      - name: thanos_components
        interval: 1m
        rules:
          - alert: ThanosReceiverDown
            expr: up{job="thanos-receiver"} == 0
            for: 5m
            labels:
              severity: critical
              component: thanos
            annotations:
              summary: "Thanos Receiver 다운"
              description: "Remote Write가 실패할 수 있습니다."
```

### 멀티클러스터 라벨 활용

엣지 클러스터마다 `external_labels`를 설정하므로, Ruler에서 이를 활용:

```yaml
groups:
  - name: multicluster_alerts
    rules:
      # 특정 클러스터만 알림
      - alert: ProductionClusterDown
        expr: up{job="prometheus", cluster="prod-cluster"} == 0
        for: 5m
        labels:
          severity: critical
          environment: production
        annotations:
          summary: "프로덕션 클러스터 다운"

      # 특정 환경 (여러 클러스터)
      - alert: ProductionEnvironmentHighLoad
        expr: cluster:cpu_usage:total{environment="production"} > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "프로덕션 환경 고부하: {{ $labels.cluster }}"

      # 모든 클러스터 통합 알림
      - alert: AnyClusterHighLoad
        expr: cluster:cpu_usage:total > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "클러스터 {{ $labels.cluster }} 고부하"
          description: "CPU 사용률: {{ $value | humanizePercentage }}"
```

---

## ConfigMap으로 외부 파일 사용

대규모 환경에서는 `config:` 대신 **ConfigMap**을 사용하는 것이 관리하기 편합니다.

### 방법 1: ConfigMap 직접 생성

```bash
# rules.yaml 파일 생성
cat <<EOF > rules.yaml
groups:
  - name: example
    rules:
      - record: cluster:cpu_usage:total
        expr: sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)

      - alert: ClusterDown
        expr: up{job="prometheus"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "클러스터 다운"
EOF

# ConfigMap 생성
kubectl create configmap thanos-ruler-rules \
  --from-file=rules.yaml \
  -n monitoring
```

### 방법 2: Helm values.yaml에서 참조

```yaml
ruler:
  enabled: true

  # 외부 ConfigMap 사용
  existingConfigmap: thanos-ruler-rules

  # configReloader 사용 (자동 리로드)
  configReloader:
    enabled: true
```

### ConfigMap 업데이트 후 리로드

```bash
# ConfigMap 업데이트
kubectl create configmap thanos-ruler-rules \
  --from-file=rules.yaml \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

# Ruler Pod 재시작 (자동 리로드 안 되는 경우)
kubectl rollout restart statefulset/thanos-ruler -n monitoring
```

---

## Kustomize를 사용한 Rule 관리

### 디렉토리 구조

```
overlays/cluster-01-central/thanos-ruler/
├── kustomization.yaml
├── rules/
│   ├── recording-rules.yaml
│   ├── alerting-rules-cluster.yaml
│   ├── alerting-rules-thanos.yaml
│   └── alerting-rules-app.yaml
└── values.yaml
```

### kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
  - ../../../base/thanos-ruler

# ConfigMap 생성 (Rule 파일들)
configMapGenerator:
  - name: thanos-ruler-rules
    files:
      - rules/recording-rules.yaml
      - rules/alerting-rules-cluster.yaml
      - rules/alerting-rules-thanos.yaml
      - rules/alerting-rules-app.yaml

# Helm Values 패치
patchesStrategicMerge:
  - values.yaml
```

### Recording Rules 파일

```yaml
# rules/recording-rules.yaml
groups:
  - name: multicluster_aggregation
    interval: 30s
    rules:
      - record: cluster:cpu_usage:total
        expr: sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)

      - record: cluster:memory_usage:total
        expr: sum(container_memory_working_set_bytes) by (cluster)

      - record: cluster:node_count:total
        expr: count(up{job="node-exporter"}) by (cluster)
```

### Alerting Rules 파일 (클러스터)

```yaml
# rules/alerting-rules-cluster.yaml
groups:
  - name: cluster_health
    interval: 1m
    rules:
      - alert: ClusterDown
        expr: up{job="prometheus"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "클러스터 다운"

      - alert: HighCPUUsage
        expr: cluster:cpu_usage:total > 0.8
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "클러스터 CPU 사용률 높음"
```

### Alerting Rules 파일 (Thanos)

```yaml
# rules/alerting-rules-thanos.yaml
groups:
  - name: thanos_components
    interval: 1m
    rules:
      - alert: ThanosReceiverDown
        expr: up{job="thanos-receiver"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Thanos Receiver 다운"

      - alert: ThanosQueryDown
        expr: up{job="thanos-query"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Thanos Query 다운"
```

### Values 패치 파일

```yaml
# values.yaml
ruler:
  enabled: true

  alertmanagers:
    - http://alertmanager.monitoring.svc.cluster.local:9093

  queries:
    - dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local

  # ConfigMap 참조
  existingConfigmap: thanos-ruler-rules

  configReloader:
    enabled: true
```

---

## 검증 및 테스트

### Rule 문법 검증

```bash
# promtool 다운로드
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xvf prometheus-2.45.0.linux-amd64.tar.gz
cd prometheus-2.45.0.linux-amd64

# Rule 파일 검증
./promtool check rules rules.yaml

# 출력 예시:
# Checking rules.yaml
#   SUCCESS: 5 rules found
```

### Rule 테스트

```bash
# 특정 시간대의 데이터로 Rule 테스트
./promtool test rules test.yaml
```

test.yaml 예시:

```yaml
rule_files:
  - rules.yaml

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      - series: 'up{job="prometheus", cluster="cluster-01"}'
        values: '0+0x10'  # 10분간 0

    alert_rule_test:
      - eval_time: 5m
        alertname: ClusterDown
        exp_alerts:
          - exp_labels:
              severity: critical
              cluster: cluster-01
            exp_annotations:
              summary: "클러스터 cluster-01가 다운되었습니다"
```

### 배포된 Rule 확인

```bash
# Ruler Pod에서 현재 로드된 Rule 확인
kubectl exec -it thanos-ruler-0 -n monitoring -- \
  wget -qO- http://localhost:10902/api/v1/rules

# Rule 평가 상태 확인
kubectl exec -it thanos-ruler-0 -n monitoring -- \
  wget -qO- http://localhost:10902/api/v1/alerts
```

### Rule 변경 후 리로드

```bash
# ConfigMap 업데이트
kubectl apply -f rules-configmap.yaml

# configReloader가 활성화되어 있으면 자동 리로드
# 수동 리로드가 필요한 경우:
kubectl rollout restart statefulset/thanos-ruler -n monitoring

# 리로드 확인
kubectl logs -f thanos-ruler-0 -n monitoring | grep -i "reload"
```

---

## 필수 Ingress 설정

멀티클러스터 환경에서 **Prometheus Agent + Receiver** 패턴을 사용할 때 필요한 Ingress 설정:

### 중앙 클러스터 필수 Ingress

| 컴포넌트 | Ingress 필요 | 우선순위 | 이유 |
|---------|-------------|---------|------|
| **Thanos Receiver** | ✅ 필수 | 최우선 | 엣지 클러스터 Remote Write 엔드포인트 |
| **Thanos Query** | ✅ 필수 | 필수 | Grafana 데이터소스, 통합 쿼리 |
| **Grafana** | ✅ 필수 | 필수 | 사용자 접근 UI |
| **Query Frontend** | ⚠️ 선택 | 권장 | 쿼리 캐싱 및 성능 최적화 |
| **Bucket Web** | ⚠️ 선택 | 선택 | S3 블록 상태 디버깅 |
| **Ruler** | ❌ 불필요 | - | 내부 통신만 사용 |
| **Compactor** | ❌ 불필요 | - | S3와만 통신 |
| **Store Gateway** | ❌ 불필요 | - | 내부 gRPC 통신 |

### Ingress 설정 예시

```yaml
# values.yaml (중앙 클러스터)

# 1. Thanos Receiver (필수)
receive:
  enabled: true
  ingress:
    enabled: true
    hostname: thanos-receiver.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
    tls: true

# 2. Thanos Query (필수)
query:
  enabled: true
  ingress:
    enabled: true
    hostname: thanos-query.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls: true

# 3. Grafana (필수)
grafana:
  enabled: true
  ingress:
    enabled: true
    hostname: grafana.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls: true

# 4. Ruler (Ingress 불필요 - 내부 통신만)
ruler:
  enabled: true
  ingress:
    enabled: false  # 외부 접근 불필요
```

### 엣지 클러스터 Prometheus Agent 설정

```yaml
# prometheus-agent-config.yaml (엣지 클러스터)
global:
  external_labels:
    cluster: edge-01
    region: us-west
    environment: production

remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive
    queue_config:
      capacity: 10000
      max_shards: 50
      max_samples_per_send: 5000

    # 보안 설정
    tls_config:
      insecure_skip_verify: false

    # Basic Auth (선택)
    # basic_auth:
    #   username: edge-01
    #   password: secret
```

---

## 모범 사례

### 1. Rule 그룹 분리

```yaml
# 목적별로 그룹 분리
groups:
  - name: recording_rules_cluster    # Recording Rules: 클러스터
  - name: recording_rules_app        # Recording Rules: 애플리케이션
  - name: alerting_rules_critical    # Alerting Rules: Critical
  - name: alerting_rules_warning     # Alerting Rules: Warning
  - name: alerting_rules_info        # Alerting Rules: Info
```

### 2. 라벨 일관성 유지

```yaml
# 모든 Alert에 공통 라벨 사용
labels:
  severity: critical | warning | info
  team: platform | dev | ops
  component: thanos | prometheus | kubernetes
  environment: production | staging | development
```

### 3. Annotation 템플릿 활용

```yaml
annotations:
  summary: "간단한 요약"
  description: "상세한 설명 (값: {{ $value }})"
  runbook_url: "https://wiki.example.com/runbook/{{ $labels.alertname }}"
  dashboard_url: "https://grafana.example.com/d/dashboard?var-cluster={{ $labels.cluster }}"
```

### 4. For 절 적절히 사용

```yaml
# 일시적인 장애 무시
- alert: TransientError
  expr: error_rate > 0.1
  for: 5m  # 5분 동안 지속되어야 알림

# 즉시 알림 필요
- alert: CriticalError
  expr: critical_error > 0
  for: 0s  # 즉시 알림
```

### 5. Recording Rules 활용

```yaml
# 복잡한 쿼리는 Recording Rule로 사전 계산
- record: cluster:cpu_usage:total
  expr: sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)

# Alert에서는 간단하게 사용
- alert: HighCPU
  expr: cluster:cpu_usage:total > 0.8
```

---

## 요약

| 항목 | 내용 |
|------|------|
| **Recording Rules** | 자주 사용하는 쿼리를 사전 계산하여 저장 |
| **Alerting Rules** | 조건 만족 시 Alertmanager로 알림 전송 |
| **멀티클러스터** | `cluster` 레이블로 클러스터별 규칙 작성 |
| **관리 방법** | ConfigMap + Kustomize 사용 권장 |
| **검증** | `promtool check rules` 사용 |
| **리로드** | configReloader 활성화 또는 수동 재시작 |
| **Ingress** | Ruler는 Ingress 불필요 (내부 통신만) |

**핵심**: 멀티클러스터 환경에서는 **클러스터별 집계** Recording Rule과 **클러스터 상태 모니터링** Alerting Rule이 가장 중요합니다!
