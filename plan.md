DataOps Observability 모니터링 플랫폼

업무 정의 및 업무 계획 (2025-12-01 ~ 2026-02-28)


---

1. 목적 및 배경

1.1 목적

BigData Service 의 k8s 전환에 앞서, 여러 개의 Kubernetes 클러스터(dev / stage / prod)에서 발생하는 Metric / Log 를 중앙의 Observability 클러스터로 집약하고,
서비스팀 / 플랫폼 관리자 / 총괄 클라이언트가 공통된 관점에서 클러스터 상태, 자원 상황, 서비스 상태, 스케줄링, 가용 자원, Health 등을 관찰할 수 있는 표준 모니터링 플랫폼을 마련한다.

이를 위해:

kustomize + Helm 기반의 표준 모니터링 스택 템플릿을 정의하고

GitOps + Argo CD 로 모든 클러스터에 일관된 방식으로 배포/관리하며

Observability 클러스터에서

kube-prometheus-stack + Thanos (Prometheus Agent)

OpenSearch + Fluent Bit
를 통해 Metrics / Logs 를 중앙 수집 및 시각화하고


Storage 클러스터의 MinIO S3 에 저장되는

Thanos Metric 데이터

OpenSearch Cold Data
에 대한 네트워크 트래픽 및 I/O 최적화 전략을 수립·검증하는 것이 핵심 목표이다.



> 본 문서는 2025-12-01 ~ 2026-02-28 기간 동안, 신규 클러스터(stage/prod) 구성 전에 수행해야 할 업무 정의와 세부 계획 + 문서 체계를 정리한다.




---

2. 목표 및 성공 기준

2.1 기술적 목표

1. Observability 클러스터 아키텍처 설계 완료

kube-prometheus-stack + Thanos(Agent 모드) + OpenSearch + Fluent Bit + Grafana 를 이용한 End-to-End Observability 아키텍처 정의

Dev 환경에서 참조 아키텍처(Reference Implementation) 구축



2. 멀티 클러스터 모니터링 구성

Dev 기준:

Observability 클러스터: Full 스택 (Thanos + OpenSearch)

Compute / Storage / Portal 클러스터:
Prometheus Agent, node-exporter, kube-state-metrics, Fluent Bit 등의 Minimal 모니터링 에이전트 구성


Stage / Prod 확장을 고려한 스케일링/구성 원칙 수립



3. 네트워크 및 Storage 영향도 분석 & 최적화

Thanos → MinIO S3 Metric 저장 패턴 분석

OpenSearch Cold Data → MinIO S3 연동 전략 정의

네트워크 트래픽, 스토리지 사용량, IOPS 관점에서 최적화 가이드 도출



4. GitOps 기반 배포 파이프라인 표준화

kustomize + Helm Chart 조합을 활용한 클러스터별/환경별 모니터링 스택 템플릿

Argo CD 를 통한 자동 동기화 전략 (App of Apps 패턴 등) 수립



5. 모니터링 대시보드 및 알람 표준 템플릿

서비스팀, 인프라팀, 클라이언트용 역할 기반(RBAC 기반) Grafana 대시보드

주요 지표(Cluster, Node, Namespace, 애플리케이션, Job, Batch, Capacity 등)에 대한 공통 템플릿 정의

Alertmanager / OpenSearch Alerting 등과 연계한 알람 정책 가이드라인 수립




2.2 비즈니스/운영적 목표

1. 원활한 k8s 전환

BigData Service 의 On-prem / Legacy 구성을 k8s 로 옮길 때 가시성 부족으로 인한 리스크 최소화



2. 운영 효율화

팀별로 제각각 사용하는 모니터링 도구를 줄이고, 공통 플랫폼으로 통합



3. 총괄 클라이언트 보고 체계 정립

SLA, 자원 사용 추이, 장애 이력, 용량 계획 관련 정보를 Grafana / 보고 템플릿으로 표준화



4. Dev → Stage → Prod 전환시 재사용성 극대화

Dev 환경에서 설계/구현한 구조와 코드/템플릿을 Stage/Prod 에 최소 변경으로 확장 가능하게 설계




2.3 성공 판단 기준 (Success Criteria)

[ ] Dev Observability 클러스터에서

모든 Dev 클러스터(Compute / Storage / Portal / Observability) Metric/Log 수집 성공

평균 Scrape/수집 실패율 < 1%


[ ] Grafana 대시보드 템플릿 최소 10개 이상 (Infra 4+, K8s 4+, Service 2+)

[ ] Thanos / OpenSearch / MinIO 연동으로 Cold Data 보존 및 조회 확인

[ ] 네트워크 및 S3 I/O 관점에서 예상 비용·부하 시뮬레이션 + 최적화 방안 문서화

[ ] 운영/장애 대응 Runbook 및 SLO/알람 기준 문서화 완료



---

3. 범위 (Scope) / 비범위 (Out of Scope)

3.1 Scope (이번 업무 기간 내)

1. Dev 단계 Observability 인프라 구축


2. Stage/Prod 대비 아키텍처 설계 및 기준 정의


3. Metrics / Logs 중심의 Observability


4. Network / S3 스토리지 영향도 분석 및 최적화 설계


5. GitOps/Argo CD 기반 배포 구조 설계 및 Dev 환경 적용


6. Grafana 대시보드/알람 템플릿 설계


7. 운영 가이드/Runbook, 장애 대응 프로세스 초안 작성



3.2 Out of Scope (향후 단계에서)

Stage/Prod 실제 클러스터 구축 및 Observability 스택 실 배포

APM / Tracing (예: Tempo, Jaeger) 본격 도입 (단, 확장 여지는 설계 단계에 반영)

FinOps(비용 최적화) 상세 분석 및 실제 비용 리포팅 자동화

SSO/IDP 연동 세부 구현 (개념적 설계 수준까지만 포함)



---

4. 용어 및 구성 요소 정의

Observability 클러스터
: 중심 모니터링 인프라가 배치된 전담 k8s 클러스터
(kube-prometheus-stack, Thanos, OpenSearch, Fluent Bit, Grafana, Alertmanager 등)

Workload 클러스터 (Compute / Storage / Portal 등)
: 실제 서비스/데이터 워크로드가 동작하는 클러스터들
(여기에는 최소 모니터링 에이전트만 설치)

Metrics 스택

Prometheus (kube-prometheus-stack)

Thanos (Agent / Querier / Store Gateway / Compactor)

MinIO S3 (Metric 장기 보관)


Logs 스택

Fluent Bit : 각 클러스터에서 로그 shipper

OpenSearch : 로그 인덱스 저장/검색

MinIO S3 : OpenSearch 스냅샷 및 cold data 용


GitOps

kustomize + Helm 조합으로 설정 관리

Argo CD 를 통해 각 클러스터에 선언적 배포 및 동기화




---

5. 전체 아키텍처 개요

5.1 환경별 구성

Dev 환경 (현재 중점 대상)

클러스터:

dev-compute

dev-storage (MinIO S3 포함)

dev-portal

dev-observability


Observability:

dev-observability 클러스터에 Full stack

나머지 dev-* 클러스터는 Minimal Agent



Stage / Prod 환경 (설계만, 실 배포는 향후)

동일한 패턴:

stage-compute, stage-storage, stage-portal, stage-observability

prod-compute, prod-storage, prod-portal, prod-observability


Dev 에서 검증된 템플릿을 거의 그대로 재사용



5.2 Metrics 경로 (High-level)

1. Workload 클러스터

node-exporter, kube-state-metrics, cAdvisor, 앱 Exporter 등이 Metric 제공

Prometheus Agent (또는 Prometheus + Thanos Sidecar) 가 scrape

Thanos Agent 가 Observability 클러스터의 Thanos Receive 또는 Querier/Store 로 전송



2. Observability 클러스터

Thanos Receive/Store-Gateway/Compactor가 MinIO S3 에 Metric Block 저장

Thanos Querier 가 MinIO + 각 Store를 통합 조회

Grafana 가 Thanos Querier 를 datasource 로 사용




5.3 Logs 경로 (High-level)

1. Workload 클러스터

Fluent Bit DaemonSet 이 Pod / Node 로그 수집

Observability 클러스터의 OpenSearch Ingest/API 로 전송



2. Observability 클러스터

OpenSearch Cluster (Hot/Warm/Cold 노드 설계)

로그 인덱스 관리 및 검색

일정 기간 이후 Cold 인덱스 또는 Snapshot 을 MinIO S3 로 이전

Grafana, Kibana/OpenSearch Dashboards 로 시각화





---

6. 네트워크 & Storage 최적화 관점 설계

6.1 고려 포인트

1. Thanos ↔ MinIO S3

Metric Block 저장/조회 시 발생하는 S3 트래픽, API 호출 수, IOPS

Compactor 가 수행하는 Block 병합/다운샘플링 시 S3 I/O 급증 가능성



2. OpenSearch Cold Data ↔ MinIO S3

Snapshot/Restore 트래픽

Cold Tier 를 실제 S3 기반으로 둘 경우 네트워크 및 Latency



3. Workload 클러스터 ↔ Observability 클러스터

Metrics Remote Write / gRPC 통신

Fluent Bit 의 Log 전송(HTTP/HTTPS) 트래픽



4. 클러스터 간 네트워크 Topology

동일 VPC/Subnet 인지, Cross-AZ 인지, On-prem ↔ Cloud 인지

네트워크 대역폭, 지연 시간, 비용




6.2 Thanos 최적화 방향 (개념)

Scrape Interval & Retention 설계

핵심 시스템: 15s ~ 30s

일반 서비스: 30s ~ 60s

Retention:

Prometheus Local: 6~24h 정도로 짧게

Thanos/MinIO: 6~12개월 이상 (Downsampling: 5m / 1h 등)



Thanos Compactor / Store-Gateway Scaling

Compactor: I/O Burst 반영, 작업 시간대 (off-peak) 조정

Store-Gateway: 자주 조회되는 최근 데이터에 대해 로컬 캐시 활용


Block Size / Upload 설정

인터벌, 샤딩 등을 통해 S3에 쓰는 Block 크기 최적화

너무 잦은 작은 Block 업로드 → S3 요청 수 증가 → 비용 및 부하 증가



6.3 OpenSearch 최적화 방향 (개념)

Index Lifecycle Management (ILM)

Hot (14주) → Cold (S3 Snapshot) 단계 설계

Stage/Prod 에서의 로그량을 가정하여 인덱스 롤오버 기준(Rollover by size / time) 정의


Shards & Replicas 전략

Dev: 최소 샤드/복제, 클러스터 헬스 검증 목적

Stage/Prod: 샤드 수 산정 공식(일 로그량, retention 기준)에 따라 설계


Fluent Bit 최적화

Batch 크기, flush interval 조절

불필요한 필드 제거, 필터에서의 과도한 정규식 사용 지양




---

7. GitOps / 배포 구조 설계

7.1 Repo 구조 제안 (예시)

observability-gitops/
├─ base/
│  ├─ monitoring/
│  │  ├─ kube-prometheus-stack/   # Helm chart values base
│  │  ├─ thanos/                  # Thanos 공통 설정
│  │  ├─ fluent-bit/              # Fluent Bit base 설정
│  │  ├─ opensearch/              # OpenSearch 공통 설정
│  │  └─ grafana/                 # 공통 Dashboard, Datasource
│  └─ argocd/
│     └─ applications/            # App of Apps 등 공통 Argo CD App
├─ overlays/
│  ├─ dev/
│  │  ├─ dev-observability/
│  │  ├─ dev-compute/
│  │  ├─ dev-storage/
│  │  └─ dev-portal/
│  ├─ stage/
│  │  ├─ stage-observability/
│  │  └─ ...
│  └─ prod/
│     ├─ prod-observability/
│     └─ ...
└─ docs/
   ├─ architecture/
   ├─ runbook/
   └─ dashboard-spec/

base: 모든 환경에서 공통으로 사용하는 Helm values, kustomize base

overlays: 환경별/클러스터별 오버레이

예: dev-observability 에서는 OpenSearch 리소스를 축소, Retention 짧게

prod-observability 에서는 고가용성, 백업 정책 강화



7.2 Argo CD 전략

App of Apps 패턴

각 환경(dev/stage/prod)에 대한 최상위 App 정의

각 환경 App 이 해당 환경에 필요한 모니터링 컴포넌트 App 들을 포함


Sync 정책

Observability 클러스터: Auto-sync + PR 승인 후 반영

Workload 클러스터: Auto-sync 가능하나, 특정 네임스페이스만 허용




---

8. Grafana / 대시보드 및 알람 설계

8.1 대상 사용자 그룹

1. 서비스팀

서비스별 Latency, Error Rate, Throughput (RED metrics)

Pod/Deployment 수준의 상태, HPA 지표



2. 플랫폼/인프라 관리자

클러스터 Health (API 서버, etcd, Controller, Scheduler)

Node 리소스(CPU, 메모리, 디스크, 네트워크)

스케줄링 실패, Pending Pod, Evicted Pod, OOMKilled



3. 총괄 클라이언트

SLA 관점: 서비스 가용률, 주요 장애 이력, Capacity/리소스 사용 추이

상위 레벨 요약: “이번 달 장애 건수 / 평균 복구 시간(MTTR) / 미해결 이슈”




8.2 대시보드 템플릿 예시

Cluster Overview

클러스터별 CPU/Memory/Pod 사용률

Control Plane 컴포넌트 상태

Node 상태 / Condition 요약


Namespace / 서비스별 리소스 사용

Namespace별 CPU/메모리/Pod 수

네임스페이스 별 Quota 사용률


Job/Batch 파이프라인 모니터링 (BigData 특화)

CronJob 성공/실패, 수행 시간

데이터 파이프라인 단계별 처리가능량/지연 시간


Storage / MinIO / S3 연동 상태

Thanos S3 오류율

OpenSearch Snapshot 성공률

S3 요청량, 지연 시간 지표(가능할 경우)



8.3 알람 정책 (초안)

인프라 레벨

Node NotReady 상태 지속 (>5분)

API 서버 에러율 증가

etcd 지연 시간 및 QoS 이상


자원 레벨

CPU/Memory 사용률 임계치 초과 (예: 80% 이상 지속)

디스크 사용량 80% 이상 / Inode 부족


서비스 레벨

HTTP 5xx 비율 상승

Latency P95/P99 기준 초과


스토리지/Observability 레벨

Thanos Compactor 실패

MinIO S3 Write/Read 오류 증가

OpenSearch 클러스터 상태 RED/YELLOW




---

9. 보안, 권한, 멀티 테넌시 고려

Grafana RBAC

팀별 Folder / Dashboard 권한 분리

클라이언트용 readonly 계정/Role


OpenSearch 멀티테넌시

인덱스/패턴을 기준으로 팀별 접근 제어


Metric/Log 데이터 보안

민감 정보가 Metrics/Logs 로 유출되지 않도록 개발 가이드 제공

Fluent Bit 필터 단계에서 민감 필드 마스킹 기능 고려


GitOps 접근 제어

Git Repo 에 대한 Branch 보호, PR 리뷰 필수

Argo CD 에서도 RBAC 설정으로 특정 App 수정 권한 제한




---

10. 리스크 및 대응 전략

리스크	설명	대응 전략

Observability 클러스터 단일 장애점	중앙 관제 장애시 전체 모니터링 불가	HA 구성, Multi-AZ 고려, 필수 메트릭은 각 클러스터 로컬 Prometheus 로도 일정 기간 조회 가능하게 구성
S3 / MinIO 장애 시 Thanos / OpenSearch 영향	Block/Snapshot 쓰기 실패	Retry/Backoff, S3 장애 알람, 단기 로컬 스토리지 버퍼링 전략 검토
로그/메트릭 과다 수집	네트워크 및 스토리지 비용 폭증	Metric/Log 화이트리스트 기반 수집, 샘플링/필터링 정책 수립
Stage/Prod 확장시 설계 부족	Dev 기준 설계가 확장성 부족	초기에 Stage/Prod 수준의 데이터량/노드 수를 가정하고 Capacity Planning 문서화



---

11. 기간별 업무 계획 (2025-12-01 ~ 2026-02-28)

> 약 3개월을 4개 Phase 로 나누어 진행 (주 단위는 상황에 따라 조정 가능)



Phase 1. 요구사항 정리 & 아키텍처 설계 (2025-12-01 ~ 2025-12-15)

목표: 기술·비즈니스 요구사항을 명확히 하고, 상위 아키텍처 및 기준 정책 수립

주요 Task

1. 이해관계자 인터뷰

서비스팀 / 인프라팀 / 클라이언트 담당자

모니터링 요구사항, SLA/SLO, 보고 요구사항 수집



2. 현행 인프라/모니터링 현황 분석

기존 BigData/Legacy 모니터링 도구 파악

현재 네트워크/스토리지 구성 및 제한사항 분석



3. 상위 아키텍처 초안 작성

Observability / Workload 클러스터 구성도

Thanos + OpenSearch + MinIO 연동 구조

GitOps/Argo CD 구조 초안



4. 주요 정책 정의

환경별(Dev/Stage/Prod) 격리 수준

Metrics/Logs retention 기준, 샘플링 전략 방향



5. 산출물

Observability-HighLevel-Architecture-v0.1.md

Requirements-and-UseCases-v0.1.md





---

Phase 2. 상세 설계 및 GitOps 구조 설계 (2025-12-16 ~ 2026-01-05)

목표: Dev 기준 상세 설계 및 GitOps Repository 구조 정의

주요 Task

1. Metrics 스택 상세 설계

kube-prometheus-stack 구성 (values.yaml 설계)

Thanos 컴포넌트별 역할/리소스/구성 파라미터 정의

MinIO 버킷 구조, 정책 설계 (Metric / Log Snapshot 분리 등)



2. Logs 스택 상세 설계

Fluent Bit DaemonSet 구성, 파서/필터 전략 설계

OpenSearch 노드 구조 (Hot/Warm/Cold 후보), 인덱스/ILM 설계 초안

MinIO snapshot 대상/주기 정의



3. GitOps Repo 상세 설계

base/overlays 구조 구체화

환경별/클러스터별 변수/오버레이 설계

Argo CD Application 매니페스트 설계



4. 네트워크/성능 가정 및 설계

Dev/Stage/Prod 별 예상 Metric 시계열 수, Log TPS 추정

그에 따른 S3 트래픽/스토리지 대략적 산출 (가정치 기반)



5. 산출물

Metrics-Detail-Design-v0.1.md

Logs-Detail-Design-v0.1.md

GitOps-Repo-Structure-and-Deployment-Flow-v0.1.md

Capacity-and-Network-Estimation-v0.1.md





---

Phase 3. Dev Observability 구축 & PoC (2026-01-06 ~ 2026-02-05)

목표: Dev 환경에 Observability 클러스터 및 Minimal Agent 설치, End-to-End 흐름 검증

주요 Task

1. Observability 클러스터 구축 (dev-observability)

kube-prometheus-stack 설치 (Helm + kustomize)

Thanos 구성 (Agent/Querier/Store/Compactor)

OpenSearch Cluster(소규모) 구축

MinIO S3 버킷 생성 및 연동



2. Workload 클러스터 모니터링 에이전트 배포

dev-compute / dev-storage / dev-portal 에

node-exporter, kube-state-metrics, Prometheus Agent 설치

Fluent Bit 설치, 로그 전송 테스트




3. GitOps / Argo CD 적용

Git Repo 에 base/overlays 정리

Argo CD 에 environment별 App 등록

Git 변경 → 자동 배포/Sync 확인



4. Grafana / Dashboard / Alerting PoC

주요 대시보드 템플릿 생성 및 검증

기본 알람 규칙 설정 및 알람 채널(Slack/메일 등) 테스트



5. 네트워크/스토리지 영향 1차 측정

Dev 환경에서 실제 Metric/Log 수집량 측정

Thanos/MinIO, OpenSearch/MinIO 간 트래픽 간략 계측 및 패턴 분석



6. 산출물

Dev-Observability-Implementation-Guide-v0.1.md

Grafana-Dashboard-List-and-Definition-v0.1.md

Initial-Network-and-Storage-Observation-v0.1.md





---

Phase 4. 최적화 설계, 문서 정리 및 Stage/Prod 가이드 (2026-02-06 ~ 2026-02-28)

목표: Dev PoC 결과를 반영하여 최적화 전략 수립, 문서화 및 Stage/Prod 확장 가이드 완성

주요 Task

1. 네트워크 / S3 I/O 최적화 전략 구체화

Thanos Block 크기, Compaction 주기 조정안

Scrape Interval / Retention / Downsampling 정책 확정

OpenSearch ILM 정책(Hot/Warm/Cold + Snapshot) 확정



2. Stage/Prod 확장 시나리오 설계

예상 노드 수 / 로그량 / 메트릭량 기반 자원 산정

Stage/Prod Observability 클러스터 사이즈 및 구성 제안



3. 운영 프로세스 / Runbook 정리

장애 유형별 진단 플로우

Node 추가, 클러스터 추가 시 모니터링 스택 확장 절차

Backup / Restore / Disaster Recovery 시나리오 개요



4. 문서 통합 및 리뷰

전체 설계 문서 통합 버전(v1.0) 정리

이해관계자 리뷰 및 피드백 반영



5. 최종 산출물

Observability-Architecture-and-Operation-v1.0.md

Thanos-and-S3-Optimization-Guide-v1.0.md

OpenSearch-ILM-and-Snapshot-Strategy-v1.0.md

Stage-Prod-Scaling-Guide-v1.0.md

Operations-Runbook-and-SLO-v1.0.md





---

12. 문서 구성 템플릿 제안

업무를 체계적으로 수행하기 위해, 아래와 같은 문서 템플릿 구조를 제안한다. 실제 문서는 위에서 언급한 산출물 이름에 맞춰 생성하고, 공통적으로 다음 목차를 활용할 수 있다.

12.1 아키텍처 설계서 공통 템플릿

# {문서명} (예: Observability-Architecture-and-Operation)

## 1. 문서 개요
- 목적
- 대상 독자
- 문서 범위

## 2. 배경 및 요구사항
- 비즈니스 요구사항
- 기술적 요구사항
- 제약사항 (네트워크, 보안, 조직 구조 등)

## 3. 상위 아키텍처
- 전체 구성도
- 주요 컴포넌트 설명
- 데이터 흐름 (Metrics / Logs / Traces)

## 4. 상세 아키텍처
- Metrics 스택 상세
- Logs 스택 상세
- Storage (MinIO S3) 연동 구조
- GitOps / 배포 구조

## 5. 환경별 설계 차이 (Dev / Stage / Prod)
- 클러스터 구성 차이
- 리소스/스펙 차이
- Retention / ILM 정책 차이

## 6. 보안 및 권한 설계
- 인증/인가 구조
- 데이터 보호 방안
- RBAC 전략

## 7. 성능 및 용량 계획
- 데이터량 가정
- 네트워크/스토리지/CPU/메모리 추정
- 스케일링 전략

## 8. 운영 및 장애 대응
- 운영 시나리오
- 장애 유형 및 대응 플로우
- 백업/복구 개요

## 9. 향후 확장 방향
- Stage/Prod 적용 계획
- 추가 Observability (Tracing, APM 등) 로드맵

## 10. 부록
- 용어 정리
- 주요 설정 예시 (values.yaml, kustomization.yaml 등)

12.2 Runbook 템플릿

# Observability Runbook

## 1. 목적
운영자가 모니터링 플랫폼에서 발생하는 이슈에 신속하게 대응할 수 있도록 표준 절차 제공

## 2. 공통 기준
- 장애 등급 정의 (Severity)
- 대응 시간(SLA), 복구 시간 목표(MTTR) 기준

## 3. 장애 시나리오별 대응

### 3.1 Thanos 관련 장애
- 증상 (예: Thanos Querier 조회 실패, S3 Write 에러)
- 즉각 조치
- 근본 원인 분석 체크리스트
- 재발 방지 방안

### 3.2 OpenSearch 관련 장애
- 클러스터 상태 RED/YELLOW
- 인덱스 할당 실패
- 성능 저하 (검색 지연 등)

### 3.3 Fluent Bit / 로그 수집 장애
- 로그 수집 중단/지연
- 특정 네임스페이스 로그 미수집

### 3.4 Grafana / 대시보드 장애
- 로그인 불가
- 데이터 소스 오류

## 4. 운영 작업 절차
- 신규 클러스터 모니터링 스택 추가 절차
- 버전 업그레이드 절차
- 백업/복구 절차(개요)

## 5. 연락망 및 Escalation
- 담당자/팀 연락처
- Escalation 단계

12.3 Dashboard 정의 문서 템플릿

# Grafana Dashboard Definition

## 1. 개요
- 대시보드 명
- 대상 사용자(서비스팀/인프라팀/클라이언트 등)
- 주요 목적

## 2. 데이터 소스
- Thanos / Prometheus / OpenSearch 등

## 3. 패널 정의
- 패널 목록
  - 제목
  - 쿼리
  - 단위/축
  - 임계치 색상/경고 기준

## 4. Drill-down 구조
- 상위 대시보드 → 하위 대시보드 링크 구조

## 5. 권한 및 공유 범위
- 읽기/편집 권한
- 팀/폴더 구조


---

13. 마무리 코멘트 (전문가 관점에서의 보완 포인트)

Dev 단계에서 실제 Stage/Prod 수준의 데이터량을 “가짜 부하”로 시뮬레이션해 보는 것이 중요하다.

예: Load Generator 로 메트릭/로그를 일부러 많이 발생시켜 Thanos/MinIO, OpenSearch/MinIO 의 병목을 미리 확인.


Observability 클러스터를 단일 장애점으로 두지 않기 위해, 고가용성(HA) 구성과 DR 계획을 최소 개념 수준으로라도 정의해두는 것이 좋다.

Stage/Prod 확장 시, 단순히 Dev 구성을 복사하는 것이 아니라, 클러스터 수 × 노드 수 × 로그/메트릭 밀도에 따라

샤드 수

Prometheus/Thanos 구성

OpenSearch 노드 수
를 수식 기반으로 산정하는 Capacity Planning을 작성해 두면 향후 매우 큰 도움이 된다.


GitOps 를 초기에 잘 설계하면, 환경/클러스터 추가 시 인력이 거의 들지 않는 구조를 만들 수 있으므로,
base/overlay 구조와 Argo CD App-of-Apps 패턴을 이번 기간 안에 제대로 정리하는 것이 핵심 투자 포인트다.



---

필요하다면 위 문서를 실제로 나눠서 쓸 수 있도록

Observability-HighLevel-Architecture 초안

Runbook 초안

GitOps Repo 구조 예시(manifest)
같은 것을 각각 작성해 줄 수도 있어.
지금 이 전체 문서는 “업무 정의 + 업무 계획 + 문서 구성 체계”의 마스터 초안으로 생각하면 된다.
