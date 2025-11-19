아래 문서는 이미 아키텍처 설계 및 Metric/Log 스택 배포가 완료된 상태를 전제로,
그 이후 단계인:

🔔 알람(Alarm) 설계 & 자동화(Ops as Code)

👩‍💻 사용자 가이드 (서비스팀 / 인프라팀 / 클라이언트)

🛠 운영 가이드 (Runbook, 운영 프로세스)

📦 네트워크·스토리지 최적화 관점 운영 방안

🕵️ Audit Log 구성 및 활용 가이드


에만 집중해서 정리한 “운영상/실무 중심 문서”입니다.
(Grafana 인증/인가, 대시보드 설계/구성, 기본 Metric/Log 배포 내용은 의도적으로 제외했습니다.)


---

DataOps Observability 운영 및 알람/감사 체계 설계서

(아키텍처/배포 완료 이후 단계)


---

1. 문서 개요

1.1 전제 조건

Observability 클러스터에 다음 스택이 이미 배포 완료됨

Metrics: kube-prometheus-stack + Thanos (Agent/Store/Querier/Compactor)

Logs: OpenSearch + Fluent Bit

Storage: MinIO S3 (Thanos Metric Block + OpenSearch Snapshot/Cold Data)


각 Dev 클러스터(Compute / Storage / Portal / Observability)에
최소 모니터링 에이전트가 설치되어 Metrics/Logs가 Observability 클러스터로 수집되는 상태

Grafana 설치는 되어 있으나, 인증/인가, 대시보드 구성 세부 내용은 본 문서 범위에서 제외


1.2 이 문서의 목표

1. 알람 설계 및 자동화(Ops)

Prometheus/Thanos, OpenSearch 기준 알람 룰 설계

GitOps 기반 “알람 as Code” 구조 정립

알람 라우팅 / Silence / 유지보수 프로세스 정리



2. 사용자/운영 가이드

서비스팀 / 인프라팀 / 클라이언트가 알람 및 모니터링을 사용하는 방법 정리

운영팀이 평시 및 장애 시 어떤 절차로 대응할지 Runbook 제공



3. 네트워크·스토리지 최적화 운영 방안

Thanos ↔ MinIO, OpenSearch ↔ MinIO 간 I/O 및 트래픽 최적화

샘플링, retention, downsampling 전략 운영 관점 가이드



4. Audit Log 구성 및 가이드

Kubernetes / Observability 스택 / GitOps / OpenSearch 보안 등
주요 컴포넌트의 감사 로그 수집 및 활용 방법 정리





---

2. 알람(Alarm) 설계 및 자동화(Ops)

2.1 설계 원칙

1. 역할 기반 설계 (Role-based)

인프라팀 / 서비스팀 / 클라이언트별로 관심 알람 / 심각도 / 표현 방식 분리



2. 중복/노이즈 최소화

한 장애에 대해 여러 알람이 “폭탄”처럼 터지지 않도록 룰/라우팅 설계



3. 알람은 “행동 가능한 정보”

알람마다 반드시 “어떤 액션을 취해야 하는지”가 Runbook에 연결되도록 설계



4. 알람 as Code

모든 알람 설정은 GitRepo에서 선언적으로 관리

리뷰/테스트 후 Argo CD 통해 배포 (수동 콘솔 편집 금지 원칙)





---

2.2 알람 구성 요소 개요

PrometheusRule (kube-prometheus-stack)

Kubernetes 리소스로 저장되는 Prometheus 알람 룰 (RecordingRule / AlertingRule)


Alertmanager

알람 라우팅/그룹핑/쓰기 채널 관리 (Slack, 이메일 등)


OpenSearch Alerting (또는 ISM)

로그 기반 알람 (Error 로그 비율, 특정 에러 패턴, 보안 이벤트 등)


Notification 채널

Slack 채널, 이메일, Webhook 등




---

2.3 알람 분류 체계

2.3.1 심각도(Severity)

CRITICAL (P1)

즉시 장애 대응 필요, 서비스 중단/중대한 SLA 위반 가능

예: Kubernetes API Down, 다수의 Node NotReady, Storage 장애, 핵심 서비스 5xx 폭증


MAJOR (P2)

단기간 내 서비스 장애로 이어질 가능성, 빠른 조치 필요

예: 특정 노드 CPU/Memory/디스크 사용률 90% 지속, 주요 Job 반복 실패


MINOR (P3)

추세/경고 수준, 일일/주간 리포트에서 다루는 수준

예: 디스크 사용량 75% 이상, Namespace별 리소스 사용량 증가 추세



2.3.2 영역별 알람

1. 인프라/클러스터 레벨

Node Ready 상태, Pod Pending/Evicted, Control Plane 상태, etcd Latency 등



2. 리소스/Capacity 레벨

CPU/Memory/Storage 사용률, S3 용량/요청 실패율



3. 서비스/애플리케이션 레벨

HTTP 에러율/Latency, Retry 폭증, Job 실패



4. Observability 스택 내부

Thanos Compactor 오류, Store-Gateway down, OpenSearch 클러스터 상태 RED/YELLOW



5. 보안/감사(Audit) 레벨

비정상 로그인 시도, 비인가 사용자/계정의 설정 변경 시도 등





---

2.4 Prometheus 알람 설계 (Metrics 기반)

2.4.1 PrometheusRule 관리 구조

Git Repo 예시:

observability-gitops/
└─ base/
   └─ monitoring/
      └─ alert-rules/
         ├─ infra-rules.yaml
         ├─ service-rules.yaml
         ├─ observability-rules.yaml
         └─ capacity-rules.yaml

각 파일은 PrometheusRule CRD 를 포함

환경별 차이는 overlays/{env}/alert-rules 에서
labels, threshold, enabled/disabled 정도만 patch


2.4.2 주요 알람 예시 (개념)

Node NotReady

조건: kube_node_status_condition{condition="Ready", status="true"} == 0 5분 이상

Severity: CRITICAL

라우팅: 인프라팀 on-call


Pod Pending/Evicted 증가

조건: 일정 시간 이상 Pending, Evicted Pod 수가 Threshold 초과

Severity: MAJOR

라우팅: 인프라팀 / 해당 Namespace 소유 팀


Cluster Capacity

조건: CPU/메모리 사용률 80% 이상 15분 이상, Pod 용량 임계치 근접

Severity: MAJOR

라우팅: 인프라팀, 월간 리포트에도 반영


Thanos Store/Compactor 상태

조건: up{job="thanos-store"} == 0 3분 이상, thanos_compact_downsampling_failures_total 증가

Severity: CRITICAL (Store), MAJOR (Compactor Failures)




---

2.5 Alertmanager 구성 및 자동화

2.5.1 Alertmanager 설정 as Code

Git Repo 내 alertmanager/ 디렉토리에서 ConfigMap 또는 Secret 템플릿 관리

환경별 route, receiver 차이는 overlay 로 patch


구조 예시:

observability-gitops/
└─ base/
   └─ monitoring/
      └─ alertmanager/
         └─ alertmanager-config.yaml    # 공통 기본값
└─ overlays/
   └─ dev/
      └─ alertmanager/
         └─ patch-dev.yaml              # dev용 route/receiver 설정 patch

2.5.2 라우팅 정책 개요

기본 라우트

모든 알람은 먼저 공통 루트로 들어가서 Severity 및 라벨을 기준으로 분기


예시 라우팅

severity=critical → #oncall-infra Slack + 이메일

severity=major & team=service-X → #svc-X-alerts

severity=minor → 주간 요약 리포트 또는 낮은 우선순위 채널



2.5.3 Silence / Maintenance 윈도우

신규 배포/점검 시 불필요 알람 폭주 방지를 위해:

GitOps 기반으로 정기 점검 시간대 라벨을 route 조건에 반영하거나

운영팀이 Alertmanager UI에서 Silence 생성하되,
사유/기간/범위를 Runbook에 기록하는 프로세스 수립




---

2.6 OpenSearch 기반 로그 알람

2.6.1 대상

특정 로그 패턴 (예: “ERROR”, “Exception”, “Unauthorized”, “Failed to connect…”)

보안 이벤트 (비정상 로그인, 권한 실패 다수 발생)

데이터 파이프라인 Job 로그에서 “failed”, “timeout” 등 키워드


2.6.2 Alert 정의 전략

인덱스 패턴 기준 (예: logs-app-*, logs-system-*, audit-*)

Alert 조건:

특정 기간 내 에러 로그 카운트 > N

비정상 패턴 (특정 IP/계정에서 연속 실패 등)


Notification:

OpenSearch Alert → Webhook → Alertmanager → Slack
또는 Slack/E-mail 직접 연동




---

2.7 알람 자동화(Ops) 플로우 요약

1. 개발/운영자가 알람 변경요청 이슈 등록


2. Git Repo 내 알람 정의 파일 수정 (PR 생성)


3. 코드 리뷰 & 승인


4. Argo CD가 cluster로 config Sync


5. Alertmanager / PrometheusRule 자동 재적용


6. 테스트 알람 발생 여부 확인


7. 변경 내용 Runbook/문서에 반영




---

3. 사용자 가이드 (알람 및 관찰 관점)

3.1 대상 사용자

1. 서비스팀

자신이 담당하는 Namespace/서비스에 대한 알람과 지표 확인

장애 시 1차 분석 및 인프라팀과 커뮤니케이션



2. 인프라/플랫폼팀

클러스터/노드/Observability 스택/스토리지 등 전반 담당

알람 룰/구성 변경 권한 보유



3. 총괄 클라이언트

SLA/SLO, 장애 이력, Capacity 추이 등의 상위 지표와 리포트 확인





---

3.2 알람 수신 및 반응 프로세스(사용자 관점)

3.2.1 공통

1. 알람 수신 (Slack/메일 등)


2. 알람 메시지 내 포함 정보 확인:

summary, description, severity, team, namespace, runbook_url 등



3. 알람에 링크된 Runbook 문서 또는 대시보드 URL 접속


4. Runbook에서 “초기 확인 단계” 수행



3.2.2 서비스팀 절차 예시

알람 예: HTTP 5xx Rate 이상 (service=portal-api)

1. Portal API 대시보드 접속


2. 최근 배포 여부 확인 (리릴리즈 로그)


3. Pod 상태, 에러 로그 확인


4. 서비스 코드/설정 문제로 판단되면 롤백 또는 설정 수정


5. 인프라 이슈 의심 시 인프라팀에 escalation




3.2.3 인프라팀 절차 예시

알람 예: Node NotReady, Thanos Compactor Failures

1. 관련 노드/서비스 상태 확인 (kubectl, 대시보드)


2. 하드웨어/네트워크/스토리지 상태 점검


3. 필요 시 노드 드레인, 재할당, 스케일아웃


4. 관찰 결과 및 조치 내용을 티켓/위키에 기록





---

4. 운영 가이드 (Runbook / 프로세스)

4.1 평시 운영 체크리스트

4.1.1 일일 점검 (Daily)

Observability 클러스터 상태 확인

Thanos / OpenSearch / MinIO Pod 상태


전일 기준 CRITICAL / MAJOR 알람 목록 확인

MinIO S3 용량 및 에러율 확인

OpenSearch 클러스터 상태 (GREEN/RED) 체크


4.1.2 주간 점검 (Weekly)

주요 Capacity 추이 검토 (CPU/Memory/Storage/네트워크)

알람 룰 노이즈 여부 평가 (False Positive, 중복 알람)

새로 추가된 클러스터/Namespace 모니터링 상태 확인

Audit Log 인덱스/보존 상태 점검



---

4.2 장애 대응(Run Incident) 프로세스

1. 알람 감지

알람 채널에서 CRITICAL/MAJOR 감지



2. 규모 및 영향도 판단

영향 서비스/고객, 범위, 현재 상태 파악



3. Runbook 따라 초기 조치

관련 Runbook의 “초기 진단 단계” 수행



4. 에스컬레이션

서비스팀 ↔ 인프라팀 간 역할에 따라 상향 보고



5. 원인 분석 & 임시 복구

롤백, 스케일 조정, 재시작 등



6. 사후 분석 (Postmortem)

root cause, 개선 과제, 알람 룰 개선 여부 점검



7. 문서화 & 공유

장애 리포트 생성, 관련자 공유





---

4.3 변경 관리(Change Management)

알람 룰, Observability 설정 변경은 반드시 티켓+PR을 동반

주요 변경 사항 예:

Scrape Interval 변경

Retention 조정

신규 알람 룰 추가/삭제

OpenSearch ILM 정책 변경


변경 후:

작은 범위에서 테스트 → 점진 rollout

변경 전/후 지표 비교 및 알람 노이즈 확인




---

5. 네트워크·스토리지 최적화 운영 가이드

이미 스택은 구축되어 있으므로, 운영하면서 조정해야 할 항목들을 중심으로 정리합니다.

5.1 Thanos ↔ MinIO S3

5.1.1 Scrape Interval & Retention 조정

기본 원칙:

핵심 시스템: 1560초

Prometheus Local Retention: 6~24시간

Thanos Storage Retention: 6~12개월 (Downsampling 적용)


운영 측면:

네트워크/스토리지 사용량 모니터링 후, 필요시 Interval/Retention 상향/하향 조정

변경은 values.yaml 또는 별도 config로 관리 후 GitOps 배포



5.1.2 Thanos Compactor/Store 운영

Compactor:

I/O 부하가 큰 작업이므로, 야간/비업무 시간대 중심으로 동작하도록 리소스/옵션 조정

Compaction 실패 알람을 반드시 설정해서 장기 보존 데이터 품질 확보


Store-Gateway:

자주 조회되는 “최근 X일”에 대해 캐시 설정 검토

Pod 개수/리소스를 Stage/Prod 대비 상향 설계




---

5.2 OpenSearch ↔ MinIO S3

5.2.1 ILM 정책 운영

Hot/Warm/Cold 레이어:

Hot: 최근 1~3일

Warm: 1~4주

Cold: Snapshot/S3 (읽기 드문 과거 데이터)


운영 포인트:

인덱스 크기 및 샤드 수를 주기적으로 확인하고, ILM 정책이 제대로 롤오버되는지 점검

Cold 데이터 조회가 정말 필요한지, 빈도/비용을 감안해 정책 튜닝



5.2.2 Fluent Bit 최적화

Batch/Flush Interval 조정으로 네트워크 트래픽 균형

필터에서 불필요 필드 제거 → 인덱스 크기 감소

특정 Namespace/Pod 로그는 샘플링 또는 별도 인덱스 전략 적용 가능



---

6. Audit Log 구성 및 가이드

6.1 Audit 대상 정의

1. Kubernetes 레벨

API 서버 Audit Log (리소스 생성/수정/삭제, 권한 실패 등)



2. Observability 스택

OpenSearch 보안/감사 로그 (로그 조회, 인덱스 삭제, 설정 변경 등)

Thanos/Prometheus 설정 변경 자체는 주로 GitOps & k8s audit에서 추적



3. GitOps / CI/CD

Git Commit/PR (누가 어떤 manifest를 언제 변경했는지)

Argo CD Audit (누가 어떤 App을 Sync/rollback 했는지)



4. 접근 제어 시스템

SSO/IDP 로그(별도 시스템이라면 링크만 명시)





---

6.2 Audit Log 수집 구조

6.2.1 Kubernetes Audit Log

각 클러스터의 kube-apiserver에서 Audit Log를 특정 파일/Endpoint로 출력

Fluent Bit로 Audit Log 파일 수집 → Observability 클러스터의 OpenSearch audit-k8s-* 인덱스로 전송

필수 필드:

user.username, user.groups, verb, resource, namespace, responseStatus.code, sourceIPs 등



6.2.2 OpenSearch Audit

OpenSearch Security Plugin 또는 Audit 플러그인 활성화

Audit 로그를 별도의 파일 또는 인덱스 (audit-opensearch-*)로 분리

Fluent Bit 또는 OpenSearch 내부 설정으로 audit-opensearch-* 인덱스에 수집


6.2.3 GitOps / Argo CD Audit

Git:

Git의 commit history / PR 기록이 곧 audit의 근간 → 별도 로그 수집보다는 정책/운영으로 관리


Argo CD:

Argo CD 서버 로그에서 Sync/rollback, user action 로그를 수집

Fluent Bit를 통해 audit-argocd-* 인덱스로 전송




---

6.3 Audit Log 인덱스/보존 정책

Audit 로그는 보안/규제 요구에 따라 보존 기간이 다를 수 있음

예: 기본 6개월~1년, 규제가 있으면 더 길게


OpenSearch ILM 정책:

Hot(1주) → Warm(1~3개월) → Cold(S3 Snapshot)


Audit 인덱스는 용량 증가가 빠를 수 있으므로 정기적인 용량 점검 및 샤드 수 조정이 필요



---

6.4 Audit Log 활용 시나리오

1. 권한 남용/오용 조사

“누가, 언제, 어디서, 어떤 리소스를 바꿨는가?” 질문에 대한 답을 제공

K8s + Argo CD + Git + OpenSearch Audit를 조합하여 시나리오 재구성



2. 장애/사고 분석

장애 발생 직전, 어떤 설정 변경이나 배포가 있었는지 추적

예: 특정 ConfigMap 수정 → 재시작 → 장애



3. 보안 점검/정기 감사

주기적으로 Audit 인덱스를 검색하여 위험 신호 탐지

예: 반복되는 권한 실패, 다수의 실패 로그인, 비업무시간대의 위험 작업





---

6.5 Audit Log 조회 및 분석 가이드(사용자 관점)

보통 인프라/보안 담당자가 대상


1. OpenSearch Dashboards (또는 Kibana equiv.) 접속


2. audit-* 인덱스 패턴 선택


3. 시간 범위 지정 (사건 발생 추정 시간 ± N분/시간)


4. 필터:

user.username:"xxx" 또는 verb:delete

resource:"deployments" 등



5. 결과를 기반으로 사건 타임라인 정리:

예: userA 가 namespaceB 의 deploymentC 를 10:05에 수정
→ 10:07에 Pod 재시작 / CrashLoopBackOff 발생



6. 필요 시 Export/Report 기능 사용하여 보고서 첨부




---

7. 문서 및 Runbook 구조 제안 (관계 정리)

실제 문서를 나눠 작성할 때는 다음처럼 구조화할 수 있습니다.

Observability-Alarm-and-Operations-Guide.md

알람 설계 원칙, Alertmanager/PrometheusRule 구조, 운영 프로세스


Observability-User-Guide-ServiceTeam.md

서비스팀 관점 알람 확인 방법, 자주 보는 지표, self-check 플로우


Observability-User-Guide-InfraTeam.md

인프라/Observability 전담팀 상세 가이드


Observability-Runbook-Incidents.md

장애 유형별 대응 플로우 (Node, Thanos, OpenSearch, S3, 네트워크 등)


Observability-Audit-Log-Guide.md

Audit 수집 구조, 조회 예시, 보안 점검 절차



각 알람 Rule에는 가능한 한 Runbook URL을 라벨로 추가해서
알람 → Runbook 으로 자연스럽게 이어지도록 하는 것이 핵심입니다.


---

여기까지가 아키텍처/배포/대시보드/인증 부분을 제외한 “운영·알람·감사·최적화” 전체 설계/가이드 초안이에요.

원하면 다음처럼도 도와줄 수 있어요:

실제 PrometheusRule / Alertmanager / OpenSearch Alert의 YAML 템플릿 예시를 작성

Audit Log 인덱스 쿼리 예시(KQL/DSL) 샘플 정리

팀별로 따로 나눠 쓸 수 있는 User Guide skeleton 문서까지 쪼개서 작성


어떤 부분을 먼저 “진짜 운영 문서”로 구체화하고 싶은지 말해주면, 그 부분부터 바로 글자만 바꿔 쓰면 될 수준으로 다듬어 줄게.
