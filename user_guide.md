# Observability Platform 사용자 가이드 작성 요구사항

## 목적
베어메탈 Kubernetes 환경에서 운영되는 Observability 플랫폼(Metric + Log)에 대한 **개발자 대상 사용자 가이드** 작성

> **대상 독자**: Kubernetes 및 DevOps 경험이 제한적인 애플리케이션 개발자

## 현재 인프라 구성

### Metric 시스템
- **스택**: kube-prometheus-stack
- **수집 메커니즘**: Prometheus Operator가 ServiceMonitor/PodMonitor CRD를 감지하여 자동 수집, 특히 operator가 label을 감지하여 자동감지
- **레이블링 전략**:
  - `app`: 애플리케이션 이름
  - `service-team`: 서비스 팀 식별자
  - `namespace`: 네임스페이스 기반 팀 구분
  - `monitor` : dataops-metric (모니터링 대상 설정)
- **목적**: 팀/앱 단위로 메트릭 필터링 가능

### Log 시스템
- **스택**: OpenSearch + Fluent-Bit
- **수집 플로우**:
  1. Fluent-Bit가 노드의 컨테이너 로그를 tail 방식으로 수집
  2. Lua 필터를 통한 전처리 및 가공
  3. OpenSearch Index Pattern으로 전송
- **레이블링**: Kubernetes 레이블(`app`, `service-team`)을 통한 필터링
- **로그 레벨**: debug, info, warn, error, audit
- **주요 요구사항**:
  - **로그 드롭 방지**: 대량 로그 발생 시에도 손실 없이 수집
  - **Multiline 지원**: Java stacktrace, exception 등이 잘리지 않고 수집
  - **선택적 수집**: 필요한 로그만 수집 가능하도록 설정

## 문서 작성 요구사항

### 1. 문서 구조
다음 순서로 사용자 여정(User Journey)을 구성:

```
1. 아키텍처 이해
   ├─ Metric 수집 아키텍처 (Mermaid 다이어그램)
   └─ Log 수집 아키텍처 (Mermaid 다이어그램)

2. 배포 전 설정 (Pre-Deployment)
   ├─ Metric 수집을 위한 설정
   │  ├─ ServiceMonitor/PodMonitor 작성법
   │  ├─ 필수 레이블 설정 (app, service-team)
   │  └─ 설정 예제 (YAML)
   └─ Log 수집을 위한 설정
      ├─ Log Format 가이드
      │  ├─ JSON 형식 권장사항
      │  ├─ Log Level 설정 (debug/info/warn/error/audit)
      │  ├─ Multiline 처리 (Java exception, stacktrace)
      │  └─ 커스텀 태그 추가
      └─ 설정 예제 (애플리케이션 코드)

3. 배포 방법
   ├─ GitOps 기반 배포 (ArgoCD)
   ├─ Jenkins CI/CD 파이프라인 배포
   └─ kubectl을 통한 직접 배포

4. 배포 후 검증 (Post-Deployment)
   ├─ Metric 수집 확인
   │  ├─ kubectl로 ServiceMonitor/PodMonitor 리소스 확인
   │  ├─ Prometheus UI에서 Target 상태 확인
   │  └─ Grafana에서 메트릭 쿼리 확인
   └─ Log 수집 확인
      ├─ kubectl logs로 컨테이너 로그 확인
      ├─ Fluent-Bit 전처리 상태 확인
      └─ OpenSearch/Grafana에서 로그 검색 확인

5. 트러블슈팅
   ├─ Metric 수집 실패 케이스
   │  ├─ ServiceMonitor가 감지되지 않는 경우
   │  ├─ 레이블이 누락된 경우
   │  └─ Prometheus Target이 Down 상태인 경우
   └─ Log 수집 실패 케이스
      ├─ 로그가 OpenSearch에 나타나지 않는 경우
      ├─ Multiline 로그가 잘리는 경우
      └─ 로그 드롭이 발생하는 경우

6. FAQ 및 Best Practices
```

### 2. 필수 포함 요소

#### Mermaid 다이어그램
- **Metric 수집 흐름**:
  - Application → Metrics Endpoint → ServiceMonitor/PodMonitor → Prometheus Operator → Prometheus → Thanos → Grafana
- **Log 수집 흐름**:
  - Application → Container Log → Fluent-Bit (tail) → Lua Filter → OpenSearch → Grafana

#### 코드 예제
- ServiceMonitor/PodMonitor YAML (주석 포함)
- 애플리케이션 로그 포맷 예제 (JSON, Multiline)
- kubectl 검증 명령어
- PromQL 쿼리 예제
- OpenSearch 쿼리 예제

#### 스크린샷 예시 위치
- Prometheus Targets 페이지
- Grafana Explore에서 메트릭 조회
- OpenSearch Discover에서 로그 조회

### 3. 문서 작성 원칙

#### 명확성
- 각 단계마다 **왜(Why)** 필요한지 설명
- 전문 용어는 첫 사용 시 한글 해석 제공
- 예: "ServiceMonitor(서비스 모니터 - Prometheus가 메트릭을 수집할 대상을 정의하는 Kubernetes 리소스)"

#### 상세성
- 모든 명령어에 대한 출력 예제 포함
- 오류 발생 시 예상되는 에러 메시지와 해결 방법 명시
- "정상" 상태와 "비정상" 상태 비교 설명

#### 단계별 접근
- 각 섹션은 독립적으로 이해 가능하도록 작성
- 체크리스트 형식으로 진행 상황 추적 가능하게 구성
- 예: "✅ ServiceMonitor 생성 완료 → ✅ Prometheus Target 확인 완료"

#### 시각화
- 복잡한 개념은 Mermaid 다이어그램으로 시각화
- 테이블을 활용한 설정 옵션 비교
- 코드 블록에는 언어별 syntax highlighting 적용

### 4. 특별 고려사항

#### Metric 관련
- **네임스페이스 격리**: 각 팀의 네임스페이스에서만 메트릭 조회 가능하도록 RBAC 설명
- **레이블 일관성**: app, service-team 레이블의 네이밍 컨벤션 제공
- **성능 영향**: 고빈도 메트릭 수집 시 주의사항 (특히 대규모 병렬 app : spark, trino, airflow)

#### Log 관련
- **대용량 로그 처리**: 로그 드롭 방지를 위한 Fluent-Bit 버퍼 설정 가이드
- **Multiline 패턴**: Java/Python 등 언어별 Exception 패턴 예제
- **비용 최적화**: 불필요한 debug 로그는 프로덕션에서 비활성화 권장
- **보안**: 민감정보(비밀번호, API 키) 로깅 금지 가이드

### 5. 문서 메타데이터

```yaml
title: "Observability Platform 사용자 가이드"
version: "1.0.0"
last_updated: "YYYY-MM-DD"
target_audience: "애플리케이션 개발자 (Kubernetes 초급)"
prerequisites:
  - 기본적인 YAML 문법 이해
  - 애플리케이션 로깅 라이브러리 사용 경험
  - kubectl 기본 명령어 숙지
estimated_reading_time: "30분"
```

## 산출물

### 메인 문서 (한글)
- `USER_GUIDE.md`: 전체 사용자 가이드 (한글)

### 개별 문서 (한글)
- 'Metric 수집 을 위한 사용자 guide.md': 사용자 가이드 (한글)
    - 수집, 배포확인, 모니터링
    - 대규모 분산 환경에서 특정 pod(work) 구분하기위한 설정 및 조회방법
- 'Log 수집 을 위한 사용자 guide.md': 사용자 가이드 (한글)
    - 수집, 배포확인, 모니터링
    - 대규모 분산 환경에서 특정 pod(work) 구분하기위한 설정 및 조회방법
- '트러블 슈팅을 위한 Metric / Logging 을위한 grafana 대시보드 사용 가이드' (한글)
- 'Q&A 문서' (한글)

### 부록
- `examples/`: 예제 YAML 및 코드 샘플 디렉토리
  - `servicemonitor-example.yaml`
  - `podmonitor-example.yaml`
  - `log-format-java.java`
  - `log-format-python.py`
  - `log-format-json-example.json`
- `diagrams/`: Mermaid 소스 파일
  - `metric-architecture.mmd`
  - `log-architecture.mmd`

### 체크리스트
- `DEPLOYMENT_CHECKLIST.md`: 배포 전후 검증 체크리스트

## 성공 기준

1. Kubernetes/DevOps 경험이 없는 개발자도 30분 내 문서를 읽고 배포 가능
2. 각 단계별 검증 방법이 명확하여 스스로 문제 해결 가능
3. 트러블슈팅 섹션에서 90% 이상의 일반적인 문제 해결 가능
4. 실제 배포 시나리오를 반영한 예제 코드 제공
