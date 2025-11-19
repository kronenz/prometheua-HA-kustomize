바로 쓸 수 있게 스프린트 기반 일정/이슈 시트 형태로 정리해볼게요.
아래는:

1. 스프린트 캘린더(기간/목표)


2. Jira용 Epic 리스트


3. Story/Task 백로그 (스프린트/기간 매핑 포함)



형태로 작성했습니다.
복사해서 Excel/Google Sheet/Jira(테이블 뷰) 등에 그대로 쓰기 좋게 만들었어요.


---

1. 스프린트 캘린더 (2025-12-01 ~ 2026-02-28)

> 가정: 2주 단위 스프린트
마지막 주(2/23~2/28)는 버퍼 & 릴리즈/인수인계 용도로 사용



스프린트	기간	주요 목표 (Goal)	주요 Epic

Sprint 1	2025-12-01 ~ 2025-12-14	요구사항 수집, 현행 분석, 상위 Observability 아키텍처 초안	EPIC-1
Sprint 2	2025-12-15 ~ 2025-12-28	Metrics/Logs 상세 설계, GitOps Repo 구조/Argo CD 설계, Capacity 가정	EPIC-1,2
Sprint 3	2025-12-29 ~ 2026-01-11	Dev Observability 클러스터 구축(기본 Metrics 스택 + MinIO 연동), 일부 Workload 클러스터 Metric 수집 시작	EPIC-3
Sprint 4	2026-01-12 ~ 2026-01-25	Logs 스택(OpenSearch+Fluent Bit) 구축, GitOps/Argo CD 실제 적용, 기본 Grafana 대시보드/알람 PoC	EPIC-3
Sprint 5	2026-01-26 ~ 2026-02-08	네트워크/스토리지 영향 계측, Thanos/OpenSearch 최적화 전략 도출, Stage/Prod 확장 설계	EPIC-4
Sprint 6	2026-02-09 ~ 2026-02-22	최종 문서 통합(v1.0), Runbook/SLO 정의, 이해관계자 리뷰/피드백 반영	EPIC-4
Buffer	2026-02-23 ~ 2026-02-28	남은 이슈 처리, QA, 인수인계/교육, Jira 정리	EPIC-전체



---

2. Jira용 Epic 리스트 (Epic 이슈)

> Jira에서 “Epic” 타입으로 등록할 항목들입니다.
Key 는 예시이므로 실제 프로젝트 키에 맞게 변경해서 쓰면 됩니다. (예: OBS-EP1 등)



| Epic Key | Epic 이름                                      | 기간(타겟)                      | 설명 |
|----------|-----------------------------------------------|---------------------------------|------|
| EPIC-1   | Observability 요구사항 & 상위 아키텍처 설계     | 2025-12-01 ~ 2025-12-28        | 이해관계자 요구사항 수집, 현행 분석, 상위 Observability 아키텍처와 정책 정의 |
| EPIC-2   | Metrics/Logs 상세 설계 & GitOps 구조 설계       | 2025-12-15 ~ 2026-01-05        | Metrics/Logs 상세 구조, Thanos/MinIO, OpenSearch/Fluent Bit 설계, GitOps Repo/Argo CD 설계 |
| EPIC-3   | Dev Observability 클러스터 구축 & PoC          | 2025-12-29 ~ 2026-01-25        | Dev Observability 클러스터에 End-to-End Metrics/Logs 수집/시각화 PoC 구성 |
| EPIC-4   | 최적화 & Stage/Prod 확장 설계 & 문서화          | 2026-01-26 ~ 2026-02-22        | 네트워크/스토리지 최적화, Stage/Prod 확장 가이드, Runbook/SLO, 최종 문서 통합 |


---

3. Story / Task 백로그 시트 (Jira/Sheet용)

아래는 Story/Task 단위로 쪼갠 일정/업무 목록입니다.

Issue Type: Epic / Story / Task

Epic Link: 상위 Epic (EPIC-1 등)

Sprint: 배정할 스프린트 (예: Sprint 1)

Estimate(d): 대략적인 작업일(Man-day) 가정치 (자유 조정 가능)

Assignee: 담당자 미정 시 TBD 로 두고, 나중에 배정


> 👉 팁:

이 표를 Excel/Google Sheet로 옮긴 뒤 Jira CSV Import 규격에 맞게 컬럼명만 바꿔도 됩니다.

너무 길면 팀 상황에 맞게 과감히 줄이거나 나누면 됩니다.




| Key(예시) | Issue Type | Summary                                                        | Epic Link | Sprint   | Target 기간                     | Estimate(d) | Assignee | Description |
|----------|------------|----------------------------------------------------------------|-----------|----------|---------------------------------|-------------|----------|-------------|
| OBS-EP1  | Epic       | Observability 요구사항 & 상위 아키텍처 설계                     |           |          | 2025-12-01 ~ 2025-12-28        |             |          | Epic 정의용 |
| OBS-1    | Story      | 이해관계자 요구사항 수집 및 정리                               | EPIC-1    | Sprint 1 | 2025-12-01 ~ 2025-12-07        | 3           | TBD      | 서비스팀/인프라팀/클라이언트 인터뷰, 모니터링 요구사항 및 SLA/SLO 후보 정리 |
| OBS-2    | Task       | 서비스팀 인터뷰 및 요구사항 문서화                             | EPIC-1    | Sprint 1 | 2025-12-01 ~ 2025-12-03        | 1.5         | TBD      | 주 사용 지표, 장애 인지 방법, 대시보드 니즈 파악 |
| OBS-3    | Task       | 인프라/플랫폼 팀 인터뷰 및 요구사항 문서화                     | EPIC-1    | Sprint 1 | 2025-12-02 ~ 2025-12-04        | 1.5         | TBD      | 클러스터/노드/네트워크/스토리지 관점에서 필요 지표/로그 파악 |
| OBS-4    | Task       | 총괄 클라이언트 요구사항 및 보고 체계 요구 수집               | EPIC-1    | Sprint 1 | 2025-12-03 ~ 2025-12-05        | 1           | TBD      | SLA/월간 보고, 장애 리포트 양식 등 요구 정리 |
| OBS-5    | Task       | 요구사항 정리 문서 초안 작성 (Requirements-and-UseCases-v0.1) | EPIC-1    | Sprint 1 | 2025-12-05 ~ 2025-12-07        | 2           | TBD      | 인터뷰 결과 및 요구사항 정리 문서화 |

| OBS-6    | Story      | 현행 인프라/모니터링/네트워크/스토리지 구조 분석               | EPIC-1    | Sprint 1 | 2025-12-01 ~ 2025-12-10        | 3           | TBD      | 기존 BigData 서비스 및 모니터링, 네트워크/스토리지 구성 파악 |
| OBS-7    | Task       | 기존 모니터링 도구/지표/알람 현황 조사                        | EPIC-1    | Sprint 1 | 2025-12-01 ~ 2025-12-04        | 1.5         | TBD      | 사용중인 Prometheus, ELK, 기타 도구 조사 |
| OBS-8    | Task       | 현행 네트워크/스토리지(MinIO 포함) 구성 및 제약사항 파악      | EPIC-1    | Sprint 1 | 2025-12-04 ~ 2025-12-07        | 1.5         | TBD      | 대역폭, Latency, IOPS, 스토리지 정책 등 |
| OBS-9    | Task       | 현행 분석 결과를 정리한 요약 문서 작성                        | EPIC-1    | Sprint 1 | 2025-12-07 ~ 2025-12-10        | 1           | TBD      | 현행 분석 요약 문서 (선행 과제) |

| OBS-10   | Story      | 상위 Observability 아키텍처 초안 정의                          | EPIC-1    | Sprint 1 | 2025-12-08 ~ 2025-12-14        | 4           | TBD      | 전체 클러스터 구조 및 Observability 아키텍처 정의 |
| OBS-11   | Task       | 멀티 클러스터(Dev/Stage/Prod) 구성도 설계                     | EPIC-1    | Sprint 1 | 2025-12-08 ~ 2025-12-10        | 1.5         | TBD      | compute/storage/portal/observability 클러스터 간 관계도 |
| OBS-12   | Task       | Metrics/Logs 데이터 플로우 상위 설계                          | EPIC-1    | Sprint 1 | 2025-12-10 ~ 2025-12-12        | 1.5         | TBD      | Prometheus Agent, Thanos, Fluent Bit, OpenSearch, MinIO 간 흐름 |
| OBS-13   | Task       | GitOps/Argo CD 배포 패턴 상위 설계                            | EPIC-1    | Sprint 1 | 2025-12-12 ~ 2025-12-14        | 1           | TBD      | App of Apps, base/overlay, 환경별 배포 전략 |
| OBS-14   | Task       | Observability-HighLevel-Architecture-v0.1 문서 작성           | EPIC-1    | Sprint 1 | 2025-12-12 ~ 2025-12-14        | 1           | TBD      | 상위 아키텍처 문서 초안 |

| OBS-EP2  | Epic       | Metrics/Logs 상세 설계 & GitOps 구조 설계                      |           |          | 2025-12-15 ~ 2026-01-05        |             |          | Epic 정의용 |
| OBS-15   | Story      | Metrics 스택 상세 설계 (kube-prometheus-stack + Thanos)       | EPIC-2    | Sprint 2 | 2025-12-15 ~ 2025-12-21        | 4           | TBD      | values.yaml, Thanos 컴포넌트 설계, S3 연동 정책 |
| OBS-16   | Task       | kube-prometheus-stack values 설계 (Dev 기준)                  | EPIC-2    | Sprint 2 | 2025-12-15 ~ 2025-12-18        | 2           | TBD      | 스크레이프 인터벌, retention, exporter 설정 |
| OBS-17   | Task       | Thanos 구성 설계 (Agent/Querier/Store/Compactor)             | EPIC-2    | Sprint 2 | 2025-12-17 ~ 2025-12-20        | 2           | TBD      | 컴포넌트 수, 리소스, 포트, 인증 등 |
| OBS-18   | Task       | MinIO S3 버킷 구조 및 정책 설계 (Metrics용)                  | EPIC-2    | Sprint 2 | 2025-12-19 ~ 2025-12-21        | 1.5         | TBD      | 버킷명, retention 정책, lifecycle rule 후보 |

| OBS-19   | Story      | Logs 스택 상세 설계 (Fluent Bit + OpenSearch + S3 Snapshot)   | EPIC-2    | Sprint 2 | 2025-12-15 ~ 2025-12-23        | 4           | TBD      | 로그 수집/저장/스냅샷 상세 설계 |
| OBS-20   | Task       | Fluent Bit DaemonSet 기본 설정 및 필터/파서 설계             | EPIC-2    | Sprint 2 | 2025-12-15 ~ 2025-12-18        | 2           | TBD      | 네임스페이스/앱 기준 태깅, 불필요 로그 필터링 |
| OBS-21   | Task       | OpenSearch 인덱스/샤드/ILM 정책 설계                          | EPIC-2    | Sprint 2 | 2025-12-18 ~ 2025-12-21        | 2           | TBD      | Hot/Warm/Cold 설계, 롤오버 기준 |
| OBS-22   | Task       | OpenSearch Snapshot 및 MinIO 연동 전략 설계                   | EPIC-2    | Sprint 2 | 2025-12-21 ~ 2025-12-23        | 1.5         | TBD      | 스냅샷 주기/보관 기간 설계 |

| OBS-23   | Story      | GitOps Repo 구조 및 Argo CD 배포 구조 설계                    | EPIC-2    | Sprint 2 | 2025-12-20 ~ 2025-12-28        | 3           | TBD      | base/overlay, 환경별 오버레이 설계 |
| OBS-24   | Task       | Git Repo 디렉토리 구조 정의 (base/overlays/docs 등)          | EPIC-2    | Sprint 2 | 2025-12-20 ~ 2025-12-22        | 1.5         | TBD      | 실제 디렉토리 구조 설계 |
| OBS-25   | Task       | Argo CD App of Apps 패턴 설계 및 application 매니페스트 초안 | EPIC-2    | Sprint 2 | 2025-12-22 ~ 2025-12-25        | 1.5         | TBD      | 환경별 루트 App 설계 |
| OBS-26   | Task       | Capacity-and-Network-Estimation-v0.1 문서 작성               | EPIC-2    | Sprint 2 | 2025-12-25 ~ 2025-12-28        | 2           | TBD      | 예상 메트릭/로그량, S3/네트워크 가정 정리 |

| OBS-27   | Story      | Metrics/Logs 상세 설계 문서 v0.1 작성                         | EPIC-2    | Sprint 2 | 2025-12-23 ~ 2025-12-28        | 2           | TBD      | Metrics-Detail-Design, Logs-Detail-Design 초안 |
| OBS-28   | Task       | Metrics-Detail-Design-v0.1 문서 작성                         | EPIC-2    | Sprint 2 | 2025-12-23 ~ 2025-12-26        | 1.5         | TBD      | Prometheus/Thanos 설계 정리 |
| OBS-29   | Task       | Logs-Detail-Design-v0.1 문서 작성                            | EPIC-2    | Sprint 2 | 2025-12-24 ~ 2025-12-28        | 1.5         | TBD      | OpenSearch/Fluent Bit 설계 정리 |

| OBS-EP3  | Epic       | Dev Observability 클러스터 구축 & PoC                         |           |          | 2025-12-29 ~ 2026-01-25        |             |          | Epic 정의용 |
| OBS-30   | Story      | Dev Observability 클러스터 Metrics 스택 구축                 | EPIC-3    | Sprint 3 | 2025-12-29 ~ 2026-01-06        | 5           | TBD      | kube-prometheus-stack, Thanos, MinIO 연동 설치 |
| OBS-31   | Task       | dev-observability 클러스터에 kube-prometheus-stack 설치       | EPIC-3    | Sprint 3 | 2025-12-29 ~ 2026-01-01        | 2           | TBD      | Helm + kustomize로 배포 |
| OBS-32   | Task       | Thanos(Agent/Querier/Store/Compactor) 배포 및 기본 설정      | EPIC-3    | Sprint 3 | 2025-12-31 ~ 2026-01-03        | 2           | TBD      | S3 endpoint/크레덴셜 설정 포함 |
| OBS-33   | Task       | MinIO S3 버킷 생성 및 Thanos 연동 테스트                     | EPIC-3    | Sprint 3 | 2026-01-02 ~ 2026-01-06        | 1.5         | TBD      | 메트릭 블록 실제 업로드/조회 확인 |

| OBS-34   | Story      | Dev Workload 클러스터 Metrics 에이전트 설치                  | EPIC-3    | Sprint 3 | 2026-01-02 ~ 2026-01-11        | 4           | TBD      | dev-compute/storage/portal에 에이전트 설치 |
| OBS-35   | Task       | dev-compute 클러스터 node-exporter/kube-state-metrics 배포   | EPIC-3    | Sprint 3 | 2026-01-02 ~ 2026-01-05        | 1.5         | TBD      | 최소 모니터링 스택 설치 |
| OBS-36   | Task       | dev-storage 클러스터 Prometheus Agent 배포                   | EPIC-3    | Sprint 3 | 2026-01-04 ~ 2026-01-07        | 1.5         | TBD      | MinIO 관련 메트릭 포함 |
| OBS-37   | Task       | dev-portal 클러스터 Prometheus Agent + Exporter 배포         | EPIC-3    | Sprint 3 | 2026-01-06 ~ 2026-01-11        | 2           | TBD      | 포털 애플리케이션 지표 수집 |

| OBS-38   | Story      | Dev Observability Logs 스택 구축                             | EPIC-3    | Sprint 4 | 2026-01-12 ~ 2026-01-20        | 5           | TBD      | OpenSearch/Fluent Bit 배포 및 로그 수집 PoC |
| OBS-39   | Task       | dev-observability 클러스터에 OpenSearch 클러스터 배포        | EPIC-3    | Sprint 4 | 2026-01-12 ~ 2026-01-16        | 3           | TBD      | 소규모 노드, 기본 보안 설정 |
| OBS-40   | Task       | dev-observability에 OpenSearch Dashboards 배포               | EPIC-3    | Sprint 4 | 2026-01-15 ~ 2026-01-17        | 1           | TBD      | UI 접속 및 기본 대시보드 확인 |
| OBS-41   | Task       | dev-compute/storage/portal에 Fluent Bit DaemonSet 배포       | EPIC-3    | Sprint 4 | 2026-01-16 ~ 2026-01-20        | 2           | TBD      | 로그 전송 및 인덱스 생성 확인 |

| OBS-42   | Story      | GitOps/Argo CD 실제 적용 및 자동 배포 파이프라인 구축       | EPIC-3    | Sprint 4 | 2026-01-12 ~ 2026-01-25        | 4           | TBD      | Argo CD App 생성, Git 변경 → 배포 검증 |
| OBS-43   | Task       | Git Repo에 base/overlays 구조 적용 및 초기 manifest 반영    | EPIC-3    | Sprint 4 | 2026-01-12 ~ 2026-01-16        | 2           | TBD      | metrics/logs 컴포넌트별 overlay 구성 |
| OBS-44   | Task       | Argo CD에 dev 환경 App of Apps 구성                         | EPIC-3    | Sprint 4 | 2026-01-16 ~ 2026-01-20        | 2           | TBD      | dev-observability/dev-compute 등 구성 |
| OBS-45   | Task       | GitOps-Repo-Structure-and-Deployment-Flow-v0.1 문서 작성    | EPIC-3    | Sprint 4 | 2026-01-20 ~ 2026-01-25        | 2           | TBD      | 실제 적용 구조를 문서화 |

| OBS-46   | Story      | Grafana 대시보드/알람 PoC 및 Dev Observability E2E 검증     | EPIC-3    | Sprint 4 | 2026-01-18 ~ 2026-01-25        | 4           | TBD      | 주요 대시보드/알람 PoC |
| OBS-47   | Task       | Grafana 설치 및 Thanos/OpenSearch datasource 연결           | EPIC-3    | Sprint 4 | 2026-01-18 ~ 2026-01-20        | 1.5         | TBD      | 기본 연결 확인 |
| OBS-48   | Task       | Infra/Cluster/Namespace 기본 대시보드 템플릿 제작           | EPIC-3    | Sprint 4 | 2026-01-20 ~ 2026-01-23        | 2           | TBD      | 4~5개 기본 대시보드 |
| OBS-49   | Task       | 기본 알람룰 생성 및 알람 채널 연동 테스트                   | EPIC-3    | Sprint 4 | 2026-01-23 ~ 2026-01-25        | 1.5         | TBD      | Slack/메일 등 연동 |

| OBS-EP4  | Epic       | 최적화 & Stage/Prod 확장 설계 & 문서화                       |           |          | 2026-01-26 ~ 2026-02-22        |             |          | Epic 정의용 |
| OBS-50   | Story      | Thanos + MinIO S3 네트워크/스토리지 최적화 설계             | EPIC-4    | Sprint 5 | 2026-01-26 ~ 2026-02-02        | 4           | TBD      | Block 크기, Compaction, retention 최적화 |
| OBS-51   | Task       | Dev 환경에서 Thanos S3 트래픽/IO 패턴 계측                  | EPIC-4    | Sprint 5 | 2026-01-26 ~ 2026-01-29        | 2           | TBD      | 메트릭 수집 및 지표 정의 |
| OBS-52   | Task       | Scrape Interval/Retention/Downsampling 정책 튜닝안 도출     | EPIC-4    | Sprint 5 | 2026-01-29 ~ 2026-02-01        | 1.5         | TBD      | 성능/비용 밸런스 최적안 |
| OBS-53   | Task       | Thanos-and-S3-Optimization-Guide-v1.0 문서 작성             | EPIC-4    | Sprint 5 | 2026-02-01 ~ 2026-02-02        | 1.5         | TBD      | 최종 가이드 문서화 |

| OBS-54   | Story      | OpenSearch + Fluent Bit 로그 스택 최적화 및 ILM/스냅샷 확정 | EPIC-4    | Sprint 5 | 2026-01-26 ~ 2026-02-05        | 4           | TBD      | ILM 정책, Snapshot 전략 확정 |
| OBS-55   | Task       | Dev 환경 로그량/인덱스 사용량 분석                          | EPIC-4    | Sprint 5 | 2026-01-26 ~ 2026-01-29        | 1.5         | TBD      | 로그 패턴/인덱스 크기 분석 |
| OBS-56   | Task       | ILM(Hot/Warm/Cold) + Snapshot Policy 최종 설계             | EPIC-4    | Sprint 5 | 2026-01-29 ~ 2026-02-02        | 1.5         | TBD      | 운영 정책 확정 |
| OBS-57   | Task       | OpenSearch-ILM-and-Snapshot-Strategy-v1.0 문서 작성         | EPIC-4    | Sprint 5 | 2026-02-02 ~ 2026-02-05        | 1.5         | TBD      | 가이드 문서화 |

| OBS-58   | Story      | Stage/Prod 확장 설계 및 Capacity Planning                    | EPIC-4    | Sprint 5 | 2026-02-02 ~ 2026-02-08        | 3           | TBD      | Stage/Prod 구성을 위한 설계 |
| OBS-59   | Task       | Stage/Prod 노드 수/로그량/메트릭량 가정 및 산정             | EPIC-4    | Sprint 5 | 2026-02-02 ~ 2026-02-05        | 1.5         | TBD      | 예상 스케일 정의 |
| OBS-60   | Task       | Stage/Prod Observability 클러스터 사이징 가이드 작성        | EPIC-4    | Sprint 5 | 2026-02-05 ~ 2026-02-08        | 1.5         | TBD      | Stage-Prod-Scaling-Guide-v1.0 |

| OBS-61   | Story      | 운영 Runbook 및 SLO/알람 기준 정의                          | EPIC-4    | Sprint 6 | 2026-02-09 ~ 2026-02-16        | 4           | TBD      | Runbook/SLO 문서화 |
| OBS-62   | Task       | 주요 장애 시나리오 정리 및 대응 플로우 설계                 | EPIC-4    | Sprint 6 | 2026-02-09 ~ 2026-02-12        | 2           | TBD      | Thanos/OpenSearch/Fluent Bit/Grafana 장애 |
| OBS-63   | Task       | Observability Runbook 초안 작성                              | EPIC-4    | Sprint 6 | 2026-02-11 ~ 2026-02-14        | 1.5         | TBD      | Observability-Runbook-v1.0 |
| OBS-64   | Task       | SLO 후보 및 알람 기준 정의 (각 역할별)                      | EPIC-4    | Sprint 6 | 2026-02-13 ~ 2026-02-16        | 1.5         | TBD      | 서비스팀/인프라/클라이언트 관점 SLO 정의 |

| OBS-65   | Story      | 최종 문서 통합 및 이해관계자 리뷰/피드백 반영               | EPIC-4    | Sprint 6 | 2026-02-15 ~ 2026-02-22        | 4           | TBD      | 전체 문서 v1.0 통합 |
| OBS-66   | Task       | Observability-Architecture-and-Operation-v1.0 정리          | EPIC-4    | Sprint 6 | 2026-02-15 ~ 2026-02-18        | 2           | TBD      | 상위/상세 설계 문서 통합 |
| OBS-67   | Task       | 관련 가이드 문서(Optimization/Scaling/Runbook) 통합 링크 정리 | EPIC-4  | Sprint 6 | 2026-02-17 ~ 2026-02-20        | 1.5         | TBD      | 문서 구조/인덱스 정리 |
| OBS-68   | Task       | 이해관계자 리뷰 세션 진행 및 피드백 반영                    | EPIC-4    | Sprint 6 | 2026-02-20 ~ 2026-02-22        | 1.5         | TBD      | 리뷰 회의 및 수정 작업 |

| OBS-69   | Story      | 인수인계/교육 및 Jira 정리 (버퍼 기간 활용)                 | EPIC-전체 | Buffer   | 2026-02-23 ~ 2026-02-28        | 3           | TBD      | 최종 인수인계 및 스프린트 마무리 |
| OBS-70   | Task       | 팀 내부 교육 세션 (Observability 아키텍처/운영)             | EPIC-전체 | Buffer   | 2026-02-23 ~ 2026-02-26        | 2           | TBD      | 주요 개념/운영 방법 공유 |
| OBS-71   | Task       | Jira 이슈 정리 및 후속 과제(Technical Debt) 백로그 정리     | EPIC-전체 | Buffer   | 2026-02-26 ~ 2026-02-28        | 1           | TBD      | 남은 TODO/개선 포인트 백로그화 |


---

4. 이렇게 쓰면 편해요 (간단 활용 가이드)

1단계 – Epic 생성
Jira에서 EPIC-1~4에 해당하는 Epic들을 만들고, 위 테이블의 Epic Link 컬럼에 실제 Epic Key(예: OBS-23)를 매핑합니다.

2단계 – Story/Task 이슈 입력
위 테이블 내용을 기준으로 Story/Task를 생성하면서:

Sprint 컬럼을 활용해 스프린트 배정

Estimate(d)를 스토리 포인트나 시간으로 변환해서 입력


3단계 – 팀 상황에 맞춰 커스터마이징

인원/역할에 따라 Assignee 지정

너무 큰 Story는 쪼개고, 필요 없는 Task는 과감히 제거




---

원하면 “Jira CSV Import용 컬럼명에 딱 맞는 버전”(예: Summary, Issue Type, Description, Epic Link, Sprint, Story Points 등)으로도 다시 정리해 줄 수 있어요.
지금 버전은 읽기 편한 백로그 + 일정 관리 시트용이라고 보면 됩니다.
