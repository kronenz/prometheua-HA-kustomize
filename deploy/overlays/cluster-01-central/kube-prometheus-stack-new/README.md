# 중앙 클러스터 (Cluster-01) - kube-prometheus-stack + Thanos

## 📋 개요

이 디렉토리는 **중앙 클러스터**의 모니터링 스택 배포 설정입니다.

### 배포 구성

**1. kube-prometheus-stack (Helm)**
- ✅ Prometheus Operator
- ✅ Prometheus (Full 모드 + Thanos Sidecar)
- ✅ Grafana (모든 클러스터 시각화)
- ✅ Alertmanager (Alert 중앙 관리)
- ✅ node-exporter
- ✅ kube-state-metrics

**2. Thanos 컴포넌트 (수동 YAML)**
- ✅ Thanos Receiver (엣지 메트릭 수신)
- ✅ Thanos Query (통합 쿼리)
- ✅ Thanos Store (S3 장기 데이터)
- ✅ Thanos Compactor (압축/다운샘플링)
- ✅ Thanos Ruler (글로벌 Rule)

---

## 📁 파일 구조

```
deploy/overlays/cluster-01-central/kube-prometheus-stack-new/
├── kustomization.yaml       # Kustomize 설정 (Base + Overlay)
├── values-central.yaml      # 중앙 클러스터 전용 Helm values
├── namespace.yaml           # monitoring 네임스페이스
└── README.md                # 이 파일
```

---

## 🎯 중앙 클러스터 특징

### 1. Full Prometheus 모드
```yaml
prometheus:
  prometheusSpec:
    # Full 모드 (Agent 아님)
    # - 로컬 TSDB 저장소 사용
    # - 15일 retention
    # - 50Gi 스토리지
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 50Gi
```

### 2. Thanos Sidecar 활성화
```yaml
prometheus:
  prometheusSpec:
    thanos:
      enabled: true  # 🔑 핵심!
      objectStorageConfig:
        name: thanos-s3-config
```

**Sidecar 역할:**
- ✅ Prometheus 데이터를 S3에 업로드 (2시간마다)
- ✅ Thanos Query에 gRPC StoreAPI 제공
- ✅ 로컬 데이터 + S3 데이터 통합 조회

### 3. Grafana 활성화
```yaml
grafana:
  enabled: true  # 중앙에서만 활성화

  datasources:
    datasources.yaml:
      datasources:
        # Thanos Query (기본)
        - name: Thanos Query
          url: http://thanos-query.monitoring.svc.cluster.local:9090
          isDefault: true

        # 로컬 Prometheus
        - name: Prometheus (Local)
          url: http://kube-prometheus-stack-prometheus:9090
```

### 4. Ingress 설정
```yaml
# Prometheus
prometheus.k8s-cluster-01.miribit.lab

# Grafana
grafana.k8s-cluster-01.miribit.lab

# Alertmanager
alertmanager.k8s-cluster-01.miribit.lab
```

---

## 🚀 배포 방법

### 사전 준비

1. **S3 Secret 생성**
```bash
# thanos-s3-secret.yaml 수정 (S3 정보 입력)
vi ../kube-prometheus-stack/thanos-s3-secret.yaml

# Secret 생성
kubectl apply -f ../kube-prometheus-stack/thanos-s3-secret.yaml
```

2. **네임스페이스 생성** (선택사항, kustomize가 자동 생성)
```bash
kubectl create namespace monitoring
```

### 배포

**Option 1: Kustomize 직접 사용**
```bash
# 빌드 확인
kustomize build deploy/overlays/cluster-01-central/kube-prometheus-stack-new

# 배포
kustomize build deploy/overlays/cluster-01-central/kube-prometheus-stack-new | kubectl apply -f -
```

**Option 2: kubectl + kustomize**
```bash
kubectl apply -k deploy/overlays/cluster-01-central/kube-prometheus-stack-new
```

**Option 3: ArgoCD (권장)**
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
    path: deploy/overlays/cluster-01-central/kube-prometheus-stack-new
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## ✅ 배포 후 확인

### 1. Pod 상태
```bash
kubectl get pods -n monitoring

# 예상 출력:
# prometheus-kube-prometheus-stack-prometheus-0
# kube-prometheus-stack-grafana-xxx
# kube-prometheus-stack-alertmanager-0
# kube-prometheus-stack-operator-xxx
# kube-prometheus-stack-kube-state-metrics-xxx
# prometheus-node-exporter-xxx (DaemonSet)
# thanos-receiver-0, thanos-receiver-1, thanos-receiver-2
# thanos-query-xxx
# thanos-store-0
# thanos-compactor-0
# thanos-ruler-0
```

### 2. Prometheus 확인
```bash
# Prometheus CRD 확인
kubectl get prometheus -n monitoring

# Prometheus Pod 로그
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus

# Thanos Sidecar 로그
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c thanos-sidecar
# "uploaded block" 메시지 확인
```

### 3. ServiceMonitor 자동 감지 확인
```bash
# ServiceMonitor 목록
kubectl get servicemonitor -A

# Prometheus UI 접속
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090/targets
# → 모든 ServiceMonitor가 자동으로 표시됨
```

### 4. Grafana 접속
```bash
# Port Forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# 브라우저
http://localhost:3000
# ID: admin
# PW: admin123

# 또는 Ingress
http://grafana.k8s-cluster-01.miribit.lab
```

**Grafana에서 확인할 것:**
- Thanos Query 데이터소스 연결 확인
- 모든 클러스터 메트릭 조회 가능 확인
- cluster 레이블로 필터링 가능 확인

### 5. Thanos Query 확인
```bash
# Thanos Query Pod
kubectl get pods -n monitoring -l app=thanos-query

# Thanos Query UI
kubectl port-forward -n monitoring svc/thanos-query 9090:9090
# http://localhost:9090

# Store 확인
# Stores 탭에서 다음 확인:
# - Prometheus Sidecar (중앙 클러스터)
# - Thanos Receiver (엣지 메트릭)
# - Thanos Store (S3 데이터)
# - Thanos Ruler (Rule 결과)
```

### 6. S3 블록 확인
```bash
# MinIO/S3에서 확인
# Bucket: thanos-bucket
# 2시간마다 새 블록 업로드됨

# Thanos Store 로그에서 확인
kubectl logs -n monitoring thanos-store-0 | grep "blocks loaded"
```

---

## 📊 데이터 흐름

### 메트릭 수집 흐름

```
1. 로컬 메트릭 수집:
   ServiceMonitor → Prometheus Operator → Prometheus Config 업데이트
   → Prometheus가 자동으로 Scrape

2. 로컬 데이터 저장:
   Prometheus → TSDB (로컬 스토리지, 15일)
   → Thanos Sidecar → S3 업로드 (2시간마다)

3. 엣지 메트릭 수신:
   Edge Prometheus Agent → Remote Write
   → Thanos Receiver → TSDB + S3 업로드

4. 통합 쿼리:
   Grafana → Thanos Query
   → Prometheus Sidecar (로컬 최신 데이터)
   → Thanos Receiver (엣지 최신 데이터)
   → Thanos Store (S3 장기 데이터)
   → Thanos Ruler (Rule 결과)
```

---

## 🔧 커스터마이징

### Prometheus 리소스 증가
```yaml
# values-central.yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 2
        memory: 4Gi
      limits:
        cpu: 4
        memory: 8Gi
```

### Retention 기간 변경
```yaml
# values-central.yaml
prometheus:
  prometheusSpec:
    retention: 30d  # 15d → 30d
```

### Grafana 대시보드 추가
```yaml
# values-central.yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      providers:
        - name: 'custom-dashboards'
          folder: 'Custom'
          type: file
          options:
            path: /var/lib/grafana/dashboards/custom
```

---

## 🚨 트러블슈팅

### 1. Thanos Sidecar가 S3에 업로드하지 않음
```bash
# Sidecar 로그 확인
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 thanos-sidecar

# 일반적인 원인:
# - S3 Secret 오류: credentials 확인
# - S3 버킷 없음: 버킷 생성 확인
# - 네트워크 문제: S3 endpoint 접근 확인
```

### 2. ServiceMonitor가 감지되지 않음
```bash
# Operator 로그 확인
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator

# 설정 확인
kubectl get prometheus -n monitoring kube-prometheus-stack-prometheus -o yaml | grep serviceMonitorSelector

# serviceMonitorSelectorNilUsesHelmValues: false 확인
```

### 3. Grafana에서 데이터가 안 보임
```bash
# Thanos Query 연결 확인
kubectl exec -n monitoring -it kube-prometheus-stack-grafana-xxx -- \
  curl http://thanos-query.monitoring.svc.cluster.local:9090/api/v1/query?query=up

# 데이터소스 설정 확인 (Grafana UI)
# Configuration → Data Sources → Thanos Query
```

### 4. Prometheus OOMKilled
```bash
# 메모리 증가
# values-central.yaml에서 resources.limits.memory 증가

# 또는 retention 단축
# retention: 15d → 7d
```

---

## 📚 관련 파일

- **Base 설정**: [../../../base/kube-prometheus-stack-new/](../../../base/kube-prometheus-stack-new/)
- **Thanos 컴포넌트**: [../kube-prometheus-stack/](../kube-prometheus-stack/)
- **ArgoCD App**: [../../../../argocd/apps/cluster-01-central/](../../../../argocd/apps/cluster-01-central/)

---

## 📝 다음 단계

1. ✅ 엣지 클러스터 배포 ([cluster-02-edge](../../cluster-02-edge/))
2. ✅ ArgoCD Application 생성
3. ✅ Custom ServiceMonitor 추가
4. ✅ Custom Grafana Dashboard 추가
5. ✅ Alert Rule 설정

---

**작성자:** Thanos Multi-Cluster Team
**마지막 업데이트:** 2025-10-22
