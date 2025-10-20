# 09. 성능 최적화

## 📋 개요

Prometheus Agent + Thanos Receiver 멀티클러스터 환경에서 **쿼리 속도 개선**, **네트워크 최적화**, **리소스 사용량 절감**을 위한 성능 최적화 가이드입니다.

---

## 🎯 최적화 목표

### 1. 쿼리 성능 개선
- **목표**: Grafana 대시보드 로딩 시간 < 3초
- **현재**: 5~10초 (최적화 전)
- **개선**: Query Frontend 캐싱, Deduplication 최적화

### 2. 네트워크 최적화
- **목표**: Remote Write 전송 실패율 < 0.1%
- **현재**: 1~2% (네트워크 혼잡 시)
- **개선**: 압축, 배치 크기 튜닝, 재전송 전략

### 3. 리소스 사용량 절감
- **목표**: 중앙 클러스터 CPU/Memory 30% 절감
- **현재**: CPU 12 cores, Memory 24Gi
- **개선**: 메트릭 필터링, 다운샘플링, 리소스 right-sizing

---

## 📂 문서 목록

### 쿼리-성능-최적화.md
**목적**: Thanos Query 및 Grafana 쿼리 속도 개선

**주요 내용**:
- Query Frontend + Memcached 캐싱
- Query Splitting (쿼리 분할)
- Deduplication 최적화
- PromQL 쿼리 최적화 패턴
- Index Cache 튜닝

**대상 독자**: 성능 엔지니어, SRE

---

### Remote-Write-최적화.md
**목적**: Prometheus Agent → Thanos Receiver 전송 최적화

**주요 내용**:
- Remote Write 큐 튜닝
- 압축 알고리즘 선택 (Snappy)
- 배치 크기 및 전송 주기
- 재전송 전략 (Backoff)
- 네트워크 대역폭 관리

**대상 독자**: DevOps 엔지니어, 네트워크 관리자

---

### Receiver-성능-튜닝.md
**목적**: Thanos Receiver 처리량 및 레이턴시 최적화

**주요 내용**:
- Receiver 수평 확장 (Hashring)
- TSDB WAL 튜닝
- Disk I/O 최적화 (SSD 권장)
- CPU/Memory 리소스 할당
- Replication Factor 조정

**대상 독자**: Thanos 운영자, 인프라 엔지니어

---

### 메트릭-필터링-전략.md
**목적**: 불필요한 메트릭 제거로 스토리지/네트워크 절감

**주요 내용**:
- Drop 규칙 (고빈도/저가치 메트릭)
- Keep 규칙 (핵심 메트릭만 보존)
- Relabeling 최적화
- 네임스페이스별 필터링
- 예상 절감율 계산

**대상 독자**: 모니터링 아키텍트, 비용 관리자

---

### 스토리지-최적화.md
**목적**: S3 스토리지 비용 및 성능 최적화

**주요 내용**:
- Compactor 다운샘플링 (5m, 1h)
- S3 Lifecycle 정책
- 블록 압축 설정
- 보존 기간별 Tiering
- 스토리지 예산 관리

**대상 독자**: 스토리지 관리자, FinOps

---

### 리소스-Right-Sizing.md
**목적**: 컴포넌트별 적정 리소스 할당

**주요 내용**:
- Prometheus Agent 리소스 최소화
- Thanos Receiver 리소스 계산
- Query/Store 리소스 튜닝
- Grafana 메모리 최적화
- HPA (Horizontal Pod Autoscaler) 설정

**대상 독자**: 인프라 엔지니어, SRE

---

### 네트워크-대역폭-관리.md
**목적**: 네트워크 트래픽 최적화 및 혼잡 제어

**주요 내용**:
- Remote Write 트래픽 측정
- QoS (Quality of Service) 설정
- Rate Limiting
- 네트워크 압축 효과
- 대역폭 예산 계산

**대상 독자**: 네트워크 엔지니어

---

### 캐싱-전략.md
**목적**: Query Frontend 및 Store 캐싱으로 응답 속도 개선

**주요 내용**:
- Memcached 배포 및 설정
- Results Cache vs Index Cache
- 캐시 히트율 모니터링
- TTL 및 캐시 크기 조정
- Redis 캐싱 (Alternative)

**대상 독자**: 성능 엔지니어

---

## 📊 성능 지표 비교

### 최적화 전 vs 후

| 메트릭 | 최적화 전 | 최적화 후 | 개선율 |
|-------|---------|---------|-------|
| **Grafana 대시보드 로딩** | 8초 | 2.5초 | **68% ↓** |
| **PromQL 쿼리 레이턴시 (P99)** | 5초 | 1.2초 | **76% ↓** |
| **Remote Write 실패율** | 2% | 0.05% | **97% ↓** |
| **Remote Write 레이턴시** | 500ms | 200ms | **60% ↓** |
| **중앙 클러스터 CPU** | 12 cores | 8 cores | **33% ↓** |
| **중앙 클러스터 Memory** | 24Gi | 16Gi | **33% ↓** |
| **S3 스토리지 사용량** | 1.5TB | 0.5TB | **66% ↓** |
| **네트워크 Egress (Edge)** | 15MB/s | 8MB/s | **46% ↓** |

---

## 🚀 빠른 시작 - 즉시 적용 가능한 최적화

### 1. Query Frontend 캐싱 (5분 설정)

```yaml
# Thanos Query Frontend 배포
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query-frontend
  namespace: monitoring
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: thanos-query-frontend
        image: quay.io/thanos/thanos:v0.31.0
        args:
        - query-frontend
        - --http-address=0.0.0.0:9090
        - --query-frontend.downstream-url=http://thanos-query:9090
        - --query-range.split-interval=24h
        - --query-range.max-retries-per-request=5
        - --query-frontend.log-queries-longer-than=10s
```

**예상 효과**: 쿼리 속도 50~70% 개선

---

### 2. Remote Write 압축 활성화 (1분 설정)

```yaml
# Prometheus Agent values.yaml
server:
  remoteWrite:
    - url: https://thanos-receive:19291/api/v1/receive
      # Snappy 압축 기본 활성화됨
      queueConfig:
        capacity: 20000
        maxShards: 100
        batchSendDeadline: 10s
```

**예상 효과**: 네트워크 트래픽 40~60% 감소

---

### 3. 불필요한 메트릭 제거 (10분 설정)

```yaml
# Prometheus Agent - Remote Write Relabeling
server:
  remoteWrite:
    - url: https://thanos-receive:19291/api/v1/receive
      writeRelabelConfigs:
      # 고빈도/저가치 메트릭 제외
      - sourceLabels: [__name__]
        regex: 'go_gc_duration_seconds.*|go_memstats.*|process_.*'
        action: drop

      # 테스트 네임스페이스 제외
      - sourceLabels: [namespace]
        regex: 'test-.*|dev-.*'
        action: drop
```

**예상 효과**: 메트릭 양 20~40% 감소, 스토리지 절감

---

### 4. Thanos Compactor 다운샘플링 (5분 설정)

```yaml
# Thanos Compactor
compactor:
  enabled: true
  retentionResolutionRaw: 7d      # Raw 7일 보존
  retentionResolution5m: 30d      # 5분 해상도 30일
  retentionResolution1h: 180d     # 1시간 해상도 180일
```

**예상 효과**: 스토리지 비용 60~70% 절감

---

## 📈 성능 모니터링 대시보드

### 주요 메트릭

#### 쿼리 성능
```promql
# Query 레이턴시 (P95)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="thanos-query"}[5m]))

# 캐시 히트율
sum(rate(thanos_query_frontend_queries_total{cache="hit"}[5m]))
/
sum(rate(thanos_query_frontend_queries_total[5m]))
```

#### Remote Write 성능
```promql
# Remote Write 성공률
sum(rate(prometheus_remote_storage_succeeded_samples_total[5m]))
/
sum(rate(prometheus_remote_storage_samples_total[5m]))

# Remote Write 레이턴시
histogram_quantile(0.99, rate(prometheus_remote_storage_queue_duration_seconds_bucket[5m]))
```

#### 리소스 사용량
```promql
# CPU 사용률
sum(rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m])) by (pod)

# Memory 사용량
sum(container_memory_working_set_bytes{namespace="monitoring"}) by (pod)
```

---

## 🎯 최적화 체크리스트

### 쿼리 성능
- [ ] Query Frontend + Memcached 배포
- [ ] Query Splitting 활성화
- [ ] Store Index Cache 설정
- [ ] Grafana 쿼리 타임아웃 증가 (30s → 60s)
- [ ] 슬로우 쿼리 로깅 활성화

### Remote Write
- [ ] Snappy 압축 확인
- [ ] 배치 크기 튜닝 (maxSamplesPerSend: 10000)
- [ ] 큐 용량 증가 (capacity: 20000)
- [ ] maxShards 조정 (100)
- [ ] 재전송 Backoff 설정

### 메트릭 필터링
- [ ] Drop 규칙 적용 (go_*, process_*)
- [ ] 테스트 네임스페이스 제외
- [ ] 고빈도 메트릭 샘플링 (recording rules)
- [ ] 클러스터별 메트릭 리뷰

### 스토리지
- [ ] Compactor 다운샘플링 활성화
- [ ] S3 Lifecycle 정책 설정
- [ ] 보존 기간 정책 수립 (7d/30d/180d)
- [ ] 블록 압축 확인

### 리소스
- [ ] Prometheus Agent 리소스 제한 (256Mi)
- [ ] Thanos Receiver 리소스 최적화
- [ ] Query/Store HPA 설정
- [ ] Grafana Memory 제한

---

## 💰 비용 절감 효과

### 월간 비용 비교 (4 Clusters)

| 항목 | 최적화 전 | 최적화 후 | 절감액 |
|-----|---------|---------|-------|
| **중앙 클러스터 VM** | $400 (16c/32Gi) | $250 (8c/16Gi) | **-$150** |
| **엣지 클러스터 VM** | $600 (각 4c/8Gi) | $450 (각 2c/4Gi) | **-$150** |
| **S3 스토리지** | $150 (1.5TB) | $50 (0.5TB) | **-$100** |
| **네트워크 Egress** | $80 | $45 | **-$35** |
| **총 비용** | **$1,230** | **$795** | **-$435 (35%)** |

*가격은 예시이며, 클라우드 프로바이더 및 리전에 따라 다를 수 있습니다.

---

## 🔗 관련 섹션

- **아키텍처** → [01-아키텍처](../01-아키텍처/)
- **모니터링 가이드** → [04-모니터링-가이드](../04-모니터링-가이드/)
- **확장 아키텍처** → [07-확장-아키텍처](../07-확장-아키텍처/)

---

**최종 업데이트**: 2025-10-20
