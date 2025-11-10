# Observability Platform 배포 체크리스트

> **목적**: 메트릭 및 로그 수집이 올바르게 설정되었는지 단계별로 확인
> **사용 방법**: 각 단계를 순서대로 진행하며 체크 ✅

---

## 📋 배포 전 준비사항

### 애플리케이션 코드 준비

- [ ] **메트릭 엔드포인트 구현**
  - [ ] `/metrics` 엔드포인트가 Prometheus 포맷으로 메트릭 노출
  - [ ] 로컬에서 `curl http://localhost:9090/metrics` 테스트 완료
  - [ ] 메트릭 네이밍이 `<namespace>_<subsystem>_<metric>_<unit>` 규칙 준수

- [ ] **로그 포맷 설정**
  - [ ] JSON 형식으로 로그 출력 (`stdout/stderr`)
  - [ ] 필수 필드 포함: `timestamp`, `level`, `app`, `service-team`, `message`
  - [ ] 민감정보(비밀번호, API 키 등) 로깅 제거 확인
  - [ ] Java Exception Multiline 처리 설정 (해당 시)

### Kubernetes 리소스 준비

- [ ] **Deployment/StatefulSet 준비**
  - [ ] Pod 레이블 설정: `app`, `service-team`
  - [ ] 메트릭 포트 정의: `name: metrics`, `containerPort: 9090`
  - [ ] 리소스 제한 설정: `requests`, `limits`

- [ ] **Service 준비 (ServiceMonitor 사용 시)**
  - [ ] Service 레이블 설정: `app`, `service-team`
  - [ ] Service 포트 정의: `name: metrics`, `port: 9090`
  - [ ] Service selector가 Pod 레이블과 일치

- [ ] **ServiceMonitor 또는 PodMonitor 준비**
  - [ ] 레이블 설정: `release: kube-prometheus-stack`
  - [ ] Selector가 Service/Pod 레이블과 일치
  - [ ] 엔드포인트 설정: `port: metrics`, `interval: 30s`

---

## 🚀 배포 단계

### 1단계: 리소스 배포

- [ ] **네임스페이스 확인**
  ```bash
  kubectl get namespace myteam-prod
  ```
  - 네임스페이스가 없으면 생성: `kubectl create namespace myteam-prod`

- [ ] **리소스 배포 실행**
  - [ ] GitOps (ArgoCD): Application 생성 및 Sync
  - [ ] Jenkins: Pipeline 실행
  - [ ] kubectl: `kubectl apply -f .` 실행

- [ ] **배포 상태 확인**
  ```bash
  kubectl rollout status deployment/myapp -n myteam-prod
  ```
  - 출력: `deployment "myapp" successfully rolled out` ✅

### 2단계: Pod 정상 동작 확인

- [ ] **Pod 상태 확인**
  ```bash
  kubectl get pods -n myteam-prod -l app=myapp
  ```
  - 모든 Pod가 `Running` 상태
  - `READY` 컬럼이 `1/1` (또는 컨테이너 수와 일치)

- [ ] **Pod 로그 확인**
  ```bash
  kubectl logs -n myteam-prod <pod-name> --tail=20
  ```
  - JSON 형식으로 로그 출력 확인
  - 에러 로그 없음 확인

- [ ] **메트릭 엔드포인트 접근 확인**
  ```bash
  kubectl exec -n myteam-prod <pod-name> -- curl http://localhost:9090/metrics
  ```
  - Prometheus 포맷의 메트릭 출력 확인

---

## 📊 메트릭 수집 검증

### 3단계: ServiceMonitor/PodMonitor 확인

- [ ] **리소스 존재 확인**
  ```bash
  kubectl get servicemonitor -n myteam-prod
  # 또는
  kubectl get podmonitor -n myteam-prod
  ```

- [ ] **레이블 확인**
  ```bash
  kubectl get servicemonitor myapp-metrics -n myteam-prod --show-labels
  ```
  - `release=kube-prometheus-stack` 레이블 존재 확인

- [ ] **상세 정보 확인**
  ```bash
  kubectl describe servicemonitor myapp-metrics -n myteam-prod
  ```
  - Selector가 올바른지 확인
  - Endpoints 설정이 올바른지 확인

### 4단계: Service 및 Endpoints 확인

- [ ] **Service 확인**
  ```bash
  kubectl get svc myapp-metrics -n myteam-prod
  ```
  - `TYPE`이 `ClusterIP`
  - `PORT(S)`에 `9090/TCP` 존재

- [ ] **Endpoints 확인**
  ```bash
  kubectl get endpoints myapp-metrics -n myteam-prod
  ```
  - `ENDPOINTS` 컬럼에 Pod IP가 표시됨 (예: `10.244.1.10:9090`)
  - Pod IP 개수가 Deployment의 replicas와 일치

### 5단계: Prometheus Target 확인

- [ ] **Prometheus UI 접속**
  ```bash
  kubectl port-forward -n monitor svc/kube-prometheus-stack-prometheus 9090:9090
  ```
  - 브라우저에서 http://localhost:9090 접속

- [ ] **Targets 페이지 확인**
  - **Status → Targets** 메뉴 클릭
  - `serviceMonitor/myteam-prod/myapp-metrics` 검색
  - **State**: `UP` ✅ (DOWN이면 에러 메시지 확인)
  - **Last Scrape**: 최근 시간
  - **Scrape Duration**: 1000ms 이하

- [ ] **에러 없음 확인**
  - State가 `DOWN`이면 Error 컬럼의 메시지 확인
  - 일반적인 에러:
    - `context deadline exceeded`: 타임아웃 (Pod 응답 느림)
    - `connection refused`: 포트 닫힘 (메트릭 엔드포인트 없음)
    - `no such host`: Service DNS 문제

### 6단계: Grafana에서 메트릭 조회

- [ ] **Grafana UI 접속**
  ```bash
  kubectl port-forward -n monitor svc/kube-prometheus-stack-grafana 3000:80
  ```
  - 브라우저에서 http://localhost:3000 접속
  - 로그인: `admin` / `prom-operator`

- [ ] **Explore 페이지에서 쿼리**
  - 좌측 메뉴에서 **Explore** 클릭
  - Data source: **Prometheus** 선택
  - 쿼리 입력:
    ```promql
    up{app="myapp", service_team="myteam"}
    ```
  - 결과 값이 `1`이면 ✅

- [ ] **애플리케이션 메트릭 조회**
  ```promql
  rate(http_requests_total{app="myapp"}[5m])
  ```
  - 메트릭이 조회되면 ✅

- [ ] **대시보드 확인 (선택사항)**
  - **Dashboards → Kubernetes / Compute Resources / Namespace (Pods)** 선택
  - Namespace: `myteam-prod` 선택
  - `myapp-*` Pod 필터링하여 CPU/Memory 확인

---

## 📝 로그 수집 검증

### 7단계: Fluent-Bit 로그 수집 확인

- [ ] **Fluent-Bit Pod 상태 확인**
  ```bash
  kubectl get pods -n monitor -l app.kubernetes.io/name=fluent-bit
  ```
  - 모든 Pod가 `Running` 상태

- [ ] **Fluent-Bit 로그 확인**
  ```bash
  kubectl logs -n monitor <fluent-bit-pod> --tail=50
  ```
  - `myapp` 로그 파일 읽기 로그 확인:
    ```
    [info] [input:tail:tail.0] inotify_fs_add(): inode=123456 watch_fd=1 name=/var/log/containers/myapp-xxx.log
    ```
  - JSON 파싱 성공 로그 확인 (에러 없음)

- [ ] **파싱 에러 없음 확인**
  ```bash
  kubectl logs -n monitor <fluent-bit-pod> --tail=100 | grep error
  ```
  - `failed to parse JSON` 에러가 없으면 ✅
  - 에러가 있으면 애플리케이션 로그 포맷 재확인

### 8단계: OpenSearch 인덱싱 확인

- [ ] **OpenSearch Dashboards 접속**
  ```bash
  kubectl port-forward -n monitor svc/opensearch-dashboards 5601:5601
  ```
  - 브라우저에서 http://localhost:5601 접속

- [ ] **Index Pattern 생성 (최초 1회)**
  - **Management → Stack Management → Index Patterns** 선택
  - **Create index pattern** 클릭
  - Index pattern name: `logs-*`
  - Time field: `@timestamp` 선택
  - **Create** 클릭 ✅

- [ ] **Discover 페이지에서 로그 검색**
  - **Discover** 메뉴 클릭
  - Index pattern: `logs-*` 선택
  - 검색 쿼리:
    ```
    app:"myapp" AND service-team:"myteam"
    ```
  - 로그가 표시되면 ✅

- [ ] **로그 필드 확인**
  - 필수 필드 존재 확인: `timestamp`, `level`, `app`, `service-team`, `message`
  - Kubernetes 메타데이터 확인: `namespace`, `pod_name`, `container_name`

### 9단계: Grafana에서 로그 조회

- [ ] **Grafana Explore 페이지**
  - Grafana UI 접속 (http://localhost:3000)
  - 좌측 메뉴에서 **Explore** 클릭
  - Data source: **OpenSearch** 선택

- [ ] **로그 쿼리**
  - Query 입력:
    ```json
    {
      "query": {
        "bool": {
          "must": [
            { "match": { "app": "myapp" } },
            { "match": { "service-team": "myteam" } }
          ]
        }
      }
    }
    ```
  - 로그가 표시되면 ✅

- [ ] **실시간 로그 스트리밍**
  - **Live** 버튼 클릭
  - 애플리케이션에서 로그 생성 (API 호출 등)
  - Grafana에서 실시간으로 로그 표시 확인 ✅

---

## 🔍 종합 검증

### 10단계: End-to-End 테스트

- [ ] **애플리케이션 API 호출**
  ```bash
  # 애플리케이션 엔드포인트 호출
  kubectl exec -n myteam-prod <pod-name> -- curl http://localhost:8080/api/test
  ```

- [ ] **메트릭 증가 확인**
  - Grafana Explore에서 쿼리:
    ```promql
    increase(http_requests_total{app="myapp", endpoint="/api/test"}[1m])
    ```
  - 값이 증가하면 ✅

- [ ] **로그 생성 확인**
  - OpenSearch 또는 Grafana에서 검색:
    ```
    app:"myapp" AND message:"test"
    ```
  - 방금 생성한 로그가 표시되면 ✅

- [ ] **알림 테스트 (선택사항)**
  - Grafana에서 Alert Rule 생성
  - 테스트 조건 트리거
  - 알림 채널 (Slack, Email 등) 수신 확인

---

## ⚠️ 트러블슈팅 체크리스트

### 메트릭 수집 실패 시

- [ ] ServiceMonitor 레이블 확인: `release=kube-prometheus-stack`
- [ ] Service selector와 Pod 레이블 일치 확인
- [ ] Prometheus Target State 에러 메시지 확인
- [ ] NetworkPolicy로 차단되지 않았는지 확인
- [ ] 메트릭 엔드포인트 직접 접근 테스트 (`curl http://localhost:9090/metrics`)

### 로그 수집 실패 시

- [ ] Pod 로그가 JSON 형식인지 확인
- [ ] Fluent-Bit 로그에서 파싱 에러 확인
- [ ] OpenSearch에 Index가 생성되었는지 확인 (`_cat/indices`)
- [ ] Fluent-Bit → OpenSearch 연결 에러 확인
- [ ] DaemonSet 재시작: `kubectl rollout restart daemonset/fluent-bit -n monitor`

---

## 📌 완료 확인

### 최종 체크리스트

- [ ] **메트릭 수집**
  - [ ] Prometheus Target이 `UP` 상태
  - [ ] Grafana에서 메트릭 조회 가능
  - [ ] 대시보드에서 애플리케이션 상태 확인 가능

- [ ] **로그 수집**
  - [ ] Fluent-Bit이 로그 파일 읽기 중
  - [ ] OpenSearch에 로그 인덱싱 완료
  - [ ] Grafana에서 로그 검색 가능
  - [ ] 실시간 로그 스트리밍 동작

- [ ] **문서화**
  - [ ] 배포 절차 문서화 완료
  - [ ] 트러블슈팅 가이드 작성 완료
  - [ ] 팀원에게 공유 완료

---

## 📞 지원 요청

모든 체크리스트를 완료했는데도 문제가 해결되지 않는 경우:

1. **로그 수집**
   ```bash
   # Prometheus Operator 로그
   kubectl logs -n monitor -l app.kubernetes.io/name=prometheus-operator --tail=100

   # Fluent-Bit 로그
   kubectl logs -n monitor -l app.kubernetes.io/name=fluent-bit --tail=100

   # OpenSearch 로그
   kubectl logs -n monitor opensearch-0 --tail=100
   ```

2. **문의 채널**
   - Slack: #observability-support
   - Email: platform-team@example.com
   - Jira: PLATFORM 프로젝트에 이슈 생성

3. **제공할 정보**
   - 네임스페이스: `myteam-prod`
   - 애플리케이션 이름: `myapp`
   - ServiceMonitor YAML
   - Prometheus Target 에러 메시지
   - Fluent-Bit 파싱 에러 로그

---

## 📚 참고 자료

- [Observability Platform 사용자 가이드](USER_GUIDE.md)
- [트러블슈팅 가이드](USER_GUIDE.md#6-트러블슈팅)
- [예제 파일](examples/)
- [아키텍처 다이어그램](diagrams/)

---

**버전**: 1.0.0
**최종 업데이트**: 2025-01-15
