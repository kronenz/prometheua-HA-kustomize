# Thanos Multi-Cluster 빠른 시작 가이드 (15분)

이 가이드는 노드 196 (중앙 클러스터)에 최소 모니터링 스택을 15분 안에 배포하는 방법을 안내합니다.

## 사전 준비 (5분)

### 1. SSH 접속
```bash
ssh bsh@192.168.101.196
# Password: 123qwe
```

### 2. 저장소 확인
```bash
cd ~/thanos-multi-cluster
ls -la
```

### 3. 사전 검증
```bash
# 노드 리소스 확인
nproc  # 4+ 예상
free -h  # 16GB+ 예상

# S3 연결 확인
curl -I http://console.minio.miribit.lab
# HTTP/1.1 200 OK 예상
```

## Minikube 설치 (5분)

```bash
# Minikube 설치 스크립트 실행
chmod +x scripts/minikube/install-minikube.sh
./scripts/minikube/install-minikube.sh

# 설치 확인
minikube status
kubectl get nodes

# 예상 출력:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   2m    v1.28.3
```

## S3 버킷 생성 (1분)

```bash
# MinIO 버킷 생성
chmod +x scripts/s3/create-buckets.sh
./scripts/s3/create-buckets.sh

# 생성되는 버킷:
# - thanos-bucket
# - opensearch-logs
# - longhorn-backups
```

## 모니터링 스택 배포 (8분)

### 1. Longhorn Storage (3분)
```bash
chmod +x scripts/deploy-component.sh
./scripts/deploy-component.sh longhorn cluster-196-central

# 배포 완료 대기
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# 확인
kubectl get pods -n longhorn-system
```

### 2. NGINX Ingress (2분)
```bash
./scripts/deploy-component.sh ingress-nginx cluster-196-central

kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=180s

# 확인
kubectl get pods -n ingress-nginx
```

### 3. Prometheus + Thanos (3분)
```bash
./scripts/deploy-component.sh prometheus cluster-196-central

# 배포 완료 대기 (이미지 다운로드 포함)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --timeout=600s

# 확인
kubectl get pods -n monitoring
```

## 검증 (1분)

### 1. 배포 상태 확인
```bash
chmod +x scripts/validate-deployment.sh
./scripts/validate-deployment.sh

# 예상 출력: 성공률 90%+
```

### 2. Grafana 접속
```bash
# Port forwarding (로컬에서 접속하는 경우)
kubectl port-forward -n monitoring svc/grafana 3000:80

# 브라우저에서 접속:
# - URL: http://localhost:3000
# - Username: admin
# - Password: prom-operator
```

**DNS가 설정된 경우**:
- URL: http://grafana.mkube-196.miribit.lab
- Username: admin
- Password: prom-operator

### 3. 메트릭 확인

Grafana에서:
1. **Explore** 메뉴 클릭
2. Datasource: **Prometheus** 선택
3. 쿼리 입력: `up`
4. **Run Query** 클릭

**예상 결과**: Prometheus와 관련 컴포넌트의 메트릭이 표시됨

## 다음 단계

중앙 클러스터 배포가 완료되었습니다! 다음 작업을 진행하세요:

### Edge 클러스터 추가 (선택사항)
```bash
# 노드 197, 198에 동일하게 반복
ssh bsh@192.168.101.197
cd ~/thanos-multi-cluster

./scripts/minikube/install-minikube.sh
./scripts/deploy-component.sh longhorn cluster-197-edge
./scripts/deploy-component.sh ingress-nginx cluster-197-edge
./scripts/deploy-component.sh prometheus cluster-197-edge
```

### 로깅 스택 추가 (선택사항)
```bash
# OpenSearch 배포
./scripts/deploy-component.sh opensearch cluster-196-central
kubectl wait --for=condition=ready pod -l app=opensearch -n logging --timeout=600s

# Fluent-bit 배포
./scripts/deploy-component.sh fluent-bit cluster-196-central
kubectl get ds -n logging fluent-bit
```

### 전체 배포 가이드
상세한 배포 절차는 [deployment-guide.md](./deployment-guide.md)를 참조하세요.

## 문제 해결

### Pods가 Pending 상태

```bash
# 이벤트 확인
kubectl get events --sort-by='.lastTimestamp' | tail -20

# PVC 상태 확인
kubectl get pvc -A

# Longhorn 상태 확인
kubectl get pods -n longhorn-system
```

### Grafana 접속 불가

```bash
# NGINX Ingress 확인
kubectl get pods -n ingress-nginx

# Port forwarding으로 직접 접속
kubectl port-forward -n monitoring svc/grafana 3000:80
# 브라우저: http://localhost:3000
```

### 로그 확인

```bash
# Prometheus 로그
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=50

# Grafana 로그
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50

# 전체 이벤트
kubectl get events -A --sort-by='.lastTimestamp'
```

## 성공 기준

✅ 모든 Pods가 Running 상태
✅ Grafana 접속 가능
✅ Prometheus 메트릭 수집 중
✅ Storage Class 사용 가능
✅ Ingress Controller 작동 중

## 소요 시간 요약

| 단계 | 예상 시간 |
|------|-----------|
| 사전 준비 | 5분 |
| Minikube 설치 | 5분 |
| S3 버킷 생성 | 1분 |
| Longhorn 배포 | 3분 |
| NGINX Ingress 배포 | 2분 |
| Prometheus 배포 | 3분 |
| 검증 | 1분 |
| **총계** | **20분** |

*실제 소요 시간은 네트워크 속도와 시스템 리소스에 따라 다를 수 있습니다.*

---

**다음 문서**: [전체 배포 가이드](./deployment-guide.md)
**문제 발생 시**: [운영 가이드](./operations-guide.md)
