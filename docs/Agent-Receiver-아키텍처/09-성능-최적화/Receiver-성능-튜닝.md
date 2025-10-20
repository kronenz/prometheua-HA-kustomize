# Receiver 성능 튜닝

## 📋 개요

Thanos Receiver의 처리량, 레이턴시, 리소스 효율을 최적화하여 대량의 Remote Write 트래픽을 안정적으로 처리합니다.

---

## 🎯 최적화 목표

- **처리량**: 50,000 samples/sec → **100,000 samples/sec** (2배)
- **수신 레이턴시 (P99)**: 200ms → **100ms** (50% 개선)
- **메모리 사용량**: 4Gi → **2.5Gi** (37% 절감)

---

## 1️⃣ Receiver 수평 확장 (Hashring)

### StatefulSet Replicas 증가

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-receive
  namespace: monitoring
spec:
  replicas: 5  # 3 → 5로 증가
  serviceName: thanos-receive
  template:
    spec:
      containers:
      - name: thanos-receive
        image: quay.io/thanos/thanos:v0.31.0
        args:
        - receive
        - --receive.replication-factor=3
        - --receive.hashrings-file=/etc/thanos/hashrings.json
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 2000m
            memory: 4Gi
```

### Hashring 재구성 (5 Receivers)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: thanos-receive-hashring
  namespace: monitoring
data:
  hashrings.json: |
    [
      {
        "hashring": "default",
        "endpoints": [
          "thanos-receive-0.thanos-receive:10901",
          "thanos-receive-1.thanos-receive:10901",
          "thanos-receive-2.thanos-receive:10901",
          "thanos-receive-3.thanos-receive:10901",
          "thanos-receive-4.thanos-receive:10901"
        ],
        "tenants": []
      }
    ]
```

### 스케일링 적용

```bash
# Receiver 확장
kubectl scale statefulset thanos-receive -n monitoring --replicas=5

# Hashring ConfigMap 업데이트
kubectl apply -f thanos-receive-hashring.yaml

# Receiver Pod 재시작 (Hashring 리로드)
kubectl rollout restart statefulset thanos-receive -n monitoring
```

**예상 효과**:
- 처리량: 50k → 100k samples/sec (linear scaling)
- 레이턴시: 부하 분산으로 20~30% 개선

---

## 2️⃣ Replication Factor 조정

### Replication Factor = 1 (성능 우선)

```yaml
args:
- receive
- --receive.replication-factor=1  # 3 → 1로 변경
```

**장점**:
- 쓰기 성능 3배 향상
- 네트워크 트래픽 66% 감소
- 메모리 사용량 66% 감소

**단점**:
- 고가용성 손실 (Receiver 1대 장애 시 데이터 손실)
- 프로덕션 환경 비권장

### Replication Factor = 2 (균형)

```yaml
args:
- receive
- --receive.replication-factor=2  # 3 → 2로 변경
```

**Trade-off**:
- 성능: 50% 향상
- 고가용성: 1대 장애까지 복구 가능
- **권장**: 성능과 안정성의 균형

---

## 3️⃣ TSDB 설정 최적화

### WAL 압축 활성화

```yaml
args:
- receive
- --tsdb.wal-compression  # WAL 압축 (기본 비활성화)
```

**효과**:
- WAL 디스크 사용량 40~60% 감소
- 쓰기 성능: ~5% 오버헤드 (무시 가능)

### TSDB Retention 조정

```yaml
args:
- receive
- --tsdb.retention=7d  # 15d → 7d로 축소
```

**효과**:
- 로컬 디스크 사용량 50% 감소
- Compaction 부하 감소
- PVC 크기 축소 가능 (100Gi → 50Gi)

### TSDB Block Duration

```yaml
args:
- receive
- --tsdb.min-block-duration=2h  # 기본값
- --tsdb.max-block-duration=2h  # 기본값
```

**권장**: 기본값 유지 (2h)
- 너무 작으면 블록 수 증가 → Compaction 부하 ↑
- 너무 크면 메모리 사용량 증가

---

## 4️⃣ 리소스 할당 최적화

### CPU/Memory Right-Sizing

```yaml
# Before (과다 할당)
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 4000m
    memory: 8Gi

# After (적정 할당)
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

### 리소스 사용량 측정

```promql
# CPU 사용률
rate(container_cpu_usage_seconds_total{
  pod=~"thanos-receive-.*",
  namespace="monitoring"
}[5m])

# Memory 사용량
container_memory_working_set_bytes{
  pod=~"thanos-receive-.*",
  namespace="monitoring"
}
```

### HPA (Horizontal Pod Autoscaler)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: thanos-receive-hpa
  namespace: monitoring
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: thanos-receive
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Pods
        value: 2
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Pods
        value: 1
        periodSeconds: 120
```

---

## 5️⃣ Disk I/O 최적화

### SSD 사용 (권장)

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ssd-storage  # HDD → SSD
      resources:
        requests:
          storage: 100Gi
```

**성능 비교**:
```
HDD (7200 RPM):
- Sequential Write: 100 MB/s
- IOPS: 100

SSD (SATA):
- Sequential Write: 500 MB/s
- IOPS: 10,000

NVMe SSD:
- Sequential Write: 3,000 MB/s
- IOPS: 100,000
```

### I/O Scheduler 최적화

```bash
# Node에서 실행 (SSD 전용)
echo "none" > /sys/block/sda/queue/scheduler

# 또는 mq-deadline (권장)
echo "mq-deadline" > /sys/block/sda/queue/scheduler
```

---

## 6️⃣ 네트워크 최적화

### gRPC Max Message Size

```yaml
args:
- receive
- --grpc.max-send-msg-size=100MB      # 기본 4MB
- --grpc.max-recv-msg-size=100MB      # 기본 4MB
```

**효과**: 대용량 시계열 전송 시 오류 방지

### HTTP Keep-Alive

```yaml
# Nginx Ingress Annotation
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: thanos-receive-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/upstream-keepalive-connections: "100"
    nginx.ingress.kubernetes.io/upstream-keepalive-timeout: "60"
```

---

## 7️⃣ Compaction 최적화

### Compactor 분리 (권장)

```yaml
# Compactor 전용 Pod (Receiver와 분리)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-compactor
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: thanos-compactor
        args:
        - compact
        - --data-dir=/data
        - --objstore.config-file=/etc/thanos/objstore.yml
        - --retention.resolution-raw=7d
        - --retention.resolution-5m=30d
        - --retention.resolution-1h=180d
        - --wait  # Continuous compaction
        - --compact.concurrency=4  # 병렬 압축
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
```

**효과**:
- Receiver CPU/메모리 부하 제거
- Compaction 전용 리소스 할당 가능

---

## 📊 성능 측정

### Receiver 성능 메트릭

```promql
# 초당 수신 샘플 수
rate(thanos_receive_replication_requests_total[5m]) * on (instance) group_left
  thanos_receive_replication_request_duration_seconds_count

# 수신 레이턴시 (P99)
histogram_quantile(0.99,
  rate(thanos_receive_http_request_duration_seconds_bucket{
    handler="receive"
  }[5m])
)

# TSDB 쓰기 레이턴시
rate(prometheus_tsdb_head_samples_appended_total[5m])
```

### 리소스 사용량

```promql
# CPU 사용률 (%)
rate(container_cpu_usage_seconds_total{pod=~"thanos-receive-.*"}[5m]) * 100

# Memory 사용량 (Gi)
container_memory_working_set_bytes{pod=~"thanos-receive-.*"} / 1024 / 1024 / 1024

# Disk I/O
rate(container_fs_writes_bytes_total{pod=~"thanos-receive-.*"}[5m]) / 1024 / 1024
```

---

## 🚨 모니터링 및 알림

### Receiver 과부하 알림

```yaml
- alert: ThanosReceiverHighCPU
  expr: |
    rate(container_cpu_usage_seconds_total{
      pod=~"thanos-receive-.*",
      namespace="monitoring"
    }[5m]) > 1.5
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Receiver CPU > 150% for 10m"

- alert: ThanosReceiverHighMemory
  expr: |
    container_memory_working_set_bytes{
      pod=~"thanos-receive-.*",
      namespace="monitoring"
    } / 1024 / 1024 / 1024 > 3
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Receiver memory > 3Gi"
```

### Receiver 레이턴시 알림

```yaml
- alert: ThanosReceiverHighLatency
  expr: |
    histogram_quantile(0.99,
      rate(thanos_receive_http_request_duration_seconds_bucket{
        handler="receive"
      }[5m])
    ) > 0.5
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Receiver P99 latency > 500ms"
```

---

## 🎯 최적화 체크리스트

### 수평 확장
- [ ] Receiver replicas 증가 (3 → 5+)
- [ ] Hashring 재구성
- [ ] HPA 설정 (자동 스케일링)

### Replication
- [ ] Replication Factor 검토 (3 → 2)
- [ ] 성능 vs 고가용성 Trade-off 평가

### TSDB
- [ ] WAL 압축 활성화
- [ ] Retention 조정 (15d → 7d)
- [ ] Block duration 검토

### 리소스
- [ ] CPU/Memory Right-Sizing
- [ ] SSD 스토리지 사용
- [ ] I/O Scheduler 최적화

### 네트워크
- [ ] gRPC max message size 증가
- [ ] Ingress Keep-Alive 설정

### Compaction
- [ ] Compactor 분리 배포
- [ ] Compaction 병렬도 조정

---

## 💡 베스트 프랙티스

### 1. Receiver per 25k samples/sec

```
목표 처리량: 100k samples/sec
→ Receiver replicas = 100k / 25k = 4개

여유율 20% 추가:
→ Receiver replicas = 4 × 1.2 = 5개
```

### 2. CPU:Memory 비율

```
Receiver 권장 비율: 1 core : 2Gi
- CPU: 1 core → Memory: 2Gi
- CPU: 2 cores → Memory: 4Gi
```

### 3. Disk 크기 계산

```
샘플 크기 = 16 bytes (average)
Retention = 7d
Samples/sec = 25,000

Disk = 25,000 × 86,400 × 7 × 16 bytes
     = 241 GB (raw)
     ≈ 100 GB (with compression)

권장 PVC: 150 GB (여유율 50%)
```

---

## 🔗 관련 문서

- **Thanos Receiver 패턴** → [../01-아키텍처/Thanos-Receiver-패턴.md](../01-아키텍처/Thanos-Receiver-패턴.md)
- **Remote Write 최적화** → [Remote-Write-최적화.md](./Remote-Write-최적화.md)
- **리소스 Right-Sizing** → [리소스-Right-Sizing.md](./리소스-Right-Sizing.md)

---

**최종 업데이트**: 2025-10-20
