# 새로운 Prometheus + Thanos 멀티클러스터 아키텍처

## 목표

1. **kube-prometheus-stack Helm Chart 활용**
   - values.yaml로 모든 설정 관리
   - Prometheus Operator 자동 배포
   - ServiceMonitor/PodMonitor 자동 감지

2. **최소한의 명세 파일**
   - Kustomize + Helm 통합
   - Overlay로 클러스터별 차별화
   - ArgoCD GitOps 배포

3. **자동 Service Discovery**
   - Prometheus Operator가 ServiceMonitor 자동 감지
   - 새 서비스 추가 시 ServiceMonitor만 생성
   - 각 클러스터 독립적으로 운영

---

## 새로운 디렉토리 구조

```
deploy/
├── base/
│   └── kube-prometheus-stack/
│       ├── kustomization.yaml          # Helm Chart 참조
│       ├── Chart.yaml                  # Helm Chart 정의
│       └── values.yaml                 # 공통 기본 설정 (한글 주석)
│
└── overlays/
    ├── cluster-01-central/
    │   └── kube-prometheus-stack/
    │       ├── kustomization.yaml      # Base + Thanos 컴포넌트
    │       ├── values-central.yaml     # 중앙 클러스터 전용 설정
    │       ├── thanos-receiver.yaml    # Thanos Receiver (수동 배포)
    │       ├── thanos-query.yaml       # Thanos Query
    │       ├── thanos-store.yaml       # Thanos Store
    │       ├── thanos-compactor.yaml   # Thanos Compactor
    │       └── thanos-ruler.yaml       # Thanos Ruler
    │
    ├── cluster-02-edge/
    │   └── kube-prometheus-stack/
    │       ├── kustomization.yaml      # Base 참조
    │       └── values-edge.yaml        # 엣지 클러스터 전용 설정
    │
    ├── cluster-03-edge/
    │   └── kube-prometheus-stack/
    │       ├── kustomization.yaml
    │       └── values-edge.yaml
    │
    └── cluster-04-edge/
        └── kube-prometheus-stack/
            ├── kustomization.yaml
            └── values-edge.yaml
```

---

## 배포 아키텍처

### 중앙 클러스터 (Cluster-01)

```yaml
kube-prometheus-stack (Helm):
  ├── Prometheus Operator (자동)
  ├── Prometheus (Full 모드)
  │   ├── ServiceMonitor 자동 감지
  │   ├── 로컬 메트릭 수집
  │   └── Thanos Sidecar (S3 업로드)
  ├── Grafana
  ├── Alertmanager
  ├── node-exporter (자동)
  └── kube-state-metrics (자동)

Thanos 컴포넌트 (수동 배포):
  ├── Thanos Receiver (엣지 메트릭 수신)
  ├── Thanos Query (통합 쿼리)
  ├── Thanos Store (S3 장기 데이터)
  ├── Thanos Compactor (압축/다운샘플링)
  └── Thanos Ruler (글로벌 Rule)
```

### 엣지 클러스터 (Cluster-02/03/04)

```yaml
kube-prometheus-stack (Helm):
  ├── Prometheus Operator (자동)
  ├── Prometheus (Agent 모드)
  │   ├── ServiceMonitor 자동 감지
  │   ├── 로컬 메트릭 수집
  │   └── Remote Write → Thanos Receiver
  ├── node-exporter (자동)
  └── kube-state-metrics (자동)

비활성화:
  ├── Grafana (중앙에서만)
  ├── Alertmanager (중앙에서만)
  └── Thanos Sidecar (Agent 모드 사용)
```

---

## Kustomize + Helm 통합 방식

### Base 구성

```yaml
# deploy/base/kube-prometheus-stack/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: kube-prometheus-stack
    repo: https://prometheus-community.github.io/helm-charts
    version: 78.2.1
    releaseName: kube-prometheus-stack
    namespace: monitoring
    valuesFile: values.yaml
```

### Overlay 구성 (중앙)

```yaml
# deploy/overlays/cluster-01-central/kube-prometheus-stack/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

bases:
  - ../../../base/kube-prometheus-stack

helmCharts:
  - name: kube-prometheus-stack
    repo: https://prometheus-community.github.io/helm-charts
    version: 78.2.1
    releaseName: kube-prometheus-stack
    namespace: monitoring
    valuesFile: values-central.yaml

resources:
  - thanos-receiver.yaml
  - thanos-query.yaml
  - thanos-store.yaml
  - thanos-compactor.yaml
  - thanos-ruler.yaml
  - thanos-s3-secret.yaml
```

### Overlay 구성 (엣지)

```yaml
# deploy/overlays/cluster-02-edge/kube-prometheus-stack/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

bases:
  - ../../../base/kube-prometheus-stack

helmCharts:
  - name: kube-prometheus-stack
    repo: https://prometheus-community.github.io/helm-charts
    version: 78.2.1
    releaseName: kube-prometheus-stack
    namespace: monitoring
    valuesFile: values-edge.yaml
```

---

## values.yaml 핵심 설정

### Base values.yaml (공통)

```yaml
# Prometheus Operator 설정
prometheusOperator:
  enabled: true

# ServiceMonitor 자동 감지
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # 모든 ServiceMonitor 감지
    podMonitorSelectorNilUsesHelmValues: false      # 모든 PodMonitor 감지
```

### values-central.yaml (중앙)

```yaml
# Full Prometheus 모드
prometheus:
  prometheusSpec:
    mode: server  # Full 모드
    externalLabels:
      cluster: cluster-01-central
    thanos:
      enabled: true  # Sidecar 활성화

# Grafana 활성화
grafana:
  enabled: true

# Alertmanager 활성화
alertmanager:
  enabled: true
```

### values-edge.yaml (엣지)

```yaml
# Agent 모드
prometheus:
  prometheusSpec:
    mode: agent  # Agent 모드
    externalLabels:
      cluster: cluster-02-edge  # 클러스터별 변경
    remoteWrite:
      - url: http://thanos-receiver.k8s-cluster-01.miribit.lab/api/v1/receive

# Grafana 비활성화
grafana:
  enabled: false

# Alertmanager 비활성화
alertmanager:
  enabled: false
```

---

## ServiceMonitor 자동 감지 원리

### 1. Prometheus Operator 배포
```
Helm Chart → Prometheus Operator → CRD 생성
```

### 2. ServiceMonitor 생성
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
```

### 3. 자동 감지 과정
```
ServiceMonitor 생성
  ↓
Prometheus Operator 감지
  ↓
Prometheus Config 자동 업데이트
  ↓
자동으로 Scrape 시작
```

---

## ArgoCD Application 구조

```yaml
# argocd/apps/cluster-01-central/kube-prometheus-stack.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
spec:
  project: monitoring
  source:
    repoURL: https://github.com/kronenz/prometheua-HA-kustomize
    targetRevision: main
    path: deploy/overlays/cluster-01-central/kube-prometheus-stack
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 마이그레이션 계획

### Phase 1: Base 구성
1. ✅ Base values.yaml 작성 (한글 주석)
2. ✅ Base kustomization.yaml 작성
3. ✅ Chart.yaml 작성

### Phase 2: 중앙 클러스터
1. ✅ values-central.yaml 작성
2. ✅ Thanos 컴포넌트 YAML 유지 (기존 것 활용)
3. ✅ kustomization.yaml 작성

### Phase 3: 엣지 클러스터
1. ✅ values-edge.yaml 작성
2. ✅ 클러스터별 kustomization.yaml 작성
3. ✅ 기존 prometheus-agent 제거

### Phase 4: ArgoCD 연동
1. ✅ Application 명세 작성
2. ✅ 배포 및 검증

---

## 장점

### 1. 명세 파일 최소화
- **기존**: 수십 개의 YAML 파일
- **신규**: values.yaml 2-3개 + Thanos 컴포넌트 5개

### 2. 자동 Service Discovery
- ServiceMonitor만 생성하면 자동 수집
- 수동 prometheus.yml 편집 불필요

### 3. Operator 기반 관리
- 선언적 관리 (CRD)
- 자동 설정 업데이트
- 표준 방식

### 4. GitOps 친화적
- Kustomize + Helm 통합
- ArgoCD 자동 동기화
- 버전 관리 용이

---

## 다음 단계

1. ✅ Base values.yaml 작성 (상세 한글 주석)
2. ✅ 중앙 클러스터 values-central.yaml 작성
3. ✅ 엣지 클러스터 values-edge.yaml 작성
4. ✅ Kustomization 파일 작성
5. ✅ ArgoCD Application 작성
6. ✅ 배포 및 검증
7. ✅ 문서화
