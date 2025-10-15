# Thanos Multi-Cluster 배포 가이드

**작성일**: 2025-10-14
**대상 환경**: 3개 노드 (192.168.101.196, 197, 198)
**예상 소요 시간**: 약 90분

## 📋 목차

1. [사전 준비사항](#1-사전-준비사항)
2. [Phase 1: Minikube 설치](#2-phase-1-minikube-설치)
3. [Phase 2: S3 버킷 생성](#3-phase-2-s3-버킷-생성)
4. [Phase 3: 인프라 구성 요소 배포](#4-phase-3-인프라-구성-요소-배포)
5. [Phase 4: 모니터링 스택 배포](#5-phase-4-모니터링-스택-배포)
6. [Phase 5: 로깅 스택 배포](#6-phase-5-로깅-스택-배포)
7. [Phase 6: 검증 및 확인](#7-phase-6-검증-및-확인)
8. [문제 해결](#8-문제-해결)

---

## 1. 사전 준비사항

### 1.1 노드 정보

| 노드 번호 | IP 주소 | 역할 | 호스트네임 패턴 |
|-----------|---------|------|-----------------|
| 196 | 192.168.101.196 | Central Cluster | *.mkube-196.miribit.lab |
| 197 | 192.168.101.197 | Edge Cluster | *.mkube-197.miribit.lab |
| 198 | 192.168.101.198 | Edge Cluster | *.mkube-198.miribit.lab |

**SSH 접속 정보**: `bsh / 123qwe`

### 1.2 외부 의존성

| 서비스 | 엔드포인트 | 용도 |
|--------|-----------|------|
| MinIO S3 | http://s3.minio.miribit.lab | 메트릭 및 로그 저장 |
| MinIO Console | http://console.minio.miribit.lab | S3 관리 UI |

**MinIO 인증 정보**: `minio / minio123`

### 1.3 필수 소프트웨어 (운영자 워크스테이션)

```bash
# Kustomize 설치
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# sshpass 설치 (원격 배포용)
sudo apt-get update && sudo apt-get install -y sshpass

# 설치 확인
kustomize version
kubectl version --client
sshpass -V
```

### 1.4 저장소 클론

```bash
cd ~
git clone <repository-url> thanos-multi-cluster
cd thanos-multi-cluster
```

---

## 2. Phase 1: Minikube 설치

**목표**: 각 노드에 Minikube 클러스터 설치
**소요 시간**: 노드당 약 15분 (총 45분)

### 2.1 사전 검증

```bash
# 사전 요구사항 검증
./scripts/validate-prerequisites.sh
```

**예상 출력**:
- ✓ MinIO Console 접근 가능
- S3 API 연결 확인 (노드별)
- DNS 해석 확인
- 노드 리소스 확인 (4+ CPU, 16+ GB RAM)

### 2.2 노드 196 (Central) 설치

```bash
# SSH 접속
ssh bsh@192.168.101.196

# Minikube 설치 스크립트 다운로드 (또는 scp로 전송)
# 로컬에서 실행하는 경우:
# scp scripts/minikube/install-minikube.sh bsh@192.168.101.196:~/

# 스크립트 실행
chmod +x install-minikube.sh
./install-minikube.sh

# 설치 확인
minikube status
kubectl get nodes
```

**예상 결과**:
```
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running

NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   2m    v1.28.3
```

### 2.3 노드 197, 198 (Edge) 설치

**노드 197**:
```bash
ssh bsh@192.168.101.197
chmod +x install-minikube.sh
./install-minikube.sh
minikube status
```

**노드 198**:
```bash
ssh bsh@192.168.101.198
chmod +x install-minikube.sh
./install-minikube.sh
minikube status
```

### 2.4 검증

모든 노드에서 다음 명령 실행:

```bash
# 노드 상태
kubectl get nodes

# 기본 Pods 확인
kubectl get pods -A

# 테스트 Pod 배포
kubectl run test-nginx --image=nginx --restart=Never
kubectl wait --for=condition=Ready pod/test-nginx --timeout=60s
kubectl get pod test-nginx
kubectl delete pod test-nginx
```

✅ **Checkpoint**: 3개 노드 모두에서 Minikube Running, kubectl 정상 작동

---

## 3. Phase 2: S3 버킷 생성

**목표**: MinIO에 필요한 S3 버킷 생성
**소요 시간**: 약 5분

### 3.1 버킷 생성 (로컬 또는 노드 196에서 실행)

```bash
# MinIO Client 설치 및 버킷 생성
./scripts/s3/create-buckets.sh
```

**생성되는 버킷**:
- `thanos`: Prometheus 메트릭 블록 저장
- `opensearch-logs`: OpenSearch 로그 스냅샷
- `longhorn-backups`: Longhorn 볼륨 백업

### 3.2 MinIO Console에서 확인

1. 브라우저에서 http://console.minio.miribit.lab 접속
2. `minio / minio123`로 로그인
3. **Buckets** 메뉴에서 3개 버킷 확인

✅ **Checkpoint**: MinIO에 thanos, opensearch-logs, longhorn-backups 버킷 존재

---

## 4. Phase 3: 인프라 구성 요소 배포

**목표**: Longhorn Storage + NGINX Ingress 배포
**소요 시간**: 노드당 약 10분 (총 30분)

### 4.1 노드 196 인프라 배포

```bash
ssh bsh@192.168.101.196
cd ~/thanos-multi-cluster

# Longhorn 배포
./scripts/deploy-component.sh longhorn cluster-196-central

# 배포 완료 대기 (약 3-5분)
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# NGINX Ingress 배포
./scripts/deploy-component.sh ingress-nginx cluster-196-central

# 배포 완료 대기
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=180s

# 상태 확인
kubectl get pods -n longhorn-system
kubectl get pods -n ingress-nginx
```

### 4.2 노드 197, 198 인프라 배포

**노드 197**:
```bash
ssh bsh@192.168.101.197
cd ~/thanos-multi-cluster

./scripts/deploy-component.sh longhorn cluster-197-edge
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

./scripts/deploy-component.sh ingress-nginx cluster-197-edge
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=180s
```

**노드 198**: (동일하게 반복, cluster-198-edge)

### 4.3 Storage Class 확인

모든 노드에서:
```bash
# Storage Class 확인
kubectl get storageclass

# 테스트 PVC 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# PVC 바인딩 확인 (60초 이내)
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/test-pvc --timeout=60s
kubectl get pvc test-pvc

# 테스트 PVC 삭제
kubectl delete pvc test-pvc
```

✅ **Checkpoint**:
- Longhorn pods Running on all nodes
- NGINX Ingress pods Running on all nodes
- PVC 생성 및 바인딩 성공 (60초 이내)

---

## 5. Phase 4: 모니터링 스택 배포

**목표**: Prometheus, Grafana, Thanos 배포
**소요 시간**: 약 20분

### 5.1 노드 196 (Central) 모니터링 배포

```bash
ssh bsh@192.168.101.196
cd ~/thanos-multi-cluster

# Prometheus Stack 배포 (Prometheus, Grafana, Alertmanager, Thanos 포함)
./scripts/deploy-component.sh prometheus cluster-196-central

# 배포 완료 대기 (약 5-10분, 이미지 다운로드 시간 포함)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=600s

# 배포 상태 확인
kubectl get pods -n monitoring
kubectl get svc -n monitoring
kubectl get ingress -n monitoring
```

**주요 컴포넌트 확인**:
- Prometheus Operator
- Prometheus Server
- Grafana
- Alertmanager
- Thanos Query (2 replicas)
- Thanos Store Gateway
- Thanos Compactor
- Thanos Ruler

### 5.2 노드 197, 198 (Edge) 모니터링 배포

**노드 197**:
```bash
ssh bsh@192.168.101.197
cd ~/thanos-multi-cluster

./scripts/deploy-component.sh prometheus cluster-197-edge

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=600s
kubectl get pods -n monitoring
```

**노드 198**: (동일하게 반복, cluster-198-edge)

### 5.3 Grafana 접속 확인

1. **노드 196 Grafana**: http://grafana.mkube-196.miribit.lab
   - Username: `admin`
   - Password: `prom-operator` (기본값, values.yaml에서 변경 가능)

2. **대시보드 확인**:
   - General → Home → Kubernetes / Compute Resources
   - Thanos Overview (사용자 정의 대시보드)

### 5.4 Thanos Query 확인

```bash
# 노드 196에서 Thanos Query 상태 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=thanos-query

# Thanos Query API 테스트
kubectl port-forward -n monitoring svc/thanos-query 9090:9090 &
curl http://localhost:9090/api/v1/query?query=up

# Port forward 종료
killall kubectl
```

✅ **Checkpoint**:
- Prometheus pods Running on all nodes
- Grafana accessible at grafana.mkube-196.miribit.lab
- Thanos Query 2 replicas Running on node 196

---

## 6. Phase 5: 로깅 스택 배포

**목표**: OpenSearch + Fluent-bit 배포
**소요 시간**: 약 15분

### 6.1 OpenSearch 배포 (모든 노드)

**노드 196**:
```bash
ssh bsh@192.168.101.196
cd ~/thanos-multi-cluster

./scripts/deploy-component.sh opensearch cluster-196-central
kubectl wait --for=condition=ready pod -l app=opensearch -n logging --timeout=600s
```

**노드 197, 198**: (동일하게 반복)

### 6.2 Fluent-bit 배포 (모든 노드)

**노드 196**:
```bash
./scripts/deploy-component.sh fluent-bit cluster-196-central
kubectl get ds -n logging fluent-bit
```

**노드 197, 198**: (동일하게 반복)

### 6.3 OpenSearch 클러스터 확인

```bash
# 노드 196에서 OpenSearch 상태 확인
kubectl port-forward -n logging svc/opensearch 9200:9200 &
curl http://localhost:9200/_cluster/health?pretty

# 예상 출력:
# {
#   "cluster_name" : "opensearch-cluster",
#   "status" : "green",
#   "number_of_nodes" : 3,
#   ...
# }

killall kubectl
```

### 6.4 로그 수집 테스트

```bash
# 테스트 로거 Pod 생성
kubectl run test-logger --image=busybox --restart=Never -- sh -c "while true; do echo 'Test log message'; sleep 1; done"

# 30초 대기
sleep 30

# OpenSearch에서 로그 확인
kubectl port-forward -n logging svc/opensearch 9200:9200 &
curl "http://localhost:9200/logs-*/_search?q=Test&pretty" | grep "Test log"

# 정리
kubectl delete pod test-logger
killall kubectl
```

✅ **Checkpoint**:
- OpenSearch 3-node cluster green status
- Fluent-bit DaemonSet running on all nodes
- Logs flowing to OpenSearch (30초 이내)

---

## 7. Phase 6: 검증 및 확인

**목표**: 전체 배포 검증
**소요 시간**: 약 10분

### 7.1 자동 검증 스크립트 실행

각 노드에서:
```bash
./scripts/validate-deployment.sh
```

**예상 출력**:
```
╔═══════════════════════════════════════════════╗
║       Thanos 배포 상태 검증 스크립트          ║
╚═══════════════════════════════════════════════╝

[1/6] 클러스터 연결 확인
───────────────────────────────────────────────
✓ Kubernetes 클러스터 연결
✓ 노드 상태

[2/6] 네임스페이스 확인
───────────────────────────────────────────────
✓ 네임스페이스: longhorn-system
✓ 네임스페이스: ingress-nginx
✓ 네임스페이스: monitoring
✓ 네임스페이스: logging

...

╔═══════════════════════════════════════════════╗
║             검증 결과 요약                     ║
╚═══════════════════════════════════════════════╝

총 체크: 25
통과: 23
경고: 2
실패: 0

성공률: 92%

✓ 일부 경고가 있지만 핵심 기능은 정상입니다.
```

### 7.2 주요 UI 접속 확인

**노드 196 (Central)**:
- Grafana: http://grafana.mkube-196.miribit.lab
- Prometheus: http://prometheus.mkube-196.miribit.lab
- OpenSearch: http://opensearch.mkube-196.miribit.lab

**노드 197, 198 (Edge)**:
- Grafana: http://grafana.mkube-{197,198}.miribit.lab
- Prometheus: http://prometheus.mkube-{197,198}.miribit.lab

### 7.3 메트릭 통합 확인

1. **Grafana (노드 196)** 접속
2. **Explore** 메뉴로 이동
3. Datasource: **Thanos Query** 선택
4. 쿼리 입력: `up{job="prometheus"}`
5. **Run Query** 클릭

**예상 결과**: 3개 클러스터의 메트릭이 모두 표시됨
```
up{cluster="196", job="prometheus"} = 1
up{cluster="197", job="prometheus"} = 1
up{cluster="198", job="prometheus"} = 1
```

### 7.4 S3 업로드 확인

```bash
# 노드 197 또는 198에서 Thanos Sidecar 로그 확인
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus -c thanos-sidecar --tail=50

# "upload success" 메시지 확인 (2시간 후)
# 즉시 확인하려면 Prometheus TSDB 블록이 생성될 때까지 대기
```

### 7.5 MinIO Console에서 확인

1. http://console.minio.miribit.lab 접속
2. **Buckets → thanos** 클릭
3. 폴더 구조 확인 (클러스터별 블록 업로드)

✅ **Final Checkpoint**:
- 모든 UI 접근 가능
- Thanos Query가 3개 클러스터 메트릭 통합
- S3에 메트릭 블록 업로드 중
- OpenSearch에 로그 수집 중

---

## 8. 문제 해결

### 8.1 Pods가 Pending 상태

**증상**: `kubectl get pods`에서 Pods가 Pending 상태

**원인**:
- PVC 바인딩 실패
- 리소스 부족

**해결**:
```bash
# PVC 상태 확인
kubectl get pvc -A

# Longhorn 상태 확인
kubectl get pods -n longhorn-system

# 노드 리소스 확인
kubectl top nodes

# 이벤트 확인
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

### 8.2 Ingress 접속 불가

**증상**: Grafana URL 접속 시 "Site can't be reached"

**원인**:
- DNS 설정 오류
- NGINX Ingress Controller 미실행

**해결**:
```bash
# NGINX Ingress 상태 확인
kubectl get pods -n ingress-nginx

# Ingress 리소스 확인
kubectl get ingress -A

# DNS 확인
nslookup grafana.mkube-196.miribit.lab

# 임시 해결: /etc/hosts 수동 추가
echo "192.168.101.196 grafana.mkube-196.miribit.lab" | sudo tee -a /etc/hosts
```

### 8.3 Thanos Sidecar S3 업로드 실패

**증상**: Sidecar 로그에 "connection refused" 또는 "access denied"

**원인**:
- S3 엔드포인트 접근 불가
- S3 인증 정보 오류

**해결**:
```bash
# S3 연결 테스트
curl http://s3.minio.miribit.lab

# S3 Secret 확인
kubectl get secret thanos-s3-config -n monitoring -o yaml

# Secret 재생성
kubectl delete secret thanos-s3-config -n monitoring
kubectl apply -f deploy/base/thanos/s3-secret.yaml

# Pod 재시작
kubectl rollout restart statefulset prometheus-kube-prometheus-prometheus -n monitoring
```

### 8.4 OpenSearch 클러스터 Red 상태

**증상**: `_cluster/health` API가 "red" 반환

**원인**:
- 노드 간 통신 실패
- 샤드 할당 실패

**해결**:
```bash
# 클러스터 상태 상세 확인
kubectl port-forward -n logging svc/opensearch 9200:9200
curl "http://localhost:9200/_cat/shards?v"
curl "http://localhost:9200/_cluster/allocation/explain?pretty"

# Pods 재시작
kubectl rollout restart statefulset opensearch -n logging
```

### 8.5 로그 수집 안됨

**증상**: OpenSearch에 로그가 수집되지 않음

**원인**:
- Fluent-bit 설정 오류
- OpenSearch 엔드포인트 접근 불가

**해결**:
```bash
# Fluent-bit 로그 확인
kubectl logs -n logging -l app=fluent-bit --tail=100

# Fluent-bit 설정 확인
kubectl get configmap fluent-bit -n logging -o yaml

# OpenSearch 접근 테스트
kubectl exec -it -n logging ds/fluent-bit -- curl http://opensearch.logging.svc:9200
```

---

## 부록 A: 주요 명령어 요약

### 전체 배포 (자동화)

```bash
# 전체 노드에 일괄 배포 (원격 실행)
./scripts/deploy-all-clusters.sh
```

### 개별 컴포넌트 배포

```bash
# 현재 클러스터에 특정 컴포넌트 배포
./scripts/deploy-component.sh <component> [cluster-name]

# 예시
./scripts/deploy-component.sh longhorn cluster-196-central
./scripts/deploy-component.sh prometheus  # 자동 감지
```

### 상태 확인

```bash
# 전체 배포 상태 검증
./scripts/validate-deployment.sh

# Pods 상태
kubectl get pods -A

# Services 상태
kubectl get svc -A

# Ingress 상태
kubectl get ingress -A

# PVC 상태
kubectl get pvc -A
```

### 로그 확인

```bash
# 특정 Pod 로그
kubectl logs -n <namespace> <pod-name>

# 특정 컨테이너 로그
kubectl logs -n <namespace> <pod-name> -c <container-name>

# 실시간 로그
kubectl logs -n <namespace> <pod-name> -f

# 레이블 셀렉터로 로그
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100
```

---

## 부록 B: 배포 순서 요약

```
1. Minikube 설치 (노드 196, 197, 198)
   └─> 검증: minikube status

2. S3 버킷 생성 (MinIO)
   └─> 검증: MinIO Console에서 버킷 확인

3. Longhorn 배포 (모든 노드)
   └─> 검증: PVC 생성 및 바인딩 테스트

4. NGINX Ingress 배포 (모든 노드)
   └─> 검증: Ingress Controller pods Running

5. Prometheus Stack 배포 (모든 노드)
   └─> 검증: Grafana 접속, Thanos Query 작동

6. OpenSearch 배포 (모든 노드)
   └─> 검증: Cluster health green

7. Fluent-bit 배포 (모든 노드)
   └─> 검증: 로그 수집 확인

8. 최종 검증
   └─> 검증: validate-deployment.sh 실행
```

---

**작성자**: Claude AI
**버전**: 1.0
**최종 수정**: 2025-10-14
