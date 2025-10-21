# Grafana 멀티클러스터 조회 가이드

배포 일시: 2025-10-20
상태: ✅ **전체 4개 클러스터 데이터 정상 수집 중**

---

## ✅ 현재 상태 확인

### 수집 중인 클러스터
```bash
$ kubectl exec -n monitoring thanos-query-8dcb8b89c-lnhz5 -- \
    wget -O- -q "http://localhost:10902/api/v1/query?query=count(kube_node_info)by(cluster)"

결과:
✓ cluster-01: 1 node(s)
✓ cluster-02: 1 node(s)
✓ cluster-03: 1 node(s)
✓ cluster-04: 1 node(s)
```

**→ 백엔드 시스템은 정상 동작 중입니다!**

---

## 🔴 문제: "cluster-01만 보입니다"

### 원인 분석

Grafana에는 **3개의 데이터소스**가 프로비저닝되어 있습니다:

1. **Thanos-Query** (기본) ⭐
   - URL: `http://thanos-query.monitoring:9090`
   - 포함 클러스터: **cluster-01, 02, 03, 04** (전체)

2. **Prometheus-Local-0**
   - URL: `http://kube-prometheus-stack-prometheus-0...`
   - 포함 클러스터: **cluster-01만**

3. **Prometheus-Local-1**
   - URL: `http://kube-prometheus-stack-prometheus-1...`
   - 포함 클러스터: **cluster-01만**

### 가능한 원인

| 원인 | 확인 방법 | 해결 방법 |
|------|-----------|-----------|
| 잘못된 데이터소스 선택 | Explore 페이지 상단 드롭다운 | "Thanos-Query" 선택 |
| 대시보드 고정 데이터소스 | Dashboard Settings → Variables | datasource 변수를 Thanos-Query로 변경 |
| 브라우저 캐시 | 개발자도구에서 네트워크 요청 확인 | Ctrl+F5 강제 새로고침 |
| 쿼리 필터 오류 | 쿼리에 `{cluster="cluster-01"}` 하드코딩 | 필터 제거 또는 `{cluster=~"cluster-.*"}` 사용 |

---

## ✅ 해결 방법

### 방법 1: Explore에서 직접 확인 (권장)

1. **Grafana 접속**
   - URL: http://grafana.k8s-cluster-01.miribit.lab
   - Username: `admin`
   - Password: `admin123`

2. **Explore 메뉴 이동**
   - 왼쪽 사이드바에서 나침반 아이콘 클릭

3. **데이터소스 확인**
   - 상단 드롭다운에서 **"Thanos-Query"** 선택되어 있는지 확인
   - ⚠️ "Prometheus-Local"이면 안됨!

4. **쿼리 실행**
   ```promql
   # 모든 클러스터 노드 확인
   kube_node_info

   # 클러스터별 집계
   count(kube_node_info) by (cluster)

   # Edge 클러스터만 필터
   kube_node_info{cluster=~"cluster-0[234]"}
   ```

5. **결과 확인**
   - Table 탭에서 `cluster` 컬럼 확인
   - cluster-01, cluster-02, cluster-03, cluster-04가 모두 보여야 함

### 방법 2: 대시보드 데이터소스 변경

기존 대시보드에서 cluster-01만 보이는 경우:

1. **대시보드 설정 열기**
   - Dashboard 상단 ⚙️ Settings 클릭

2. **Variables 탭 이동**
   - 왼쪽 메뉴에서 "Variables" 선택

3. **datasource 변수 편집**
   - 변수 목록에서 `datasource` 또는 `DS_PROMETHEUS` 찾기
   - Edit 버튼 클릭
   - Query options:
     ```
     Type: Datasource
     Query: prometheus
     ```
   - Preview of values에서 **"Thanos-Query"** 선택

4. **패널별 데이터소스 확인**
   - 각 패널 Edit → Query options
   - Datasource: `${datasource}` 또는 직접 "Thanos-Query" 선택

### 방법 3: 새 대시보드 생성

1. **+ 버튼 → Create Dashboard**
2. **Add visualization**
3. **Datasource: "Thanos-Query" 선택**
4. **쿼리 입력**:
   ```promql
   # 클러스터별 노드 수
   count(kube_node_info) by (cluster, node)

   # 클러스터별 Pod 수
   count(kube_pod_info) by (cluster)

   # 클러스터별 CPU 사용률
   sum(rate(container_cpu_usage_seconds_total{cluster=~"cluster-.*"}[5m])) by (cluster)
   ```

---

## 🧪 검증 방법

### CLI에서 직접 확인

```bash
# 1. Grafana Pod에서 Thanos Query로 직접 쿼리
kubectl exec -n monitoring $(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') -c grafana -- \
  wget -O- -q "http://thanos-query.monitoring:9090/api/v1/query?query=count(kube_node_info)by(cluster)"

# 예상 결과:
# {"status":"success","data":{"result":[
#   {"metric":{"cluster":"cluster-01"},"value":[...]},
#   {"metric":{"cluster":"cluster-02"},"value":[...]},
#   {"metric":{"cluster":"cluster-03"},"value":[...]},
#   {"metric":{"cluster":"cluster-04"},"value":[...]}
# ]}}

# 2. 클러스터 레이블 목록 확인
kubectl exec -n monitoring $(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') -c grafana -- \
  wget -O- -q "http://thanos-query.monitoring:9090/api/v1/label/cluster/values"

# 예상 결과:
# {"status":"success","data":["cluster-01","cluster-02","cluster-03","cluster-04"]}
```

---

## 📊 유용한 쿼리 예제

### 멀티클러스터 대시보드용 쿼리

```promql
# 1. 클러스터별 노드 정보
kube_node_info

# 2. 클러스터별 노드 수
count(kube_node_info) by (cluster)

# 3. 클러스터별 Pod 수
count(kube_pod_info) by (cluster)

# 4. 클러스터별 총 CPU 코어 수
sum(kube_node_status_allocatable{resource="cpu"}) by (cluster)

# 5. 클러스터별 총 메모리 (GB)
sum(kube_node_status_allocatable{resource="memory"}) by (cluster) / 1024 / 1024 / 1024

# 6. 클러스터별 CPU 사용률 (%)
100 * (
  sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (cluster)
  /
  sum(kube_node_status_allocatable{resource="cpu"}) by (cluster)
)

# 7. 클러스터별 메모리 사용률 (%)
100 * (
  sum(container_memory_working_set_bytes{container!=""}) by (cluster)
  /
  sum(kube_node_status_allocatable{resource="memory"}) by (cluster)
)

# 8. Edge 클러스터만 필터
kube_pod_info{cluster=~"cluster-0[234]"}

# 9. 특정 클러스터 제외
kube_pod_info{cluster!="cluster-01"}

# 10. 클러스터 + Namespace 집계
count(kube_pod_info) by (cluster, namespace)
```

### Variable 설정

Dashboard에서 동적 필터링을 위한 Variable 설정:

```
Name: cluster
Type: Query
Datasource: Thanos-Query
Query: label_values(kube_node_info, cluster)
Multi-value: Yes
Include All: Yes
```

패널 쿼리에서 사용:
```promql
kube_pod_info{cluster=~"$cluster"}
```

---

## 🔧 트러블슈팅

### 증상 1: "No data" 에러

**확인 사항**:
1. 시간 범위: 최근 5분 이내로 설정
2. 데이터소스: "Thanos-Query" 선택 확인
3. 쿼리 문법: PromQL 문법 오류 확인

**해결**:
```bash
# 데이터가 실제로 있는지 확인
kubectl exec -n monitoring thanos-query-8dcb8b89c-lnhz5 -- \
  wget -O- -q "http://localhost:10902/api/v1/query?query=kube_node_info"
```

### 증상 2: "Bad Gateway" 또는 연결 오류

**확인 사항**:
1. Thanos Query Pod 상태
2. Service 상태

**해결**:
```bash
# Pod 상태 확인
kubectl get pods -n monitoring | grep thanos-query

# Service 확인
kubectl get svc -n monitoring thanos-query

# 로그 확인
kubectl logs -n monitoring thanos-query-8dcb8b89c-lnhz5 --tail=50
```

### 증상 3: cluster 레이블이 없음

**원인**: Prometheus Agent의 external_labels 설정 누락

**확인**:
```bash
kubectl --context cluster-02 get cm -n monitoring prometheus-agent-config -o yaml | grep -A 5 "external_labels:"
```

**예상 결과**:
```yaml
external_labels:
  cluster: cluster-02
  region: edge
  prometheus_replica: $(POD_NAME)
```

---

## 📈 성능 최적화 팁

### 1. 쿼리 최적화

```promql
# ❌ 느림 (모든 시계열 스캔)
{__name__=~".+", cluster="cluster-02"}

# ✅ 빠름 (메트릭 이름 명시)
kube_pod_info{cluster="cluster-02"}
```

### 2. 시간 범위 제한

- Explore: 최근 1시간 이내
- Dashboard: Auto refresh는 최소 30초 이상

### 3. Aggregation 활용

```promql
# ❌ 수천 개 시계열 반환
container_memory_usage_bytes

# ✅ 클러스터당 1개 시계열 반환
sum(container_memory_usage_bytes) by (cluster)
```

---

## 📚 관련 문서

- [Thanos Receiver 배포 완료 보고서](THANOS_RECEIVER_DEPLOYMENT.md)
- [Prometheus 감사 보고서](PROMETHEUS_AUDIT_REPORT.md)
- [아키텍처 스펙 v2.0](SPEC.md)
- [Thanos 공식 문서](https://thanos.io/tip/components/query.md/)

---

## 요약

✅ **4개 클러스터 모두 정상 수집 중**
✅ **Thanos-Query 데이터소스 정상 동작**
✅ **Grafana에서 조회 가능**

**문제 발생 시**: Grafana UI에서 **데이터소스가 "Thanos-Query"로 선택**되어 있는지 확인!

---

**작성**: Claude Code Agent
**검증 완료**: 2025-10-20 15:05 KST
**문서 버전**: 1.0
