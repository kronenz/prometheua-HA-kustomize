# Agent 관리

## 📋 개요

Prometheus Agent Mode의 일상 운영, 모니터링, 문제 해결 방법을 다룹니다.

---

## 🎯 Agent 운영 목표

- **가용성**: 99.9% Uptime (월 43분 다운타임 허용)
- **Remote Write 성공률**: 99.5% 이상
- **WAL 크기**: 50Gi PVC의 80% 이하 유지
- **메모리 사용량**: 512Mi 미만
- **응답 시간**: Remote Write 지연 < 1초 (p99)

---

## 1️⃣ Agent 상태 모니터링

### Pod 상태 확인

```bash
# Agent Pod 목록
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# 출력:
# NAME                                READY   STATUS    RESTARTS   AGE
# prometheus-agent-prometheus-agent-0   2/2     Running   0          5d

# 상세 정보
kubectl describe pod -n monitoring prometheus-agent-prometheus-agent-0

# 리소스 사용량
kubectl top pod -n monitoring prometheus-agent-prometheus-agent-0

# 출력:
# NAME                                CPU(cores)   MEMORY(bytes)
# prometheus-agent-prometheus-agent-0   250m         320Mi
```

### Health Check

```bash
# Agent HTTP API (/-/healthy)
kubectl port-forward -n monitoring prometheus-agent-prometheus-agent-0 9090:9090 &

curl http://localhost:9090/-/healthy

# 출력:
# Prometheus is Healthy.

# Ready Check
curl http://localhost:9090/-/ready

# 출력:
# Prometheus is Ready.
```

### PromQL로 Agent 상태 확인

```promql
# Agent Up 상태
up{job="prometheus-agent", cluster="cluster-03"}

# 출력: 1 (정상)

# Agent 메모리 사용량
process_resident_memory_bytes{job="prometheus-agent", cluster="cluster-03"} / 1024 / 1024

# 출력: 320 (MB)

# Agent CPU 사용량
rate(process_cpu_seconds_total{job="prometheus-agent"}[5m])

# 출력: 0.25 (0.25 cores)

# Scrape 성공률
rate(prometheus_tsdb_head_samples_appended_total[5m])

# Scrape 실패
rate(prometheus_target_scrapes_exceeded_sample_limit_total[5m])
```

---

## 2️⃣ WAL 관리

### WAL 크기 확인

```bash
# Agent Pod 접속
kubectl exec -it -n monitoring prometheus-agent-prometheus-agent-0 -- sh

# WAL 디렉토리 확인
du -sh /prometheus/wal/

# 출력:
# 12G    /prometheus/wal/

# WAL 세그먼트 수
ls -1 /prometheus/wal/ | wc -l

# 출력: 48 (세그먼트)

# 최근 WAL 파일
ls -lt /prometheus/wal/ | head -10
```

### WAL PVC 용량 확인

```bash
# PVC 목록
kubectl get pvc -n monitoring

# 출력:
# NAME                                STATUS   CAPACITY   STORAGECLASS
# prometheus-agent-prometheus-agent-0  Bound    50Gi       longhorn

# PVC 사용량 (df)
kubectl exec -it -n monitoring prometheus-agent-prometheus-agent-0 -- df -h /prometheus

# 출력:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/longhorn   50G   15G  35G   30%  /prometheus
```

### WAL Rotation

```yaml
# Prometheus Agent WAL 압축 설정
prometheus:
  prometheusSpec:
    # WAL 압축 활성화
    walCompression: true

    # Retention (WAL 크기 제한, Agent Mode에서는 무시됨)
    # Agent는 Remote Write 완료 후 WAL 자동 삭제
```

### WAL 문제 해결

```bash
# WAL Corruption 확인
kubectl logs -n monitoring prometheus-agent-prometheus-agent-0 | grep "WAL corruption"

# 로그 예시 (오류 시):
# level=error ts=... msg="WAL corruption detected" segment=42

# WAL 복구 (데이터 손실 가능)
kubectl exec -it -n monitoring prometheus-agent-prometheus-agent-0 -- \
  /bin/prometheus --storage.tsdb.path=/prometheus --wal-truncate

# 또는 Pod 재시작 (자동 복구)
kubectl delete pod -n monitoring prometheus-agent-prometheus-agent-0
```

---

## 3️⃣ Remote Write 큐 모니터링

### Queue Metrics

```promql
# Remote Write 큐 길이
prometheus_remote_storage_queue_length{cluster="cluster-03"}

# 정상: 0-100
# 주의: 100-1000
# 경고: 1000+

# 큐 용량
prometheus_remote_storage_queue_capacity{cluster="cluster-03"}

# 출력: 20000 (설정된 capacity)

# Shards 수
prometheus_remote_storage_shards{cluster="cluster-03"}

# 출력: 50 (동적 조정)

# 전송 중인 샘플
prometheus_remote_storage_pending_samples{cluster="cluster-03"}

# Remote Write 속도 (samples/s)
rate(prometheus_remote_storage_sent_samples_total{cluster="cluster-03"}[5m])

# 출력: 8000 (samples/s)
```

### Remote Write 성공/실패

```promql
# 성공 샘플
rate(prometheus_remote_storage_succeeded_samples_total{cluster="cluster-03"}[5m])

# 실패 샘플
rate(prometheus_remote_storage_failed_samples_total{cluster="cluster-03"}[5m])

# 성공률
rate(prometheus_remote_storage_succeeded_samples_total[5m])
/
(rate(prometheus_remote_storage_succeeded_samples_total[5m])
 + rate(prometheus_remote_storage_failed_samples_total[5m]))

# 출력: 0.995 (99.5%, 정상)

# 재시도 횟수
rate(prometheus_remote_storage_retried_samples_total[5m])

# Drop된 샘플
rate(prometheus_remote_storage_dropped_samples_total[5m])
```

### Remote Write 지연 시간

```promql
# Remote Write 지연 (초)
histogram_quantile(0.99,
  rate(prometheus_remote_storage_send_duration_seconds_bucket{cluster="cluster-03"}[5m])
)

# 목표: < 1s (p99)

# 평균 지연
rate(prometheus_remote_storage_send_duration_seconds_sum[5m])
/
rate(prometheus_remote_storage_send_duration_seconds_count[5m])

# 목표: < 0.5s (avg)
```

---

## 4️⃣ Scrape 타겟 관리

### 타겟 상태 확인

```bash
# Targets API
curl http://localhost:9090/api/v1/targets | jq .

# 출력:
# {
#   "status": "success",
#   "data": {
#     "activeTargets": [
#       {
#         "discoveredLabels": {...},
#         "labels": {"job": "node-exporter", "instance": "10.244.0.5:9100"},
#         "scrapePool": "monitoring/prometheus-agent/0",
#         "scrapeUrl": "http://10.244.0.5:9100/metrics",
#         "lastError": "",
#         "lastScrape": "2025-10-20T10:15:00Z",
#         "lastScrapeDuration": 0.012,
#         "health": "up"
#       }
#     ]
#   }
# }
```

### PromQL로 Scrape 메트릭

```promql
# Up 상태 타겟 수
count(up == 1) by (cluster, job)

# 출력:
# {cluster="cluster-03", job="node-exporter"} 1
# {cluster="cluster-03", job="kube-state-metrics"} 1

# Scrape Duration
scrape_duration_seconds{cluster="cluster-03"}

# Scrape 샘플 수
scrape_samples_scraped{cluster="cluster-03"}

# Scrape 실패
up == 0
```

### ServiceMonitor/PodMonitor 관리

```bash
# ServiceMonitor 목록
kubectl get servicemonitor -n monitoring

# 출력:
# NAME                AGE
# node-exporter       5d
# kube-state-metrics  5d

# ServiceMonitor 상세
kubectl describe servicemonitor -n monitoring node-exporter

# PodMonitor 목록
kubectl get podmonitor -n monitoring
```

---

## 5️⃣ Agent 재시작 및 복구

### 정상 재시작 (Graceful)

```bash
# StatefulSet Rollout 재시작
kubectl rollout restart statefulset/prometheus-agent -n monitoring

# Pod 상태 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -w

# 출력:
# prometheus-agent-0   2/2   Terminating
# prometheus-agent-0   0/2   Pending
# prometheus-agent-0   2/2   Running  (새 Pod)

# 재시작 완료 대기
kubectl rollout status statefulset/prometheus-agent -n monitoring

# 출력:
# statefulset rolling update complete
```

### 긴급 재시작 (Forced)

```bash
# Pod 강제 삭제
kubectl delete pod -n monitoring prometheus-agent-0 --force --grace-period=0

# StatefulSet이 자동으로 새 Pod 생성
kubectl get pods -n monitoring -w
```

### 재시작 후 검증

```bash
# 1. Pod 상태
kubectl get pods -n monitoring prometheus-agent-0

# 2. Remote Write 연결
kubectl logs -n monitoring prometheus-agent-0 | grep "remote write"

# 로그 예시:
# level=info msg="Starting remote storage" queue=thanos-receiver

# 3. 메트릭 쿼리
curl "http://localhost:9090/api/v1/query?query=up"

# 4. WAL 복구 확인
kubectl exec -it -n monitoring prometheus-agent-0 -- ls -lh /prometheus/wal/
```

---

## 6️⃣ 로그 분석

### 주요 로그 패턴

```bash
# 최근 로그 (100줄)
kubectl logs -n monitoring prometheus-agent-0 --tail=100

# Remote Write 관련 로그
kubectl logs -n monitoring prometheus-agent-0 | grep "remote"

# 로그 예시:
# level=info ts=... msg="Starting remote storage" queue=thanos-receiver
# level=info ts=... msg="remote write succeeded" samples=1250

# 에러 로그만
kubectl logs -n monitoring prometheus-agent-0 | grep "level=error"

# WAL 관련 로그
kubectl logs -n monitoring prometheus-agent-0 | grep "WAL"

# 로그 예시:
# level=info msg="WAL checkpoint complete" duration=1.5s
```

### 로그 Export (Fluent-Bit)

```yaml
# Fluent-Bit DaemonSet (Pod 로그 수집)
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: logging
data:
  fluent-bit.conf: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/prometheus-agent*.log
        Parser            docker
        Tag               kube.prometheus-agent

    [FILTER]
        Name              kubernetes
        Match             kube.*
        Kube_Tag_Prefix   kube.

    [OUTPUT]
        Name              opensearch
        Match             kube.prometheus-agent
        Host              opensearch.logging.svc.cluster.local
        Port              9200
        Index             prometheus-agent-logs
```

---

## 7️⃣ 성능 튜닝

### Scrape 최적화

```yaml
# Scrape Interval 조정
prometheus:
  prometheusSpec:
    # 기본 30초
    scrapeInterval: 30s

    # Timeout
    scrapeTimeout: 10s

    # Evaluation Interval (Agent Mode에서는 무시)
    evaluationInterval: 30s
```

### Remote Write Queue 최적화

```yaml
# Remote Write Queue 설정
prometheus:
  prometheusSpec:
    remoteWrite:
      - url: http://thanos-receive-lb:19291/api/v1/receive
        queueConfig:
          # 큐 용량 (default: 2500)
          capacity: 20000

          # 최대 Shards (default: 5)
          maxShards: 100

          # 최소 Shards
          minShards: 10

          # Shard당 최대 샘플
          maxSamplesPerSend: 10000

          # 배치 전송 마감 시간
          batchSendDeadline: 10s

          # Backoff
          minBackoff: 30ms
          maxBackoff: 5s
```

### 리소스 Right-Sizing

```yaml
# Agent 리소스 조정
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 200m      # 실제 사용량 기반 조정
        memory: 256Mi

      limits:
        cpu: 500m
        memory: 512Mi
```

---

## 8️⃣ Alert Rules

### Prometheus Agent Alerts

```yaml
# PrometheusRule CRD
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: prometheus-agent-alerts
  namespace: monitoring
spec:
  groups:
  - name: prometheus-agent
    interval: 30s
    rules:
    # Agent Down
    - alert: PrometheusAgentDown
      expr: up{job="prometheus-agent"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Prometheus Agent {{ $labels.cluster }} is down"
        description: "Agent has been down for more than 5 minutes"

    # Remote Write 실패
    - alert: RemoteWriteFailing
      expr: |
        rate(prometheus_remote_storage_failed_samples_total[5m])
        / rate(prometheus_remote_storage_sent_samples_total[5m])
        > 0.01
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Remote Write failure rate > 1%"
        description: "Cluster {{ $labels.cluster }} Remote Write failing"

    # Queue 길이 증가
    - alert: RemoteWriteQueueHigh
      expr: prometheus_remote_storage_queue_length > 5000
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "Remote Write queue length > 5000"
        description: "Queue backlog in cluster {{ $labels.cluster }}"

    # WAL Corruption
    - alert: WALCorruption
      expr: increase(prometheus_tsdb_wal_corruptions_total[1h]) > 0
      labels:
        severity: critical
      annotations:
        summary: "WAL corruption detected"
        description: "Cluster {{ $labels.cluster }} WAL corrupted"

    # 높은 메모리 사용
    - alert: AgentHighMemory
      expr: |
        container_memory_usage_bytes{pod=~"prometheus-agent.*"}
        / container_spec_memory_limit_bytes{pod=~"prometheus-agent.*"}
        > 0.9
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Agent memory usage > 90%"
```

---

## 9️⃣ 트러블슈팅

### 문제: Remote Write 실패

**증상**:
```promql
rate(prometheus_remote_storage_failed_samples_total[5m]) > 0
```

**원인**:
1. Receiver 다운
2. 네트워크 문제
3. Queue Overflow

**해결**:
```bash
# 1. Receiver 상태 확인
kubectl get pods -n monitoring -l app=thanos-receive

# 2. 네트워크 테스트
kubectl exec -it -n monitoring prometheus-agent-0 -- \
  curl -v http://thanos-receive-lb:19291/-/ready

# 3. Queue 확인
# PromQL: prometheus_remote_storage_queue_length

# 4. Agent 재시작
kubectl rollout restart statefulset/prometheus-agent -n monitoring
```

### 문제: WAL 크기 급증

**증상**:
```bash
du -sh /prometheus/wal/
# 출력: 45G (PVC 50G의 90%)
```

**원인**:
- Remote Write 실패로 WAL 쌓임
- Receiver 다운

**해결**:
```bash
# 1. Remote Write 상태 확인
kubectl logs -n monitoring prometheus-agent-0 | grep "remote write"

# 2. Receiver 복구
kubectl rollout restart statefulset/thanos-receive -n monitoring

# 3. WAL 정리 (최후 수단, 데이터 손실)
kubectl delete pod -n monitoring prometheus-agent-0
```

### 문제: 높은 메모리 사용

**증상**:
```bash
kubectl top pod prometheus-agent-0 -n monitoring
# 출력: 480Mi / 512Mi (94%)
```

**원인**:
- 높은 Cardinality 메트릭
- Remote Write Queue 누적

**해결**:
```yaml
# 1. 메트릭 필터링 (Drop Rules)
prometheus:
  prometheusSpec:
    remoteWrite:
      - writeRelabelConfigs:
          - sourceLabels: [__name__]
            regex: 'go_gc_.*|go_memstats_.*'
            action: drop

# 2. 리소스 증가
resources:
  limits:
    memory: 1Gi
```

---

## 🎯 Agent 운영 체크리스트

### 일일 점검
- [x] Agent Pod Running 상태
- [x] Remote Write 성공률 > 99%
- [x] WAL 크기 < 40Gi
- [x] 메모리 사용량 < 400Mi
- [x] Queue Length < 1000

### 주간 점검
- [x] PVC 용량 확인 (80% 미만)
- [x] 로그 에러 검토
- [x] Scrape 타겟 상태 확인
- [x] Alert Rule 검증

### 월간 점검
- [x] Prometheus 버전 업데이트 확인
- [x] 리소스 Right-Sizing
- [x] WAL Rotation 검증
- [x] 백업 테스트

---

## 🔗 관련 문서

- **Receiver 관리** → [Receiver-관리.md](./Receiver-관리.md)
- **Remote Write 최적화** → [../09-성능-최적화/Remote-Write-최적화.md](../09-성능-최적화/Remote-Write-최적화.md)
- **트러블슈팅** → [일반-트러블슈팅.md](./일반-트러블슈팅.md)

---

**최종 업데이트**: 2025-10-20
