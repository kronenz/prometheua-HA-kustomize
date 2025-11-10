# Observability Platform 문서

> Kubernetes 기반 통합 모니터링 시스템 사용자 가이드

## 📚 문서 구성

### 메인 문서
- **[USER_GUIDE.md](USER_GUIDE.md)** - 종합 사용자 가이드 (필독)
  - 아키텍처 이해 (Metric + Log)
  - 배포 전 설정 가이드
  - 배포 방법 (GitOps/Jenkins/kubectl)
  - 배포 후 검증 단계
  - 트러블슈팅 가이드
  - FAQ 및 Best Practices

### 체크리스트
- **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** - 배포 전후 검증 체크리스트
  - 10단계 검증 절차
  - 메트릭/로그 수집 확인
  - 트러블슈팅 체크리스트

### 예제 파일
- **[examples/](examples/)** - 실무 코드 예제

  **애플리케이션 메트릭:**
  - `servicemonitor-example.yaml` - ServiceMonitor 설정 (주석 포함)
  - `podmonitor-example.yaml` - PodMonitor 설정
  - `deployment-with-metrics.yaml` - Deployment + Service 통합 예제

  **표준 Exporter (데이터 플랫폼):**
  - `spark-metrics.yaml` - Apache Spark 메트릭 수집 (Prometheus Servlet)
  - `trino-metrics.yaml` - Trino 메트릭 수집 (JMX Exporter)
  - `airflow-metrics.yaml` - Apache Airflow 메트릭 수집 (StatsD Exporter)

  **로그 포맷:**
  - `log-format-java.java` - Java 로그 설정 (SLF4J + Logback)
  - `log-format-python.py` - Python 로그 설정 (python-json-logger)
  - `log-format-json-example.json` - JSON 로그 포맷 예제 모음

### 다이어그램
- **[diagrams/](diagrams/)** - Mermaid 아키텍처 다이어그램
  - `metric-architecture.mmd` - Metric 수집 아키텍처
  - `log-architecture.mmd` - Log 수집 아키텍처

## 🚀 빠른 시작

### 1단계: 사전 요구사항 확인
- [ ] YAML 문법 이해
- [ ] 로깅 라이브러리 사용 경험 (SLF4J, Python logging)
- [ ] kubectl 기본 명령어 숙지

### 2단계: 문서 읽기
1. [USER_GUIDE.md](USER_GUIDE.md) 전체 읽기 (약 30분)
2. 해당하는 언어의 예제 코드 확인
   - Java: [examples/log-format-java.java](examples/log-format-java.java)
   - Python: [examples/log-format-python.py](examples/log-format-python.py)

### 3단계: 애플리케이션 설정
- [ ] 메트릭 엔드포인트 구현 (`/metrics`)
- [ ] JSON 로그 포맷 설정
- [ ] ServiceMonitor/PodMonitor 작성

### 4단계: 배포 및 검증
- [ ] [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) 따라 진행
- [ ] Prometheus Target 상태 확인
- [ ] Grafana에서 메트릭/로그 조회 확인

## 📊 기술 스택

| 구분 | 스택 | 목적 |
|-----|------|-----|
| **메트릭 수집** | kube-prometheus-stack + Thanos | 성능 지표 수집 및 장기 보관 |
| **로그 수집** | OpenSearch + Fluent-Bit | 로그 수집 및 검색 |
| **시각화** | Grafana | 통합 대시보드 및 알림 |

## 🎯 주요 특징

### 개발자 친화적
- 초급 개발자도 30분 내 이해 가능
- 모든 전문 용어에 한글 해석 제공
- 단계별 명령어 + 예상 출력 포함

### 실무 중심
- 실제 프로덕션 환경 코드 예제
- 트러블슈팅 실패 케이스별 해결책
- Best Practices 및 성능 최적화 가이드

### 시각화 강화
- Mermaid 아키텍처 다이어그램
- 비교 테이블
- 체크리스트 형식

## 📖 주요 개념

### SLF4J vs Log4j
> **Q: Log4j를 일반적으로 쓰지 않나요?**

**SLF4J (Simple Logging Facade for Java)**
- 로깅 프레임워크의 **추상화 레이어** (인터페이스)
- 실제 구현체: Logback, Log4j2, JUL 등
- 장점: 구현체 교체 유연성, 성능 최적화

**권장 조합:**
- ✅ SLF4J API + Logback (Spring Boot 기본)
- ✅ SLF4J API + Log4j2 (고성능 요구 시)
- ❌ Log4j 1.x (2015년 EOL, 보안 취약점)

상세 설명: [USER_GUIDE.md - Q6](USER_GUIDE.md#q6-slf4j는-무엇이며-log4j와-어떻게-다른가요)

### 메트릭 수집 흐름
```
Application → /metrics 엔드포인트
    ↓
ServiceMonitor (CRD)
    ↓
Prometheus Operator (자동 설정)
    ↓
Prometheus (30초마다 scrape)
    ↓
Thanos (S3 장기 보관)
    ↓
Grafana (시각화)
```

### 로그 수집 흐름
```
Application → JSON 로그 (stdout)
    ↓
Container Runtime (/var/log/containers/)
    ↓
Fluent-Bit DaemonSet (tail)
    ↓
Lua Filter (JSON 파싱)
    ↓
OpenSearch (인덱싱)
    ↓
Grafana (검색/시각화)
```

## 🔍 자주 묻는 질문

### Q1. ServiceMonitor를 만들었는데 메트릭이 수집되지 않아요.
→ [USER_GUIDE.md - Q1](USER_GUIDE.md#q1-servicemonitor를-만들었는데-메트릭이-수집되지-않아요) 참조

### Q2. 로그가 JSON이 아닌데 어떻게 해야 하나요?
→ [USER_GUIDE.md - Q2](USER_GUIDE.md#q2-로그가-json이-아닌데-어떻게-해야-하나요) 참조

### Q3. DEBUG 로그를 프로덕션에서도 활성화해도 되나요?
→ [USER_GUIDE.md - Q3](USER_GUIDE.md#q3-debug-로그를-프로덕션에서도-활성화해도-되나요) 참조

### Q4. Thanos는 왜 필요한가요?
→ [USER_GUIDE.md - Q4](USER_GUIDE.md#q4-thanos는-왜-필요한가요-prometheus만으로는-안-되나요) 참조

### Q5. 메트릭과 로그의 correlation_id를 연결하려면?
→ [USER_GUIDE.md - Q5](USER_GUIDE.md#q5-메트릭과-로그의-correlation_id를-연결하려면-어떻게-하나요) 참조

### Q6. SLF4J는 무엇이며, Log4j와 어떻게 다른가요?
→ [USER_GUIDE.md - Q6](USER_GUIDE.md#q6-slf4j는-무엇이며-log4j와-어떻게-다른가요) 참조

## 🛠️ 트러블슈팅

### 메트릭 수집 실패
- [ServiceMonitor가 감지되지 않는 경우](USER_GUIDE.md#611-servicemonitor가-감지되지-않는-경우)
- [레이블이 누락된 경우](USER_GUIDE.md#612-레이블이-누락된-경우)
- [Prometheus Target이 DOWN 상태인 경우](USER_GUIDE.md#613-prometheus-target이-down-상태인-경우)

### 로그 수집 실패
- [로그가 OpenSearch에 나타나지 않는 경우](USER_GUIDE.md#621-로그가-opensearch에-나타나지-않는-경우)
- [Multiline 로그가 잘리는 경우](USER_GUIDE.md#622-multiline-로그가-잘리는-경우)
- [로그 드롭이 발생하는 경우](USER_GUIDE.md#623-로그-드롭이-발생하는-경우)

## 📞 지원

### 문의 채널
- **Slack**: #observability-support
- **Email**: platform-team@example.com
- **위키**: https://wiki.example.com/observability

### 이슈 보고 시 필요한 정보
- 네임스페이스
- 애플리케이션 이름
- ServiceMonitor/PodMonitor YAML
- Prometheus Target 에러 메시지
- Fluent-Bit 로그 (파싱 에러)

## 📌 버전 정보

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| 1.0.0 | 2025-01-15 | 초기 문서 작성 |

## 🔗 관련 링크

### 공식 문서
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Thanos](https://thanos.io/tip/thanos/getting-started.md/)
- [Fluent-Bit](https://docs.fluentbit.io/)
- [OpenSearch](https://opensearch.org/docs/)
- [Grafana](https://grafana.com/docs/)

### 참고 자료
- [PromQL 가이드](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [SLF4J 공식 문서](http://www.slf4j.org/manual.html)
- [Logback 공식 문서](http://logback.qos.ch/manual/)
- [Kubernetes Logging Architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)

---

**문서 기여:** 개선 사항이나 오류 발견 시 platform-team@example.com으로 연락 부탁드립니다.
