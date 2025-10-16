# GitOps 멀티클러스터 운영 빠른 참조 가이드

## 목차
- [접속 정보](#접속-정보)
- [배포](#배포)
- [모니터링](#모니터링)
- [트러블슈팅](#트러블슈팅)
- [일반 작업](#일반-작업)

---

## 접속 정보

### UI 대시보드

```bash
# 중앙 클러스터 (192.168.101.194)
ArgoCD:              http://argocd.k8s-cluster-01.miribit.lab
GitLab:              http://gitlab.k8s-cluster-01.miribit.lab
Grafana:             http://grafana.k8s-cluster-01.miribit.lab
Thanos Query:        http://thanos-query.k8s-cluster-01.miribit.lab
Prometheus:          http://prometheus.k8s-cluster-01.miribit.lab
OpenSearch:          http://opensearch-dashboards.k8s-cluster-01.miribit.lab
```

### CLI 로그인

```bash
# ArgoCD
argocd login argocd.k8s-cluster-01.miribit.lab \
  --username admin \
  --password $(cat argocd-credentials.txt | grep Password | awk '{print $2}') \
  --insecure

# kubectl 컨텍스트
kubectl config use-context cluster-01-context    # 중앙 클러스터
kubectl config use-context cluster-02-context    # 엣지 클러스터 02
kubectl config use-context cluster-03-context    # 엣지 클러스터 03
kubectl config use-context cluster-04-context    # 엣지 클러스터 04
```

---

## 배포

### 초기 배포

```bash
# 1. ArgoCD 설치
./scripts/deploy-argocd.sh

# 2. GitLab 설치
export S3_ACCESS_KEY="your_key"
export S3_SECRET_KEY="your_secret"
./scripts/deploy-gitlab.sh

# 3. GitLab에서 프로젝트 생성
# - 그룹: observability
# - 프로젝트: thanos-multi-cluster

# 4. ArgoCD-GitLab 연동
./scripts/configure-argocd-gitlab.sh

# 5. 코드 푸시
git init
git remote add origin http://gitlab.k8s-cluster-01.miribit.lab/observability/thanos-multi-cluster.git
git add .
git commit -m "Initial commit"
git push -u origin main

# 6. Root Application 동기화
argocd app sync root-application
```

### 설정 변경 및 배포

```bash
# 1. 로컬 변경
vim deploy/overlays/cluster-01-central/kube-prometheus-stack/kube-prometheus-stack-values.yaml

# 2. Git 커밋 및 푸시
git add .
git commit -m "chore: update prometheus config"
git push origin main

# 3. 자동 동기화 대기 (최대 5분)
# 또는 수동 동기화
argocd app sync kube-prometheus-stack-cluster-01
```

### Application 관리

```bash
# Application 목록
argocd app list

# Application 상태 확인
argocd app get <app-name>

# Application 동기화
argocd app sync <app-name>

# Application 동기화 대기
argocd app wait <app-name> --health

# Application 삭제
argocd app delete <app-name>

# 모든 Application 동기화
argocd app sync --all

# Dry-run (실제 배포 없이 확인)
argocd app sync <app-name> --dry-run
```

### 롤백

```bash
# Git 기반 롤백 (권장)
git revert HEAD
git push origin main

# ArgoCD 기반 롤백
argocd app history <app-name>
argocd app rollback <app-name> <revision>
```

---

## 모니터링

### Application 상태

```bash
# 모든 Application 상태
argocd app list

# 특정 Application 상세
argocd app get <app-name>

# Application 이벤트
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Application 리소스
argocd app resources <app-name>
```

### 파드 상태

```bash
# 중앙 클러스터
kubectl --context cluster-01-context get pods -n monitoring
kubectl --context cluster-01-context get pods -n logging
kubectl --context cluster-01-context get pods -n argocd

# 엣지 클러스터
for ctx in cluster-02-context cluster-03-context cluster-04-context; do
  echo "=== $ctx ==="
  kubectl --context $ctx get pods -n monitoring
done

# 모든 네임스페이스
kubectl get pods --all-namespaces --context cluster-01-context
```

### 로그 확인

```bash
# ArgoCD Application Controller
kubectl logs -n argocd deployment/argocd-application-controller

# ArgoCD Server
kubectl logs -n argocd deployment/argocd-server

# Prometheus
kubectl logs -n monitoring statefulset/prometheus-kube-prometheus-stack-prometheus

# Thanos Query
kubectl logs -n monitoring deployment/thanos-query

# OpenSearch
kubectl logs -n logging statefulset/opensearch-cluster-master-0
```

### 메트릭 확인

```bash
# Prometheus 메트릭 쿼리
curl -s 'http://prometheus.k8s-cluster-01.miribit.lab/api/v1/query?query=up' | jq

# Thanos Query 메트릭
curl -s 'http://thanos-query.k8s-cluster-01.miribit.lab/api/v1/query?query=up' | jq

# ArgoCD 메트릭
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082
curl -s http://localhost:8082/metrics | grep argocd_app
```

---

## 트러블슈팅

### ArgoCD Application이 Out-of-Sync

```bash
# 차이점 확인
argocd app diff <app-name>

# 하드 리프레시 (캐시 무시)
argocd app get <app-name> --hard-refresh

# 수동 동기화
argocd app sync <app-name>
```

### ArgoCD Application이 Progressing에서 멈춤

```bash
# Application 상태 확인
argocd app get <app-name>

# 리소스 상태 확인
argocd app resources <app-name>

# 특정 리소스 상세
kubectl describe <resource-kind> <resource-name> -n <namespace>

# 파드 로그
kubectl logs <pod-name> -n <namespace>
```

### Git 저장소 연결 실패

```bash
# 저장소 목록 확인
argocd repo list

# 저장소 재등록
kubectl delete secret gitlab-repo-creds -n argocd
kubectl create secret generic gitlab-repo-creds \
  -n argocd \
  --from-literal=username="root" \
  --from-literal=password="new_password"

# ArgoCD 재시작
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout restart deployment/argocd-application-controller -n argocd
```

### 클러스터 연결 실패

```bash
# 클러스터 목록 확인
argocd cluster list

# 클러스터 연결 테스트
kubectl cluster-info --context=cluster-02-context

# 클러스터 Secret 확인
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster

# 클러스터 재등록
./scripts/configure-argocd-gitlab.sh
```

### GitLab 파드가 시작되지 않음

```bash
# PostgreSQL 상태
kubectl get pods -n gitlab -l app=postgresql
kubectl logs -n gitlab -l app=postgresql

# Redis 상태
kubectl get pods -n gitlab -l app=redis
kubectl logs -n gitlab -l app=redis

# GitLab Webservice
kubectl get pods -n gitlab -l app=webservice
kubectl logs -n gitlab -l app=webservice

# GitLab 재시작
kubectl rollout restart statefulset/postgresql -n gitlab
kubectl rollout restart statefulset/redis -n gitlab
```

### Kustomize 빌드 실패

```bash
# 로컬에서 빌드 테스트
cd deploy/overlays/cluster-01-central/kube-prometheus-stack
kustomize build .

# Helm 차트 렌더링 테스트
kustomize build . --enable-helm

# YAML 검증
yamllint kustomization.yaml
```

---

## 일반 작업

### S3 버킷 관리

```bash
# MinIO 클라이언트 설정
mc alias set minio http://s3.minio.miribit.lab:9000 $S3_ACCESS_KEY $S3_SECRET_KEY

# 버킷 목록
mc ls minio/

# 버킷 생성
mc mb minio/new-bucket

# 버킷 용량 확인
mc du minio/thanos-metrics

# 파일 목록
mc ls --recursive minio/thanos-metrics

# 파일 다운로드
mc cp minio/thanos-metrics/path/to/file ./
```

### Longhorn 스토리지 관리

```bash
# Volume 목록
kubectl get pv
kubectl get pvc --all-namespaces

# Longhorn UI 접속
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# http://localhost:8080

# Volume 스냅샷
kubectl get volumesnapshot --all-namespaces

# Backup 목록
kubectl get backup -n longhorn-system
```

### 인증서 갱신 (kubeadm)

```bash
# 각 클러스터에서 실행
ssh bsh@192.168.101.194

# 인증서 확인
sudo kubeadm certs check-expiration

# 인증서 갱신
sudo kubeadm certs renew all

# kubeconfig 업데이트
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# 중앙 클러스터에서 ArgoCD Secret 재생성
./scripts/configure-argocd-gitlab.sh
```

### 네임스페이스 정리

```bash
# 특정 네임스페이스의 모든 리소스 삭제
kubectl delete all --all -n <namespace>

# 네임스페이스 삭제 (Application도 함께 삭제됨)
kubectl delete namespace <namespace>

# ArgoCD Application 삭제 (finalizer 주의)
argocd app delete <app-name> --cascade
```

### 로그 수집

```bash
# ArgoCD 로그
kubectl logs -n argocd deployment/argocd-application-controller > argocd-controller.log
kubectl logs -n argocd deployment/argocd-server > argocd-server.log

# 모든 파드 상태
kubectl get pods --all-namespaces -o wide > all-pods.txt

# 이벤트
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > events.txt

# 압축
tar czf debug-logs-$(date +%Y%m%d-%H%M%S).tar.gz *.log *.txt
```

### 성능 모니터링

```bash
# 노드 리소스 사용량
kubectl top nodes --context cluster-01-context

# 파드 리소스 사용량
kubectl top pods -n monitoring --context cluster-01-context

# Prometheus 쿼리 성능
curl -s 'http://prometheus.k8s-cluster-01.miribit.lab/api/v1/query?query=up' \
  -w '\nTime: %{time_total}s\n'

# Thanos 메트릭 카운트
curl -s 'http://thanos-query.k8s-cluster-01.miribit.lab/api/v1/label/__name__/values' | \
  jq '.data | length'
```

### 백업

```bash
# ArgoCD 설정 백업
kubectl get configmap argocd-cm -n argocd -o yaml > backup/argocd-cm.yaml
kubectl get secret -n argocd -o yaml > backup/argocd-secrets.yaml

# GitLab 백업
kubectl exec -it <gitlab-task-runner-pod> -n gitlab -- \
  gitlab-backup create SKIP=registry

# Prometheus 데이터 스냅샷
# (자동으로 S3에 업로드됨)

# 매니페스트 백업
git clone http://gitlab.k8s-cluster-01.miribit.lab/observability/thanos-multi-cluster.git backup/
```

---

## 유용한 원라이너

```bash
# 모든 클러스터의 파드 상태
for ctx in cluster-01-context cluster-02-context cluster-03-context cluster-04-context; do
  echo "=== $ctx ==="
  kubectl --context $ctx get pods --all-namespaces | grep -v Running | grep -v Completed
done

# ArgoCD Application 동기화 상태
argocd app list -o json | jq '.[] | {name: .metadata.name, sync: .status.sync.status, health: .status.health.status}'

# Prometheus 타겟 상태
curl -s http://prometheus.k8s-cluster-01.miribit.lab/api/v1/targets | \
  jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# GitLab CI/CD 파이프라인 상태
# (GitLab API Token 필요)
curl --header "PRIVATE-TOKEN: <your_token>" \
  "http://gitlab.k8s-cluster-01.miribit.lab/api/v4/projects/1/pipelines" | jq

# 실패한 파드 재시작
kubectl get pods --all-namespaces --field-selector=status.phase!=Running \
  -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read ns pod; do kubectl delete pod $pod -n $ns; done
```

---

## 관련 문서

- [GITOPS_DEPLOYMENT_GUIDE.md](./GITOPS_DEPLOYMENT_GUIDE.md) - GitOps 배포 상세 가이드
- [GITOPS_SETUP_SUMMARY.md](./GITOPS_SETUP_SUMMARY.md) - GitOps 환경 구성 요약
- [OPERATOR_BASED_MULTI_CLUSTER_OBSERVABILITY.md](./OPERATOR_BASED_MULTI_CLUSTER_OBSERVABILITY.md) - 전체 아키텍처

---

## 지원 및 문의

- **이슈**: GitLab Issues
- **문서**: `docs/` 디렉토리
- **로그**: 위의 로그 수집 방법 참조
