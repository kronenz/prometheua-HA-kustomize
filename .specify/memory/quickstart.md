# Thanos Multi-Cluster Quickstart (15분)

**목적**: 최소 구성으로 중앙 클러스터(196번 노드)에 모니터링 스택을 빠르게 배포하여 시스템 검증

## 사전 준비 (5분)

### 1. SSH 접속
```bash
ssh bsh@192.168.101.196
# Password: 123qwe
```

### 2. 필수 도구 설치 확인
```bash
# Minikube 확인
minikube version
# Expected: minikube version: v1.32.0 or higher

# Kubectl 확인
kubectl version --client
# Expected: v1.28.0 or higher

# Kustomize 확인
kustomize version
# Expected: v4.5.0 or higher

# containerd 확인
sudo systemctl status containerd
# Expected: active (running)
```

### 3. MinIO S3 접근 확인
```bash
curl -k https://172.20.40.21:30001/minio/health/live
# Expected: HTTP 200 OK
```

## 배포 (8분)

### Step 1: Minikube 시작 (2분)
```bash
minikube start \
  --driver=containerd \
  --cpus=4 \
  --memory=16384 \
  --disk-size=100g \
  --kubernetes-version=v1.28.0

# 검증
kubectl get nodes
# Expected: 1 node in Ready state
```

### Step 2: Longhorn 스토리지 배포 (2분)
```bash
cd /path/to/thanos-multi-cluster/deploy

kustomize build overlays/cluster-196-central/longhorn --enable-helm | \
  kubectl apply -f - -n longhorn-system

# 대기 (약 90초)
kubectl wait --for=condition=ready pod \
  -l app=longhorn-manager \
  -n longhorn-system \
  --timeout=180s

# 검증
kubectl get storageclass longhorn
# Expected: longhorn storage class present
```

### Step 3: NGINX Ingress 배포 (1분)
```bash
kustomize build overlays/cluster-196-central/nginx-ingress --enable-helm | \
  kubectl apply -f - -n ingress-nginx

# 대기
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=controller \
  -n ingress-nginx \
  --timeout=120s

# 검증
kubectl get pods -n ingress-nginx
# Expected: nginx-ingress-controller pod Running
```

### Step 4: Prometheus + Grafana 배포 (2분)
```bash
# S3 Secret 생성
kubectl create secret generic thanos-s3-secret \
  --from-literal=objstore.yml="
type: S3
config:
  bucket: thanos
  endpoint: 172.20.40.21:30001
  access_key: minio
  secret_key: minio123
  insecure: false
" \
  -n monitoring

# Prometheus Stack 배포
kustomize build overlays/cluster-196-central/kube-prometheus-stack --enable-helm | \
  kubectl apply -f - -n monitoring

# 대기 (약 90초)
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=prometheus \
  -n monitoring \
  --timeout=180s

# 검증
kubectl get pods -n monitoring
# Expected: prometheus-0, grafana-xxx, alertmanager-0 all Running
```

### Step 5: Thanos Query 배포 (1분)
```bash
kustomize build overlays/cluster-196-central/thanos --enable-helm | \
  kubectl apply -f - -n monitoring

# 대기
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=thanos-query \
  -n monitoring \
  --timeout=120s

# 검증
kubectl get pods -n monitoring | grep thanos
# Expected: thanos-query-xxx (2 replicas), thanos-store-gateway-xxx Running
```

## 검증 (2분)

### 1. Pod 상태 확인
```bash
kubectl get pods -n monitoring
kubectl get pods -n longhorn-system
kubectl get pods -n ingress-nginx
```

**성공 기준**: 모든 pod가 `Running` 상태이고 `READY` 컬럼이 `N/N` (예: `1/1`, `2/2`)

### 2. Prometheus Targets 확인
```bash
# Port forward (다른 터미널에서 실행)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# 브라우저에서 접속
# http://localhost:9090/targets
```

**성공 기준**: 모든 targets가 `UP` 상태

### 3. Grafana 접속
```bash
# Grafana password 확인
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo

# Ingress 확인
kubectl get ing -n monitoring

# 브라우저에서 접속
# https://grafana.mkube-196.miribit.lab
# Username: admin
# Password: (위에서 확인한 값)
```

**성공 기준**:
- Grafana 로그인 성공
- "Thanos Overview" 대시보드에서 메트릭 표시 확인
- Datasource "Thanos Query" 연결 확인 (Configuration → Data Sources)

### 4. Thanos S3 업로드 확인
```bash
# Thanos Sidecar 로그 확인
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 \
  -c thanos-sidecar --tail=50

# "upload" 키워드 검색
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 \
  -c thanos-sidecar --tail=100 | grep -i upload
```

**성공 기준**: 로그에 `"msg"="upload block"` 및 `"msg"="upload completed"` 메시지 확인 (약 2시간 후)

## 최종 체크리스트

- [ ] ✅ Minikube cluster `Running` 상태
- [ ] ✅ Longhorn storage class 사용 가능
- [ ] ✅ NGINX Ingress controller `Running`
- [ ] ✅ Prometheus pod `Running`, targets 100% `UP`
- [ ] ✅ Grafana 접속 가능 (https://grafana.mkube-196.miribit.lab)
- [ ] ✅ Thanos Query pod `Running` (2 replicas)
- [ ] ✅ Thanos Sidecar S3 업로드 로그 확인 (2시간 경과 후)

## Troubleshooting

### Issue: Minikube 시작 실패
```bash
# 기존 클러스터 삭제 후 재시작
minikube delete
minikube start [options]
```

### Issue: Pod ImagePullBackOff
```bash
# 이미지 pull 상태 확인
kubectl describe pod <pod-name> -n <namespace>

# Minikube docker 환경에서 수동 pull
minikube ssh
sudo ctr -n k8s.io images pull <image-name>
```

### Issue: Longhorn pod CrashLoopBackOff
```bash
# 노드에 필수 패키지 설치 확인
sudo apt-get install -y open-iscsi nfs-common

# Longhorn 재배포
kubectl delete ns longhorn-system
kustomize build ... | kubectl apply -f -
```

### Issue: Prometheus targets Down
```bash
# ServiceMonitor 확인
kubectl get servicemonitor -n monitoring

# Service endpoint 확인
kubectl get endpoints -n monitoring

# Network Policy 확인 (혹시 차단되었는지)
kubectl get networkpolicy -n monitoring
```

### Issue: Grafana 접속 안됨
```bash
# Ingress 확인
kubectl get ing -n monitoring -o yaml

# DNS 확인
nslookup grafana.mkube-196.miribit.lab
# Expected: 192.168.101.196

# NGINX Ingress 로그 확인
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

### Issue: Thanos S3 업로드 실패
```bash
# S3 Secret 확인
kubectl get secret thanos-s3-secret -n monitoring -o yaml

# S3 연결 테스트 (Prometheus pod 내부)
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 \
  -c thanos-sidecar -- \
  wget -O- https://172.20.40.21:30001/minio/health/live

# Thanos Sidecar 상세 로그
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 \
  -c thanos-sidecar -f
```

## Cleanup (시스템 정리)

전체 스택 제거:
```bash
# 모든 namespace 삭제
kubectl delete ns monitoring
kubectl delete ns longhorn-system
kubectl delete ns ingress-nginx

# Minikube 정지 (클러스터 유지)
minikube stop

# Minikube 완전 삭제
minikube delete
```

## 다음 단계

이 Quickstart가 성공했다면:
1. `/speckit.tasks` 명령으로 전체 tasks.md 생성
2. User Story 2 (Edge Clusters 197/198) 배포
3. User Story 3 (OpenSearch + Fluent-bit) 배포
4. User Story 5 (Unified Dashboard) 검증
5. `docs/deployment.md` (한글 상세 가이드) 참고하여 프로덕션 배포

## 참고 자료

- Thanos 문서: https://thanos.io/
- Prometheus Operator: https://prometheus-operator.dev/
- Longhorn: https://longhorn.io/docs/
- Kustomize: https://kustomize.io/
- Constitution: `.specify/memory/constitution.md`
