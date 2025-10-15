# Grafana 네비게이션 대시보드

이 디렉토리에는 Thanos 멀티클러스터 모니터링을 위한 Grafana 네비게이션 대시보드가 포함되어 있습니다.

## 📊 포함된 대시보드

### 1. 기본 네비게이션 (nav-portal-stable)
- **파일**: `grafana-dashboard-stable-nav.yaml`
- **UID**: `nav-portal-stable`
- **설명**: 시스템 기능 중심의 안정적인 네비게이션 포털
- **섹션**:
  - 인프라 모니터링
  - Kubernetes
  - Thanos & Prometheus
  - 스토리지
  - 데이터 플랫폼
  - GitOps & CI/CD

### 2. 운영 메인 네비게이션 (ops-nav-main)
- **파일**: `grafana-dashboard-ops-main-navigation.yaml`
- **UID**: `ops-nav-main`
- **설명**: 운영/성능 메트릭 중심의 메인 네비게이션
- **홈 대시보드로 설정됨** ✅
- **섹션**:
  - 인프라 운영 (드릴다운 →)
  - 쿠버네티스 운영 (드릴다운 →)
  - 모니터링 플랫폼 (드릴다운 →)
  - 데이터 플랫폼 운영 (드릴다운 →)

### 3. 운영 드릴다운 대시보드

#### 3.1. 인프라 운영 (ops-nav-infrastructure)
- **UID**: `ops-nav-infrastructure`
- **카테고리**:
  - 노드 성능 메트릭 (CPU, 메모리, 시스템)
  - 네트워크 성능 (대역폭, 지연, 에러)
  - 디스크 I/O 성능 (IOPS, 처리량, 용량)
  - 스토리지 운영 (Longhorn, 백업, MinIO)

#### 3.2. 쿠버네티스 운영 (ops-nav-kubernetes)
- **UID**: `ops-nav-kubernetes`
- **카테고리**:
  - 클러스터 헬스 (가용성, 컴포넌트, Condition)
  - 워크로드 성능 (Deployment, StatefulSet, Service)
  - 리소스 활용 (CPU, 메모리, 네트워크)
  - Pod 성능 & 안정성 (재시작, 준비 상태, 로드)

#### 3.3. 모니터링 플랫폼 (ops-nav-monitoring)
- **UID**: `ops-nav-monitoring`
- **카테고리**:
  - Thanos 쿼리 성능 (응답시간, 연결, 캐시)
  - Prometheus 성능 (스크랩, 쿼리, TSDB)
  - S3 스토리지 운영 (Sidecar, Compactor, Store)
  - 알림 & 규칙 성능 (Alertmanager, Ruler, 응답시간)

#### 3.4. 데이터 플랫폼 운영 (ops-nav-dataplatform)
- **UID**: `ops-nav-dataplatform`
- **카테고리**:
  - Apache Spark 작업 성능 (Job, Stage, Executor)
  - Trino 쿼리 성능 (실행 성능, Worker, Connector)
  - 데이터베이스 성능 (Oracle 쿼리, 연결풀, 테이블스페이스)
  - 파이프라인 운영 (ArgoCD, Jenkins, DORA)

## 🚀 배포 방법

### 자동 배포 (Kustomize)

대시보드는 kube-prometheus-stack 배포 시 자동으로 포함됩니다:

```bash
# Base에서 직접 배포
cd /root/develop/thanos/deploy/base/kube-prometheus-stack
kustomize build . --enable-helm | kubectl apply -f -

# Overlay를 통한 배포 (권장)
cd /root/develop/thanos/deploy/overlays/cluster-01-central/kube-prometheus-stack
kustomize build . --enable-helm | kubectl apply -f -
```

### ConfigMap 확인

```bash
# 배포된 ConfigMap 확인
kubectl get configmap -n monitoring | grep grafana-dashboard

# ConfigMap 상세 확인
kubectl describe configmap grafana-dashboard-ops-main-navigation -n monitoring
```

### Grafana에서 확인

1. Grafana에 접속: `http://grafana.k8s-cluster-01.miribit.lab`
2. 로그인: `admin` / `admin123`
3. 홈 화면에서 "🎯 플랫폼 운영 네비게이션" 대시보드 확인
4. 각 섹션의 "드릴다운 →" 버튼 클릭

## 🔧 구성 상세

### Grafana Values 설정

`values.yaml`에 다음 설정이 포함되어 있습니다:

```yaml
grafana:
  # Dashboard providers - enables loading dashboards from ConfigMaps
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default

  # Dashboard ConfigMaps - automatically loaded
  dashboardsConfigMaps:
    default: grafana-dashboard-stable-nav
    operations: grafana-dashboard-ops-main-navigation
    infrastructure: grafana-dashboard-ops-nav-infrastructure
    kubernetes: grafana-dashboard-ops-nav-kubernetes
    monitoring: grafana-dashboard-ops-nav-monitoring
    dataplatform: grafana-dashboard-ops-nav-dataplatform
```

### Kustomization 리소스

`kustomization.yaml`에 다음 리소스가 포함되어 있습니다:

```yaml
resources:
  - namespace.yaml
  - thanos-s3-secret.yaml
  - grafana-dashboard-stable-nav.yaml
  - grafana-dashboard-ops-main-navigation.yaml
  - grafana-dashboard-ops-nav-infrastructure.yaml
  - grafana-dashboard-ops-nav-kubernetes.yaml
  - grafana-dashboard-ops-nav-monitoring.yaml
  - grafana-dashboard-ops-nav-dataplatform.yaml
```

## 🎨 디자인 특징

### 색상 시스템
- 🔵 Blue (`#4299e1`): 인프라, GitOps/CI/CD
- 🟢 Green (`#48bb78`): Kubernetes, 로그
- 🟣 Purple (`#9f7aea`): Thanos & Prometheus, 알림
- 🟠 Orange (`#ed8936`): 데이터 플랫폼, HOT 배지

### 폰트
- **헤더**: 배민 도현체 (BMDOHYEON)
- **본문**: 시스템 폰트 스택

### 네비게이션 구조
```
메인 포털
├── 인프라 운영 [드릴다운]
│   └── 12개 상세 대시보드
├── 쿠버네티스 운영 [드릴다운]
│   └── 12개 상세 대시보드
├── 모니터링 플랫폼 [드릴다운]
│   └── 12개 상세 대시보드
└── 데이터 플랫폼 운영 [드릴다운]
    └── 12개 상세 대시보드
```

## 📝 수정 방법

### 대시보드 수정

1. `/tmp/` 디렉토리에서 JSON 파일 수정
2. ConfigMap YAML 재생성:

```bash
cd /root/develop/thanos/deploy/base/kube-prometheus-stack

# 예: ops-main-navigation 수정
cat > grafana-dashboard-ops-main-navigation.yaml << CONFIGMAP_HEADER
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-ops-main-navigation
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  ops-main-navigation.json: |-
CONFIGMAP_HEADER

cat /tmp/ops-main-navigation.json | sed 's/^/    /' >> grafana-dashboard-ops-main-navigation.yaml
```

3. 재배포:

```bash
kustomize build . --enable-helm | kubectl apply -f -
```

### 새 대시보드 추가

1. Grafana에서 대시보드 생성 및 JSON export
2. ConfigMap YAML 생성
3. `kustomization.yaml`의 `resources` 섹션에 추가
4. `values.yaml`의 `dashboardsConfigMaps` 섹션에 추가
5. 재배포

## 🔍 문제 해결

### 대시보드가 Grafana에 나타나지 않는 경우

```bash
# ConfigMap이 생성되었는지 확인
kubectl get configmap -n monitoring | grep grafana-dashboard

# Grafana Pod 로그 확인
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana

# Grafana Pod 재시작
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

### 대시보드 링크가 작동하지 않는 경우

- 대시보드 UID가 올바른지 확인
- 링크 형식: `/d/<dashboard-uid>/<slug>`
- 예: `/d/ops-nav-main/b629aa8`

## 📚 참고 자료

- [Grafana Dashboard Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards)
- [Kustomize Helm Chart Integration](https://kubectl.docs.kubernetes.io/references/kustomize/builtins/#_helmchartinflationgenerator_)
- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

---

**Last Updated**: 2025-10-15
**Maintained by**: Platform Operations Team
