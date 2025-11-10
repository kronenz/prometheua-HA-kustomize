# DataOps Dev 클러스터 Health Status 대시보드 배포 가이드

**프로젝트명**: DataOps Dev Cluster Health Status Dashboard
**버전**: v1.0
**배포 일시**: 2025-11-10

---

## 📊 대시보드 개요

### 목적
DataOps Dev 클러스터의 Portal, Compute, Storage 각 클러스터 상태를 **신호등(Traffic Light) 형태**로 시각화하여 포털 메인 화면에서 한눈에 Health Status를 파악할 수 있도록 합니다.

### 주요 기능
- ✅ **전체 상태 신호등**: 전체 클러스터 상태를 한눈에 확인 (🟢 HEALTHY / 🟡 WARNING / 🔴 DOWN)
- 🌐 **Portal 클러스터**: Web UI, API Gateway 등
- ⚙️ **Compute 클러스터**: Spark, Trino, Airflow 등
- 💾 **Storage 클러스터**: MinIO, Database, Longhorn 등
- 📊 **상세 테이블**: 각 컴포넌트의 CPU/Memory 사용률
- 📈 **가동률 추이**: 24시간 동안의 가동률 그래프

---

## 🎨 대시보드 구성

### 1. 전체 상태 신호등 (상단)
```
┌──────────────────────────────────────────────┐
│  🚦 DataOps Dev 클러스터 전체 상태           │
│                                              │
│           ✅ HEALTHY                        │
│      (또는 ⚠️ WARNING / ❌ DOWN)           │
└──────────────────────────────────────────────┘
```

**판정 기준:**
- ✅ **HEALTHY**: 모든 클러스터 (Portal, Compute, Storage) 정상
- ⚠️ **WARNING**: 1개 클러스터 문제
- ❌ **DOWN**: 2개 이상 클러스터 문제

### 2. 클러스터별 신호등 (중단)
```
┌─────────────┬─────────────┬─────────────┐
│ 🌐 Portal   │ ⚙️ Compute  │ 💾 Storage  │
│             │             │             │
│ 🟢 HEALTHY  │ 🟢 HEALTHY  │ 🟢 HEALTHY  │
│             │             │             │
└─────────────┴─────────────┴─────────────┘
```

**각 클러스터 판정 기준:**
- 🟢 **HEALTHY (1)**: 모든 컴포넌트 UP
- 🔴 **DOWN (0)**: 하나 이상의 컴포넌트 DOWN

### 3. 상세 상태 테이블
| Cluster | Component | Status | CPU Usage % | Memory Usage % |
|---------|-----------|--------|-------------|----------------|
| dataops-dev | portal-web | ✅ UP | 45% (게이지) | 60% (게이지) |
| dataops-dev | compute-spark | ✅ UP | 70% (게이지) | 75% (게이지) |
| dataops-dev | storage-minio | ✅ UP | 30% (게이지) | 50% (게이지) |

**색상 임계값:**
- CPU: 🟢 < 70% | 🟡 70-85% | 🔴 > 85%
- Memory: 🟢 < 80% | 🟡 80-90% | 🔴 > 90%

### 4. 컴포넌트 분포 (Donut Chart)
- 각 클러스터별 컴포넌트 비율을 원형 차트로 표시
- Portal: Web UI, API Gateway, Auth Service
- Compute: Spark, Trino, Airflow
- Storage: MinIO, PostgreSQL, Longhorn

### 5. 가동률 추이 그래프
- 최근 24시간 동안의 각 클러스터 가동률 추이
- 파스텔 색상 적용:
  - Portal: `#B8D8F0` (연한 파란색)
  - Compute: `#B8E5C5` (연한 녹색)
  - Storage: `#D5C9E8` (연한 보라색)

---

## 📦 배포 방법

### 방법 1: Grafana UI를 통한 Import (권장)

#### 1단계: 대시보드 JSON 파일 복사
```bash
# JSON 파일 위치 확인
cat /root/develop/thanos/docs/08-그라파나디자인/dataops-dev-health-status-dashboard.json
```

#### 2단계: Grafana UI 접속
```
URL: http://grafana.k8s-cluster-01.miribit.lab
Username: admin
Password: admin123
```

#### 3단계: 대시보드 Import
1. 좌측 메뉴에서 **"+"** 버튼 클릭 → **Import** 선택
2. **Upload JSON file** 버튼 클릭
3. `dataops-dev-health-status-dashboard.json` 파일 선택
4. **Data Source** 드롭다운에서 `Prometheus` 선택
5. **Import** 버튼 클릭

#### 4단계: 확인
- 대시보드가 자동으로 열리며 실시간 데이터 표시
- 검색: **"DataOps-Dev-클러스터-Health-Status"**

---

### 방법 2: ConfigMap을 통한 자동 배포

#### 1단계: ConfigMap YAML 생성
```bash
cat > /root/develop/thanos/deploy-new/overlays/cluster-01-central/kube-prometheus-stack/dashboards/dataops-dev/health-status.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-dataops-dev-health-v1
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  dataops-dev-health-status.json: |
$(cat /root/develop/thanos/docs/08-그라파나디자인/dataops-dev-health-status-dashboard.json | sed 's/^/    /')
EOF
```

#### 2단계: ConfigMap 배포
```bash
kubectl --context cluster-01 apply -f /root/develop/thanos/deploy-new/overlays/cluster-01-central/kube-prometheus-stack/dashboards/dataops-dev/health-status.yaml
```

#### 3단계: Grafana 재시작 (ConfigMap 반영)
```bash
kubectl --context cluster-01 rollout restart deployment -n monitoring kube-prometheus-stack-grafana
```

#### 4단계: 배포 확인
```bash
# ConfigMap 확인
kubectl --context cluster-01 get configmap -n monitoring | grep dataops-dev-health

# Grafana Pod 재시작 확인
kubectl --context cluster-01 get pods -n monitoring -l app.kubernetes.io/name=grafana
```

---

## 🔧 메트릭 요구사항

### 필요한 Prometheus Metrics

#### 1. 기본 가동 상태 메트릭 (필수)
```promql
# 각 컴포넌트의 UP/DOWN 상태
up{cluster="dataops-dev"}

# Portal 클러스터
up{job=~".*portal.*", cluster="dataops-dev"}

# Compute 클러스터
up{job=~".*compute.*", cluster="dataops-dev"}

# Storage 클러스터
up{job=~".*storage.*", cluster="dataops-dev"}
```

#### 2. 리소스 사용률 메트릭
```promql
# CPU 사용률
100 - (avg by (job) (rate(node_cpu_seconds_total{mode="idle",cluster="dataops-dev"}[5m])) * 100)

# Memory 사용률
100 - (avg by (job) (node_memory_MemAvailable_bytes{cluster="dataops-dev"} / node_memory_MemTotal_bytes{cluster="dataops-dev"}) * 100)
```

### 메트릭 레이블 요구사항

모든 메트릭은 다음 레이블을 포함해야 합니다:

| 레이블 | 값 예시 | 설명 |
|--------|---------|------|
| `cluster` | `dataops-dev` | 클러스터 식별자 |
| `job` | `portal-web`, `compute-spark`, `storage-minio` | 컴포넌트 이름 |
| `instance` | `10.0.1.10:9100` | 인스턴스 주소 |

---

## 🎯 컴포넌트별 Job 이름 예시

### Portal 클러스터
```yaml
Jobs:
  - portal-web-ui        # 웹 UI 서비스
  - portal-api-gateway   # API Gateway
  - portal-auth-service  # 인증 서비스
  - portal-nginx         # Ingress Nginx
```

### Compute 클러스터
```yaml
Jobs:
  - compute-spark-driver     # Spark Driver
  - compute-spark-executor   # Spark Executor
  - compute-trino-coord      # Trino Coordinator
  - compute-trino-worker     # Trino Worker
  - compute-airflow-web      # Airflow Webserver
  - compute-airflow-scheduler # Airflow Scheduler
```

### Storage 클러스터
```yaml
Jobs:
  - storage-minio          # MinIO Object Storage
  - storage-postgres       # PostgreSQL Database
  - storage-longhorn       # Longhorn Storage
  - storage-redis          # Redis Cache
```

---

## 🔍 트러블슈팅

### 문제 1: "No data" 표시
**원인**: Prometheus에서 메트릭을 수집하지 못함

**해결:**
```bash
# 1. Prometheus Target 상태 확인
kubectl --context cluster-01 port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# 브라우저에서 http://localhost:9090 접속
# Status → Targets 에서 dataops-dev 클러스터 컴포넌트 확인

# 2. ServiceMonitor 확인
kubectl --context cluster-01 get servicemonitor -n monitoring | grep dataops

# 3. 메트릭 레이블 확인
# Prometheus UI → Graph 에서 쿼리 실행:
up{cluster="dataops-dev"}
```

### 문제 2: 전체 상태가 항상 DOWN
**원인**: PromQL 쿼리 오류 또는 레이블 불일치

**해결:**
```promql
# 각 클러스터별 상태 개별 확인
min(up{job=~".*portal.*", cluster="dataops-dev"})
min(up{job=~".*compute.*", cluster="dataops-dev"})
min(up{job=~".*storage.*", cluster="dataops-dev"})

# 결과가 1이면 정상, 0이면 문제
```

### 문제 3: CPU/Memory 사용률 표시 안 됨
**원인**: node-exporter 미설치 또는 레이블 누락

**해결:**
```bash
# node-exporter 설치 확인
kubectl --context cluster-01 get pods -n monitoring -l app.kubernetes.io/name=node-exporter

# node-exporter 메트릭 확인
kubectl --context cluster-01 port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Prometheus UI에서 쿼리:
node_cpu_seconds_total{cluster="dataops-dev"}
node_memory_MemTotal_bytes{cluster="dataops-dev"}
```

---

## 📊 대시보드 커스터마이징

### 임계값 변경

#### CPU 임계값 수정
```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"color": "green", "value": null},
    {"color": "yellow", "value": 70},  // 70% 이상 노란색
    {"color": "red", "value": 85}      // 85% 이상 빨간색
  ]
}
```

#### Memory 임계값 수정
```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    {"color": "green", "value": null},
    {"color": "yellow", "value": 80},  // 80% 이상 노란색
    {"color": "red", "value": 90}      // 90% 이상 빨간색
  ]
}
```

### 색상 변경 (파스텔 톤 유지)

현재 적용된 색상:
```css
--portal-color: #B8D8F0;    /* 연한 파란색 */
--compute-color: #B8E5C5;   /* 연한 녹색 */
--storage-color: #D5C9E8;   /* 연한 보라색 */
```

색상 변경 방법:
1. Grafana UI에서 대시보드 열기
2. 패널 제목 클릭 → **Edit**
3. 우측 **Overrides** 탭 클릭
4. **Color** → **Fixed color** 에서 색상 코드 변경
5. **Save dashboard** 클릭

### 자동 새로고침 간격 변경

현재 설정: **30초**

변경 방법:
1. 대시보드 우측 상단 **⏱️** 아이콘 클릭
2. Refresh interval 선택 (10s, 30s, 1m, 5m)
3. 또는 Dashboard Settings → Time options에서 변경

---

## 🚀 알림 설정 (선택사항)

### Grafana Alert 추가

#### 1. 전체 클러스터 DOWN 알림
```yaml
Alert Rule:
  Name: DataOps Dev 클러스터 전체 DOWN
  Condition:
    Query: (min(up{job=~".*portal.*", cluster="dataops-dev"}) * min(up{job=~".*compute.*", cluster="dataops-dev"}) * min(up{job=~".*storage.*", cluster="dataops-dev"})) == 0
    Threshold: = 0
  Notification: Slack, Email
  Message: "🚨 DataOps Dev 클러스터 전체가 DOWN 상태입니다!"
```

#### 2. 개별 클러스터 DOWN 알림
```yaml
Portal DOWN:
  Condition: min(up{job=~".*portal.*", cluster="dataops-dev"}) == 0
  Message: "🔴 Portal 클러스터 DOWN"

Compute DOWN:
  Condition: min(up{job=~".*compute.*", cluster="dataops-dev"}) == 0
  Message: "🔴 Compute 클러스터 DOWN"

Storage DOWN:
  Condition: min(up{job=~".*storage.*", cluster="dataops-dev"}) == 0
  Message: "🔴 Storage 클러스터 DOWN"
```

#### 3. 알림 채널 설정
```bash
# Grafana UI → Alerting → Contact points → New contact point
# Slack Webhook URL 또는 Email SMTP 설정
```

---

## 📈 활용 시나리오

### 시나리오 1: 포털 메인 화면 임베딩
```html
<!-- 포털 메인 페이지에 iframe으로 임베딩 -->
<iframe
  src="http://grafana.k8s-cluster-01.miribit.lab/d/dataops-dev-health-v1/dataops-dev-클러스터-health-status?orgId=1&kiosk=tv"
  width="100%"
  height="600px"
  frameborder="0">
</iframe>
```

**Kiosk 모드 옵션:**
- `?kiosk=tv`: 메뉴 숨김, 전체 화면
- `?kiosk=1`: 메뉴 숨김
- `&refresh=30s`: 자동 새로고침

### 시나리오 2: TV 모니터 표시
```
대형 모니터에 전체 화면으로 표시
- 브라우저를 전체 화면 모드 (F11)
- URL: http://grafana.../d/dataops-dev-health-v1?kiosk=tv&refresh=30s
- 자동 새로고침으로 실시간 모니터링
```

### 시나리오 3: 모바일 앱 연동
```javascript
// React Native / Flutter 등에서 WebView 사용
<WebView
  source={{ uri: 'http://grafana.../d/dataops-dev-health-v1?kiosk=1' }}
  style={{ flex: 1 }}
/>
```

---

## ✅ 배포 검증 체크리스트

### 사전 요구사항
- [ ] Prometheus 설치 완료
- [ ] Grafana 설치 완료
- [ ] node-exporter 설치 완료 (CPU/Memory 메트릭)
- [ ] ServiceMonitor 생성 완료 (각 컴포넌트별)

### 배포 확인
- [ ] 대시보드 Import 성공
- [ ] 전체 상태 신호등 표시
- [ ] Portal/Compute/Storage 신호등 표시
- [ ] 상세 테이블에 데이터 표시
- [ ] 컴포넌트 Donut Chart 표시
- [ ] 가동률 추이 그래프 표시
- [ ] 자동 새로고침 동작 (30초)

### 기능 테스트
- [ ] 컴포넌트 Down 시뮬레이션 (Pod 삭제)
  ```bash
  kubectl --context cluster-01 delete pod <portal-pod-name> -n <namespace>
  ```
- [ ] 신호등 색상 변경 확인 (🟢 → 🔴)
- [ ] 가동률 그래프 변화 확인

---

## 📚 참고 자료

- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
- [Prometheus PromQL 가이드](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Grafana Stat Panel 문서](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/stat/)
- [Grafana Alert 설정 가이드](https://grafana.com/docs/grafana/latest/alerting/)

---

## 🎉 결론

✅ **DataOps Dev 클러스터 Health Status 대시보드 생성 완료**

**주요 특징:**
- 🚦 신호등 형태로 직관적인 상태 표시
- 🌐⚙️💾 Portal, Compute, Storage 각 클러스터 구분
- 📊 상세 테이블 및 트렌드 그래프 제공
- 🎨 파스텔 색상 시스템 적용 (눈의 피로도 최소화)
- 🔄 30초 자동 새로고침

**접속 정보:**
- **URL**: http://grafana.k8s-cluster-01.miribit.lab/d/dataops-dev-health-v1
- **UID**: `dataops-dev-health-v1`
- **검색어**: "DataOps-Dev-클러스터-Health-Status"

---

**작성자**: Platform Engineering Team
**최종 수정**: 2025-11-10
**버전**: 1.0
