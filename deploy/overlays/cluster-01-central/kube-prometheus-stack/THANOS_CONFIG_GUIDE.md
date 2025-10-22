# Thanos 설정 가이드

이 문서는 Thanos 멀티 클러스터 모니터링 시스템의 각 컴포넌트 설정에 대한 상세한 설명을 제공합니다.

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [Thanos Query 설정](#thanos-query-설정)
3. [Thanos Receiver 설정](#thanos-receiver-설정)
4. [Thanos Store 설정](#thanos-store-설정)
5. [Thanos Compactor 설정](#thanos-compactor-설정)
6. [Thanos Ruler 설정](#thanos-ruler-설정)
7. [S3 스토리지 설정](#s3-스토리지-설정)
8. [운영 가이드](#운영-가이드)
9. [문제 해결](#문제-해결)

---

## 아키텍처 개요

### 전체 데이터 흐름

```
┌─────────────────┐
│  Edge Clusters  │
│  (02, 03, 04)   │
│                 │
│  Prometheus     │
│  Agent          │
└────────┬────────┘
         │ Remote Write
         │ (HTTP)
         ↓
┌─────────────────┐
│ Central Cluster │
│    (01)         │
│                 │
│  ┌───────────┐  │
│  │  Thanos   │  │
│  │  Receiver │  │
│  └─────┬─────┘  │
│        │        │
│        ↓        │
│   ┌────────┐   │
│   │   S3   │   │  ← Thanos Store (장기 데이터)
│   └────┬───┘   │
│        │       │
│        ↑       │
│  ┌─────┴────┐  │
│  │  Thanos  │  │
│  │  Query   │  │
│  └────┬─────┘  │
│       │        │
│       ↓        │
│  ┌─────────┐   │
│  │ Grafana │   │
│  └─────────┘   │
└─────────────────┘
```

### 컴포넌트 역할

| 컴포넌트 | 역할 | 배포 위치 | 확장성 |
|---------|------|----------|-------|
| **Thanos Query** | 통합 쿼리 계층 | Central | Horizontal |
| **Thanos Receiver** | 메트릭 수신/저장 | Central | Horizontal (Hashring) |
| **Thanos Store** | S3 데이터 쿼리 | Central | Horizontal |
| **Thanos Compactor** | 데이터 압축/정리 | Central | Singleton |
| **Thanos Ruler** | Alert/Recording Rule | Central | Horizontal |
| **Prometheus Agent** | 메트릭 수집 | Edge | Per-Cluster |

---

## Thanos Query 설정

### 목적
- 모든 데이터 소스(Receiver, Store, Ruler)를 통합하여 쿼리
- Grafana에게 단일 엔드포인트 제공
- Deduplication 수행

### 주요 설정 (`thanos-query.yaml`)

```yaml
args:
  - query
  - --log.level=info

  # Replica 라벨 (중복 제거용)
  # - 동일한 데이터의 여러 복제본을 구분
  # - 쿼리 결과에서 자동으로 중복 제거
  - --query.replica-label=prometheus_replica
  - --query.replica-label=rule_replica
  - --query.replica-label=receive_replica

  # Store 엔드포인트 (데이터 소스)
  # - Prometheus Operator (중앙 클러스터의 Full Prometheus)
  - --store=dnssrv+_grpc._tcp.prometheus-operated.monitoring.svc.cluster.local

  # - Thanos Store (S3 장기 데이터)
  - --store=thanos-store.monitoring.svc.cluster.local:10901

  # - Thanos Ruler (Recording/Alerting Rule 결과)
  - --store=thanos-ruler.monitoring.svc.cluster.local:10901

  # - Thanos Receiver (실시간 Edge 데이터)
  - --store=dnssrv+_grpc._tcp.thanos-receiver-headless.monitoring.svc.cluster.local
```

### 최적화 팁

1. **리소스 설정**
   ```yaml
   resources:
     limits:
       cpu: 500m      # 쿼리 부하가 높으면 1-2 CPU로 증가
       memory: 1Gi    # 복잡한 쿼리는 2-4Gi 필요
   ```

2. **고가용성 (HA)**
   ```yaml
   replicas: 2  # 최소 2개 권장
   ```

3. **쿼리 성능**
   - Store 개수가 많으면 쿼리 속도 저하
   - 필요한 Store만 연결
   - Time range 제한 권장

---

## Thanos Receiver 설정

### 목적
- Edge Prometheus Agent로부터 메트릭 수신
- 실시간 데이터를 S3에 업로드
- Hashring을 통한 수평 확장

### 주요 설정 (`thanos-receiver.yaml`)

```yaml
# StatefulSet 설정
replicas: 3  # 최소 3개 권장 (Hashring 안정성)

args:
  - receive
  - --log.level=info

  # TSDB 설정
  # - 로컬 디스크에 임시 저장 후 S3 업로드
  - --tsdb.path=/var/thanos/receive
  - --tsdb.retention=2h  # 로컬 보관 시간 (짧을수록 디스크 절약)

  # Remote Write 엔드포인트
  - --remote-write.address=0.0.0.0:19291

  # S3 설정
  - --objstore.config-file=/etc/thanos/objstore.yml

  # Hashring 설정 (수평 확장)
  - --receive.hashrings-file=/etc/thanos/hashrings.json

  # Replication Factor
  - --receive.replication-factor=1  # 3개 권장 (고가용성)
```

### Hashring 설정

```json
[
  {
    "hashring": "default",
    "endpoints": [
      "thanos-receiver-0.thanos-receiver-headless.monitoring.svc.cluster.local:10901",
      "thanos-receiver-1.thanos-receiver-headless.monitoring.svc.cluster.local:10901",
      "thanos-receiver-2.thanos-receiver-headless.monitoring.svc.cluster.local:10901"
    ]
  }
]
```

### 최적화 팁

1. **스토리지**
   ```yaml
   volumeClaimTemplates:
     - metadata:
         name: data
       spec:
         accessModes: ["ReadWriteOnce"]
         resources:
           requests:
             storage: 50Gi  # TSDB 보관 시간에 따라 조정
   ```

2. **메모리**
   - 높은 카디널리티: 4-8Gi
   - 일반적인 환경: 2Gi

3. **Replica 수**
   - 3개: 기본 권장
   - 5개 이상: 높은 처리량 환경

4. **TSDB Retention**
   - 2시간: 빠른 S3 업로드 (디스크 절약)
   - 12시간: 네트워크 장애 대비

---

## Thanos Store 설정

### 목적
- S3에 저장된 장기 데이터 쿼리
- 블록 메타데이터 캐싱으로 성능 향상

### 주요 설정 (`thanos-store.yaml`)

```yaml
args:
  - store
  - --log.level=info

  # 데이터 경로
  - --data-dir=/var/thanos/store

  # S3 설정
  - --objstore.config-file=/etc/thanos/objstore.yml

  # 인덱스 캐시 (성능 향상)
  - --index-cache-size=512MB  # 메모리에 따라 1-4GB로 증가

  # 청크 캐시
  - --chunk-pool-size=2GB

  # 최소 시간 (쿼리 범위 제한)
  # - 최근 데이터는 Receiver에서 처리
  # - Store는 오래된 데이터만 담당
  - --min-time=-6h
```

### 최적화 팁

1. **캐시 크기**
   ```yaml
   --index-cache-size=2GB  # 메트릭 종류가 많으면 증가
   --chunk-pool-size=4GB   # 쿼리 성능 향상
   ```

2. **시간 파티셔닝**
   ```yaml
   # 최근 6시간은 Receiver가 담당
   --min-time=-6h

   # 1년 이상 데이터만 담당하려면
   --min-time=-8760h
   ```

3. **수평 확장**
   ```yaml
   # Store는 Stateless이므로 자유롭게 확장 가능
   replicas: 3  # 쿼리 부하에 따라 조정
   ```

---

## Thanos Compactor 설정

### 목적
- S3 블록 압축 및 다운샘플링
- 오래된 데이터 정리
- 스토리지 비용 절감

### 주요 설정 (`thanos-compactor.yaml`)

```yaml
args:
  - compact
  - --log.level=info

  # 작업 디렉토리
  - --data-dir=/var/thanos/compact

  # S3 설정
  - --objstore.config-file=/etc/thanos/objstore.yml

  # Retention 정책
  # - 원본 데이터: 7일 보관
  - --retention.resolution-raw=7d
  # - 5분 다운샘플: 30일 보관
  - --retention.resolution-5m=30d
  # - 1시간 다운샘플: 365일 보관
  - --retention.resolution-1h=365d

  # Compaction 설정
  - --compact.concurrency=1  # 동시 압축 작업 수
  - --delete-delay=48h  # 블록 삭제 대기 시간
  - --wait  # 지속적으로 압축 작업 수행
```

### Downsampling 설명

| Resolution | 설명 | 보관 기간 | 용도 |
|-----------|------|----------|------|
| **Raw** | 원본 데이터 | 7일 | 최근 데이터 상세 분석 |
| **5m** | 5분 집계 | 30일 | 주간/월간 트렌드 |
| **1h** | 1시간 집계 | 365일 | 연간 트렌드, 용량 통계 |

### 최적화 팁

1. **스토리지 절감**
   ```yaml
   # 짧은 보관 기간 (비용 절감)
   --retention.resolution-raw=3d
   --retention.resolution-5m=14d
   --retention.resolution-1h=90d
   ```

2. **성능**
   ```yaml
   # 높은 compaction 성능
   --compact.concurrency=3

   # 더 많은 메모리 할당
   resources:
     limits:
       memory: 4Gi
   ```

3. **주의사항**
   - Compactor는 단일 인스턴스만 실행 (Singleton)
   - 여러 인스턴스 실행 시 데이터 손상 가능

---

## Thanos Ruler 설정

### 목적
- Alerting Rule 평가
- Recording Rule 평가
- Alert Manager에 알림 전송

### 주요 설정 (`thanos-ruler.yaml`)

```yaml
args:
  - rule
  - --log.level=info

  # 데이터 디렉토리
  - --data-dir=/var/thanos/rule

  # Query 엔드포인트 (rule 평가용 데이터 소스)
  - --query=thanos-query.monitoring.svc.cluster.local:9090

  # S3 업로드 (Recording Rule 결과)
  - --objstore.config-file=/etc/thanos/objstore.yml

  # Alert Manager
  - --alertmanagers.url=http://alertmanager:9093

  # Rule 파일 경로
  - --rule-file=/etc/thanos/rules/*.yaml

  # 외부 라벨
  - --label=ruler_cluster="cluster-01"
  - --label=ruler_replica="$(POD_NAME)"
```

### Rule 파일 예시

```yaml
# /etc/thanos/rules/recording-rules.yaml
groups:
  - name: cluster_metrics
    interval: 30s
    rules:
      # Recording Rule: CPU 사용률 계산
      - record: cluster:cpu_usage:rate5m
        expr: |
          sum(rate(container_cpu_usage_seconds_total[5m])) by (cluster)

      # Recording Rule: 메모리 사용률
      - record: cluster:memory_usage:bytes
        expr: |
          sum(container_memory_usage_bytes) by (cluster)
```

---

## S3 스토리지 설정

### S3 Secret (`thanos-s3-secret.yaml`)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-s3-config
  namespace: monitoring
type: Opaque
stringData:
  objstore.yml: |
    type: S3
    config:
      bucket: ${S3_BUCKET_NAME}          # S3 버킷 이름
      endpoint: ${S3_ENDPOINT}            # MinIO 또는 S3 엔드포인트
      access_key: ${S3_ACCESS_KEY}        # Access Key
      secret_key: ${S3_SECRET_KEY}        # Secret Key
      insecure: false                     # HTTPS 사용
      signature_version2: false           # V4 서명 사용

      # HTTP 설정
      http_config:
        idle_conn_timeout: 90s
        response_header_timeout: 2m
        insecure_skip_verify: false
```

### 버킷 구조

```
s3://thanos-metrics/
├── compact/           # Compactor가 생성한 압축 블록
│   ├── 01H...         # 압축된 블록 ID
│   └── 01H...
├── receive/           # Receiver가 업로드한 원본 블록
│   ├── default/       # Hashring 이름
│   │   └── 01H...
└── debug/             # 디버그 메타데이터 (선택)
```

### 최적화 팁

1. **버킷 정책**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": [
         "s3:ListBucket",
         "s3:GetObject",
         "s3:PutObject",
         "s3:DeleteObject"
       ],
       "Resource": [
         "arn:aws:s3:::thanos-metrics",
         "arn:aws:s3:::thanos-metrics/*"
       ]
     }]
   }
   ```

2. **Lifecycle 정책**
   ```json
   {
     "Rules": [{
       "Id": "DeleteOldBlocks",
       "Status": "Enabled",
       "Expiration": {
         "Days": 395  # Compactor retention보다 길게
       }
     }]
   }
   ```

---

## 운영 가이드

### 배포 순서

1. **S3 Secret 생성**
   ```bash
   kubectl apply -f thanos-s3-secret.yaml
   ```

2. **Thanos Store 배포**
   ```bash
   kubectl apply -f thanos-store.yaml
   ```

3. **Thanos Receiver 배포**
   ```bash
   kubectl apply -f thanos-receiver.yaml
   ```

4. **Thanos Query 배포**
   ```bash
   kubectl apply -f thanos-query.yaml
   ```

5. **Thanos Compactor 배포**
   ```bash
   kubectl apply -f thanos-compactor.yaml
   ```

### 상태 확인

```bash
# 모든 Thanos Pod 확인
kubectl get pods -n monitoring | grep thanos

# Thanos Query Store 연결 확인
kubectl port-forward -n monitoring svc/thanos-query 9090:9090
# http://localhost:9090/stores 접속

# S3 블록 확인
kubectl exec -n monitoring thanos-store-0 -- \
  thanos tools bucket ls \
  --objstore.config-file=/etc/thanos/objstore.yml
```

### 메트릭 확인

```bash
# Thanos Query에서 모든 클러스터 메트릭 확인
curl "http://thanos-query:9090/api/v1/query?query=kube_node_info"

# 특정 클러스터만 필터링
curl "http://thanos-query:9090/api/v1/query?query=kube_node_info{cluster='cluster-02'}"
```

---

## 문제 해결

### 1. Receiver가 메트릭을 받지 못함

**증상**:
```
curl http://thanos-receiver:19291/api/v1/receive
connection refused
```

**해결**:
```bash
# Service 확인
kubectl get svc -n monitoring thanos-receiver

# Pod 로그 확인
kubectl logs -n monitoring thanos-receiver-0 | grep receive

# Ingress 확인
kubectl get ingress -n monitoring thanos-receiver-ingress
```

### 2. Query에서 데이터가 보이지 않음

**증상**: Grafana에서 특정 클러스터 데이터 없음

**해결**:
```bash
# Query Store 연결 확인
kubectl exec -n monitoring thanos-query-xxx -- \
  wget -qO- localhost:10902/api/v1/stores

# Receiver 로그 확인 (데이터 수신 여부)
kubectl logs -n monitoring thanos-receiver-0 | grep "samples ingested"
```

### 3. Compactor가 압축하지 않음

**증상**: S3에 너무 많은 작은 블록

**해결**:
```bash
# Compactor 로그 확인
kubectl logs -n monitoring thanos-compactor-0

# S3 블록 수 확인
kubectl exec -n monitoring thanos-compactor-0 -- \
  thanos tools bucket ls \
  --objstore.config-file=/etc/thanos/objstore.yml | wc -l

# Compaction 강제 실행
kubectl delete pod -n monitoring thanos-compactor-0
```

### 4. 메모리 부족

**증상**: OOMKilled, Pod 재시작

**해결**:
```yaml
# 리소스 증가
resources:
  limits:
    memory: 4Gi  # 2Gi에서 증가
  requests:
    memory: 2Gi
```

### 5. S3 연결 실패

**증상**:
```
failed to upload block: access denied
```

**해결**:
```bash
# Secret 확인
kubectl get secret -n monitoring thanos-s3-config -o yaml

# S3 연결 테스트
kubectl exec -n monitoring thanos-store-0 -- \
  thanos tools bucket inspect \
  --objstore.config-file=/etc/thanos/objstore.yml
```

---

## 모니터링 메트릭

### Thanos 자체 모니터링

```promql
# Receiver 수신률
rate(thanos_receive_write_requests_total[5m])

# Query 요청률
rate(thanos_query_gate_queries_total[5m])

# Store 블록 수
thanos_objstore_bucket_blocks

# Compactor 압축률
rate(thanos_compact_iterations_total[5m])
```

### Alert Rule 예시

```yaml
groups:
  - name: thanos_alerts
    rules:
      - alert: ThanosReceiverDown
        expr: up{job="thanos-receiver"} == 0
        for: 5m
        annotations:
          summary: "Thanos Receiver is down"

      - alert: ThanosQuerySlow
        expr: |
          histogram_quantile(0.99,
            rate(thanos_query_duration_seconds_bucket[5m])
          ) > 30
        for: 10m
        annotations:
          summary: "Thanos Query is slow"
```

---

## 참고 자료

- [Thanos 공식 문서](https://thanos.io/)
- [Thanos GitHub](https://github.com/thanos-io/thanos)
- [Best Practices](https://thanos.io/tip/operating/best-practices.md/)
