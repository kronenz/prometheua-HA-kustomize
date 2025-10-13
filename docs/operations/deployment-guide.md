# 배포 가이드

본 문서는 Thanos Multi-Cluster 인프라를 처음부터 배포하는 전체 과정을 설명합니다.

## 사전 요구사항

### 하드웨어
- 3개 물리 서버 또는 VM
  - 192.168.101.196 (중앙 클러스터)
  - 192.168.101.197 (엣지 클러스터)
  - 192.168.101.198 (엣지 클러스터)
- 각 서버: 최소 4 CPU, 16GB RAM, 50GB 디스크

### 소프트웨어
- Ubuntu 20.04+ 또는 CentOS 7+
- containerd 런타임
- SSH 접근 (bsh / 123qwe)

### 외부 서비스
- MinIO S3: https://172.20.40.21:30001
- 접근 자격 증명: minio / minio123
- DNS: *.mkube-{196,197,198}.miribit.lab → 각 노드 IP

## 배포 단계

### 1단계: 프로젝트 클론

```bash
# 중앙 클러스터 (196)에서 실행
ssh bsh@192.168.101.196
cd /opt
sudo git clone <repository-url> thanos-monitoring
cd thanos-monitoring
```

### 2단계: S3 버킷 생성

```bash
# 스크립트 실행 (어느 노드에서든 가능)
./scripts/s3/create-buckets.sh

# 출력:
# === MinIO S3 버킷 생성 ===
# ✓ MinIO 연결 성공
# ✓ 버킷 생성 완료: thanos
# ✓ 버킷 생성 완료: opensearch-logs
# ✓ 버킷 생성 완료: longhorn-backups

# 버킷 검증
./scripts/s3/verify-buckets.sh
```

### 3단계: Minikube 설치 (각 노드별)

#### 노드 196 (중앙 클러스터)

```bash
ssh bsh@192.168.101.196
cd /opt/thanos-monitoring

# Minikube 설치 및 시작
./scripts/minikube/install-minikube.sh

# 출력 확인:
# ║        Minikube 설치 완료!             ║
# 클러스터 상태: Running
# 노드: minikube   Ready   control-plane   4.0   16Gi
```

#### 노드 197 (엣지 클러스터)

```bash
ssh bsh@192.168.101.197
cd /opt/thanos-monitoring

./scripts/minikube/install-minikube.sh
```

#### 노드 198 (엣지 클러스터)

```bash
ssh bsh@192.168.101.198
cd /opt/thanos-monitoring

./scripts/minikube/install-minikube.sh
```

### 4단계: 중앙 클러스터 배포

```bash
ssh bsh@192.168.101.196
cd /opt/thanos-monitoring

# 전체 스택 배포 (약 10-15분 소요)
./scripts/deploy-cluster-196-central.sh
```

**배포 순서:**
1. Longhorn (스토리지 CSI) - 약 3분
2. Ingress-nginx - 약 1분
3. Prometheus + Thanos - 약 5분
4. OpenSearch - 약 3분
5. Fluent-bit - 약 1분

**예상 출력:**
```
════════════════════════════════════════
1/5 Longhorn 배포 중...
════════════════════════════════════════
Longhorn 배포 중...
✓ Longhorn 배포 완료

════════════════════════════════════════
2/5 NGINX Ingress 배포 중...
════════════════════════════════════════
✓ NGINX Ingress 배포 완료

... (생략)

╔════════════════════════════════════════╗
║          배포 완료!                    ║
╚════════════════════════════════════════╝
```

### 5단계: 중앙 클러스터 검증

```bash
# 모니터링 스택 확인
./scripts/validation/verify-monitoring.sh

# 로깅 스택 확인
./scripts/validation/verify-logging.sh

# 모든 Pod 확인
kubectl get pods --all-namespaces
```

**정상 상태:**
- 모든 Pod: Running
- Prometheus: 1/1 Ready
- Thanos Query/Store/Compactor/Ruler: 각 1/1 Ready
- Grafana: 1/1 Ready
- OpenSearch: 1/1 Ready
- Fluent-bit: DaemonSet 1/1

### 6단계: 엣지 클러스터 배포

#### 노드 197

```bash
ssh bsh@192.168.101.197
cd /opt/thanos-monitoring

./scripts/deploy-cluster-197-edge.sh

# 배포 완료 후 검증
./scripts/validation/verify-monitoring.sh
./scripts/validation/verify-logging.sh
```

#### 노드 198

```bash
ssh bsh@192.168.101.198
cd /opt/thanos-monitoring

./scripts/deploy-cluster-198-edge.sh

# 배포 완료 후 검증
./scripts/validation/verify-monitoring.sh
./scripts/validation/verify-logging.sh
```

### 7단계: 멀티클러스터 연결 확인

```bash
# 중앙 클러스터 (196)로 돌아가기
ssh bsh@192.168.101.196

# Thanos Query가 모든 클러스터를 인식하는지 확인
kubectl exec -n monitoring deployment/thanos-query -- \
  wget -qO- http://localhost:9090/api/v1/stores | jq .

# 예상 출력: 3개 store 엔드포인트
# - kube-prometheus-stack-prometheus (로컬)
# - thanos-store (S3)
# - 192.168.101.197:30901 (엣지 197)
# - 192.168.101.198:30901 (엣지 198)
```

### 8단계: Grafana 접근 및 데이터 소스 설정

```bash
# Grafana 초기 비밀번호 확인
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo
```

**브라우저에서 접근:**
1. http://grafana.mkube-196.miribit.lab:30080 접속
2. 사용자: `admin`, 비밀번호: (위에서 확인한 값)
3. Configuration → Data Sources 확인
   - Prometheus (기본) → 로컬 Prometheus
   - Thanos (추가 필요) → http://thanos-query.monitoring.svc.cluster.local:9090

**Thanos 데이터 소스 추가:**
1. Configuration → Data Sources → Add data source
2. 타입: Prometheus
3. 이름: Thanos
4. URL: http://thanos-query.monitoring.svc.cluster.local:9090
5. Save & Test

### 9단계: 멀티클러스터 쿼리 테스트

**Grafana Explore에서 테스트:**

```promql
# 모든 클러스터의 노드 개수
count(kube_node_info) by (cluster)

# 예상 결과:
# cluster-196-central: 1
# cluster-197-edge: 1
# cluster-198-edge: 1

# 모든 클러스터의 Pod 수
count(kube_pod_info) by (cluster)

# 각 클러스터의 메모리 사용량
sum(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) by (cluster)
```

### 10단계: 로그 수집 확인

```bash
# OpenSearch 인덱스 확인
kubectl exec -n logging opensearch-cluster-master-0 -- \
  curl -s http://localhost:9200/_cat/indices?v

# 로그 쿼리 테스트
kubectl exec -n logging opensearch-cluster-master-0 -- \
  curl -s http://localhost:9200/logs-*/_search?size=1 | jq .
```

**예상 결과:**
- `logs-k8s-YYYY.MM.DD` 인덱스 존재
- `logs-host-YYYY.MM.DD` 인덱스 존재
- cluster 레이블로 각 클러스터 구분 가능

## 배포 후 체크리스트

### 중앙 클러스터 (196)

- [ ] Longhorn UI 접근: http://longhorn.mkube-196.miribit.lab:30080
- [ ] Grafana 접근: http://grafana.mkube-196.miribit.lab:30080
- [ ] Thanos Query 접근: http://thanos.mkube-196.miribit.lab:30080
- [ ] Prometheus 접근: http://prometheus.mkube-196.miribit.lab:30080
- [ ] Alertmanager 접근: http://alertmanager.mkube-196.miribit.lab:30080
- [ ] OpenSearch 접근: http://opensearch.mkube-196.miribit.lab:30080
- [ ] Thanos Store 엔드포인트 연결 확인
- [ ] S3 버킷에 메트릭 블록 업로드 확인
- [ ] 3개 클러스터 메트릭 통합 조회 확인

### 엣지 클러스터 (197, 198)

- [ ] Grafana 로컬 접근 확인
- [ ] Prometheus 로컬 메트릭 수집 확인
- [ ] Thanos Sidecar NodePort 30901 접근 확인
- [ ] S3 버킷에 메트릭 블록 업로드 확인
- [ ] Fluent-bit 로그 수집 확인

### 전체 시스템

- [ ] 3개 클러스터 메트릭 통합 쿼리 성공
- [ ] S3 버킷 3개 모두 사용 중 확인
- [ ] 각 클러스터 로그가 OpenSearch에 수집됨
- [ ] Alertmanager 알림 수신 테스트
- [ ] Longhorn 볼륨 백업 테스트

## 트러블슈팅

### Pod가 Pending 상태

```bash
kubectl describe pod <pod-name> -n <namespace>

# 일반적인 원인:
# - 리소스 부족: Minikube 메모리/CPU 증가 필요
# - 스토리지 클래스 없음: Longhorn 배포 확인
# - 이미지 풀 실패: 네트워크 연결 확인
```

### Thanos Query가 Store를 찾지 못함

```bash
# Store 엔드포인트 확인
kubectl logs -n monitoring deployment/thanos-query | grep store

# 엣지 클러스터 Sidecar 접근 확인
curl http://192.168.101.197:30901/api/v1/labels

# 해결 방법:
# 1. thanos-query.yaml의 --store 플래그 확인
# 2. 엣지 클러스터 thanos-sidecar-external 서비스 확인
# 3. 네트워크 방화벽 30901 포트 개방
```

### OpenSearch Pod CrashLoopBackOff

```bash
kubectl logs -n logging opensearch-cluster-master-0

# 일반적인 원인:
# - vm.max_map_count 설정 필요
# - 메모리 부족

# 해결 방법:
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### S3 연결 실패

```bash
# Secret 확인
kubectl get secret thanos-s3-config -n monitoring -o yaml

# 연결 테스트
kubectl run -it --rm test-s3 --image=amazon/aws-cli --restart=Never -- \
  s3 --endpoint-url=https://172.20.40.21:30001 \
  --no-verify-ssl ls s3://thanos

# 해결 방법:
# 1. MinIO 서버 상태 확인
# 2. 네트워크 연결 확인 (ping 172.20.40.21)
# 3. 자격 증명 확인
```

## 업그레이드

### Helm Chart 버전 업그레이드

```bash
# 1. base/*/kustomization.yaml의 version 업데이트
# 2. 변경 사항 미리보기
kustomize build deploy/overlays/cluster-196-central/prometheus --enable-helm > /tmp/new.yaml
kubectl diff -f /tmp/new.yaml

# 3. 적용
kubectl apply -f /tmp/new.yaml
```

### 롤링 업데이트

Prometheus, Thanos 등 StatefulSet은 자동으로 롤링 업데이트됩니다.

```bash
# 업데이트 진행 상황 확인
kubectl rollout status statefulset/prometheus-kube-prometheus-stack-prometheus -n monitoring
```

## 백업 및 복구

### Prometheus 데이터 백업

Thanos가 자동으로 S3에 블록을 업로드하므로 별도 백업 불필요.

### OpenSearch 스냅샷 생성

```bash
# 스냅샷 리포지토리 등록 (최초 1회)
kubectl exec -n logging opensearch-cluster-master-0 -- \
  curl -X PUT "http://localhost:9200/_snapshot/s3-snapshots" \
  -H 'Content-Type: application/json' -d'
{
  "type": "s3",
  "settings": {
    "bucket": "opensearch-logs",
    "client": "default",
    "base_path": "snapshots"
  }
}'

# 수동 스냅샷 생성
kubectl exec -n logging opensearch-cluster-master-0 -- \
  curl -X PUT "http://localhost:9200/_snapshot/s3-snapshots/snapshot_$(date +%Y%m%d_%H%M%S)?wait_for_completion=false"
```

### Longhorn 볼륨 백업

Longhorn UI (http://longhorn.mkube-<cluster>.miribit.lab:30080)에서:
1. 볼륨 선택
2. Create Backup
3. S3 버킷 `longhorn-backups`에 저장됨

## 다음 단계

- [운영 가이드](operations-guide.md) 읽기
- [트러블슈팅 가이드](troubleshooting.md) 참조
- [모니터링 대시보드](dashboards.md) 설정
