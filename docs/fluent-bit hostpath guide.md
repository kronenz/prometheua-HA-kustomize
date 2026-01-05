아래는 서비스 애플리케이션 개발자가 Fluent Bit 로그 파이프라인 사용을 요청했을 때 제공하는 표준 사용자 가이드 문서 예시입니다.
요청하신 대로 hostPath 경로 정책, Fluent Bit 전체 로그 파이프라인 구성 (input / parser / filter / output), OpenSearch index & index pattern 정책, Grafana datasource 및 운영 정책, 작업 절차(온보딩 플로우) 까지 실무 기준으로 상세하게 작성했습니다.


---

Fluent Bit Log Pipeline 사용자 가이드

(Kubernetes 환경 · HostPath 기반 · OpenSearch 연동)


---

1. 문서 목적 및 범위

본 문서는 Kubernetes 환경에서 서비스 애플리케이션 로그를 Fluent Bit을 통해 수집하고 OpenSearch에 적재한 뒤 Grafana에서 시각화하기 위한 표준 로그 파이프라인 구성 가이드이다.

대상 독자

서비스 애플리케이션 개발자

플랫폼/인프라 엔지니어

SRE / DevOps 엔지니어


범위

애플리케이션 로그 파일 경로 및 네이밍 정책

Fluent Bit HostPath 기반 로그 수집 구조

Fluent Bit Input / Parser / Filter / Output 구성

OpenSearch Index 및 Index Pattern 정책

Grafana Datasource 및 Dashboard 정책

서비스 로그 온보딩 작업 절차



---

2. 전체 로그 파이프라인 아키텍처

[Application Pod]
   └─ logs → /var/log/<namespace>/<policy>-YYYY-MM-dd.log
        ↓ (hostPath mount)
[Fluent Bit DaemonSet]
        ↓
[OpenSearch Cluster]
        ↓
[Grafana]


---

3. 애플리케이션 로그 경로 및 파일 정책 (필수)

3.1 로그 저장 경로 정책

애플리케이션은 반드시 아래 경로 규칙을 준수해야 한다.

/var/log/<namespace>/<policy>-YYYY-MM-dd.log

항목 설명

항목	설명

<namespace>	Kubernetes Namespace 이름
<policy>	로그 정책 식별자 (서비스명 또는 도메인명)
YYYY-MM-dd	로그 생성 날짜


예시

/var/log/payment/payment-api-2026-01-05.log
/var/log/auth/auth-server-2026-01-05.log


---

3.2 로그 로테이션 정책 (권장)

일 단위 파일 분리

애플리케이션 레벨에서 날짜 기준 파일 생성

Fluent Bit는 파일 단위 tailing 수행


> ⚠️ logrotate 사용 시 copytruncate 방식은 권장하지 않음




---

4. Kubernetes HostPath 설정 가이드

4.1 애플리케이션 Pod 설정 예시

volumeMounts:
  - name: app-log
    mountPath: /var/log
volumes:
  - name: app-log
    hostPath:
      path: /var/log
      type: Directory

> 모든 애플리케이션 Pod는 /var/log 를 hostPath로 마운트해야 함




---

4.2 Fluent Bit DaemonSet HostPath 설정

volumeMounts:
  - name: varlog
    mountPath: /var/log
    readOnly: true
volumes:
  - name: varlog
    hostPath:
      path: /var/log


---

5. Fluent Bit 구성 가이드


---

5.1 Input 설정 (Tail)

[INPUT]
    Name              tail
    Path              /var/log/*/*.log
    Exclude_Path      *.gz
    Tag               kube.log.*
    Refresh_Interval  5
    Rotate_Wait       30
    Mem_Buf_Limit     100MB
    Skip_Long_Lines   On


---

5.2 Parser 설정

5.2.1 JSON 로그 (권장)

[PARSER]
    Name        json_parser
    Format      json
    Time_Key    timestamp
    Time_Format %Y-%m-%dT%H:%M:%S.%LZ

5.2.2 Plain Text 로그 (Fallback)

[PARSER]
    Name   plain_parser
    Format regex
    Regex  ^(?<message>.*)$


---

5.3 Filter 설정

5.3.1 Kubernetes Metadata 추가

[FILTER]
    Name                kubernetes
    Match               kube.log.*
    Kube_Tag_Prefix     kube.log.
    Merge_Log           On
    Keep_Log            Off
    Annotations         Off


---

5.3.2 Namespace / Service 식별 필드 추가

[FILTER]
    Name    modify
    Match   kube.log.*
    Add     cluster_name   prod-cluster


---

5.4 Output 설정 (OpenSearch)

[OUTPUT]
    Name            opensearch
    Match           kube.log.*
    Host            opensearch.logging.svc
    Port            9200
    Index           logs-${kubernetes['namespace_name']}
    Logstash_Format On
    Logstash_Prefix app-log
    Replace_Dots    On
    Retry_Limit     False


---

6. OpenSearch Index 정책


---

6.1 Index Naming Convention

logs-<namespace>-YYYY.MM.dd

예시

logs-payment-2026.01.05
logs-auth-2026.01.05


---

6.2 Index Template 정책

{
  "index_patterns": ["logs-*"],
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  },
  "mappings": {
    "dynamic": true,
    "properties": {
      "@timestamp": { "type": "date" },
      "level": { "type": "keyword" },
      "message": { "type": "text" },
      "service": { "type": "keyword" }
    }
  }
}


---

6.3 Index Lifecycle (ILM) 정책 (권장)

단계	기간

Hot	7일
Warm	14일
Delete	30일



---

7. Grafana 구성 가이드


---

7.1 OpenSearch Datasource 설정

항목	값

Type	OpenSearch
URL	http://opensearch.logging.svc:9200
Index Pattern	logs-*
Time Field	@timestamp



---

7.2 Dashboard 구성 정책

Namespace 기준 필터 필수

Service / Pod Name 필터 제공

Log Level 별 색상 규칙 적용



---

8. 서비스 로그 온보딩 작업 절차


---

8.1 개발자 작업

1. 로그 파일 경로 정책 준수


2. JSON 로그 포맷 적용


3. /var/log/<namespace>/ 하위에 로그 생성




---

8.2 플랫폼 운영자 작업

1. Fluent Bit Input Path 확인


2. Parser 매칭 여부 검증


3. OpenSearch Index 생성 확인


4. Grafana Dashboard 연결




---

8.3 검증 체크리스트

[ ] 로그 파일 생성 확인

[ ] Fluent Bit Pod 정상 동작

[ ] OpenSearch Index 생성

[ ] Grafana 로그 조회 가능



---

9. 운영 시 주의사항

로그 폭주 서비스는 별도 Index 분리 검토

대용량 로그는 sampling 또는 drop filter 적용

개인정보/민감정보 로그 금지



---

10. 참고 사항

Fluent Bit 버전: 2.x 이상 권장

OpenSearch TLS 적용 환경에서는 인증 설정 필요

Namespace 단위 접근제어(RBAC) 권장



---

필요하시면 다음도 추가로 제공할 수 있습니다.

📄 사내 표준 템플릿용 Fluent Bit ConfigMap

📊 Grafana 표준 로그 대시보드 JSON

🔐 멀티 테넌시(OpenSearch + Grafana) 권한 정책

🚦 로그 레벨/샘플링 정책 문서


원하시는 방향 알려주시면 이어서 확장해 드릴게요.