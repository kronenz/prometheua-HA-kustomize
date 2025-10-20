# PromQL 쿼리 예제

## 📋 개요

자주 사용하는 PromQL 쿼리 패턴과 실전 예제 모음입니다.

---

## 1️⃣ Remote Write 쿼리

### 성공률 및 처리량

```promql
# Remote Write 성공률 (%)
100 * rate(prometheus_remote_storage_succeeded_samples_total[5m])
/
(rate(prometheus_remote_storage_succeeded_samples_total[5m])
 + rate(prometheus_remote_storage_failed_samples_total[5m]))

# 클러스터별 Remote Write 처리량 (samples/s)
sum(rate(prometheus_remote_storage_succeeded_samples_total[5m])) by (cluster)

# 시간대별 Remote Write 패턴 (24시간)
sum(rate(prometheus_remote_storage_succeeded_samples_total[5m])) by (cluster)
```

### Queue 모니터링

```promql
# Queue 길이 (클러스터별)
prometheus_remote_storage_queue_length

# Queue 사용률 (%)
100 * prometheus_remote_storage_queue_length
/ prometheus_remote_storage_queue_capacity

# Queue 가득 찬 클러스터
prometheus_remote_storage_queue_length
/ prometheus_remote_storage_queue_capacity
> 0.8
```

### Remote Write 지연

```promql
# P50, P90, P99 지연 (초)
histogram_quantile(0.50,
  rate(prometheus_remote_storage_send_duration_seconds_bucket[5m])
)

histogram_quantile(0.90,
  rate(prometheus_remote_storage_send_duration_seconds_bucket[5m])
)

histogram_quantile(0.99,
  rate(prometheus_remote_storage_send_duration_seconds_bucket[5m])
)

# 평균 지연
rate(prometheus_remote_storage_send_duration_seconds_sum[5m])
/
rate(prometheus_remote_storage_send_duration_seconds_count[5m])

# 클러스터별 P99 지연
histogram_quantile(0.99,
  sum(rate(prometheus_remote_storage_send_duration_seconds_bucket[5m])) by (cluster, le)
)
```

---

## 2️⃣ Thanos Receiver 쿼리

### 수신 메트릭

```promql
# Receiver 수신 속도 (requests/s)
sum(rate(thanos_receive_write_requests_total[5m])) by (instance)

# Receiver 수신 샘플 속도 (samples/s)
sum(rate(thanos_receive_write_timeseries_total[5m])) by (instance)

# Receiver별 부하 분산 확인
sum(rate(thanos_receive_write_timeseries_total[5m])) by (pod)

# Tenant별 수신 샘플
sum(rate(thanos_receive_write_timeseries_total[5m])) by (tenant)
```

### Replication 모니터링

```promql
# Replication 성공률 (%)
100 * sum(rate(thanos_receive_replication_requests_total{result="success"}[5m]))
/
sum(rate(thanos_receive_replication_requests_total[5m]))

# Replication 실패 (requests/s)
sum(rate(thanos_receive_replication_requests_total{result="error"}[5m])) by (instance)

# Replication Factor 충족 여부
thanos_receive_hashring_nodes{state="active"}
>= thanos_receive_replication_factor
```

### TSDB Stats

```promql
# TSDB Head Series (총합)
sum(thanos_receive_head_series) by (instance)

# TSDB Head Chunks
sum(thanos_receive_head_chunks) by (instance)

# TSDB Head Series 증가율 (series/min)
rate(thanos_receive_head_series[1m]) * 60

# TSDB Storage Size (GiB)
sum(prometheus_tsdb_storage_blocks_bytes{job="thanos-receive"}) by (instance) / 1024 / 1024 / 1024
```

---

## 3️⃣ 리소스 사용량 쿼리

### CPU

```promql
# Agent CPU 사용량 (cores)
sum(rate(container_cpu_usage_seconds_total{pod=~"prometheus-agent.*"}[5m])) by (cluster, pod)

# Receiver CPU 사용량 (cores)
sum(rate(container_cpu_usage_seconds_total{pod=~"thanos-receive.*"}[5m])) by (pod)

# CPU 사용률 (%)
100 * sum(rate(container_cpu_usage_seconds_total{pod=~"thanos-receive.*"}[5m])) by (pod)
/
sum(container_spec_cpu_quota{pod=~"thanos-receive.*"}) by (pod)
/ 100000

# Top 5 CPU 사용 Pod
topk(5,
  sum(rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m])) by (pod)
)
```

### Memory

```promql
# Agent 메모리 사용량 (MiB)
sum(container_memory_usage_bytes{pod=~"prometheus-agent.*"}) by (cluster, pod) / 1024 / 1024

# Receiver 메모리 사용량 (GiB)
sum(container_memory_usage_bytes{pod=~"thanos-receive.*"}) by (pod) / 1024 / 1024 / 1024

# 메모리 사용률 (%)
100 * sum(container_memory_usage_bytes{pod=~"thanos-receive.*"}) by (pod)
/
sum(container_spec_memory_limit_bytes{pod=~"thanos-receive.*"}) by (pod)

# Top 5 메모리 사용 Pod
topk(5,
  sum(container_memory_usage_bytes{namespace="monitoring"}) by (pod) / 1024 / 1024
)

# OOM Risk (메모리 사용률 > 90%)
(container_memory_usage_bytes{namespace="monitoring"}
 / container_spec_memory_limit_bytes{namespace="monitoring"})
> 0.9
```

### 네트워크

```promql
# Remote Write 네트워크 송신 (MB/s)
sum(rate(container_network_transmit_bytes_total{pod=~"prometheus-agent.*"}[5m])) by (cluster, pod) / 1024 / 1024

# Receiver 네트워크 수신 (MB/s)
sum(rate(container_network_receive_bytes_total{pod=~"thanos-receive.*"}[5m])) by (pod) / 1024 / 1024

# 총 네트워크 트래픽 (MB/s)
sum(rate(container_network_transmit_bytes_total{namespace="monitoring"}[5m])) / 1024 / 1024
+
sum(rate(container_network_receive_bytes_total{namespace="monitoring"}[5m])) / 1024 / 1024

# 클러스터별 네트워크 송신
sum(rate(container_network_transmit_bytes_total{namespace="monitoring"}[5m])) by (cluster) / 1024 / 1024
```

### 디스크

```promql
# 디스크 사용률 (%)
100 * (node_filesystem_size_bytes{mountpoint="/data"}
       - node_filesystem_avail_bytes{mountpoint="/data"})
/
node_filesystem_size_bytes{mountpoint="/data"}

# 디스크 가용 공간 (GiB)
node_filesystem_avail_bytes{mountpoint="/data"} / 1024 / 1024 / 1024

# 디스크 사용률 > 85% (경고)
(1 - (node_filesystem_avail_bytes{mountpoint="/data"}
     / node_filesystem_size_bytes{mountpoint="/data"}))
> 0.85

# 디스크 Full 예측 (24시간)
predict_linear(node_filesystem_avail_bytes{mountpoint="/data"}[6h], 24 * 3600) < 0

# 디스크 I/O 사용량 (MB/s)
rate(node_disk_written_bytes_total[5m]) / 1024 / 1024
```

---

## 4️⃣ 클러스터 집계 쿼리

### 클러스터 요약

```promql
# 클러스터별 타겟 수
count(up) by (cluster)

# 클러스터별 Up 타겟 수
count(up == 1) by (cluster)

# 클러스터별 Down 타겟 수
count(up == 0) by (cluster)

# 클러스터별 Down 비율
count(up == 0) by (cluster)
/
count(up) by (cluster)

# 클러스터별 총 샘플 수
sum(scrape_samples_scraped) by (cluster)
```

### 멀티 클러스터 비교

```promql
# 클러스터별 CPU 사용량 비교
sum(rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m])) by (cluster)

# 클러스터별 메모리 사용량 비교 (GiB)
sum(container_memory_usage_bytes{namespace="monitoring"}) by (cluster) / 1024 / 1024 / 1024

# 클러스터별 Remote Write 성공률
sum(rate(prometheus_remote_storage_succeeded_samples_total[5m])) by (cluster)
/
(sum(rate(prometheus_remote_storage_succeeded_samples_total[5m])) by (cluster)
 + sum(rate(prometheus_remote_storage_failed_samples_total[5m])) by (cluster))
```

### 전체 클러스터 통계

```promql
# 총 클러스터 수
count(count(up) by (cluster))

# 총 타겟 수
count(up)

# 총 Up 타겟
count(up == 1)

# 전체 샘플 처리량 (samples/s)
sum(rate(prometheus_remote_storage_succeeded_samples_total[5m]))

# 전체 CPU 사용량 (cores)
sum(rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m]))

# 전체 메모리 사용량 (GiB)
sum(container_memory_usage_bytes{namespace="monitoring"}) / 1024 / 1024 / 1024
```

---

## 5️⃣ Scrape 모니터링 쿼리

### Scrape 성능

```promql
# Scrape Duration (초)
scrape_duration_seconds

# P99 Scrape Duration
histogram_quantile(0.99,
  rate(scrape_duration_seconds_bucket[5m])
)

# Scrape Timeout 발생
scrape_duration_seconds > scrape_timeout_seconds

# Job별 평균 Scrape Duration
avg(scrape_duration_seconds) by (job)

# Scrape 샘플 수
scrape_samples_scraped

# Job별 총 샘플 수
sum(scrape_samples_scraped) by (job)
```

### Scrape 상태

```promql
# Up 상태
up

# Down 타겟 목록
up == 0

# Job별 Up/Down 비율
sum(up) by (job)
/
count(up) by (job)

# Scrape 실패 (최근 5분)
changes(up[5m]) > 0

# Scrape 빈도 (scrapes/min)
rate(scrape_samples_scraped[1m]) * 60
/
scrape_samples_scraped
```

---

## 6️⃣ Tenant 분리 쿼리 (Cluster-02)

### Tenant별 메트릭

```promql
# Tenant A 메트릭만
up{cluster="cluster-02", tenant="tenant-a"}

# Tenant B 메트릭만
up{cluster="cluster-02", tenant="tenant-b"}

# Tenant별 타겟 수
count(up{cluster="cluster-02"}) by (tenant)

# Tenant별 샘플 처리량
sum(rate(thanos_receive_write_timeseries_total{cluster="cluster-02"}[5m])) by (tenant)

# Tenant별 CPU 사용량
sum(rate(container_cpu_usage_seconds_total{namespace=~"monitoring-tenant-.*"}[5m])) by (namespace)
```

### Tenant 비교

```promql
# Tenant별 Agent 메모리
sum(container_memory_usage_bytes{pod=~"prometheus-agent-tenant-.*"}) by (pod) / 1024 / 1024

# Tenant별 Remote Write 성공률
sum(rate(prometheus_remote_storage_succeeded_samples_total{pod=~"prometheus-agent-tenant-.*"}[5m])) by (pod)
/
(sum(rate(prometheus_remote_storage_succeeded_samples_total{pod=~"prometheus-agent-tenant-.*"}[5m])) by (pod)
 + sum(rate(prometheus_remote_storage_failed_samples_total{pod=~"prometheus-agent-tenant-.*"}[5m])) by (pod))
```

---

## 7️⃣ 고급 쿼리 패턴

### Rate vs Increase

```promql
# Rate: 초당 증가율 (samples/s)
rate(prometheus_remote_storage_succeeded_samples_total[5m])

# Increase: 기간 내 총 증가량
increase(prometheus_remote_storage_succeeded_samples_total[5m])

# irate: 즉각 반응 (마지막 2개 샘플)
irate(prometheus_remote_storage_succeeded_samples_total[5m])
```

### Aggregation

```promql
# Sum: 합계
sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)

# Avg: 평균
avg(container_memory_usage_bytes) by (cluster)

# Max/Min: 최대/최소
max(prometheus_remote_storage_queue_length) by (cluster)
min(node_filesystem_avail_bytes) by (instance)

# Count: 개수
count(up == 1) by (cluster)

# TopK: 상위 K개
topk(5, rate(container_cpu_usage_seconds_total[5m]))

# BottomK: 하위 K개
bottomk(3, node_filesystem_avail_bytes)
```

### 시간 함수

```promql
# Offset: 1시간 전 값
up offset 1h

# Comparison: 현재 vs 1시간 전
up / (up offset 1h)

# Predict Linear: 선형 예측 (24시간 후)
predict_linear(node_filesystem_avail_bytes[6h], 24 * 3600)

# Deriv: 미분 (변화율)
deriv(node_filesystem_avail_bytes[1h])

# Delta: 기간 내 변화량
delta(node_filesystem_avail_bytes[1h])
```

### Label 연산

```promql
# Label 필터
up{cluster="cluster-03", job="node-exporter"}

# Regex 매치
up{pod=~"prometheus-agent.*"}

# Regex 제외
up{job!~"kube-.*"}

# 다중 값
up{cluster=~"cluster-03|cluster-04"}

# Label 결합
label_replace(up, "new_label", "$1", "instance", "(.*):.*")
```

---

## 8️⃣ 실전 대시보드 쿼리

### Overview 패널

```promql
# 총 클러스터 수 (Stat)
count(count(up) by (cluster))

# 클러스터별 상태 (Table)
count(up) by (cluster)

# Remote Write 성공률 (Gauge)
avg(
  rate(prometheus_remote_storage_succeeded_samples_total[5m])
  /
  (rate(prometheus_remote_storage_succeeded_samples_total[5m])
   + rate(prometheus_remote_storage_failed_samples_total[5m]))
)

# 총 샘플 처리량 (Graph)
sum(rate(prometheus_remote_storage_succeeded_samples_total[5m]))
```

### Receiver 대시보드

```promql
# Receiver 수신 속도 (Graph)
sum(rate(thanos_receive_write_timeseries_total[5m])) by (pod)

# Replication 성공률 (Gauge)
100 * sum(rate(thanos_receive_replication_requests_total{result="success"}[5m]))
/
sum(rate(thanos_receive_replication_requests_total[5m]))

# Receiver 메모리 (Graph)
sum(container_memory_usage_bytes{pod=~"thanos-receive.*"}) by (pod) / 1024 / 1024 / 1024

# TSDB Head Series (Graph)
sum(thanos_receive_head_series) by (pod)
```

---

## 🎯 쿼리 최적화 팁

### 1. 레이블 필터링 우선
```promql
# Bad: 모든 메트릭 조회 후 필터
rate(container_cpu_usage_seconds_total[5m]){namespace="monitoring"}

# Good: 먼저 레이블 필터
rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m])
```

### 2. Aggregation 레이블 최소화
```promql
# Bad: 불필요한 레이블 유지
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod, container, namespace, node)

# Good: 필요한 레이블만
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)
```

### 3. 긴 범위 쿼리 대신 Recording Rule
```promql
# Recording Rule 생성
- record: job:remote_write_success_rate:5m
  expr: |
    rate(prometheus_remote_storage_succeeded_samples_total[5m])
    /
    (rate(prometheus_remote_storage_succeeded_samples_total[5m])
     + rate(prometheus_remote_storage_failed_samples_total[5m]))

# 대시보드에서 사용
job:remote_write_success_rate:5m
```

---

## 🔗 관련 문서

- **핵심 메트릭** → [핵심-메트릭.md](./핵심-메트릭.md)
- **Grafana 대시보드** → [Grafana-대시보드.md](./Grafana-대시보드.md)
- **빠른 참조** → [../03-운영-가이드/빠른-참조.md](../03-운영-가이드/빠른-참조.md)

---

**최종 업데이트**: 2025-10-20
