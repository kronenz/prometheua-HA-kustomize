# Thanos 멀티클러스터 모니터링 - Kustomize + Helm 배포

Prometheus Agent + Thanos Receiver 패턴을 사용한 멀티클러스터 모니터링 시스템입니다.

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                   중앙 클러스터 (Cluster-01)                     │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐         │
│  │ Prometheus   │  │ Thanos Query  │  │   Grafana    │         │
│  │ (Full Mode)  │  │  (통합 쿼리)   │  │ (시각화)     │         │
│  │ + Sidecar    │  └───────────────┘  └──────────────┘         │
│  └──────────────┘         │                                     │
│         │                 ├─────────────┬────────────┐          │
│         ↓                 ↓             ↓            ↓          │
│  ┌──────────────┐  ┌─────────────┐ ┌────────┐ ┌────────┐       │
│  │     S3       │  │   Receiver  │ │ Store  │ │Compact │       │
│  │  (MinIO)     │  │ (Remote RX) │ │(S3 RD) │ │ (압축)  │       │
│  └──────────────┘  └─────────────┘ └────────┘ └────────┘       │
└─────────────────────────────────────────────────────────────────┘
                              ↑
                 ┌────────────┼────────────┐
                 │            │            │
        ┌────────┴───┐  ┌────┴─────┐  ┌──┴────────┐
        │ Cluster-02 │  │Cluster-03│  │Cluster-04 │
        │   (Edge)   │  │  (Edge)  │  │  (Edge)   │
        │ Prometheus │  │Prometheus│  │Prometheus │
        │   Agent    │  │  Agent   │  │  Agent    │
        └────────────┘  └──────────┘  └───────────┘
```

## 디렉토리 구조

```
deploy-new/
├── base/
│   └── kube-prometheus-stack/
│       ├── values.yaml              # 공통 설정
│       └── kustomization.yaml
│
└── overlays/
    ├── cluster-01-central/          # 중앙 클러스터
    │   └── kube-prometheus-stack/
    │       ├── values-central.yaml  # 중앙 오버라이드
    │       ├── kustomization.yaml
    │       ├── thanos-s3-secret.yaml
    │       ├── thanos-query.yaml
    │       ├── thanos-receiver.yaml
    │       ├── thanos-store.yaml
    │       └── thanos-compactor.yaml
    │
    ├── cluster-02-edge/             # 엣지 클러스터 1
    │   └── kube-prometheus-stack/
    │       ├── values-edge.yaml     # 엣지 오버라이드
    │       └── kustomization.yaml
    │
    ├── cluster-03-edge/             # 엣지 클러스터 2
    │   └── kube-prometheus-stack/
    │       ├── values-edge.yaml
    │       └── kustomization.yaml
    │
    └── cluster-04-edge/             # 엣지 클러스터 3
        └── kube-prometheus-stack/
            ├── values-edge.yaml
            └── kustomization.yaml
```

## 주요 특징

### 중앙 클러스터 (Cluster-01)
- **Prometheus Full Mode** (2 replicas) + Thanos Sidecar
- **Thanos Query**: 모든 클러스터 메트릭 통합 쿼리
- **Thanos Receiver**: 엣지 클러스터 Remote Write 수신
- **Thanos Store**: S3 장기 데이터 조회
- **Thanos Compactor**: 데이터 압축 및 다운샘플링
- **Grafana**: 통합 대시보드
- **Alertmanager** (2 replicas): Alert 관리

### 엣지 클러스터 (Cluster-02/03/04)
- **Prometheus Agent Mode**: 경량 메트릭 수집
- **Remote Write**: 중앙 클러스터 Thanos Receiver로 전송
- **Node Exporter**: 노드 메트릭
- **Kube State Metrics**: K8s 리소스 메트릭

## 사전 요구사항

1. **Kubernetes 클러스터** (4개)
   - Cluster-01: 192.168.101.194 (중앙)
   - Cluster-02: 192.168.101.196 (엣지)
   - Cluster-03: 192.168.101.197 (엣지)
   - Cluster-04: 192.168.101.198 (엣지)

2. **Kubectl contexts** 설정
   ```bash
   kubectl config get-contexts
   # cluster-01, cluster-02, cluster-03, cluster-04
   ```

3. **Kustomize** (v5.0.0+)
   ```bash
   kubectl kustomize version
   ```

4. **Longhorn Storage** (모든 클러스터)
   ```bash
   kubectl get storageclass longhorn
   ```

5. **Cilium Ingress** (모든 클러스터)
   ```bash
   kubectl get ingressclass cilium
   ```

6. **MinIO S3 스토리지**
   - 엔드포인트: s3.minio.miribit.lab
   - 버킷: thanos

## 배포 순서

### 1. S3 Secret 설정

먼저 S3 접속 정보를 환경 변수로 설정합니다:

```bash
export S3_ACCESS_KEY="your-access-key"
export S3_SECRET_KEY="your-secret-key"
```

S3 Secret을 생성합니다:

```bash
cd deploy-new/overlays/cluster-01-central/kube-prometheus-stack

# Secret 파일에 환경 변수 치환
envsubst < thanos-s3-secret.yaml | kubectl --context cluster-01 apply -f -
```

### 2. 중앙 클러스터 배포 (Cluster-01)

```bash
cd deploy-new/overlays/cluster-01-central/kube-prometheus-stack

# Kustomize로 빌드 및 배포
kubectl --context cluster-01 apply -k .

# 또는 Helm을 사용한 빌드
kustomize build --enable-helm . | kubectl --context cluster-01 apply -f -
```

배포 상태 확인:

```bash
kubectl --context cluster-01 get pods -n monitoring

# 다음 Pod들이 Running 상태여야 함:
# - prometheus-kube-prometheus-stack-prometheus-0/1 (3/3)
# - kube-prometheus-stack-grafana-xxx (3/3)
# - alertmanager-kube-prometheus-stack-alertmanager-0/1 (2/2)
# - thanos-query-xxx (1/1)
# - thanos-receiver-0 (1/1)
# - thanos-store-0 (1/1)
# - thanos-compactor-0 (1/1)
```

### 3. 엣지 클러스터 배포 (Cluster-02/03/04)

각 엣지 클러스터에 순차적으로 배포합니다:

```bash
# Cluster-02
cd deploy-new/overlays/cluster-02-edge/kube-prometheus-stack
kubectl --context cluster-02 apply -k .

# Cluster-03
cd deploy-new/overlays/cluster-03-edge/kube-prometheus-stack
kubectl --context cluster-03 apply -k .

# Cluster-04
cd deploy-new/overlays/cluster-04-edge/kube-prometheus-stack
kubectl --context cluster-04 apply -k .
```

배포 상태 확인:

```bash
kubectl --context cluster-02 get pods -n monitoring
kubectl --context cluster-03 get pods -n monitoring
kubectl --context cluster-04 get pods -n monitoring

# 각 클러스터에서 다음 Pod들이 Running 상태여야 함:
# - prometheus-kube-prometheus-stack-prometheus-0 (2/2)
# - kube-prometheus-stack-kube-state-metrics-xxx (1/1)
# - prometheus-node-exporter-xxx (1/1)
```

## 배포 검증

### 1. Thanos Query 연결 확인

```bash
# Thanos Query Store 엔드포인트 확인
kubectl --context cluster-01 exec -n monitoring \
  deployment/thanos-query -- \
  wget -qO- http://localhost:9090/api/v1/stores | jq
```

다음과 같은 엔드포인트가 보여야 합니다:
- Prometheus Sidecar (cluster-01)
- Thanos Receiver (cluster-01)
- Thanos Store (cluster-01)

### 2. 클러스터 레이블 확인

```bash
# Thanos Query에서 cluster 레이블 확인
curl -s http://thanos-query.k8s-cluster-01.miribit.lab/api/v1/label/cluster/values | jq

# 결과:
# ["cluster-01-central", "cluster-02-edge", "cluster-03-edge", "cluster-04-edge"]
```

### 3. 멀티클러스터 메트릭 조회

```bash
# 모든 클러스터의 노드 정보 조회
curl -s 'http://thanos-query.k8s-cluster-01.miribit.lab/api/v1/query?query=kube_node_info' | \
  jq '.data.result[] | {cluster: .metric.cluster, node: .metric.node}'
```

### 4. Grafana 접속

```bash
# URL: http://grafana.k8s-cluster-01.miribit.lab
# Username: admin
# Password: admin123
```

Grafana에서 데이터소스 확인:
- Thanos Query가 기본 데이터소스로 설정되어 있어야 함
- 쿼리에서 `cluster` 레이블로 필터링 가능

## 운영 가이드

### 스케일링

#### Prometheus Agent 스케일링
```bash
# values-edge.yaml 수정
prometheus:
  prometheusSpec:
    replicas: 2  # 1 → 2로 변경

# 재배포
kubectl --context cluster-02 apply -k .
```

#### Thanos Receiver 스케일링
```bash
# thanos-receiver.yaml 수정
spec:
  replicas: 3  # 1 → 3으로 변경

# 재배포
kubectl --context cluster-01 apply -k .
```

### 업그레이드

```bash
# Helm 차트 버전 업그레이드
# kustomization.yaml의 version 변경
helmCharts:
  - name: kube-prometheus-stack
    version: "78.2.1"  # → 새 버전으로 변경

# 재배포
kubectl --context cluster-01 apply -k .
```

### 삭제

```bash
# 중앙 클러스터
kubectl --context cluster-01 delete -k deploy-new/overlays/cluster-01-central/kube-prometheus-stack/

# 엣지 클러스터
kubectl --context cluster-02 delete -k deploy-new/overlays/cluster-02-edge/kube-prometheus-stack/
kubectl --context cluster-03 delete -k deploy-new/overlays/cluster-03-edge/kube-prometheus-stack/
kubectl --context cluster-04 delete -k deploy-new/overlays/cluster-04-edge/kube-prometheus-stack/

# Namespace 삭제
kubectl --context cluster-01 delete namespace monitoring
kubectl --context cluster-02 delete namespace monitoring
kubectl --context cluster-03 delete namespace monitoring
kubectl --context cluster-04 delete namespace monitoring
```

## 트러블슈팅

### 1. Thanos Receiver가 메트릭을 받지 못함

```bash
# Receiver 로그 확인
kubectl --context cluster-01 logs -n monitoring thanos-receiver-0

# Remote Write 엔드포인트 테스트
curl -v http://thanos-receiver.k8s-cluster-01.miribit.lab/api/v1/receive
```

### 2. 엣지 클러스터 메트릭이 보이지 않음

```bash
# Prometheus Agent externalLabels 확인
kubectl --context cluster-02 get prometheus -n monitoring \
  kube-prometheus-stack-prometheus -o yaml | grep -A3 externalLabels

# Remote Write 설정 확인
kubectl --context cluster-02 get prometheus -n monitoring \
  kube-prometheus-stack-prometheus -o yaml | grep -A10 remoteWrite
```

### 3. S3 업로드 실패

```bash
# Sidecar 로그 확인
kubectl --context cluster-01 logs -n monitoring \
  prometheus-kube-prometheus-stack-prometheus-0 -c thanos-sidecar

# S3 Secret 확인
kubectl --context cluster-01 get secret -n monitoring thanos-s3-config -o yaml
```

## 접속 정보

### 중앙 클러스터 (Cluster-01)

| 서비스 | URL | 용도 |
|--------|-----|------|
| Grafana | http://grafana.k8s-cluster-01.miribit.lab | 대시보드 |
| Thanos Query | http://thanos-query.k8s-cluster-01.miribit.lab | 쿼리 인터페이스 |
| Thanos Receiver | http://thanos-receiver.k8s-cluster-01.miribit.lab | Remote Write 수신 |
| Prometheus | http://kube-prometheus-stack-prometheus.monitoring.svc:9090 | 로컬 쿼리 (ClusterIP) |

## 참고 자료

- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Thanos 공식 문서](https://thanos.io/)
- [Prometheus Agent Mode](https://prometheus.io/docs/prometheus/latest/feature_flags/#prometheus-agent)
- [Kustomize Documentation](https://kustomize.io/)
