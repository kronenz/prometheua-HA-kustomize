# ArgoCD 배포 설정

이 디렉토리는 모든 ArgoCD 관련 설정을 통합 관리합니다.

## 디렉토리 구조

```
argocd/
├── bootstrap/                   # ArgoCD 자체 설치 및 초기 설정
│   ├── namespace.yaml          # ArgoCD namespace
│   └── ingress.yaml            # ArgoCD UI 접근용 Ingress
│
├── projects/                    # ArgoCD 프로젝트 정의
│   └── observability-project.yaml
│
├── clusters/                    # 원격 클러스터 등록 시크릿
│   ├── cluster-02-secret.yaml
│   ├── cluster-03-secret.yaml
│   └── cluster-04-secret.yaml
│
├── apps/                        # 애플리케이션 정의 (클러스터별)
│   ├── cluster-01-central/      # 중앙 클러스터 애플리케이션
│   │   ├── prometheus-operator.yaml
│   │   ├── thanos-receiver.yaml
│   │   ├── opensearch-operator.yaml
│   │   ├── opensearch-cluster.yaml
│   │   ├── fluent-operator.yaml
│   │   ├── fluentbit.yaml
│   │   ├── longhorn.yaml
│   │   └── cilium-ingress.yaml
│   │
│   ├── cluster-02-edge/         # Edge 클러스터 02
│   │   ├── prometheus-agent.yaml
│   │   ├── fluent-operator.yaml
│   │   └── fluentbit.yaml
│   │
│   ├── cluster-03-edge/         # Edge 클러스터 03
│   │   ├── prometheus-agent.yaml
│   │   ├── fluent-operator.yaml
│   │   └── fluentbit.yaml
│   │
│   └── cluster-04-edge/         # Edge 클러스터 04
│       ├── prometheus-agent.yaml
│       ├── fluent-operator.yaml
│       └── fluentbit.yaml
│
├── root-app.yaml                # App of Apps 패턴 루트 (옵션)
└── README.md                    # 이 파일
```

## 사용 방법

### 1. ArgoCD 설치

```bash
# Namespace 생성
kubectl apply -f bootstrap/namespace.yaml

# ArgoCD 설치 (Helm 또는 매니페스트)
# ... ArgoCD 설치 명령 ...

# Ingress 설정
kubectl apply -f bootstrap/ingress.yaml
```

### 2. 프로젝트 생성

```bash
kubectl apply -f projects/observability-project.yaml
```

### 3. 클러스터 등록

```bash
# 각 edge 클러스터를 ArgoCD에 등록
kubectl apply -f clusters/cluster-02-secret.yaml
kubectl apply -f clusters/cluster-03-secret.yaml
kubectl apply -f clusters/cluster-04-secret.yaml
```

### 4. 애플리케이션 배포

#### 개별 애플리케이션 배포
```bash
# 중앙 클러스터 애플리케이션
kubectl apply -f apps/cluster-01-central/prometheus-operator.yaml
kubectl apply -f apps/cluster-01-central/thanos-receiver.yaml

# Edge 클러스터 애플리케이션
kubectl apply -f apps/cluster-02-edge/prometheus-agent.yaml
kubectl apply -f apps/cluster-03-edge/prometheus-agent.yaml
kubectl apply -f apps/cluster-04-edge/prometheus-agent.yaml
```

#### 한 번에 모든 애플리케이션 배포
```bash
# 특정 클러스터의 모든 앱
kubectl apply -f apps/cluster-01-central/

# 모든 클러스터의 모든 앱
kubectl apply -f apps/
```

#### App of Apps 패턴 사용 (권장)
```bash
kubectl apply -f root-app.yaml
```

## Application 정의 파일 형식

각 애플리케이션 정의 파일은 다음 형식을 따릅니다:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
spec:
  project: observability
  source:
    repoURL: <git-repo-url>
    targetRevision: main
    path: deploy/overlays/<cluster-name>/<component>
  destination:
    server: <cluster-api-url>
    namespace: <target-namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## 클러스터 정보

- **cluster-01 (192.168.101.194)**: 중앙 클러스터 - Thanos Query, Thanos Receiver, Grafana, OpenSearch
- **cluster-02 (192.168.101.196)**: Edge 클러스터 - Prometheus Agent
- **cluster-03 (192.168.101.197)**: Edge 클러스터 - Prometheus Agent
- **cluster-04 (192.168.101.198)**: Edge 클러스터 - Prometheus Agent

## 주의사항

1. **클러스터 시크릿 보안**: `clusters/` 디렉토리의 시크릿 파일은 민감한 정보를 포함하므로 주의해서 관리
2. **Git 동기화**: ArgoCD는 Git 저장소를 기준으로 동기화하므로 변경사항은 반드시 Git에 커밋
3. **Sync Policy**: automated sync가 활성화된 경우 Git 변경이 자동으로 클러스터에 반영됨

## 트러블슈팅

### Application이 OutOfSync 상태인 경우
```bash
# 수동 동기화
argocd app sync <app-name>

# 또는 kubectl 사용
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Application이 생성되지 않는 경우
```bash
# Application 상태 확인
kubectl get application -n argocd
kubectl describe application <app-name> -n argocd
```

## 관련 문서

- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [App of Apps 패턴](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [프로젝트 루트](../README.md)
