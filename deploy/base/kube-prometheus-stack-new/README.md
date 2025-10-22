# kube-prometheus-stack Base 설정

## 📋 개요

이 디렉토리는 **kube-prometheus-stack Helm Chart**를 Kustomize로 관리하기 위한 Base 설정입니다.

모든 클러스터(중앙/엣지)의 공통 설정을 정의하며, Overlay에서 이 Base를 참조하여 클러스터별로 커스터마이징합니다.

---

## 📁 파일 구조

```
deploy/base/kube-prometheus-stack-new/
├── Chart.yaml              # Helm Chart 메타데이터
├── kustomization.yaml      # Kustomize 설정 (Helm 통합)
├── values.yaml             # 공통 Base values (상세 한글 주석)
└── README.md               # 이 파일
```

---

## 🎯 주요 기능

### 1. **Prometheus Operator 자동 배포**
- CRD 기반 Prometheus 관리
- ServiceMonitor/PodMonitor/PrometheusRule 지원

### 2. **ServiceMonitor 자동 감지**
```yaml
# values.yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # 🔑 핵심 설정
```
- **모든 네임스페이스**의 **모든 ServiceMonitor** 자동 감지
- 수동 prometheus.yml 편집 불필요

### 3. **통합 모니터링 스택**
- ✅ Prometheus (메트릭 수집)
- ✅ Alertmanager (Alert 관리)
- ✅ Grafana (시각화)
- ✅ node-exporter (노드 메트릭)
- ✅ kube-state-metrics (K8s 리소스 메트릭)

### 4. **Kustomize + Helm 통합**
- Helm Chart를 Kustomize로 감싸서 관리
- Base + Overlay 패턴으로 환경별 분리

---

## 🔧 주요 설정 (values.yaml)

### ServiceMonitor 자동 감지 설정
```yaml
prometheus:
  prometheusSpec:
    # 모든 ServiceMonitor 자동 감지
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorNamespaceSelector: {}

    # 모든 PodMonitor 자동 감지
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorNamespaceSelector: {}
```

### 리소스 설정
```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 1
        memory: 2Gi
```

### 저장소 설정
```yaml
prometheus:
  prometheusSpec:
    retention: 15d  # 데이터 보관 기간
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          resources:
            requests:
              storage: 20Gi
```

---

## 📝 사용 방법

### 1. Overlay에서 참조

**중앙 클러스터 예시:**
```yaml
# deploy/overlays/cluster-01-central/kube-prometheus-stack/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

# Base 참조
bases:
  - ../../../base/kube-prometheus-stack-new

# 중앙 클러스터 전용 설정
helmCharts:
  - name: kube-prometheus-stack
    repo: https://prometheus-community.github.io/helm-charts
    version: "78.2.1"
    releaseName: kube-prometheus-stack
    namespace: monitoring
    valuesFile: values-central.yaml  # Base + 이 파일
```

### 2. ServiceMonitor 추가

**자동 감지 예시:**
```yaml
# my-app-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-namespace  # 어떤 네임스페이스든 OK
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
```

```bash
# ServiceMonitor 생성
kubectl apply -f my-app-servicemonitor.yaml

# 자동으로 Prometheus가 감지하고 Scrape 시작!
# (추가 설정 불필요)
```

### 3. 빌드 테스트

```bash
# Base 단독 빌드 (테스트용)
kustomize build deploy/base/kube-prometheus-stack-new

# Overlay 포함 빌드
kustomize build deploy/overlays/cluster-01-central/kube-prometheus-stack
```

---

## 🔍 자동 Service Discovery 원리

```
1. ServiceMonitor 생성
   kubectl apply -f my-servicemonitor.yaml

2. Prometheus Operator가 감지
   (serviceMonitorSelectorNilUsesHelmValues: false 덕분)

3. Prometheus Config 자동 업데이트
   Operator가 prometheus.yml에 scrape_config 추가

4. 자동 Scrape 시작
   설정 리로드 후 메트릭 수집 시작
```

**장점:**
- ✅ 수동 prometheus.yml 편집 불필요
- ✅ 새 서비스 추가 시 ServiceMonitor만 생성
- ✅ 선언적 관리 (GitOps 친화적)
- ✅ 네임스페이스 격리 가능

---

## ⚙️ 커스터마이징

### Base values.yaml 수정 (모든 클러스터 공통)
```bash
# 공통 설정 변경
vi deploy/base/kube-prometheus-stack-new/values.yaml

# 예: Scrape 간격 변경
prometheus:
  prometheusSpec:
    scrapeInterval: 15s  # 30s → 15s
```

### Overlay values 추가 (클러스터별)
```bash
# 중앙 클러스터만 Grafana 활성화
vi deploy/overlays/cluster-01-central/kube-prometheus-stack/values-central.yaml

grafana:
  enabled: true  # 중앙만 활성화

# 엣지 클러스터는 Grafana 비활성화
vi deploy/overlays/cluster-02-edge/kube-prometheus-stack/values-edge.yaml

grafana:
  enabled: false  # 엣지는 비활성화
```

---

## 📊 모니터링 대상

### 자동으로 수집되는 메트릭

**Kubernetes 컴포넌트:**
- `kube-apiserver`
- `kubelet` + `cAdvisor`
- `kube-controller-manager`
- `kube-scheduler`
- `kube-proxy`
- `coredns`
- `etcd`

**시스템 메트릭:**
- `node-exporter` (CPU, 메모리, 디스크, 네트워크)
- `kube-state-metrics` (Pod, Deployment, Service 상태)

**Prometheus 자체:**
- Prometheus 내부 메트릭
- Prometheus Operator 메트릭

---

## 🚀 다음 단계

### 1. Overlay 작성
- [중앙 클러스터 Overlay](../../overlays/cluster-01-central/kube-prometheus-stack/)
- [엣지 클러스터 Overlay](../../overlays/cluster-02-edge/kube-prometheus-stack/)

### 2. Thanos 통합
- 중앙 클러스터에 Thanos 컴포넌트 추가
- 엣지 클러스터는 Prometheus Agent 모드 사용

### 3. ArgoCD 배포
- Application 명세 작성
- GitOps 자동 동기화

---

## 📚 참고 문서

- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [ServiceMonitor API](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#servicemonitor)
- [Kustomize Helm Integration](https://kubectl.docs.kubernetes.io/references/kustomize/builtins/#_helmchartinflationgenerator_)

---

## ⚠️ 주의사항

### 1. Helm Chart 버전
- 현재 버전: `78.2.1`
- 버전 변경 시 values.yaml 호환성 확인 필수

### 2. CRD 설치
- `includeCRDs: true` 유지 필수
- CRD 없으면 ServiceMonitor 사용 불가

### 3. ServiceMonitor Selector
- `serviceMonitorSelectorNilUsesHelmValues: false` 유지
- true로 변경 시 자동 감지 비활성화

### 4. 리소스 제한
- 클러스터 규모에 맞게 조정
- 작은 값으로 시작 후 모니터링하며 증가

---

## 🔧 트러블슈팅

### ServiceMonitor가 감지되지 않을 때
```bash
# 1. Prometheus Operator 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-operator

# 2. ServiceMonitor 확인
kubectl get servicemonitor -A

# 3. Prometheus Target 확인
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090/targets

# 4. Operator 로그 확인
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
```

### Prometheus OOMKilled
```yaml
# values.yaml 수정
prometheus:
  prometheusSpec:
    resources:
      limits:
        memory: 4Gi  # 증가
    retention: 7d    # 기간 단축
```

---

## 📞 지원

문제 발생 시:
1. 이 README 참조
2. values.yaml의 주석 확인
3. GitHub Issue 생성

---

**마지막 업데이트:** 2025-10-22
**작성자:** Thanos Multi-Cluster Team
