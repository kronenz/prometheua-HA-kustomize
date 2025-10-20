# 📋 7노드 220클러스터 배포 요약

> **Quick Reference**: 노드별 배포 명령어 및 검증 체크리스트

## 🎯 아키텍처 한눈에 보기

```
┌─────────────────────────────────────────────────┐
│  Tier 1: Global Layer                           │
│  ┌──────────────┐  ┌──────────────┐            │
│  │   Node 1     │  │   Node 2     │            │
│  │ Global Query │  │ Global HA    │            │
│  │ + Store      │  │ + Compactor  │            │
│  │ + Grafana    │  │ + Store      │            │
│  └──────────────┘  └──────────────┘            │
└─────────────────────────────────────────────────┘
          │                    │
          └────────┬───────────┘
                   │
    ┌──────────────┼──────────────┬──────────────┐
    │              │              │              │
┌───▼────┐   ┌────▼───┐   ┌─────▼──┐   ┌──────▼─┐
│ Node 3 │   │ Node 4 │   │ Node 5 │   │ Node 6 │
│Regional│   │Regional│   │Regional│   │Regional│
│  A1    │   │  A2    │   │  A3    │   │  BCD   │
│(1-60)  │   │(61-120)│   │(121-180)│  │(181-220)│
└────────┘   └────────┘   └────────┘   └────────┘
    │            │            │            │
    └────────────┴────────────┴────────────┘
                      │
                 ┌────▼────┐
                 │ Node 7  │
                 │MinIO S3 │
                 │ 10TB+   │
                 └─────────┘
```

## 📦 노드별 배포 체크리스트

### Node 1: Global + Store + Grafana

```bash
# 1. 노드 준비
kubectl label node node1 role=global tier=1

# 2. Namespace 생성
kubectl create namespace monitoring

# 3. S3 Secret 생성
kubectl create secret generic thanos-s3-config \
  --from-file=objstore.yml=/path/to/objstore.yml \
  -n monitoring

# 4. Global Query 배포
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: global-thanos-query
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: global-thanos-query
  template:
    metadata:
      labels:
        app: global-thanos-query
    spec:
      nodeSelector:
        role: global
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.37.2
        args:
        - query
        - --http-address=0.0.0.0:9090
        - --grpc-address=0.0.0.0:10901
        - --store=regional-query-a1.monitoring:10901
        - --store=regional-query-a2.monitoring:10901
        - --store=regional-query-a3.monitoring:10901
        - --store=regional-query-bcd.monitoring:10901
        - --store=dnssrv+_grpc._tcp.thanos-store.monitoring.svc.cluster.local
        resources:
          limits:
            cpu: 4000m
            memory: 8Gi
          requests:
            cpu: 2000m
            memory: 4Gi
        ports:
        - containerPort: 9090
        - containerPort: 10901
EOF

# 5. Store Gateway 배포
kubectl apply -f deploy/global/thanos-store-statefulset.yaml

# 6. Grafana 배포
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.enabled=true \
  --set nodeSelector.role=global

# 7. 검증
kubectl get pods -n monitoring -l app=global-thanos-query
kubectl logs -n monitoring -l app=global-thanos-query --tail=50
```

**✅ 검증 체크리스트:**
- [ ] Global Query Pod Running
- [ ] Store Gateway (2 replicas) Running
- [ ] Grafana Pod Running
- [ ] Global Query에서 4개 Regional 연결 확인

---

### Node 2: Global HA + Compactor

```bash
# 1. 노드 준비
kubectl label node node2 role=global-ha tier=1

# 2. Global Query Replica 배포
kubectl apply -f deploy/global/global-query-ha-deployment.yaml

# 3. Compactor 배포
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-compactor
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: thanos-compactor
  template:
    metadata:
      labels:
        app: thanos-compactor
    spec:
      nodeSelector:
        role: global-ha
      containers:
      - name: thanos-compactor
        image: quay.io/thanos/thanos:v0.37.2
        args:
        - compact
        - --data-dir=/var/thanos/compactor
        - --objstore.config-file=/etc/thanos/objstore.yml
        - --retention.resolution-raw=7d
        - --retention.resolution-5m=30d
        - --retention.resolution-1h=90d
        - --compact.concurrency=3
        - --delete-delay=48h
        resources:
          limits:
            cpu: 4000m
            memory: 8Gi
          requests:
            cpu: 2000m
            memory: 4Gi
        volumeMounts:
        - name: objstore-config
          mountPath: /etc/thanos
        - name: data
          mountPath: /var/thanos/compactor
      volumes:
      - name: objstore-config
        secret:
          secretName: thanos-s3-config
      - name: data
        emptyDir: {}
EOF

# 4. Alertmanager 배포
kubectl apply -f deploy/global/alertmanager-statefulset.yaml

# 5. 검증
kubectl get pods -n monitoring -l app=global-thanos-query
kubectl get pods -n monitoring -l app=thanos-compactor
kubectl logs -n monitoring -l app=thanos-compactor --tail=20 | grep "compact blocks"
```

**✅ 검증 체크리스트:**
- [ ] Global Query HA Pod Running
- [ ] Compactor Pod Running
- [ ] Alertmanager (3 replicas) Running
- [ ] Compaction 작동 확인

---

### Node 3: Regional A1 (Cluster 1-60)

```bash
# 1. 노드 준비
kubectl label node node3 role=regional-a1 tier=2

# 2. Regional Query A1 배포
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: regional-query-a1
  namespace: monitoring
spec:
  replicas: 2  # HA
  selector:
    matchLabels:
      app: regional-query-a1
  template:
    metadata:
      labels:
        app: regional-query-a1
        region: a1
    spec:
      nodeSelector:
        role: regional-a1
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.37.2
        args:
        - query
        - --http-address=0.0.0.0:9090
        - --grpc-address=0.0.0.0:10901
        - --query.replica-label=replica
        # Cluster 1-60 Sidecar 연결 (동적 발견 또는 명시)
        # 실제 환경에서는 Service Discovery 사용
        resources:
          limits:
            cpu: 4000m
            memory: 8Gi
          requests:
            cpu: 2000m
            memory: 4Gi
        ports:
        - containerPort: 9090
        - containerPort: 10901
EOF

# 3. Regional Store A1 배포
kubectl apply -f deploy/regional-a1/regional-store-statefulset.yaml

# 4. 검증
kubectl get pods -n monitoring -l app=regional-query-a1
kubectl logs -n monitoring -l app=regional-query-a1 --tail=20
```

**✅ 검증 체크리스트:**
- [ ] Regional Query A1 (2 replicas) Running
- [ ] Regional Store A1 Running
- [ ] gRPC 연결 수 확인 (60개 예상)

---

### Node 4: Regional A2 (Cluster 61-120)

```bash
# 1. 노드 준비
kubectl label node node4 role=regional-a2 tier=2

# 2. Regional Query A2 배포
kubectl apply -f deploy/regional-a2/regional-query-deployment.yaml

# 3. Regional Store A2 배포
kubectl apply -f deploy/regional-a2/regional-store-statefulset.yaml

# 4. 검증
kubectl get pods -n monitoring -l app=regional-query-a2
```

**✅ 검증 체크리스트:**
- [ ] Regional Query A2 (2 replicas) Running
- [ ] Regional Store A2 Running

---

### Node 5: Regional A3 (Cluster 121-180)

```bash
# 1. 노드 준비
kubectl label node node5 role=regional-a3 tier=2

# 2. Regional Query A3 배포
kubectl apply -f deploy/regional-a3/regional-query-deployment.yaml

# 3. Regional Store A3 배포
kubectl apply -f deploy/regional-a3/regional-store-statefulset.yaml

# 4. 검증
kubectl get pods -n monitoring -l app=regional-query-a3
```

**✅ 검증 체크리스트:**
- [ ] Regional Query A3 (2 replicas) Running
- [ ] Regional Store A3 Running

---

### Node 6: Regional BCD (Cluster 181-220)

```bash
# 1. 노드 준비
kubectl label node node6 role=regional-bcd tier=2

# 2. Regional Query BCD 배포
kubectl apply -f deploy/regional-bcd/regional-query-deployment.yaml

# 3. Regional Store BCD 배포
kubectl apply -f deploy/regional-bcd/regional-store-statefulset.yaml

# 4. 검증
kubectl get pods -n monitoring -l app=regional-query-bcd
```

**✅ 검증 체크리스트:**
- [ ] Regional Query BCD (2 replicas) Running
- [ ] Regional Store BCD Running
- [ ] gRPC 연결 수 확인 (40개 예상)

---

### Node 7: MinIO S3

```bash
# 1. 노드 준비
kubectl label node node7 role=storage tier=3

# 2. 외부 스토리지 마운트
ssh node7
sudo mkdir -p /mnt/minio-data
# NFS/iSCSI 등 외부 스토리지 마운트
sudo mount /dev/sdb1 /mnt/minio-data  # 예시

# 3. MinIO 배포
kubectl create namespace storage

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: storage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      nodeSelector:
        role: storage
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          value: "minio"
        - name: MINIO_ROOT_PASSWORD
          value: "minio123"
        resources:
          limits:
            cpu: 8000m
            memory: 16Gi
          requests:
            cpu: 4000m
            memory: 8Gi
        volumeMounts:
        - name: data
          mountPath: /data
        ports:
        - containerPort: 9000
        - containerPort: 9001
      volumes:
      - name: data
        hostPath:
          path: /mnt/minio-data
          type: Directory
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: storage
spec:
  type: ClusterIP
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
  selector:
    app: minio
EOF

# 4. S3 버킷 생성
kubectl run -it --rm mc --image=minio/mc --restart=Never -- \
  /bin/sh -c "mc alias set minio http://minio.storage:9000 minio minio123 && \
              mc mb minio/thanos-bucket"

# 5. 검증
kubectl get pods -n storage -l app=minio
kubectl exec -n storage -it minio-xxx -- ls -lh /data
```

**✅ 검증 체크리스트:**
- [ ] MinIO Pod Running
- [ ] MinIO Console 접근 가능 (http://minio.storage:9001)
- [ ] thanos-bucket 생성 확인
- [ ] 외부 스토리지 마운트 확인

---

## 🔍 전체 시스템 검증

### 1. Pod 상태 확인

```bash
# 모든 모니터링 Pod 확인
kubectl get pods -n monitoring -o wide

# 예상 출력:
# global-thanos-query-xxx          1/1  Running  node1
# global-thanos-query-ha-xxx       1/1  Running  node2
# thanos-store-0                   1/1  Running  node1
# thanos-store-1                   1/1  Running  node1
# thanos-store-2                   1/1  Running  node2
# thanos-compactor-xxx             1/1  Running  node2
# grafana-xxx                      1/1  Running  node1
# alertmanager-0,1,2               1/1  Running  node2
# regional-query-a1-xxx (2개)      1/1  Running  node3
# regional-query-a2-xxx (2개)      1/1  Running  node4
# regional-query-a3-xxx (2개)      1/1  Running  node5
# regional-query-bcd-xxx (2개)     1/1  Running  node6
# regional-store-a1-0              1/1  Running  node3
# regional-store-a2-0              1/1  Running  node4
# regional-store-a3-0              1/1  Running  node5
# regional-store-bcd-0             1/1  Running  node6
```

### 2. Store 연결 확인

```bash
# Global Query에서 모든 Store 확인
kubectl exec -n monitoring global-thanos-query-xxx -- \
  wget -qO- http://localhost:9090/api/v1/stores | jq '.data[] | {name, lastCheck, lastError}'

# 예상 출력: 총 11개 연결
# - regional-query-a1:10901    (Cluster 1-60)
# - regional-query-a2:10901    (Cluster 61-120)
# - regional-query-a3:10901    (Cluster 121-180)
# - regional-query-bcd:10901   (Cluster 181-220)
# - thanos-store-0:10901       (S3 과거 데이터)
# - thanos-store-1:10901
# - thanos-store-2:10901
# - regional-store-a1-0:10901
# - regional-store-a2-0:10901
# - regional-store-a3-0:10901
# - regional-store-bcd-0:10901
```

### 3. S3 업로드 확인

```bash
# MinIO 버킷 확인
kubectl exec -n storage minio-xxx -- \
  mc ls minio/thanos-bucket

# 예상: 220개 클러스터의 2시간 블록
```

### 4. Grafana 접속

```bash
# Grafana 포트 포워딩
kubectl port-forward -n monitoring svc/grafana 3000:3000

# 브라우저에서 http://localhost:3000 접속
# ID: admin
# PW: kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Datasource 확인: Thanos-Query (http://global-thanos-query:9090)
```

### 5. 쿼리 테스트

```promql
# 전체 클러스터 Up 확인
sum(up) by (cluster)
# 예상: 220개 클러스터 결과

# Regional별 CPU 사용률
sum(rate(container_cpu_usage_seconds_total[5m])) by (region)

# Global 메트릭
count(up == 1)
# 예상: 수천~수만 개 타겟
```

---

## 🚨 트러블슈팅

### 문제 1: Regional Query가 Sidecar 연결 못함

**증상:**
```
kubectl logs -n monitoring regional-query-a1-xxx
error: no store found
```

**해결:**
1. Sidecar Service 확인
2. NetworkPolicy 확인
3. DNS 확인

```bash
# 각 App 클러스터에서
kubectl get svc -n monitoring | grep sidecar
kubectl get networkpolicy -n monitoring
```

### 문제 2: Global Query 응답 느림

**증상:** 쿼리 응답 시간 > 30초

**해결:**
1. Regional Query 부하 확인
2. Recording Rules 추가
3. Query 캐싱 활성화

```bash
# Regional Query 리소스 확인
kubectl top pods -n monitoring -l app=regional-query-a1

# Query 메트릭 확인
kubectl exec -n monitoring global-thanos-query-xxx -- \
  wget -qO- http://localhost:9090/metrics | grep thanos_query_duration
```

### 문제 3: S3 업로드 실패

**증상:** Sidecar에서 업로드 실패 로그

**해결:**
1. MinIO 접근 확인
2. S3 Secret 확인
3. 네트워크 확인

```bash
# MinIO 상태 확인
kubectl get pods -n storage -l app=minio

# S3 Secret 확인
kubectl get secret -n monitoring thanos-s3-config -o yaml

# 네트워크 테스트
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl http://minio.storage:9000/minio/health/live
```

---

## 📊 리소스 모니터링

### 노드 리소스 사용률

```bash
# 실시간 모니터링
watch -n 5 'kubectl top nodes | grep -E "node[1-7]"'
```

### Pod 리소스 사용률

```bash
# Top 10 CPU 사용 Pod
kubectl top pods -n monitoring --sort-by=cpu | head -11

# Top 10 Memory 사용 Pod
kubectl top pods -n monitoring --sort-by=memory | head -11
```

### 네트워크 대역폭

```bash
# 각 노드에서
for i in {1..7}; do
  echo "=== Node $i ==="
  ssh node$i "sar -n DEV 1 1 | grep -E 'eth0|ens'"
done
```

---

## 📈 성능 최적화 체크리스트

- [ ] Recording Rules 구성 (고빈도 쿼리 사전 계산)
- [ ] Query 결과 캐싱 활성화
- [ ] S3 Compaction 주기 최적화 (3분 → 5분)
- [ ] Regional Query 리소스 증설 (필요 시)
- [ ] NetworkPolicy로 불필요한 트래픽 차단
- [ ] Grafana 대시보드 최적화 (쿼리 단순화)

---

**배포 완료 후 다음 단계:**
1. [OPERATIONS.md](./OPERATIONS.md) - 일상 운영 가이드
2. [BEST_PRACTICES.md](./BEST_PRACTICES.md) - 성능 최적화
3. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - 문제 해결

**Last Updated**: 2025-10-15
**Architecture**: 7 Nodes, 220 Clusters, 3-Tier Hierarchical
