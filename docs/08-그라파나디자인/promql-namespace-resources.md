# 네임스페이스별 자원 사용량 PromQL 쿼리

## 1. CPU 사용량

### 1.1 네임스페이스별 CPU 사용률 (코어 단위)
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
```

### 1.2 네임스페이스별 CPU 사용률 (밀리코어 단위)
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace) * 1000
```

### 1.3 네임스페이스별 CPU Request 대비 사용률 (%)
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
/
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
* 100
```

### 1.4 네임스페이스별 CPU Limit 대비 사용률 (%)
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
/
sum(kube_pod_container_resource_limits{resource="cpu"}) by (namespace)
* 100
```

### 1.5 네임스페이스별 CPU Throttling 비율 (%)
```promql
sum(rate(container_cpu_cfs_throttled_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
/
sum(rate(container_cpu_cfs_periods_total{container!="",container!="POD"}[5m])) by (namespace)
* 100
```

## 2. 메모리 사용량

### 2.1 네임스페이스별 메모리 사용량 (Bytes)
```promql
sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)
```

### 2.2 네임스페이스별 메모리 사용량 (GB)
```promql
sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace) / 1024 / 1024 / 1024
```

### 2.3 네임스페이스별 메모리 Request 대비 사용률 (%)
```promql
sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)
/
sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace)
* 100
```

### 2.4 네임스페이스별 메모리 Limit 대비 사용률 (%)
```promql
sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)
/
sum(kube_pod_container_resource_limits{resource="memory"}) by (namespace)
* 100
```

### 2.5 네임스페이스별 메모리 RSS (Resident Set Size)
```promql
sum(container_memory_rss{container!="",container!="POD"}) by (namespace) / 1024 / 1024 / 1024
```

### 2.6 네임스페이스별 메모리 캐시 사용량
```promql
sum(container_memory_cache{container!="",container!="POD"}) by (namespace) / 1024 / 1024 / 1024
```

## 3. 네트워크 사용량

### 3.1 네임스페이스별 네트워크 수신 속도 (Bytes/s)
```promql
sum(rate(container_network_receive_bytes_total[5m])) by (namespace)
```

### 3.2 네임스페이스별 네트워크 송신 속도 (Bytes/s)
```promql
sum(rate(container_network_transmit_bytes_total[5m])) by (namespace)
```

### 3.3 네임스페이스별 네트워크 수신 속도 (MB/s)
```promql
sum(rate(container_network_receive_bytes_total[5m])) by (namespace) / 1024 / 1024
```

### 3.4 네임스페이스별 네트워크 송신 속도 (MB/s)
```promql
sum(rate(container_network_transmit_bytes_total[5m])) by (namespace) / 1024 / 1024
```

### 3.5 네임스페이스별 네트워크 패킷 수신 속도
```promql
sum(rate(container_network_receive_packets_total[5m])) by (namespace)
```

### 3.6 네임스페이스별 네트워크 패킷 송신 속도
```promql
sum(rate(container_network_transmit_packets_total[5m])) by (namespace)
```

### 3.7 네임스페이스별 네트워크 에러율
```promql
sum(rate(container_network_receive_errors_total[5m])) by (namespace)
+
sum(rate(container_network_transmit_errors_total[5m])) by (namespace)
```

## 4. 스토리지 사용량

### 4.1 네임스페이스별 디스크 읽기 속도 (Bytes/s)
```promql
sum(rate(container_fs_reads_bytes_total{container!="",container!="POD"}[5m])) by (namespace)
```

### 4.2 네임스페이스별 디스크 쓰기 속도 (Bytes/s)
```promql
sum(rate(container_fs_writes_bytes_total{container!="",container!="POD"}[5m])) by (namespace)
```

### 4.3 네임스페이스별 디스크 읽기 속도 (MB/s)
```promql
sum(rate(container_fs_reads_bytes_total{container!="",container!="POD"}[5m])) by (namespace) / 1024 / 1024
```

### 4.4 네임스페이스별 디스크 쓰기 속도 (MB/s)
```promql
sum(rate(container_fs_writes_bytes_total{container!="",container!="POD"}[5m])) by (namespace) / 1024 / 1024
```

### 4.5 네임스페이스별 PVC 사용량 (Bytes)
```promql
sum(kubelet_volume_stats_used_bytes) by (namespace)
```

### 4.6 네임스페이스별 PVC 사용량 (GB)
```promql
sum(kubelet_volume_stats_used_bytes) by (namespace) / 1024 / 1024 / 1024
```

### 4.7 네임스페이스별 PVC 사용률 (%)
```promql
sum(kubelet_volume_stats_used_bytes) by (namespace)
/
sum(kubelet_volume_stats_capacity_bytes) by (namespace)
* 100
```

## 5. Pod 및 컨테이너 수

### 5.1 네임스페이스별 Running Pod 수
```promql
count(kube_pod_status_phase{phase="Running"}) by (namespace)
```

### 5.2 네임스페이스별 전체 Pod 수
```promql
count(kube_pod_info) by (namespace)
```

### 5.3 네임스페이스별 Failed Pod 수
```promql
count(kube_pod_status_phase{phase="Failed"}) by (namespace)
```

### 5.4 네임스페이스별 Pending Pod 수
```promql
count(kube_pod_status_phase{phase="Pending"}) by (namespace)
```

### 5.5 네임스페이스별 컨테이너 수
```promql
count(kube_pod_container_info) by (namespace)
```

### 5.6 네임스페이스별 재시작된 컨테이너 수 (최근 1시간)
```promql
sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace)
```

## 6. 리소스 Request/Limit

### 6.1 네임스페이스별 CPU Request 총합 (코어)
```promql
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
```

### 6.2 네임스페이스별 CPU Limit 총합 (코어)
```promql
sum(kube_pod_container_resource_limits{resource="cpu"}) by (namespace)
```

### 6.3 네임스페이스별 Memory Request 총합 (GB)
```promql
sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace) / 1024 / 1024 / 1024
```

### 6.4 네임스페이스별 Memory Limit 총합 (GB)
```promql
sum(kube_pod_container_resource_limits{resource="memory"}) by (namespace) / 1024 / 1024 / 1024
```

## 7. 비용 관련 메트릭 (Cost Estimation)

### 7.1 네임스페이스별 CPU 비용 추정 (CPU 사용 시간 × 가격)
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m]) * 3600) by (namespace)
# 시간당 CPU 코어 비용을 곱하면 실제 비용 계산 가능
```

### 7.2 네임스페이스별 메모리 비용 추정
```promql
sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace) / 1024 / 1024 / 1024
# GB당 시간당 비용을 곱하면 실제 비용 계산 가능
```

## 8. 복합 쿼리 (Composite Queries)

### 8.1 네임스페이스별 리소스 효율성 점수 (0-100)
```promql
(
  (
    sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
    /
    sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
  )
  +
  (
    sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)
    /
    sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace)
  )
) / 2 * 100
```

### 8.2 네임스페이스별 Over-provisioning 비율 (%)
```promql
(
  (
    sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
    -
    sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
  )
  /
  sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
) * 100
```

### 8.3 네임스페이스별 Health Score (건강도 점수)
```promql
(
  count(kube_pod_status_phase{phase="Running"}) by (namespace)
  /
  count(kube_pod_info) by (namespace)
) * 100
```

## 9. Top N 네임스페이스

### 9.1 CPU 사용량 Top 10 네임스페이스
```promql
topk(10, sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace))
```

### 9.2 메모리 사용량 Top 10 네임스페이스
```promql
topk(10, sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace))
```

### 9.3 네트워크 사용량 Top 10 네임스페이스
```promql
topk(10, sum(rate(container_network_transmit_bytes_total[5m]) + rate(container_network_receive_bytes_total[5m])) by (namespace))
```

### 9.4 디스크 I/O Top 10 네임스페이스
```promql
topk(10, sum(rate(container_fs_reads_bytes_total{container!="",container!="POD"}[5m]) + rate(container_fs_writes_bytes_total{container!="",container!="POD"}[5m])) by (namespace))
```

## 10. 시계열 추세 (Trend)

### 10.1 네임스페이스별 CPU 사용량 증가율 (최근 1시간 대비)
```promql
(
  sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
  -
  sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m] offset 1h)) by (namespace)
)
/
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m] offset 1h)) by (namespace)
* 100
```

### 10.2 네임스페이스별 메모리 사용량 증가율 (최근 1시간 대비)
```promql
(
  sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)
  -
  sum(container_memory_working_set_bytes{container!="",container!="POD"} offset 1h) by (namespace)
)
/
sum(container_memory_working_set_bytes{container!="",container!="POD"} offset 1h) by (namespace)
* 100
```

## 11. 그라파나 패널 구성 예시

### 11.1 Table 패널 (종합 리소스 현황)

**쿼리 구성:**

| Query ID | PromQL | Legend |
|----------|--------|--------|
| A | `sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)` | CPU 사용량 (코어) |
| B | `sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace) / 1024 / 1024 / 1024` | 메모리 사용량 (GB) |
| C | `sum(rate(container_network_transmit_bytes_total[5m]) + rate(container_network_receive_bytes_total[5m])) by (namespace) / 1024 / 1024` | 네트워크 사용량 (MB/s) |
| D | `count(kube_pod_status_phase{phase="Running"}) by (namespace)` | Running Pods |

**Transform:**
- Join by field: `namespace`
- Format: Table

### 11.2 Time Series 패널 (CPU 사용량 추이)

**Query:**
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
```

**Legend:** `{{namespace}}`

### 11.3 Stat 패널 (전체 네임스페이스 수)

**Query:**
```promql
count(count by (namespace) (kube_pod_info))
```

### 11.4 Bar Gauge 패널 (네임스페이스별 CPU 사용률)

**Query:**
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
/
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
* 100
```

**Display:**
- Orientation: Horizontal
- Show values: All
- Unit: percent (0-100)

### 11.5 Heatmap 패널 (시간대별 CPU 사용 패턴)

**Query:**
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
```

**Format:** Heatmap

## 12. 필터링 및 변수 활용

### 12.1 특정 네임스페이스만 조회
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD",namespace=~"$namespace"}[5m])) by (namespace)
```

### 12.2 특정 클러스터만 조회
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD",cluster="$cluster"}[5m])) by (namespace)
```

### 12.3 시스템 네임스페이스 제외
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD",namespace!~"kube-.*|default"}[5m])) by (namespace)
```

### 12.4 그라파나 변수 정의 예시

**Variable Name:** `namespace`
**Type:** Query
**Query:**
```promql
label_values(kube_pod_info, namespace)
```
**Regex:** `/^(?!kube-|default).*/` (시스템 네임스페이스 제외)
**Multi-value:** Yes
**Include All option:** Yes

## 13. 알람 규칙 예시

### 13.1 네임스페이스 CPU 사용률 80% 초과
```promql
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
/
sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
* 100 > 80
```

### 13.2 네임스페이스 메모리 사용률 90% 초과
```promql
sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)
/
sum(kube_pod_container_resource_limits{resource="memory"}) by (namespace)
* 100 > 90
```

### 13.3 네임스페이스 Pod 재시작 빈발 (1시간에 5회 이상)
```promql
sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace) > 5
```

## 14. 주의사항

### 14.1 메트릭 수집 필수 요구사항
- `cAdvisor` 메트릭 활성화 필요
- `kube-state-metrics` 배포 필수
- Prometheus ServiceMonitor 설정 필요

### 14.2 성능 최적화
- 긴 시간 범위 조회 시 `[5m]` 대신 `[15m]` 또는 `[30m]` 사용
- Recording Rule 사전 계산으로 쿼리 성능 향상
- Grafana 캐싱 활성화

### 14.3 정확도
- `container_memory_working_set_bytes`가 실제 메모리 사용량 지표
- `container_memory_usage_bytes`는 캐시 포함으로 과대 측정 가능
- CPU 사용량은 `rate()` 함수로 평균 계산 필요

## 15. Recording Rule 예시

Recording Rule을 사용하면 복잡한 쿼리를 사전 계산하여 대시보드 성능을 향상시킬 수 있습니다.

```yaml
groups:
  - name: namespace_resources
    interval: 30s
    rules:
      - record: namespace:cpu_usage:rate5m
        expr: sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)

      - record: namespace:memory_usage:bytes
        expr: sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)

      - record: namespace:network_transmit:rate5m
        expr: sum(rate(container_network_transmit_bytes_total[5m])) by (namespace)

      - record: namespace:network_receive:rate5m
        expr: sum(rate(container_network_receive_bytes_total[5m])) by (namespace)

      - record: namespace:cpu_utilization:percent
        expr: |
          sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (namespace)
          /
          sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)
          * 100

      - record: namespace:memory_utilization:percent
        expr: |
          sum(container_memory_working_set_bytes{container!="",container!="POD"}) by (namespace)
          /
          sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace)
          * 100
```

Recording Rule 적용 후 대시보드에서는 다음과 같이 간단하게 사용:
```promql
namespace:cpu_usage:rate5m
namespace:memory_usage:bytes
namespace:cpu_utilization:percent
```

---

**문서 작성일:** 2025-11-11
**작성자:** Claude Code
**버전:** 1.0
