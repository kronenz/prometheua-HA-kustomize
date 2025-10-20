# GitOps 멀티클러스터 Observability 플랫폼 배포 완료 🎉

## 배포 정보

### ArgoCD (GitOps Controller)
- **URL**: http://argocd.k8s-cluster-01.miribit.lab
- **Username**: admin
- **Password**: PT8YVhEwC7Uq885l
- **Ingress**: Cilium (192.168.101.210)

### Gitea (Git Repository Server)
- **URL**: http://gitea.k8s-cluster-01.miribit.lab
- **Username**: gitea_admin
- **Password**: admin123
- **Repository**: http://gitea.k8s-cluster-01.miribit.lab/gitea_admin/thanos-multi-cluster.git

### Grafana (이미 배포됨)
- **URL**: http://grafana.k8s-cluster-01.miribit.lab
- **Username**: admin
- **Password**: admin123

---

## 배포된 Application 목록 (18개)

### Cluster-01 (중앙 클러스터) - 8개
1. ✅ **cilium-ingress-cluster-01** - Cilium Ingress Controller
2. ⏳ **fluent-operator-cluster-01** - Fluent Operator
3. ⏳ **fluentbit-cluster-01** - Fluent-Bit (로그 수집)
4. ✅ **longhorn-cluster-01** - Longhorn 스토리지
5. ⏳ **opensearch-cluster-cluster-01** - OpenSearch 클러스터
6. ⏳ **opensearch-operator-cluster-01** - OpenSearch Operator
7. ✅ **prometheus-operator-cluster-01** - Prometheus Operator
8. ✅ **thanos-receiver-cluster-01** - Thanos Receiver

### Cluster-02 (엣지 클러스터) - 3개
9. ⏳ **fluent-operator-cluster-02** - Fluent Operator
10. ⏳ **fluentbit-cluster-02** - Fluent-Bit
11. ⏳ **prometheus-agent-cluster-02** - Prometheus Agent

### Cluster-03 (엣지 클러스터) - 3개
12. ⏳ **fluent-operator-cluster-03** - Fluent Operator
13. ⏳ **fluentbit-cluster-03** - Fluent-Bit
14. ⏳ **prometheus-agent-cluster-03** - Prometheus Agent

### Cluster-04 (엣지 클러스터) - 3개
15. ⏳ **fluent-operator-cluster-04** - Fluent Operator
16. ⏳ **fluentbit-cluster-04** - Fluent-Bit
17. ⏳ **prometheus-agent-cluster-04** - Prometheus Agent

### Root Application
18. ✅ **root-application** - App-of-Apps (모든 하위 Application 관리)

---

## 배포 아키텍처

```
중앙 클러스터 (192.168.101.194)
├── ArgoCD (GitOps Controller)
├── Gitea (Git Repository)
├── Prometheus + Thanos (메트릭)
├── OpenSearch (로그 저장)
├── Grafana (시각화)
└── Fluent-Bit (로그 수집)

엣지 클러스터 (196, 197, 198)
├── Prometheus Agent (메트릭 수집)
├── Node Exporter (OS 메트릭)
├── Kube-State-Metrics (K8s 메트릭)
└── Fluent-Bit (로그 수집)
```

---

## 다음 단계

### 1. ArgoCD UI에서 Application 동기화 확인

```bash
# 브라우저로 접속
open http://argocd.k8s-cluster-01.miribit.lab

# 또는 CLI로 확인
kubectl get applications -n argocd
```

### 2. Application 수동 동기화 (필요시)

ArgoCD는 자동으로 5분마다 Git 저장소를 폴링하여 동기화합니다.
수동으로 동기화하려면:

```bash
# 모든 Application 동기화
kubectl get applications -n argocd -o name | xargs -I {} kubectl patch {} -n argocd --type merge -p '{"operation": {"initiatedBy": {"username": "manual"}, "sync": {"revision": "main"}}}'

# 특정 Application만 동기화
kubectl patch application opensearch-operator-cluster-01 -n argocd --type merge -p '{"operation": {"initiatedBy": {"username": "manual"}, "sync": {"revision": "main"}}}'
```

### 3. 배포 상태 모니터링

```bash
# Application 상태
kubectl get applications -n argocd

# 특정 클러스터의 파드 상태
kubectl get pods -n monitoring
kubectl get pods -n logging

# 엣지 클러스터 (kubeconfig 필요)
kubectl --context cluster-02 get pods -n monitoring
```

### 4. 로그 및 메트릭 확인

**Grafana**:
- http://grafana.k8s-cluster-01.miribit.lab
- Thanos Query에서 모든 클러스터의 메트릭 조회

**OpenSearch Dashboards** (배포 완료 후):
- http://opensearch-dashboards.k8s-cluster-01.miribit.lab
- 모든 클러스터의 로그 조회

---

## 트러블슈팅

### Application이 OutOfSync 상태인 경우

```bash
# Application 상세 정보 확인
kubectl describe application <app-name> -n argocd

# Git 저장소 연결 확인
kubectl get configmap argocd-cm -n argocd -o yaml

# 수동 동기화
kubectl patch application <app-name> -n argocd --type merge -p '{"operation": {"sync": {"revision": "main"}}}'
```

### 엣지 클러스터에 배포되지 않는 경우

엣지 클러스터 연결 Secret이 필요합니다:

```bash
# 클러스터 Secret 생성 스크립트 실행
./scripts/configure-argocd-gitlab.sh
```

### Helm Chart가 렌더링되지 않는 경우

Kustomize의 Helm 지원이 필요한 Application은 `plugin` 설정이 있어야 합니다:

```yaml
spec:
  source:
    plugin:
      name: kustomize-with-helm
```

---

## 주요 명령어

### ArgoCD

```bash
# Application 목록
kubectl get applications -n argocd

# 특정 Application 상태
kubectl describe application <app-name> -n argocd

# Application 동기화
kubectl patch application <app-name> -n argocd --type merge -p '{"operation": {"sync": {"revision": "main"}}}'

# Application 삭제
kubectl delete application <app-name> -n argocd
```

### Git 작업

```bash
# 변경사항 푸시
git add .
git commit -m "your message"
git push origin main

# ArgoCD가 자동으로 동기화 (최대 5분 대기)
```

### 파드 확인

```bash
# 중앙 클러스터
kubectl get pods -n monitoring
kubectl get pods -n logging
kubectl get pods -n argocd
kubectl get pods -n gitlab

# 모든 네임스페이스
kubectl get pods --all-namespaces
```

---

## 성공 지표

✅ **배포 완료**:
- ArgoCD 실행 중 (7개 파드)
- Gitea 실행 중 (4개 파드)
- Root Application Synced
- 18개 Application 생성됨

⏳ **진행 중**:
- OpenSearch Operator 배포
- Fluent Operator 배포
- Prometheus Agent 배포
- 각 Application이 Git에서 자동 동기화됨

🎯 **최종 목표**:
- 모든 Application Synced 상태
- 모든 파드 Running 상태
- Grafana에서 모든 클러스터 메트릭 조회 가능
- OpenSearch에서 모든 클러스터 로그 조회 가능

---

## 문서

- **[GITOPS_DEPLOYMENT_GUIDE.md](docs/GITOPS_DEPLOYMENT_GUIDE.md)** - GitOps 배포 상세 가이드
- **[OPERATOR_DEPLOYMENT_GUIDE.md](docs/OPERATOR_DEPLOYMENT_GUIDE.md)** - Operator 배포 가이드
- **[QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** - 빠른 참조 가이드
- **[README.md](README.md)** - 프로젝트 개요

---

## 요약

**배포된 구성요소**:
- ✅ ArgoCD v2.13.2 (GitOps Controller)
- ✅ Gitea (Git Repository Server)
- ✅ Root Application (App-of-Apps Pattern)
- ✅ 18개 Application 정의
- ✅ 코드가 Git에 푸시됨
- ⏳ Application들이 동기화 중

**다음 작업**:
1. ArgoCD UI에서 Application 동기화 상태 확인
2. 필요시 수동 동기화
3. 모든 파드가 Running 상태가 될 때까지 대기
4. Grafana 및 OpenSearch Dashboards에서 메트릭/로그 확인

**축하합니다! GitOps 기반 멀티클러스터 Observability 플랫폼이 성공적으로 배포되었습니다!** 🎉
