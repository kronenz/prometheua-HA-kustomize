# 배포 구성 버전 정보

최종 업데이트: 2025-10-26

## 사용된 버전

### Helm Charts
- **kube-prometheus-stack**: v78.5.0 (최신, 2025년)
  - Repository: https://prometheus-community.github.io/helm-charts
  - Chart: prometheus-community/kube-prometheus-stack

### 컨테이너 이미지
- **Prometheus**: v3.7.2 (자동, kube-prometheus-stack에 포함)
  - Image: quay.io/prometheus/prometheus:v3.7.2
- **Thanos**: v0.38.0 (2025년 4월 3일 릴리스)
  - Image: quay.io/thanos/thanos:v0.38.0
  - 주요 업데이트:
    - `--matcher-cache-size` 옵션 추가 (regex matcher 캐싱)
    - Chain deduplication 알고리즘 지원
    - Query 통계 보고 수정

---

## 아키텍처 패턴

### ✅ 채택한 패턴: Prometheus Agent + Thanos Receiver

**중앙 클러스터 (Cluster-01)**:
```
Prometheus Full Mode
  ↓ (Remote Write)
Thanos Receiver → S3 (MinIO)
  ↑ (StoreAPI)
Thanos Query ← Thanos Store (S3)
  ↓
Grafana
```

**엣지 클러스터 (Cluster-02/03/04)**:
```
Prometheus Agent Mode
  ↓ (Remote Write)
Thanos Receiver (중앙)
```

### ❌ 사용하지 않는 패턴

- **Thanos Sidecar 패턴**: 사용 안함
  - Prometheus와 함께 Sidecar 컨테이너 배포하지 않음
  - 이유: Remote Write가 더 간단하고 유연함

---

## 배포 구성 요약

### 디렉토리 구조
```
deploy-new/
├── base/
│   └── kube-prometheus-stack/
│       ├── values.yaml              # 공통 기본 설정
│       └── kustomization.yaml       # Chart v78.5.0
│
└── overlays/
    ├── cluster-01-central/
    │   └── kube-prometheus-stack/
    │       ├── values-central.yaml  # Full Mode + Remote Write
    │       ├── kustomization.yaml
    │       ├── thanos-s3-secret.yaml
    │       ├── thanos-query.yaml    # v0.38.0
    │       ├── thanos-receiver.yaml # v0.38.0
    │       ├── thanos-store.yaml    # v0.38.0
    │       └── thanos-compactor.yaml # v0.38.0
    │
    ├── cluster-02-edge/
    │   └── kube-prometheus-stack/
    │       ├── values-edge.yaml     # Agent Mode
    │       └── kustomization.yaml
    │
    ├── cluster-03-edge/
    │   └── kube-prometheus-stack/
    │       ├── values-edge.yaml     # Agent Mode
    │       └── kustomization.yaml
    │
    └── cluster-04-edge/
        └── kube-prometheus-stack/
            ├── values-edge.yaml     # Agent Mode
            └── kustomization.yaml
```

### 주요 설정

#### Central 클러스터 (Cluster-01)
```yaml
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: cluster-01-central
      environment: production

    replicas: 2  # HA

    remoteWrite:
      - url: http://thanos-receiver.monitoring.svc.cluster.local:19291/api/v1/receive

    thanos:
      enabled: false  # Sidecar 사용 안함

    retention: 15d
    storage: 50Gi
```

#### Edge 클러스터 (Cluster-02/03/04)
```yaml
prometheus:
  agentMode: false  # additionalArgs로 설정

  prometheusSpec:
    additionalArgs:
      - name: enable-feature
        value: agent

    externalLabels:
      cluster: cluster-XX-edge
      environment: edge

    remoteWrite:
      - url: http://thanos-receiver.k8s-cluster-01.miribit.lab/api/v1/receive

    replicas: 1
    retention: 6h
    storage: 5Gi
```

---

## Thanos 컴포넌트 상세

### 1. Thanos Query
- **버전**: v0.38.0
- **역할**: 모든 소스 통합 쿼리
- **Store 엔드포인트**:
  - `dnssrv+_grpc._tcp.prometheus-operated.monitoring.svc.cluster.local` (사용 안함)
  - `dnssrv+_grpc._tcp.thanos-receiver-headless.monitoring.svc.cluster.local`
  - `dnssrv+_grpc._tcp.thanos-store.monitoring.svc.cluster.local`
- **Ingress**: http://thanos-query.k8s-cluster-01.miribit.lab

### 2. Thanos Receiver
- **버전**: v0.38.0
- **역할**: Remote Write 수신 및 S3 업로드
- **포트**:
  - 10901: gRPC (StoreAPI)
  - 10902: HTTP (Metrics)
  - 19291: Remote Write
- **스토리지**: 50Gi (6시간 로컬 보관)
- **Ingress**: http://thanos-receiver.k8s-cluster-01.miribit.lab

### 3. Thanos Store
- **버전**: v0.38.0
- **역할**: S3 장기 데이터 조회
- **캐시**:
  - Index: 500MB
  - Chunk Pool: 2GB
- **스토리지**: 1Gi (캐시용)

### 4. Thanos Compactor
- **버전**: v0.38.0
- **역할**: 데이터 압축 및 다운샘플링
- **Retention**:
  - Raw: 30일
  - 5분 다운샘플: 90일
  - 1시간 다운샘플: 180일
- **Delete Delay**: 48시간

---

## 업그레이드 로그

### 2025-10-26
- ✅ kube-prometheus-stack: v78.2.1 → **v78.5.0**
- ✅ Thanos: v0.36.1 → **v0.38.0**
- ✅ 아키텍처: Sidecar 패턴 → **Agent + Receiver 패턴**
- ✅ Central 클러스터: Remote Write 추가
- ✅ 모든 Thanos 컴포넌트 이미지 버전 업데이트

### 변경 사항
1. **Central values-central.yaml**:
   - Thanos Sidecar 설정 제거
   - Remote Write 설정 추가
   - 주석 업데이트

2. **모든 Thanos 매니페스트**:
   - 이미지 버전: v0.36.1 → v0.38.0

3. **모든 kustomization.yaml**:
   - Chart 버전: v78.2.1 → v78.5.0

---

## 다음 단계

### 테스트 배포
```bash
# 1. S3 Secret 설정
export S3_ACCESS_KEY="your-key"
export S3_SECRET_KEY="your-secret"
envsubst < thanos-s3-secret.yaml | kubectl apply -f -

# 2. 중앙 클러스터 배포
cd deploy-new/overlays/cluster-01-central/kube-prometheus-stack
kubectl --context cluster-01 apply -k .

# 3. 엣지 클러스터 배포
cd deploy-new/overlays/cluster-02-edge/kube-prometheus-stack
kubectl --context cluster-02 apply -k .

# 4. 검증
curl http://thanos-query.k8s-cluster-01.miribit.lab/api/v1/label/cluster/values
```

### 예상 결과
```json
{
  "status": "success",
  "data": [
    "cluster-01-central",
    "cluster-02-edge",
    "cluster-03-edge",
    "cluster-04-edge"
  ]
}
```

---

## 참고 자료

- [kube-prometheus-stack v78.5.0](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack/78.5.0)
- [Thanos v0.38.0 Release Notes](https://github.com/thanos-io/thanos/releases/tag/v0.38.0)
- [Prometheus Agent Mode](https://prometheus.io/docs/prometheus/latest/feature_flags/#prometheus-agent)
- [Thanos Receiver](https://thanos.io/tip/components/receive.md/)
