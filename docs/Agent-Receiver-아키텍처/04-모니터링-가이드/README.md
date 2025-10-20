# 04. 모니터링 가이드

## 📋 개요

Prometheus Agent + Thanos Receiver 환경에서 핵심 메트릭 수집, 대시보드 구성, 알림 규칙 설정 방법을 제공합니다.

---

## 📂 문서 목록

### 핵심-메트릭.md
**목적**: 모니터링해야 할 필수 메트릭 정의

**주요 내용**:
- Prometheus Agent 메트릭
- Thanos Receiver 메트릭
- Remote Write 성능 지표
- Hashring 상태 메트릭
- 리소스 사용량 (CPU, Memory, Disk)

**대상 독자**: SRE, 모니터링 담당자

---

### Grafana-대시보드.md
**목적**: 사전 구성된 대시보드 및 커스터마이징

**주요 내용**:
- Thanos Receiver Overview
- Prometheus Agent Dashboard
- Multi-Cluster Summary
- OpenSearch Logs Dashboard
- 커스텀 대시보드 생성 방법

**대상 독자**: 시각화 담당자, SRE

---

### 알림-규칙.md
**목적**: Prometheus Alert Rules 및 Alertmanager 설정

**주요 내용**:
- Remote Write 실패 알림
- Receiver 다운타임 알림
- 디스크 공간 부족 경고
- 메트릭 누락 감지
- Alertmanager 라우팅

**대상 독자**: SRE, 운영 담당자

---

### PromQL-쿼리-예제.md
**목적**: 자주 사용하는 PromQL 쿼리 모음

**주요 내용**:
- Remote Write 성공률
- 클러스터별 메트릭 집계
- Top N 리소스 사용 Pod
- Thanos Receiver 부하
- 네트워크 트래픽 분석

**대상 독자**: 모든 운영자

---

### 로그-수집-분석.md
**목적**: OpenSearch + Fluent-Bit 로그 수집 구성

**주요 내용**:
- Fluent-Bit 설정
- OpenSearch 인덱스 관리
- 로그 필터링 및 파싱
- Grafana 로그 대시보드
- 로그 기반 알림

**대상 독자**: 로그 관리자, SRE

---

### 성능-튜닝.md
**목적**: 메트릭 수집 및 저장 성능 최적화

**주요 내용**:
- Scrape Interval 조정
- Remote Write 큐 튜닝
- Receiver Replication Factor
- TSDB 압축 설정
- 쿼리 성능 최적화

**대상 독자**: 성능 엔지니어, SRE

---

### 멀티클러스터-뷰.md
**목적**: 4개 클러스터 통합 모니터링

**주요 내용**:
- Thanos Query 활용
- 클러스터별 레이블 전략
- 전체 클러스터 요약 대시보드
- 클러스터 간 비교 쿼리
- 멀티테넌시 메트릭 분리

**대상 독자**: 아키텍트, 통합 관리자

---

## 📊 주요 메트릭 카테고리

### 1. Prometheus Agent
```promql
# Remote Write 성공률
rate(prometheus_remote_storage_succeeded_samples_total[5m])

# Remote Write 큐 크기
prometheus_remote_storage_queue_length

# WAL 크기
prometheus_tsdb_wal_segment_current
```

### 2. Thanos Receiver
```promql
# 수신 메트릭 속도
rate(thanos_receive_replication_requests_total[5m])

# Hashring 상태
thanos_receive_hashring_nodes

# 스토리지 사용량
prometheus_tsdb_storage_blocks_bytes
```

### 3. 클러스터 리소스
```promql
# CPU 사용률 (클러스터별)
sum(rate(container_cpu_usage_seconds_total{cluster="cluster-02"}[5m])) by (namespace)

# 메모리 사용량
sum(container_memory_working_set_bytes{cluster="cluster-03"}) by (pod)
```

---

## 🎨 대시보드 구조

### 전체 클러스터 Overview
- **패널 1**: 4개 클러스터 상태 (UP/DOWN)
- **패널 2**: 총 메트릭 샘플 수 (per cluster)
- **패널 3**: Remote Write 성공률
- **패널 4**: Thanos Receiver 부하

### 클러스터별 상세
- **가 클러스터 (cluster-02)**: 멀티테넌시 메트릭 분리
- **나 클러스터 (cluster-03)**: Edge 리소스 최적화
- **다 클러스터 (cluster-04)**: Edge 리소스 최적화

---

## 🚨 핵심 알림 규칙

### 1. Remote Write 실패
```yaml
- alert: RemoteWriteFailing
  expr: |
    rate(prometheus_remote_storage_failed_samples_total[5m]) > 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Remote Write failing on {{ $labels.cluster }}"
```

### 2. Receiver 다운
```yaml
- alert: ThanosReceiverDown
  expr: |
    up{job="thanos-receive"} == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Thanos Receiver is down"
```

### 3. 디스크 공간 부족
```yaml
- alert: DiskSpaceLow
  expr: |
    (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Disk space < 10% on {{ $labels.instance }}"
```

---

## 🔗 관련 섹션

- **아키텍처** → [01-아키텍처](../01-아키텍처/)
- **배포** → [02-Kustomize-Helm-GitOps-배포](../02-Kustomize-Helm-GitOps-배포/)
- **운영** → [03-운영-가이드](../03-운영-가이드/)

---

**최종 업데이트**: 2025-10-20
