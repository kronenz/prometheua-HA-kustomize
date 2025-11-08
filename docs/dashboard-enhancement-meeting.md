# DataOps 대시보드 고도화 전문가 회의록

## 📋 회의 정보

**날짜**: 2025-11-05
**주제**: 베어메탈 Kubernetes + 빅데이터 플랫폼 통합 대시보드 고도화
**목표**: 운영 효율성 극대화 및 사용자 경험 개선

---

## 👥 참석자

### 1. Infrastructure Architect (베어메탈/K8s 전문가)
- **이름**: 김인프라
- **역할**: 베어메탈 서버, 네트워크, 스토리지, Kubernetes 인프라 담당
- **관심사**: 하드웨어 리소스 활용률, 네트워크 대역폭, 스토리지 성능

### 2. BigData Platform Engineer (빅데이터 전문가)
- **이름**: 박빅데이터
- **역할**: Spark, Airflow, Trino, Iceberg, Hive Metastore 운영
- **관심사**: Job 성공률, 데이터 파이프라인 성능, 쿼리 최적화

### 3. SRE (Site Reliability Engineer)
- **이름**: 이에스알이
- **역할**: 플랫폼 안정성, SLO 관리, 장애 대응
- **관심사**: Availability, MTTD/MTTR, Error Budget, Alert 정확도

### 4. UI/UX Designer (대시보드 디자이너)
- **이름**: 최유엑스
- **역할**: 대시보드 시각화, 색상 체계, 사용자 경험
- **관심사**: 정보 계층 구조, 색상 접근성, 인지 부하 최소화

### 5. DevOps Engineer (운영 자동화)
- **이름**: 정데브옵스
- **역할**: CI/CD, GitOps, 자동화 파이프라인
- **관심사**: 배포 속도, 파이프라인 안정성, 자동화율

---

## 🎯 회의 목표

1. **통합 관점 수립**: 베어메탈 인프라 → Kubernetes → 빅데이터 플랫폼 전체 스택 모니터링
2. **시각적 개선**: 눈의 피로를 줄이는 색상 체계 및 레이아웃 설계
3. **역할별 맞춤화**: 각 담당자가 필요한 정보를 빠르게 찾을 수 있는 구조
4. **실시간 의사결정**: 장애 발생 시 빠른 원인 파악 및 대응

---

## 💬 주요 논의 사항

### 1. 현재 대시보드의 문제점

#### Infrastructure Architect (김인프라)
> "현재 대시보드는 Kubernetes 레이어에만 집중되어 있어, **베어메탈 하드웨어 상태를 파악하기 어렵습니다.**
> - CPU/Memory는 있지만, **물리 서버 온도, 전력 소비, 디스크 SMART 상태**가 없습니다.
> - **네트워크 스위치 포트 상태, 대역폭 병목**을 볼 수 없습니다.
> - **Longhorn, Ceph, Isilon 스토리지 성능**이 분산되어 있어 전체 I/O를 파악하기 어렵습니다."

#### BigData Platform Engineer (박빅데이터)
> "빅데이터 워크로드는 **리소스 집약적**이고 **장시간 실행**되는 특성이 있습니다.
> - **Spark Executor 배치 상황**이 보이지 않아, 리소스 경합을 사전에 파악하기 어렵습니다.
> - **Iceberg Snapshot 관리 상태**가 없어서, 테이블 유지보수 시점을 놓칩니다.
> - **Hive Metastore Lock 대기 시간**이 모니터링되지 않아, 동시성 이슈를 발견하지 못합니다."

#### SRE (이에스알이)
> "운영 관점에서 가장 큰 문제는 **장애의 Root Cause를 찾기까지 여러 대시보드를 오가야 한다**는 점입니다.
> - 예: Spark Job 실패 → CPU 부족? → Node 이슈? → 물리 서버 문제?
> - **Correlation이 없어서** 매번 수동으로 연관성을 파악해야 합니다.
> - **Alert 우선순위**가 대시보드에 명확히 표시되지 않습니다."

#### UI/UX Designer (최유엑스)
> "현재 색상 체계의 문제점:
> - **고채도 Primary Color (보라, 빨강)가 많아서** 장시간 보면 눈이 피로합니다.
> - **Threshold 색상 (빨강, 노랑, 초록)**이 너무 선명해서 경고가 아닌데도 긴장감을 줍니다.
> - **Gradient 배경**이 텍스트 가독성을 떨어뜨립니다.
> - **Dark Mode 지원 부족**: 야간 On-call 시 눈부심 문제"

#### DevOps Engineer (정데브옵스)
> "GitOps 파이프라인 대시보드는 좋지만, **실제 운영에서 필요한 것**은:
> - **Rollback 이력** 및 **자동 Rollback 트리거 조건**
> - **Canary/Blue-Green 배포 진행 상황**
> - **Config Drift 탐지** (Git vs 실제 클러스터 상태)"

---

### 2. 개선 방향 합의

#### 2-1. 대시보드 계층 구조 재설계

기존 구조:
```
Main Nav → 6개 Domain (GitOps, Resource, Workload, Data, Optimization, E2E)
```

**새로운 구조 (3-Tier 아키텍처 반영):**
```
Level 0: Executive Summary (임원/관리자용)
  ├─ 플랫폼 전체 Health Score (0-100)
  ├─ 금일 SLO 달성률
  ├─ Critical Alert 요약
  └─ 비용 트렌드

Level 1: Operational Dashboards (운영자용)
  ├─ 1. Infrastructure Health (베어메탈 + K8s)
  │   ├─ Physical Servers (온도, 전력, RAID 상태)
  │   ├─ Network (스위치, 대역폭, Latency)
  │   ├─ Storage (Longhorn, Ceph, Isilon, MinIO)
  │   └─ Kubernetes (Nodes, Pods, Services)
  │
  ├─ 2. BigData Platform (Spark, Airflow, Trino, Iceberg)
  │   ├─ Compute Layer (Spark Executors, Trino Workers)
  │   ├─ Orchestration (Airflow DAGs, Scheduler)
  │   ├─ Data Layer (Iceberg Tables, Hive Metastore)
  │   └─ Query Performance (Slow Queries, Cache Hit Rate)
  │
  ├─ 3. Application Lifecycle (GitOps + Deployment)
  │   ├─ CI/CD Pipeline (Jenkins, ArgoCD)
  │   ├─ Deployment Status (Rollout, Rollback)
  │   ├─ Config Management (Drift Detection)
  │   └─ Image Registry (Harbor, Vulnerability Scan)
  │
  └─ 4. Operations & SLO
      ├─ SLO Dashboard (Error Budget, Burn Rate)
      ├─ Incident Management (MTTD, MTTR, Postmortem)
      ├─ Cost Analysis (FinOps)
      └─ Capacity Planning (Forecast)

Level 2: Deep Dive (엔지니어용)
  └─ 각 컴포넌트별 상세 메트릭, 로그, 트레이스
```

#### 2-2. 색상 체계 개선

**UI/UX Designer (최유엑스) 제안:**

**기존 문제:**
- 고채도 Gradient: `#667eea → #764ba2` (보라)
- 순수 Red/Yellow/Green Threshold

**개선된 색상 체계:**

1. **Primary Palette (저채도, 눈에 편안함)**
   ```
   Primary Blue:    #5B8DEE (Medium Saturation)
   Secondary Teal:  #4DB8A8 (Calming)
   Accent Orange:   #F5A962 (Warm, not alarming)
   Neutral Gray:    #6B7280 (Text/Background)
   ```

2. **Semantic Colors (의미 기반)**
   ```
   Success:   #10B981 (Softer Green)
   Warning:   #F59E0B (Amber, not bright yellow)
   Error:     #EF4444 (Softer Red)
   Info:      #3B82F6 (Blue)
   ```

3. **Background Colors**
   ```
   Light Mode:
     - Background: #F9FAFB
     - Card: #FFFFFF
     - Border: #E5E7EB

   Dark Mode:
     - Background: #111827
     - Card: #1F2937
     - Border: #374151
   ```

4. **Data Visualization Colors (Colorblind-friendly)**
   ```
   Series 1: #5B8DEE (Blue)
   Series 2: #10B981 (Green)
   Series 3: #F59E0B (Amber)
   Series 4: #8B5CF6 (Purple)
   Series 5: #EF4444 (Red)
   Series 6: #14B8A6 (Teal)
   ```

5. **Threshold Colors (3-step)**
   ```
   Healthy:   #D1FAE5 background + #10B981 text
   Warning:   #FEF3C7 background + #F59E0B text
   Critical:  #FEE2E2 background + #EF4444 text
   ```

#### 2-3. 레이아웃 원칙

**Information Hierarchy (정보 계층):**
1. **F-Pattern 레이아웃**: 왼쪽 상단에 가장 중요한 정보 (SLO, Critical Alerts)
2. **Card-based Design**: 각 섹션을 카드로 분리하여 시각적 그룹핑
3. **Progressive Disclosure**: 요약 → 상세 → Drill-down 순서로 정보 제공
4. **Whitespace 활용**: 패널 간 충분한 여백 (8px → 16px)

**Typography:**
- Heading: 16px Bold (중요 섹션 제목)
- Body: 14px Regular (일반 텍스트)
- Small: 12px Regular (보조 정보)
- Monospace: 13px (메트릭 값, 로그)

---

### 3. 베어메탈 인프라 모니터링 추가 항목

#### Infrastructure Architect (김인프라) 요구사항:

**Physical Server Metrics:**
```promql
# CPU 온도 (목표: <75°C)
node_hwmon_temp_celsius

# 전력 소비 (Watts)
node_power_usage_watts

# Fan 속도 (RPM)
node_hwmon_fan_rpm

# RAID 상태
node_md_disks{state="active"}

# Memory ECC Errors
node_edac_correctable_errors_total
node_edac_uncorrectable_errors_total
```

**Network Metrics:**
```promql
# 스위치 포트 상태 (SNMP Exporter)
ifOperStatus{ifDescr=~"Ethernet.*"}

# 네트워크 대역폭 활용률
rate(ifHCInOctets[5m]) * 8 / ifHighSpeed * 100

# 패킷 손실률
rate(ifInErrors[5m]) / rate(ifInPackets[5m]) * 100

# Latency (Blackbox Exporter)
probe_duration_seconds{phase="connect"}
```

**Storage Metrics (통합 뷰):**
```promql
# Longhorn (K8s Native)
longhorn_volume_actual_size_bytes
longhorn_volume_robustness{robustness="degraded"}

# Ceph (Distributed)
ceph_cluster_total_used_bytes / ceph_cluster_total_bytes * 100
ceph_osd_up

# Isilon (NAS)
isilon_cluster_ifs_bytes{usage="used"} / isilon_cluster_ifs_bytes{usage="total"} * 100

# MinIO (S3)
minio_cluster_capacity_usable_total_bytes
minio_cluster_capacity_usable_free_bytes
```

---

### 4. 빅데이터 플랫폼 상세 모니터링

#### BigData Platform Engineer (박빅데이터) 요구사항:

**Spark Executor Placement:**
```promql
# Executor 배치 현황
spark_executor_count by (application_id, node)

# Pending Executor 수 (리소스 부족 감지)
spark_executor_pending_count

# Executor 실패율
rate(spark_executor_failures_total[5m])
```

**Iceberg Table Health:**
```promql
# Snapshot 수 (목표: <100)
iceberg_table_snapshot_count

# Orphan Files 수 (목표: 0)
iceberg_table_orphan_files_count

# Manifest File 크기 (목표: <1GB)
iceberg_table_manifest_size_bytes

# 마지막 Compaction 시간 (목표: <7일)
time() - iceberg_table_last_compaction_timestamp_seconds
```

**Hive Metastore Concurrency:**
```promql
# Lock 대기 시간 (목표: <1초)
histogram_quantile(0.95, sum(rate(hive_metastore_lock_wait_seconds_bucket[5m])) by (le))

# 동시 연결 수
hive_metastore_active_connections

# 느린 DDL 작업 (>5초)
hive_metastore_ddl_duration_seconds{duration_seconds>5}
```

**Trino Query Optimizer:**
```promql
# Query Plan Analysis
trino_query_planning_duration_seconds

# Cache Hit Rate (목표: >80%)
trino_cache_hits_total / (trino_cache_hits_total + trino_cache_misses_total) * 100

# Spill to Disk (Memory 부족 지표)
rate(trino_spill_bytes_written_total[5m])
```

---

### 5. SRE 관점 개선 사항

#### SRE (이에스알이) 요구사항:

**Unified Incident Timeline:**
```
[타임라인 뷰]
10:00 - Spark Job Slow (P3)
10:05 - CPU Spike on Node-03 (P2)
10:07 - Physical Disk Latency High (P1) ← Root Cause
10:10 - RAID Degraded on Server-03 (P0) ← 실제 원인
```

**Correlation Dashboard:**
- X축: 시간
- Y축: 레이어별 이벤트
  - Layer 5: Application (Spark, Airflow)
  - Layer 4: Kubernetes (Pod Restart, Node NotReady)
  - Layer 3: Network (Latency Spike, Packet Loss)
  - Layer 2: Storage (IOPS Drop, Latency)
  - Layer 1: Physical (Disk Error, Memory ECC)

**Runbook Integration:**
- Alert Panel에 직접 Runbook 링크 표시
- 1-Click Remediation (Ansible Tower 연동)

---

### 6. 최종 합의 사항

#### 6-1. 새로운 대시보드 목록

| #  | 대시보드명                     | 주 사용자                | 업데이트 주기 |
|----|--------------------------------|--------------------------|---------------|
| 0  | Executive Summary              | 임원, 관리자             | 5분           |
| 1  | Infrastructure Health          | Infra Architect, SRE     | 30초          |
| 2  | BigData Platform               | BigData Engineer, SRE    | 30초          |
| 3  | Application Lifecycle          | DevOps, SRE              | 30초          |
| 4  | Operations & SLO               | SRE, Ops Manager         | 1분           |
| 5  | Cost & Capacity                | FinOps, Capacity Planner | 1시간         |
| 6  | Incident Timeline              | SRE, On-call             | 실시간        |

#### 6-2. 구현 우선순위

**Phase 1 (Week 1-2): 핵심 개선**
- [ ] 색상 체계 전체 변경
- [ ] Main Navigation 재설계 (Executive Summary)
- [ ] Infrastructure Health 대시보드 (베어메탈 추가)
- [ ] BigData Platform 대시보드 (상세 메트릭 추가)

**Phase 2 (Week 3-4): 운영 고도화**
- [ ] Operations & SLO 대시보드
- [ ] Incident Timeline (Correlation 뷰)
- [ ] Runbook 자동화 연동

**Phase 3 (Week 5-6): 고급 기능**
- [ ] Cost & Capacity 대시보드
- [ ] Anomaly Detection (ML 기반 이상 탐지)
- [ ] Auto-remediation Workflow

---

## 🎨 디자인 시스템 정의

### Color System

```css
/* Primary Colors */
--color-primary-50:  #EEF2FF;
--color-primary-100: #E0E7FF;
--color-primary-500: #5B8DEE;  /* Main Brand */
--color-primary-600: #4F7CD9;
--color-primary-900: #1E3A8A;

/* Secondary Colors */
--color-secondary-50:  #F0FDFA;
--color-secondary-500: #4DB8A8;  /* Teal */
--color-secondary-900: #134E4A;

/* Semantic Colors */
--color-success-50:  #D1FAE5;
--color-success-500: #10B981;
--color-success-900: #065F46;

--color-warning-50:  #FEF3C7;
--color-warning-500: #F59E0B;
--color-warning-900: #78350F;

--color-error-50:  #FEE2E2;
--color-error-500: #EF4444;
--color-error-900: #7F1D1D;

/* Neutral Colors */
--color-gray-50:  #F9FAFB;
--color-gray-100: #F3F4F6;
--color-gray-500: #6B7280;
--color-gray-900: #111827;
```

### Typography Scale

```css
--font-size-xs:   0.75rem;  /* 12px */
--font-size-sm:   0.875rem; /* 14px */
--font-size-base: 1rem;     /* 16px */
--font-size-lg:   1.125rem; /* 18px */
--font-size-xl:   1.25rem;  /* 20px */
--font-size-2xl:  1.5rem;   /* 24px */

--font-weight-normal: 400;
--font-weight-medium: 500;
--font-weight-semibold: 600;
--font-weight-bold: 700;
```

### Spacing Scale

```css
--spacing-1: 0.25rem;  /* 4px */
--spacing-2: 0.5rem;   /* 8px */
--spacing-3: 0.75rem;  /* 12px */
--spacing-4: 1rem;     /* 16px */
--spacing-6: 1.5rem;   /* 24px */
--spacing-8: 2rem;     /* 32px */
```

---

## 📊 Panel 표준화

### Stat Panel (KPI 표시)
```json
{
  "type": "stat",
  "options": {
    "textMode": "value_and_name",
    "colorMode": "background",
    "graphMode": "none",
    "orientation": "auto"
  },
  "fieldConfig": {
    "defaults": {
      "color": {"mode": "thresholds"},
      "thresholds": {
        "mode": "absolute",
        "steps": [
          {"value": 0, "color": "rgba(16, 185, 129, 0.1)"},      /* Success bg */
          {"value": 70, "color": "rgba(245, 158, 11, 0.1)"},     /* Warning bg */
          {"value": 90, "color": "rgba(239, 68, 68, 0.1)"}       /* Error bg */
        ]
      }
    }
  }
}
```

### Time Series Panel (추이 그래프)
```json
{
  "type": "timeseries",
  "fieldConfig": {
    "defaults": {
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "lineWidth": 2,
        "fillOpacity": 10,
        "spanNulls": true
      },
      "color": {"mode": "palette-classic"}
    }
  }
}
```

---

## ✅ Action Items

| 담당자           | 작업                                      | 마감일     |
|------------------|-------------------------------------------|------------|
| 최유엑스         | 디자인 시스템 Figma 템플릿 제작          | Week 1     |
| 김인프라         | 베어메탈 Exporter 설정 (IPMI, SNMP)      | Week 1     |
| 박빅데이터       | Iceberg/Hive Custom Exporter 개발         | Week 1-2   |
| 이에스알이       | Correlation 알고리즘 설계                 | Week 2     |
| 정데브옵스       | Dashboard-as-Code CI/CD 파이프라인        | Week 2     |
| 전체             | 새로운 대시보드 구현 및 배포              | Week 1-4   |

---

## 📝 회의 결론

1. **베어메탈 인프라 메트릭 추가**로 전체 스택 가시성 확보
2. **저채도 색상 체계**로 장시간 모니터링 시 눈의 피로 감소
3. **3-Tier 아키텍처 반영**한 대시보드 계층 구조로 역할별 효율성 향상
4. **Correlation Timeline**으로 장애 Root Cause 분석 시간 단축 (30분 → 5분 목표)
5. **6주 구현 계획** 수립 완료

---

**다음 회의**: 2주 후 (Phase 1 완료 후 리뷰)
**문서 버전**: v1.0
**작성자**: 회의록 봇 (Claude)
