# DataOps Dev 클러스터 Health Status 대시보드 배포 완료

**프로젝트명**: DataOps Dev Cluster Health Status Dashboard
**배포 일시**: 2025-11-10 10:18 (UTC)
**버전**: v1.0
**배포 상태**: ✅ 성공

---

## ✅ 배포 완료 요약

DataOps Dev 클러스터의 Portal, Compute, Storage 각 클러스터 상태를 **신호등(Traffic Light) 형태**로 시각화하는 대시보드를 성공적으로 배포하였습니다.

---

## 📊 배포된 대시보드 정보

### 대시보드 기본 정보
- **이름**: DataOps-Dev-클러스터-Health-Status
- **UID**: `dataops-dev-health-v1`
- **태그**: `dataops`, `health-status`, `dev-cluster`, `신호등`
- **자동 새로고침**: 30초

### 주요 패널 구성

#### 1. 전체 상태 신호등 (상단)
```
┌────────────────────────────────────────┐
│ 🚦 DataOps Dev 클러스터 전체 상태      │
│                                        │
│          ✅ HEALTHY                   │
└────────────────────────────────────────┘
```
- **크기**: 전체 너비 x 3 높이
- **판정**: 모든 클러스터 UP → 🟢 HEALTHY / 일부 DOWN → 🔴 DOWN

#### 2. 클러스터별 신호등 (중단)
```
┌─────────────┬─────────────┬─────────────┐
│ 🌐 Portal   │ ⚙️ Compute  │ 💾 Storage  │
│ 🟢 HEALTHY  │ 🟢 HEALTHY  │ 🟢 HEALTHY  │
│ (추이)      │ (추이)      │ (추이)      │
└─────────────┴─────────────┴─────────────┘
```
- **크기**: 각 8 너비 x 8 높이
- **타입**: Stat Panel (배경 색상 + 미니 그래프)

#### 3. 클러스터 상세 상태 (테이블)
| Cluster | Component | Status | CPU Usage % | Memory Usage % |
|---------|-----------|--------|-------------|----------------|
| dataops-dev | portal-* | ✅ UP | 게이지 | 게이지 |
| dataops-dev | compute-* | ✅ UP | 게이지 | 게이지 |
| dataops-dev | storage-* | ✅ UP | 게이지 | 게이지 |

- **크기**: 전체 너비 x 10 높이
- **타입**: Table Panel (색상 게이지 포함)

#### 4. 컴포넌트 분포 (Donut Charts)
- **Portal 컴포넌트**: Web UI, API Gateway, Auth
- **Compute 컴포넌트**: Spark, Trino, Airflow
- **Storage 컴포넌트**: MinIO, Database, Longhorn

#### 5. 가동률 추이 (24시간)
- **Portal**: 파스텔 블루 (#B8D8F0)
- **Compute**: 파스텔 그린 (#B8E5C5)
- **Storage**: 파스텔 퍼플 (#D5C9E8)

---

## 🚀 배포 상태

### ConfigMap 생성 확인
```bash
kubectl get configmap -n monitoring | grep dataops-dev-health
```

**결과**:
```
grafana-dashboard-dataops-dev-health-v1   1      3m
```

✅ **ConfigMap 정상 생성**

### Grafana Pod 재시작 확인
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
```

**결과**:
```
NAME                                             READY   STATUS    RESTARTS   AGE
kube-prometheus-stack-grafana-587d5f6cd4-4r4jn   3/3     Running   0          3m
```

✅ **Grafana Pod 정상 재시작 (3/3 Running)**

### 대시보드 파일 로드 확인
```bash
kubectl exec -n monitoring kube-prometheus-stack-grafana-587d5f6cd4-4r4jn -c grafana -- ls -la /tmp/dashboards/ | grep dataops-dev-health
```

**결과**:
```
-rw-r--r--    1 grafana  472    26345 Nov 10 10:18 dataops-dev-health-status.json
```

✅ **대시보드 파일 정상 로드 (26KB)**

### JSON 유효성 검증
```bash
kubectl exec -n monitoring kube-prometheus-stack-grafana-587d5f6cd4-4r4jn -c grafana -- cat /tmp/dashboards/dataops-dev-health-status.json | python3 -m json.tool > /dev/null
```

✅ **JSON 포맷 유효성 검증 완료**

---

## 📂 파일 위치

### 대시보드 JSON 원본
```
/root/develop/thanos/docs/08-그라파나디자인/dataops-dev-health-status-dashboard.json
```

### ConfigMap YAML
```
/root/develop/thanos/deploy-new/base/kube-prometheus-stack/dashboards/dataops-dev/health-status.yaml
```

### 배포 가이드 문서
```
/root/develop/thanos/docs/08-그라파나디자인/03-DataOps-Dev-Health-Status-배포가이드.md
```

---

## 🌐 Grafana 접속 정보

### 접속 방법

**URL**: http://grafana.k8s-cluster-01.miribit.lab
**Username**: admin
**Password**: admin123

### 대시보드 찾기

#### 방법 1: 검색
1. Grafana 접속
2. 좌측 메뉴 → **Dashboards** 클릭
3. 검색창에 **"DataOps"** 또는 **"Health Status"** 입력
4. **"DataOps-Dev-클러스터-Health-Status"** 클릭

#### 방법 2: 직접 URL
```
http://grafana.k8s-cluster-01.miribit.lab/d/dataops-dev-health-v1/dataops-dev-클러스터-health-status
```

#### 방법 3: Kiosk 모드 (포털 임베딩용)
```
http://grafana.k8s-cluster-01.miribit.lab/d/dataops-dev-health-v1?kiosk=tv&refresh=30s
```

---

## 📊 사용된 PromQL 쿼리

### 전체 클러스터 상태
```promql
(
  min(up{job=~".*portal.*", cluster="dataops-dev"}) *
  min(up{job=~".*compute.*", cluster="dataops-dev"}) *
  min(up{job=~".*storage.*", cluster="dataops-dev"})
) == 1
```

### 개별 클러스터 상태
```promql
# Portal 클러스터
min(up{job=~".*portal.*", cluster="dataops-dev"})

# Compute 클러스터
min(up{job=~".*compute.*", cluster="dataops-dev"})

# Storage 클러스터
min(up{job=~".*storage.*", cluster="dataops-dev"})
```

### CPU 사용률
```promql
100 - (avg by (job) (rate(node_cpu_seconds_total{mode="idle",cluster="dataops-dev"}[5m])) * 100)
```

### Memory 사용률
```promql
100 - (avg by (job) (node_memory_MemAvailable_bytes{cluster="dataops-dev"} / node_memory_MemTotal_bytes{cluster="dataops-dev"}) * 100)
```

---

## 🎯 메트릭 요구사항

### 필수 레이블

모든 메트릭은 다음 레이블을 포함해야 합니다:

| 레이블 | 값 예시 | 설명 |
|--------|---------|------|
| `cluster` | `dataops-dev` | 클러스터 식별자 (**필수**) |
| `job` | `portal-web`, `compute-spark` | 컴포넌트 이름 (**필수**) |
| `instance` | `10.0.1.10:9100` | 인스턴스 주소 (선택) |

### Job 이름 패턴

대시보드는 다음 패턴으로 클러스터를 구분합니다:

```yaml
Portal 클러스터:
  - portal-*
  - *portal*

Compute 클러스터:
  - compute-*
  - *compute*

Storage 클러스터:
  - storage-*
  - *storage*
```

### ServiceMonitor/PodMonitor 설정 예시

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: portal-web-metrics
  namespace: dataops-dev
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: portal-web
  endpoints:
    - port: metrics
      interval: 30s
      relabelings:
        # cluster 레이블 추가
        - sourceLabels: []
          targetLabel: cluster
          replacement: dataops-dev
```

---

## 🔧 트러블슈팅

### 문제 1: "No data" 표시

**원인**: Prometheus에서 메트릭을 수집하지 못함

**해결 단계**:

1. **Prometheus Target 확인**:
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# 브라우저: http://localhost:9090 → Status → Targets
# dataops-dev 클러스터 컴포넌트가 UP 상태인지 확인
```

2. **메트릭 레이블 확인**:
```promql
# Prometheus UI → Graph에서 실행
up{cluster="dataops-dev"}

# 결과가 없으면 레이블 추가 필요
```

3. **ServiceMonitor 확인**:
```bash
kubectl get servicemonitor -n dataops-dev
kubectl describe servicemonitor <name> -n dataops-dev
```

### 문제 2: 전체 상태가 항상 DOWN

**원인**: Job 이름 패턴 불일치

**해결**:
```promql
# 각 클러스터별로 개별 확인
min(up{job=~".*portal.*", cluster="dataops-dev"})
min(up{job=~".*compute.*", cluster="dataops-dev"})
min(up{job=~".*storage.*", cluster="dataops-dev"})

# 결과가 0이면 해당 클러스터에 문제
# 결과가 없으면 job 이름 패턴 확인 필요
```

**Job 이름 확인**:
```promql
# 현재 수집 중인 job 목록 확인
count by (job) (up{cluster="dataops-dev"})
```

### 문제 3: CPU/Memory 게이지 표시 안 됨

**원인**: node-exporter 미설치 또는 메트릭 부족

**해결**:
```bash
# node-exporter 설치 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=node-exporter

# 메트릭 확인
# Prometheus UI에서:
node_cpu_seconds_total{cluster="dataops-dev"}
node_memory_MemTotal_bytes{cluster="dataops-dev"}
```

---

## 📈 활용 시나리오

### 시나리오 1: 포털 메인 화면 임베딩

**HTML 코드**:
```html
<iframe
  src="http://grafana.k8s-cluster-01.miribit.lab/d/dataops-dev-health-v1?orgId=1&kiosk=tv&refresh=30s"
  width="100%"
  height="600px"
  frameborder="0"
  style="border: none;">
</iframe>
```

**Kiosk 모드 옵션**:
- `?kiosk=tv`: 메뉴 숨김, 전체 화면
- `&refresh=30s`: 30초 자동 새로고침
- `&from=now-24h&to=now`: 시간 범위 고정

### 시나리오 2: TV 모니터 전체 화면

1. TV 모니터에서 브라우저 열기
2. 다음 URL 접속:
```
http://grafana.k8s-cluster-01.miribit.lab/d/dataops-dev-health-v1?kiosk=tv&refresh=30s
```
3. 브라우저 전체 화면 (F11)

### 시나리오 3: 모바일 앱 WebView

**React Native 예제**:
```javascript
import { WebView } from 'react-native-webview';

<WebView
  source={{
    uri: 'http://grafana.../d/dataops-dev-health-v1?kiosk=1&refresh=30s'
  }}
  style={{ flex: 1 }}
  startInLoadingState={true}
/>
```

---

## 🎨 디자인 특징

### 파스텔 색상 시스템
```css
/* 클러스터별 색상 */
--portal-color: #B8D8F0;    /* 연한 파란색 */
--compute-color: #B8E5C5;   /* 연한 녹색 */
--storage-color: #D5C9E8;   /* 연한 보라색 */

/* 상태별 색상 */
--status-healthy: #D5F4E6;  /* 정상 - 연한 녹색 */
--status-warning: #FCF3CF;  /* 경고 - 연한 노란색 */
--status-critical: #FADBD8; /* 위험 - 연한 빨간색 */
```

### 신호등 이모지
- 🟢 **HEALTHY**: 모든 컴포넌트 정상
- 🔴 **DOWN**: 하나 이상의 컴포넌트 문제
- ⚠️ **WARNING**: 리소스 임계값 초과 (추후 확장)

---

## 🔔 알림 설정 (선택사항)

### Grafana Alert Rule 추가

#### 1. 전체 클러스터 DOWN 알림
```yaml
Alert Name: DataOps Dev 전체 DOWN
Condition:
  Query A: (min(up{job=~".*portal.*", cluster="dataops-dev"}) * min(up{job=~".*compute.*", cluster="dataops-dev"}) * min(up{job=~".*storage.*", cluster="dataops-dev"})) == 0
  Threshold: = 0
  For: 2m
Notification: Slack, Email
Message: "🚨 DataOps Dev 클러스터 전체가 DOWN 상태입니다!"
```

#### 2. 개별 클러스터 DOWN 알림
```yaml
Portal DOWN:
  Query: min(up{job=~".*portal.*", cluster="dataops-dev"}) == 0
  Message: "🔴 Portal 클러스터 DOWN"

Compute DOWN:
  Query: min(up{job=~".*compute.*", cluster="dataops-dev"}) == 0
  Message: "🔴 Compute 클러스터 DOWN"

Storage DOWN:
  Query: min(up{job=~".*storage.*", cluster="dataops-dev"}) == 0
  Message: "🔴 Storage 클러스터 DOWN"
```

---

## ✅ 검증 체크리스트

### 배포 완료 확인
- [x] ConfigMap 생성 완료
- [x] Grafana Pod 재시작 완료
- [x] 대시보드 파일 로드 완료 (26KB)
- [x] JSON 유효성 검증 완료
- [x] 대시보드 검색 가능
- [x] 문서화 완료

### 기능 테스트 (배포 후 수행)
- [ ] 전체 상태 신호등 표시 확인
- [ ] Portal/Compute/Storage 개별 신호등 표시 확인
- [ ] 상세 테이블에 데이터 표시 확인
- [ ] 컴포넌트 Donut Chart 표시 확인
- [ ] 가동률 추이 그래프 표시 확인
- [ ] 자동 새로고침 동작 확인 (30초)
- [ ] Kiosk 모드 동작 확인

### 메트릭 데이터 확인
- [ ] `up{cluster="dataops-dev"}` 메트릭 존재
- [ ] Portal 클러스터 메트릭 수집 중
- [ ] Compute 클러스터 메트릭 수집 중
- [ ] Storage 클러스터 메트릭 수집 중
- [ ] CPU/Memory 메트릭 수집 중

---

## 📚 참고 문서

- [배포 가이드](./03-DataOps-Dev-Health-Status-배포가이드.md) - 상세 배포 절차
- [베어메탈 K8s 인프라 대시보드](./02-K8s-인프라-대시보드-배포완료.md) - 기존 대시보드
- [Grafana Stat Panel 문서](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/stat/)
- [Prometheus PromQL 가이드](https://prometheus.io/docs/prometheus/latest/querying/basics/)

---

## 🎉 결론

✅ **DataOps Dev 클러스터 Health Status 대시보드 배포 성공**

**주요 특징:**
- 🚦 직관적인 신호등 형태 상태 표시
- 🌐⚙️💾 Portal, Compute, Storage 각 클러스터 구분
- 📊 상세 테이블 및 24시간 트렌드 제공
- 🎨 파스텔 색상으로 눈의 피로도 최소화
- 🔄 30초 자동 새로고침
- 📱 포털 임베딩 및 모바일 지원

**다음 단계:**
1. ✅ Grafana UI에서 대시보드 확인
2. ⚠️ 메트릭 데이터 수집 확인 (ServiceMonitor 설정)
3. ⚠️ Job 이름에 `cluster="dataops-dev"` 레이블 추가
4. ⚠️ 알림 규칙 설정 (선택사항)
5. ⚠️ 포털 메인 화면 임베딩 (선택사항)

**접속 정보:**
- **URL**: http://grafana.k8s-cluster-01.miribit.lab/d/dataops-dev-health-v1
- **Kiosk 모드**: 위 URL + `?kiosk=tv&refresh=30s`
- **검색어**: "DataOps-Dev-클러스터-Health-Status"

---

**작성자**: Platform Engineering Team
**배포 일시**: 2025-11-10 10:18 UTC
**최종 수정**: 2025-11-10
**버전**: 1.0
