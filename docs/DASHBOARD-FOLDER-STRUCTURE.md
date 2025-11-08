# DataOps 대시보드 폴더 구조 및 링크 가이드

## 📁 Grafana 폴더 계층 구조

DataOps 모니터링 대시보드는 계층적 폴더 구조로 정리되어 있어 쉽게 탐색할 수 있습니다.

```
📊 Grafana Dashboards
│
├── 📂 Executive Dashboard/          (Level 0 - 경영진용)
│   └── 🎯 Executive Summary
│       ├── 플랫폼 Health Score
│       ├── SLO 달성률 (30d)
│       ├── Active Alerts
│       ├── 월간 예상 비용
│       └── 4개 도메인 대시보드로 이동 (클릭 가능한 카드)
│
├── 📂 Infrastructure/               (Level 1 - 인프라 운영팀)
│   └── 🏗️ Infrastructure Health
│       ├── 물리 서버 (CPU 온도, 전력, RAID, ECC)
│       ├── 네트워크 (대역폭, 패킷 손실률)
│       ├── 스토리지 (Longhorn, Ceph, Isilon, MinIO)
│       └── Kubernetes 클러스터 (Pods, Services)
│
├── 📂 BigData Platform/            (Level 1 - 빅데이터 엔지니어)
│   └── 📊 BigData Platform
│       ├── Compute (Spark)
│       │   ├── Job 성공률
│       │   ├── Executor 배치 현황
│       │   └── GC Time Ratio
│       ├── Orchestration (Airflow)
│       │   ├── DAG 성공률
│       │   └── Scheduler 지연
│       ├── Query Engine (Trino)
│       │   ├── Query 성공률
│       │   ├── Cache Hit Rate
│       │   └── Spill to Disk
│       └── Data Layer (Iceberg)
│           ├── 테이블 수
│           ├── Small Files 비율
│           └── Snapshot 수
│
├── 📂 Operations & SLO/            (Level 1 - SRE/운영팀)
│   └── 📈 Operations & SLO
│       ├── SLO & Error Budget
│       │   ├── SLO 달성률 (99.9% 목표)
│       │   └── Error Budget 잔여량
│       ├── Burn Rate Alerts
│       │   ├── Fast Burn (1시간 윈도우)
│       │   └── Slow Burn (6시간 윈도우)
│       ├── Incident Management
│       │   ├── MTTD (Mean Time To Detect)
│       │   ├── MTTR (Mean Time To Resolve)
│       │   └── 월간 인시던트 수
│       └── Cost Analysis
│           ├── 월간 예상 비용
│           └── 일일 비용 추이
│
├── 📂 Application Lifecycle/       (Level 1 - DevOps/플랫폼팀)
│   └── 🔄 Application Lifecycle
│       ├── GitOps Pipeline Flow
│       │   └── Portal → Bitbucket → Jenkins → ArgoCD → K8s
│       ├── Jenkins CI Metrics
│       │   ├── Build 성공률/실패율
│       │   ├── Duration (p50, p95, p99)
│       │   └── 최근 빌드 테이블
│       ├── ArgoCD Deployment
│       │   ├── Sync 상태
│       │   ├── Out of Sync 수
│       │   └── Health Degraded
│       ├── Pod Readiness
│       │   ├── Startup Time 추이
│       │   └── Namespace별 준비 상태
│       └── Rollback & Config Drift
│           ├── 최근 롤백 히스토리
│           └── Drift 감지
│
└── 📂 Legacy Dashboards/           (V1 - 레거시, 마이그레이션 단계)
    ├── Main Navigation
    ├── GitOps Pipeline
    ├── Resource Capacity
    ├── Workload Execution
    ├── Data Pipeline
    ├── Optimization
    └── E2E Analytics
```

## 🔗 대시보드 링크 맵

### Executive Summary → Domain Dashboards

Executive Summary 대시보드에서 4개의 클릭 가능한 카드를 통해 각 도메인 대시보드로 이동할 수 있습니다:

| 카드 | UID | URL | 색상 테마 |
|------|-----|-----|-----------|
| 🏗️ Infrastructure Health | `dataops-infrastructure-v2` | `/d/dataops-infrastructure-v2/infrastructure-health?orgId=1` | Blue (#5B8DEE) |
| 📊 BigData Platform | `dataops-bigdata-v2` | `/d/dataops-bigdata-v2/bigdata-platform?orgId=1` | Teal (#4DB8A8) |
| 🔄 Application Lifecycle | `dataops-lifecycle-v2` | `/d/dataops-lifecycle-v2/application-lifecycle?orgId=1` | Orange (#F5A962) |
| 📈 Operations & SLO | `dataops-operations-v2` | `/d/dataops-operations-v2/operations-slo?orgId=1` | Purple (#8B5CF6) |

### Domain Dashboards → Executive Summary

모든 도메인 대시보드 헤더 우측 상단에 "← Executive" 버튼이 있습니다:

- **목적지**: Executive Summary
- **UID**: `dataops-executive-v2`
- **URL**: `/d/dataops-executive-v2/executive-summary?orgId=1`
- **위치**: 각 대시보드 헤더 패널 우측 상단

## 📋 폴더 메타데이터

| 폴더 이름 | Folder UID | 대시보드 수 | 대상 사용자 |
|-----------|------------|-------------|-------------|
| Executive Dashboard | `dataops-executive-folder` | 1 | CEO, CTO, 경영진 |
| Infrastructure | `dataops-infrastructure-folder` | 1 | Infrastructure Team, SRE |
| BigData Platform | `dataops-bigdata-folder` | 1 | BigData Engineers, Data Team |
| Operations & SLO | `dataops-operations-folder` | 1 | SRE, Operations Team |
| Application Lifecycle | `dataops-lifecycle-folder` | 1 | DevOps, Platform Team |
| Legacy Dashboards | `dataops-legacy-folder` | 7 | All (migration phase) |

## 🎨 색상 코딩 시스템

각 도메인은 일관된 색상 테마를 사용하여 시각적으로 구분됩니다:

### Primary Colors (도메인별)

```css
/* Infrastructure - Blue */
--infrastructure-color: #5B8DEE;
--infrastructure-bg: rgba(91, 141, 238, 0.15);
--infrastructure-border: rgba(91, 141, 238, 0.3);

/* BigData Platform - Teal */
--bigdata-color: #4DB8A8;
--bigdata-bg: rgba(77, 184, 168, 0.15);
--bigdata-border: rgba(77, 184, 168, 0.3);

/* Application Lifecycle - Orange */
--lifecycle-color: #F5A962;
--lifecycle-bg: rgba(245, 169, 98, 0.15);
--lifecycle-border: rgba(245, 169, 98, 0.3);

/* Operations & SLO - Purple */
--operations-color: #8B5CF6;
--operations-bg: rgba(139, 92, 246, 0.15);
--operations-border: rgba(139, 92, 246, 0.3);
```

### Semantic Colors (상태별)

```css
/* Success */
--success-color: #10B981;
--success-bg: rgba(16, 185, 129, 0.15);

/* Warning */
--warning-color: #F59E0B;
--warning-bg: rgba(245, 158, 11, 0.15);

/* Error */
--error-color: #EF4444;
--error-bg: rgba(239, 68, 68, 0.15);
```

## 🚀 사용자 여정 (User Journey)

### 경영진 (Executive)

1. **시작점**: Executive Summary 대시보드
   - 플랫폼 전체 상태를 한눈에 파악
   - Health Score, SLO 달성률, Alert 수, 비용 확인

2. **문제 발견 시**:
   - Critical Alerts 테이블에서 심각한 이슈 확인
   - 해당 도메인 카드 클릭하여 상세 대시보드로 이동

3. **상세 분석**:
   - 도메인 대시보드에서 근본 원인 파악
   - "← Executive" 버튼으로 언제든 복귀

### 인프라 운영팀 (Infrastructure Team)

1. **시작점**: Infrastructure Health 대시보드
   - 직접 URL 접근 또는 Grafana 폴더에서 선택
   - `/d/dataops-infrastructure-v2/infrastructure-health`

2. **모니터링 영역**:
   - 물리 서버: CPU 온도, 전력 소비, RAID 상태
   - 네트워크: 대역폭, 패킷 손실률
   - 스토리지: Longhorn, Ceph, Isilon, MinIO 상태
   - Kubernetes: Pod, Service 상태

3. **관련 대시보드로 이동**:
   - Executive Summary로 전체 상황 파악
   - Operations & SLO로 인시던트 현황 확인

### 빅데이터 엔지니어 (BigData Engineer)

1. **시작점**: BigData Platform 대시보드
   - `/d/dataops-bigdata-v2/bigdata-platform`

2. **모니터링 레이어**:
   - **Compute**: Spark Job 성공률, Executor 배치, GC Time
   - **Orchestration**: Airflow DAG 성공률, Scheduler 지연
   - **Query**: Trino 성능, Cache Hit Rate, Spill to Disk
   - **Data Layer**: Iceberg 테이블, Small Files 비율, Snapshot

3. **최적화 워크플로우**:
   - GC Time Ratio가 10% 초과 시 → Spark 메모리 튜닝
   - Small Files 비율이 30% 초과 시 → Iceberg Compaction 실행
   - Query Spill to Disk 증가 시 → Trino 메모리 증설

### DevOps/플랫폼 팀 (DevOps Team)

1. **시작점**: Application Lifecycle 대시보드
   - `/d/dataops-lifecycle-v2/application-lifecycle`

2. **배포 파이프라인 모니터링**:
   - GitOps Flow: Portal → Bitbucket → Jenkins → ArgoCD → K8s
   - Jenkins CI: Build 성공률, Duration, 최근 빌드 현황
   - ArgoCD: Sync 상태, Out of Sync, Health
   - Pod Readiness: Startup Time, Namespace별 준비 상태

3. **트러블슈팅**:
   - Build 실패 시 → Jenkins 빌드 로그 확인
   - Sync 실패 시 → ArgoCD UI 접속하여 Manifest 검증
   - Pod 시작 지연 시 → Resource 부족 여부 확인

### SRE/운영팀 (SRE Team)

1. **시작점**: Operations & SLO 대시보드
   - `/d/dataops-operations-v2/operations-slo`

2. **SLO 관리**:
   - **목표**: 99.9% 가용성 (월간 43.2분 다운타임 허용)
   - **Error Budget**: 실시간 잔여량 확인
   - **Burn Rate**: Fast (1h) / Slow (6h) 모니터링

3. **인시던트 대응**:
   - MTTD (Mean Time To Detect): 평균 탐지 시간
   - MTTR (Mean Time To Resolve): 평균 해결 시간
   - 최근 인시던트 히스토리 및 패턴 분석

4. **비용 최적화**:
   - 월간 예상 비용 추이 확인
   - 리소스 사용률과 비용 상관관계 분석

## 🔧 대시보드 접근 방법

### 방법 1: Grafana UI 폴더 탐색

1. Grafana 메인 페이지 접속: `http://grafana.k8s-cluster-01.miribit.lab`
2. 좌측 메뉴에서 **Dashboards** 클릭
3. 폴더 목록에서 원하는 폴더 선택:
   - `Executive Dashboard`
   - `Infrastructure`
   - `BigData Platform`
   - `Operations & SLO`
   - `Application Lifecycle`

### 방법 2: 직접 URL 접근

| 대시보드 | URL |
|----------|-----|
| Executive Summary | `http://grafana.k8s-cluster-01.miribit.lab/d/dataops-executive-v2/executive-summary` |
| Infrastructure Health | `http://grafana.k8s-cluster-01.miribit.lab/d/dataops-infrastructure-v2/infrastructure-health` |
| BigData Platform | `http://grafana.k8s-cluster-01.miribit.lab/d/dataops-bigdata-v2/bigdata-platform` |
| Operations & SLO | `http://grafana.k8s-cluster-01.miribit.lab/d/dataops-operations-v2/operations-slo` |
| Application Lifecycle | `http://grafana.k8s-cluster-01.miribit.lab/d/dataops-lifecycle-v2/application-lifecycle` |

### 방법 3: 검색 기능

1. Grafana 상단 검색바에 `DataOps` 입력
2. 모든 DataOps 관련 대시보드 표시
3. 원하는 대시보드 선택

### 방법 4: Executive Summary를 시작점으로 활용

1. Executive Summary 접속
2. 4개의 클릭 가능한 카드를 통해 도메인 대시보드로 이동
3. 각 도메인 대시보드 우측 상단 "← Executive" 버튼으로 복귀

## 📊 대시보드 버전 관리

### Version 3 (Current)

**릴리스 날짜**: 2025-11-07

**주요 변경사항**:
- ✅ 폴더 구조 추가 (`folder`, `folderUid` 필드)
- ✅ Executive Summary → Domain 링크 수정
- ✅ Domain → Executive Summary 복귀 버튼 추가
- ✅ URL에 `?orgId=1` 파라미터 추가
- ✅ 각 도메인별 색상 테마 통일

**업그레이드된 대시보드**:
- `00-executive-summary.yaml` → v3
- `01-infrastructure-health.yaml` → v3
- `02-bigdata-platform.yaml` → v3
- `03-operations-slo.yaml` → v3
- `04-application-lifecycle.yaml` → v3

### Version 2 (Previous)

**릴리스 날짜**: 2025-11-06

**주요 기능**:
- 눈이 편안한 저채도 색상 팔레트
- 베어메탈 인프라 메트릭 추가
- SLO/SLI 프레임워크 구현
- GitOps 파이프라인 시각화

### Version 1 (Legacy)

**릴리스 날짜**: 2025-11-05

**레거시 대시보드**:
- Main Navigation
- GitOps Pipeline
- Resource Capacity
- Workload Execution
- Data Pipeline
- Optimization
- E2E Analytics

## 🛠️ 관리자 가이드

### ConfigMap 위치

```bash
# V2 대시보드 (계층 구조)
/root/develop/thanos/deploy-new/overlays/cluster-01-central/kube-prometheus-stack/dashboards/dataops-v2/

# V1 대시보드 (레거시)
/root/develop/thanos/deploy-new/overlays/cluster-01-central/kube-prometheus-stack/dashboards/dataops/
```

### 대시보드 업데이트 절차

1. **ConfigMap YAML 수정**:
   ```bash
   vi /root/develop/thanos/deploy-new/overlays/cluster-01-central/kube-prometheus-stack/dashboards/dataops-v2/<dashboard>.yaml
   ```

2. **version 번호 증가**:
   ```json
   "version": 4,  // 이전 3에서 4로 증가
   ```

3. **ConfigMap 재배포**:
   ```bash
   kubectl apply -f <dashboard>.yaml
   ```

4. **Grafana Sidecar 로그 확인**:
   ```bash
   kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana -c grafana-sc-dashboard --tail=20
   ```

5. **브라우저에서 확인**:
   - Grafana 접속 후 Shift + F5 (강력 새로고침)
   - 또는 브라우저 캐시 삭제 후 재접속

### 폴더 구조 변경

폴더 이름이나 UID를 변경하려면:

1. **모든 관련 대시보드의 `folder` 및 `folderUid` 필드 수정**
2. **링크 URL 업데이트** (대시보드 간 링크가 있는 경우)
3. **동시에 모든 대시보드 재배포**

### 새 대시보드 추가

1. **ConfigMap 생성** (기존 대시보드를 템플릿으로 사용)
2. **필수 필드 설정**:
   - `uid`: 고유한 UID (예: `dataops-security-v2`)
   - `title`: 대시보드 제목
   - `folder`: 폴더 이름
   - `folderUid`: 폴더 UID
   - `tags`: 검색용 태그
3. **Label 추가**: `grafana_dashboard: "1"`
4. **배포 및 확인**

## 🔍 트러블슈팅

### 대시보드가 Grafana에 나타나지 않음

1. **ConfigMap 확인**:
   ```bash
   kubectl get configmap -n monitoring | grep grafana-dashboard-dataops
   ```

2. **Label 확인**:
   ```bash
   kubectl get configmap grafana-dashboard-dataops-executive-summary-v2 -n monitoring -o yaml | grep grafana_dashboard
   ```
   - 출력: `grafana_dashboard: "1"` 확인

3. **Sidecar 로그 확인**:
   ```bash
   kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana -c grafana-sc-dashboard --tail=50
   ```

4. **Grafana Pod 재시작** (최후의 수단):
   ```bash
   kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
   ```

### 링크가 작동하지 않음

1. **URL 형식 확인**:
   - 올바른 형식: `/d/<uid>/<slug>?orgId=1`
   - 예: `/d/dataops-executive-v2/executive-summary?orgId=1`

2. **UID 일치 확인**:
   - 링크의 UID와 실제 대시보드 UID가 일치하는지 확인

3. **브라우저 캐시 삭제**:
   - Shift + F5 또는 Ctrl + Shift + R

### 폴더가 표시되지 않음

- **참고**: Grafana의 `folder` 필드는 메타데이터일 뿐, Grafana UI의 실제 폴더 구조와는 별개입니다.
- Grafana UI에서 수동으로 폴더를 생성하고 대시보드를 이동시킬 수 있습니다.
- 또는 Grafana API를 사용하여 프로그래밍 방식으로 폴더를 생성할 수 있습니다.

## 📈 모니터링 모범 사례

### 일일 점검 (Daily Check)

1. **Executive Summary 확인** (5분):
   - Platform Health Score: 95% 이상 유지
   - Active Alerts: 5개 미만 유지
   - SLO 달성률: 99.9% 이상 유지

2. **Critical Alerts 대응** (필요시):
   - P0/P1 알림이 있으면 즉시 해당 도메인 대시보드로 이동
   - 근본 원인 파악 및 대응

### 주간 리뷰 (Weekly Review)

1. **Operations & SLO 대시보드** (15분):
   - Error Budget 소진율 확인
   - MTTD/MTTR 추이 분석
   - 인시던트 패턴 파악

2. **BigData Platform 대시보드** (15분):
   - Job 성공률 추이
   - Small Files 비율 확인 → 필요시 Compaction
   - Query 성능 이슈 파악

3. **Application Lifecycle 대시보드** (10분):
   - 배포 성공률 확인
   - Build Duration 추이 분석
   - Rollback 빈도 확인

### 월간 분석 (Monthly Analysis)

1. **전체 플랫폼 리뷰** (1시간):
   - Executive Summary의 월간 리소스 사용률 추이
   - 비용 최적화 기회 파악
   - Capacity Planning

2. **대시보드 최적화**:
   - 사용하지 않는 패널 제거
   - 새로운 메트릭 추가 검토
   - 사용자 피드백 반영

## 🎓 교육 자료

### 신입 사원 온보딩

1. **1주차**: Executive Summary 중심 교육
   - 전체 플랫폼 구조 이해
   - 주요 메트릭 의미 파악

2. **2주차**: 담당 도메인 대시보드 심화
   - Infrastructure, BigData, Lifecycle, Operations 중 택1
   - 메트릭 상세 설명
   - 트러블슈팅 시나리오

3. **3주차**: 실전 모니터링
   - 실제 인시던트 대응 연습
   - 대시보드 간 navigation 숙달

### 역할별 추천 대시보드

| 역할 | Primary Dashboard | Secondary Dashboards |
|------|-------------------|----------------------|
| CEO/CTO | Executive Summary | - |
| Infrastructure Team | Infrastructure Health | Executive Summary, Operations & SLO |
| BigData Engineer | BigData Platform | Executive Summary, Infrastructure Health |
| DevOps/Platform | Application Lifecycle | Executive Summary, Infrastructure Health |
| SRE | Operations & SLO | Infrastructure Health, BigData Platform, Lifecycle |
| Data Analyst | BigData Platform | - |

## 📞 지원 및 피드백

### 문제 보고

- **Slack**: `#dataops-monitoring`
- **Jira**: `DATAOPS` 프로젝트
- **On-call**: Pagerduty 통해 SRE 팀 호출

### 기능 요청

- **GitHub Issues**: `/root/develop/thanos` 리포지토리
- **정기 회의**: 매주 화요일 14:00 - DataOps 모니터링 리뷰

---

**Last Updated**: 2025-11-07
**Version**: 3.0
**Maintained by**: Platform Engineering Team
