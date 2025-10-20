# Kustomize 구조

## 📋 개요

Kustomize를 사용하여 base 설정과 클러스터별 overlay를 관리하고, Helm Chart와 통합하여 배포합니다.

---

## 🎯 목표

- Base/Overlay 패턴 이해
- Helm Chart + Kustomize 통합
- 클러스터별 설정 분리
- 재사용 가능한 구조 설계

---

## 🏗️ 디렉토리 구조

```
deploy/
├── base/                                # 공통 기본 설정
│   ├── kube-prometheus-stack/
│   │   ├── kustomization.yaml          # Helm Chart 참조
│   │   └── values.yaml                 # 공통 values
│   │
│   ├── prometheus-agent/
│   │   ├── kustomization.yaml
│   │   └── values.yaml
│   │
│   ├── longhorn/
│   │   ├── kustomization.yaml
│   │   └── longhorn-values.yaml
│   │
│   └── opensearch-cluster/
│       ├── kustomization.yaml
│       └── opensearch-cluster.yaml
│
└── overlays/                            # 클러스터별 설정
    ├── cluster-01-central/              # 중앙 클러스터
    │   ├── kustomization.yaml          # Overlay 메타
    │   │
    │   ├── kube-prometheus-stack/
    │   │   ├── kustomization.yaml
    │   │   ├── values-patch.yaml       # Values 오버라이드
    │   │   ├── thanos-receiver.yaml    # 추가 리소스
    │   │   ├── thanos-query.yaml
    │   │   ├── thanos-store.yaml
    │   │   ├── thanos-compactor.yaml
    │   │   └── thanos-ruler.yaml
    │   │
    │   ├── longhorn/
    │   │   ├── kustomization.yaml
    │   │   └── longhorn-s3-secret.yaml
    │   │
    │   └── opensearch-cluster/
    │       ├── kustomization.yaml
    │       └── opensearch-cluster-patch.yaml
    │
    ├── cluster-02-edge/                 # 엣지 클러스터 (멀티테넌시)
    │   ├── kustomization.yaml
    │   │
    │   ├── prometheus-agent-a/          # Tenant A
    │   │   ├── kustomization.yaml
    │   │   └── remote-write-patch.yaml
    │   │
    │   ├── prometheus-agent-b/          # Tenant B
    │   │   ├── kustomization.yaml
    │   │   └── remote-write-patch.yaml
    │   │
    │   └── longhorn/
    │       └── kustomization.yaml
    │
    ├── cluster-03-edge/                 # 엣지 클러스터
    │   ├── kustomization.yaml
    │   │
    │   ├── prometheus-agent/
    │   │   ├── kustomization.yaml
    │   │   └── remote-write-patch.yaml
    │   │
    │   └── longhorn/
    │       └── kustomization.yaml
    │
    └── cluster-04-edge/                 # 엣지 클러스터
        ├── kustomization.yaml
        │
        ├── prometheus-agent/
        │   ├── kustomization.yaml
        │   └── remote-write-patch.yaml
        │
        └── longhorn/
            └── kustomization.yaml
```

---

## 1️⃣ Base 구조

### base/kube-prometheus-stack/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

# Helm Chart 참조
helmCharts:
- name: kube-prometheus-stack
  repo: https://prometheus-community.github.io/helm-charts
  version: 58.0.0
  releaseName: kube-prometheus-stack
  namespace: monitoring
  valuesFile: values.yaml
  includeCRDs: true

# 공통 레이블
commonLabels:
  managed-by: argocd
  component: monitoring
```

### base/kube-prometheus-stack/values.yaml

```yaml
# Prometheus Operator 공통 설정
prometheus-operator:
  enabled: true

# Prometheus 기본 설정
prometheus:
  enabled: true

  prometheusSpec:
    # 공통 리소스
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi

    # 공통 Retention
    retention: 15d

    # 공통 Storage Class
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

# Grafana 기본 설정
grafana:
  enabled: true

  adminPassword: admin123  # overlay에서 오버라이드

  persistence:
    enabled: true
    storageClassName: longhorn
    size: 10Gi

  resources:
    requests:
      cpu: 200m
      memory: 512Mi

# Alertmanager
alertmanager:
  enabled: true

# Node Exporter
nodeExporter:
  enabled: true

# Kube State Metrics
kubeStateMetrics:
  enabled: true
```

---

### base/prometheus-agent/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

helmCharts:
- name: prometheus
  repo: https://prometheus-community.github.io/helm-charts
  version: 25.11.0
  releaseName: prometheus-agent
  namespace: monitoring
  valuesFile: values.yaml
```

### base/prometheus-agent/values.yaml

```yaml
# Prometheus Agent Mode (공통)
server:
  # Agent Mode 활성화
  enableAgentMode: true

  # 리소스
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  # Persistence (WAL)
  persistentVolume:
    enabled: true
    size: 10Gi
    storageClass: longhorn

  # Remote Write (overlay에서 설정)
  remoteWrite: []

  # Scrape 설정
  global:
    scrape_interval: 15s
    evaluation_interval: 15s

# Alert/Recording Rules 비활성화 (Agent Mode)
serverFiles:
  alerting_rules.yml: {}
  recording_rules.yml: {}

# Alertmanager 비활성화
alertmanager:
  enabled: false

# Pushgateway 비활성화
pushgateway:
  enabled: false

# Node Exporter
nodeExporter:
  enabled: true

# Kube State Metrics
kube-state-metrics:
  enabled: true
```

---

## 2️⃣ Overlay 구조 (Central)

### overlays/cluster-01-central/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

# Base 참조
bases:
  - ../../base/kube-prometheus-stack
  - ../../base/longhorn
  - ../../base/opensearch-cluster

# Overlay 리소스
resources:
  - kube-prometheus-stack/thanos-receiver.yaml
  - kube-prometheus-stack/thanos-query.yaml
  - kube-prometheus-stack/thanos-store.yaml
  - kube-prometheus-stack/thanos-compactor.yaml
  - kube-prometheus-stack/thanos-ruler.yaml

# Values 패치
patchesStrategicMerge:
  - kube-prometheus-stack/values-patch.yaml
  - longhorn/longhorn-s3-secret.yaml
  - opensearch-cluster/opensearch-cluster-patch.yaml

# 공통 레이블 추가
commonLabels:
  cluster: cluster-01
  role: central
```

### overlays/cluster-01-central/kube-prometheus-stack/values-patch.yaml

```yaml
# Prometheus HA 설정 오버라이드
prometheus:
  prometheusSpec:
    # Replicas 증가
    replicas: 2

    # 외부 레이블
    externalLabels:
      cluster: cluster-01
      role: central
      replica: $(POD_NAME)

    # Storage 증설
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 100Gi  # 50Gi → 100Gi

    # Thanos Sidecar
    thanos:
      image: quay.io/thanos/thanos:v0.31.0
      version: v0.31.0
      objectStorageConfig:
        key: objstore.yml
        name: thanos-objstore-secret

# Grafana 비밀번호 오버라이드
grafana:
  adminPassword: "ChangeMe123!"

  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - grafana.k8s-cluster-01.miribit.lab
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.k8s-cluster-01.miribit.lab
```

---

## 3️⃣ Overlay 구조 (Edge)

### overlays/cluster-02-edge/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

# Base 참조
bases:
  - ../../base/prometheus-agent
  - ../../base/longhorn

# Overlay 리소스
resources:
  - prometheus-agent/remote-write-patch.yaml

# 레이블
commonLabels:
  cluster: cluster-02
  role: edge
```

### overlays/cluster-02-edge/prometheus-agent/remote-write-patch.yaml

```yaml
# Prometheus Agent Remote Write 설정
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-agent-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      external_labels:
        cluster: cluster-02
        role: edge

    # Remote Write to Central Thanos Receiver
    remote_write:
      - url: https://thanos-receive.monitoring.svc.cluster-01:19291/api/v1/receive
        remote_timeout: 30s

        # Queue 설정
        queue_config:
          capacity: 20000
          max_shards: 100
          min_shards: 10
          max_samples_per_send: 10000
          batch_send_deadline: 10s

        # Write Relabeling
        write_relabel_configs:
          # 클러스터 레이블 추가
          - target_label: cluster
            replacement: cluster-02

          # 고빈도 메트릭 제외
          - source_labels: [__name__]
            regex: 'go_.*|process_.*'
            action: drop

    # Scrape 설정
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
```

---

## 4️⃣ Helm + Kustomize 통합

### kustomization.yaml에서 Helm 사용

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Helm Chart 직접 참조
helmCharts:
- name: kube-prometheus-stack
  repo: https://prometheus-community.github.io/helm-charts
  version: 58.0.0
  releaseName: kube-prometheus-stack
  namespace: monitoring
  valuesFile: values.yaml

  # Values 인라인 (선택적)
  valuesInline:
    prometheus:
      prometheusSpec:
        replicas: 2
```

### 배포 명령어

```bash
# Kustomize + Helm 빌드
kustomize build deploy/overlays/cluster-01-central --enable-helm

# 직접 배포
kustomize build deploy/overlays/cluster-01-central --enable-helm | kubectl apply -f -

# ArgoCD에서 자동 실행 (--enable-helm 옵션)
```

---

## 5️⃣ 패치 전략

### Strategic Merge Patch

```yaml
# patchesStrategicMerge
patchesStrategicMerge:
  - patch-file.yaml

# patch-file.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus-kube-prometheus-stack-prometheus
spec:
  replicas: 2  # 1 → 2로 변경
  template:
    spec:
      containers:
      - name: prometheus
        resources:
          requests:
            memory: 4Gi  # 2Gi → 4Gi
```

### JSON 6902 Patch

```yaml
# patchesJson6902
patchesJson6902:
  - target:
      group: apps
      version: v1
      kind: StatefulSet
      name: prometheus-kube-prometheus-stack-prometheus
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 2
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: 4Gi
```

---

## 6️⃣ ConfigMap/Secret Generator

### ConfigMap Generator

```yaml
# kustomization.yaml
configMapGenerator:
  - name: thanos-objstore-config
    namespace: monitoring
    files:
      - objstore.yml
    options:
      disableNameSuffixHash: true

# objstore.yml
type: S3
config:
  bucket: thanos-cluster-01
  endpoint: s3.minio.miribit.lab
  access_key: ${S3_ACCESS_KEY}
  secret_key: ${S3_SECRET_KEY}
  insecure: false
```

### Secret Generator

```yaml
# kustomization.yaml
secretGenerator:
  - name: thanos-s3-secret
    namespace: monitoring
    envs:
      - s3-credentials.env
    options:
      disableNameSuffixHash: true

# s3-credentials.env
S3_ACCESS_KEY=minio
S3_SECRET_KEY=minio123
```

---

## 7️⃣ 변수 치환 (Vars)

### Kustomize Vars

```yaml
# kustomization.yaml
vars:
  - name: CLUSTER_NAME
    objref:
      kind: ConfigMap
      name: cluster-info
      apiVersion: v1
    fieldref:
      fieldpath: data.cluster_name

# 사용 예시
containers:
  - name: prometheus
    env:
      - name: CLUSTER
        value: $(CLUSTER_NAME)
```

---

## 📊 빌드 및 검증

### 로컬 빌드

```bash
# Overlay 빌드 (Helm 포함)
kustomize build deploy/overlays/cluster-01-central --enable-helm

# 출력 확인 (YAML)
kustomize build deploy/overlays/cluster-01-central --enable-helm > output.yaml

# 리소스 수 확인
kustomize build deploy/overlays/cluster-01-central --enable-helm | grep -c "^---"
```

### Dry-run 배포

```bash
# Dry-run으로 검증
kustomize build deploy/overlays/cluster-01-central --enable-helm \
  | kubectl apply --dry-run=client -f -

# Server-side Dry-run
kustomize build deploy/overlays/cluster-01-central --enable-helm \
  | kubectl apply --dry-run=server -f -
```

### Diff 확인

```bash
# 현재 클러스터와 비교
kustomize build deploy/overlays/cluster-01-central --enable-helm \
  | kubectl diff -f -
```

---

## 🎯 베스트 프랙티스

### 1. Base는 최소한으로

```yaml
# ❌ Base에 클러스터 특정 설정
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: cluster-01  # 클러스터 특정

# ✅ Overlay에서 설정
# base는 공통 설정만
```

### 2. Values 파일 분리

```
base/
  ├── values.yaml              # 공통
  └── values-production.yaml   # 프로덕션 공통

overlays/
  ├── cluster-01/
  │   └── values-patch.yaml    # 클러스터 특정
```

### 3. Secret은 External Secrets 사용

```yaml
# ExternalSecret (권장)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: thanos-s3-secret
spec:
  secretStoreRef:
    name: vault-backend
  target:
    name: thanos-s3-secret
  data:
    - secretKey: access_key
      remoteRef:
        key: thanos/s3
        property: access_key
```

### 4. 버전 관리

```yaml
# Helm Chart 버전 명시
helmCharts:
- name: kube-prometheus-stack
  version: 58.0.0  # 정확한 버전 (latest 금지)
```

---

## 🔗 관련 문서

- **ArgoCD 설치** → [ArgoCD-설치-및-설정.md](./ArgoCD-설치-및-설정.md)
- **중앙 클러스터 배포** → [중앙-클러스터-배포.md](./중앙-클러스터-배포.md)
- **배포 검증** → [배포-검증.md](./배포-검증.md)

---

**최종 업데이트**: 2025-10-20
