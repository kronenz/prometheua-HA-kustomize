# Receiver 관리

## 📋 개요

Thanos Receiver의 일상 운영, Hashring 관리, 스케일링, 문제 해결 방법을 다룹니다.

---

## 🎯 Receiver 운영 목표

- **가용성**: 99.95% Uptime (Replication Factor=3)
- **수신 성공률**: 99.9% 이상
- **TSDB 용량**: 100Gi PVC의 70% 이하 유지
- **메모리 사용량**: 4Gi 미만
- **응답 시간**: Remote Write 처리 < 500ms (p99)

---

## 1️⃣ Receiver 상태 모니터링

### Pod 상태 확인

```bash
# Receiver StatefulSet
kubectl get statefulset -n monitoring thanos-receive

# 출력:
# NAME             READY   AGE
# thanos-receive   3/3     5d

# Pod 목록
kubectl get pods -n monitoring -l app=thanos-receive

# 출력:
# NAME               READY   STATUS    RESTARTS   AGE
# thanos-receive-0   1/1     Running   0          5d
# thanos-receive-1   1/1     Running   0          5d
# thanos-receive-2   1/1     Running   0          5d

# 리소스 사용량
kubectl top pods -n monitoring -l app=thanos-receive

# 출력:
# NAME               CPU(cores)   MEMORY(bytes)
# thanos-receive-0   1200m        2.8Gi
# thanos-receive-1   1100m        2.5Gi
# thanos-receive-2   1150m        2.6Gi
```

### Health Check

```bash
# Receiver HTTP API
kubectl port-forward -n monitoring thanos-receive-0 10902:10902 &

# Healthy Check
curl http://localhost:10902/-/healthy

# 출력:
# Thanos is Healthy.

# Ready Check
curl http://localhost:10902/-/ready

# 출력:
# Thanos is Ready.
```

### PromQL로 Receiver 상태

```promql
# Receiver Up 상태
up{job="thanos-receive", cluster="cluster-01"}

# 출력: 1 (정상)

# Receiver 메모리
container_memory_usage_bytes{pod=~"thanos-receive.*"} / 1024 / 1024 / 1024

# 출력: 2.8 (GiB)

# Receiver CPU
rate(container_cpu_usage_seconds_total{pod=~"thanos-receive.*"}[5m])

# 출력: 1.2 (cores)

# 수신 중인 시계열 수
thanos_receive_head_series{instance=~"thanos-receive.*"}

# 수신 요청 속도
rate(thanos_receive_write_requests_total[5m])

# 수신 샘플 속도
rate(thanos_receive_write_timeseries_total[5m])
```

---

## 2️⃣ Hashring 관리

### Hashring ConfigMap 확인

```bash
# ConfigMap 조회
kubectl get cm -n monitoring thanos-receive-hashring -o yaml

# 출력:
# data:
#   hashrings.json: |
#     [
#       {
#         "hashring": "default",
#         "tenants": [],
#         "endpoints": [
#           "thanos-receive-0.thanos-receive.monitoring.svc.cluster.local:10901",
#           "thanos-receive-1.thanos-receive.monitoring.svc.cluster.local:10901",
#           "thanos-receive-2.thanos-receive.monitoring.svc.cluster.local:10901"
#         ]
#       }
#     ]
```

### Hashring 업데이트

```yaml
# Multi-Tenant Hashring 추가
apiVersion: v1
kind: ConfigMap
metadata:
  name: thanos-receive-hashring
  namespace: monitoring
data:
  hashrings.json: |
    [
      {
        "hashring": "tenant-a",
        "tenants": ["tenant-a"],
        "endpoints": [
          "thanos-receive-0.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-1.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-2.thanos-receive.monitoring.svc.cluster.local:10901"
        ]
      },
      {
        "hashring": "tenant-b",
        "tenants": ["tenant-b"],
        "endpoints": [
          "thanos-receive-0.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-1.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-2.thanos-receive.monitoring.svc.cluster.local:10901"
        ]
      },
      {
        "hashring": "default",
        "tenants": [],
        "endpoints": [
          "thanos-receive-0.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-1.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-2.thanos-receive.monitoring.svc.cluster.local:10901"
        ]
      }
    ]
```

```bash
# ConfigMap 업데이트
kubectl apply -f thanos-receive-hashring.yaml

# Receiver 재시작 (Hot Reload 지원 안 함)
kubectl rollout restart statefulset/thanos-receive -n monitoring

# 재시작 확인
kubectl rollout status statefulset/thanos-receive -n monitoring
```

### Hashring 검증

```bash
# Receiver 로그에서 Hashring 로드 확인
kubectl logs -n monitoring thanos-receive-0 | grep "hashring"

# 로그 예시:
# level=info ts=... msg="loaded hashring configuration" hashrings=3

# Hashring Stats API
curl http://localhost:10902/api/v1/receive/hashrings

# 출력:
# {
#   "status": "success",
#   "data": [
#     {
#       "name": "tenant-a",
#       "tenants": ["tenant-a"],
#       "endpoints": ["receive-0:10901", "receive-1:10901", "receive-2:10901"]
#     }
#   ]
# }
```

---

## 3️⃣ Replication 모니터링

### Replication Factor 확인

```yaml
# Receiver Deployment
args:
  - receive
  - --receive.replication-factor=3  # HA: 3개 복제본
  - --receive.hashrings-file=/etc/thanos/hashrings.json
```

### Replication 메트릭

```promql
# Replication 요청
rate(thanos_receive_replication_requests_total[5m])

# Replication 성공
rate(thanos_receive_replication_requests_total{result="success"}[5m])

# Replication 실패
rate(thanos_receive_replication_requests_total{result="error"}[5m])

# Replication 성공률
rate(thanos_receive_replication_requests_total{result="success"}[5m])
/
rate(thanos_receive_replication_requests_total[5m])

# 목표: > 0.999 (99.9%)
```

### Quorum Write 확인

```bash
# Receiver 로그
kubectl logs -n monitoring thanos-receive-0 | grep "quorum"

# 로그 예시:
# level=info msg="quorum write succeeded" replicas=3 quorum=2

# Quorum 설정 (Replication Factor=3, Quorum=2)
# 3개 중 2개 성공 → Write 성공
```

---

## 4️⃣ TSDB 관리

### TSDB 상태 확인

```bash
# TSDB Stats API
curl http://localhost:10902/api/v1/status/tsdb

# 출력:
# {
#   "status": "success",
#   "data": {
#     "headStats": {
#       "numSeries": 50000,
#       "numSamples": 125000000,
#       "chunkCount": 250000,
#       "minTime": 1729400000000,
#       "maxTime": 1729414800000
#     },
#     "seriesCountByMetricName": [
#       {"name": "up", "value": 200},
#       {"name": "node_cpu_seconds_total", "value": 1600}
#     ]
#   }
# }
```

### TSDB 용량 확인

```bash
# PVC 목록
kubectl get pvc -n monitoring | grep thanos-receive

# 출력:
# data-thanos-receive-0   Bound   100Gi   longhorn
# data-thanos-receive-1   Bound   100Gi   longhorn
# data-thanos-receive-2   Bound   100Gi   longhorn

# TSDB 디스크 사용량
kubectl exec -it -n monitoring thanos-receive-0 -- df -h /data

# 출력:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/longhorn   100G  65G  35G   65%  /data

# TSDB 블록 목록
kubectl exec -it -n monitoring thanos-receive-0 -- ls -lh /data/thanos

# 출력:
# drwxr-xr-x  01HJXXX... (TSDB 블록)
# drwxr-xr-x  01HJYYY...
```

### TSDB Compaction

```promql
# Compaction 진행 중
thanos_compact_group_compactions_total

# Compaction 실패
thanos_compact_group_compactions_failures_total

# Compaction Duration
histogram_quantile(0.99,
  rate(thanos_compact_duration_seconds_bucket[1h])
)
```

---

## 5️⃣ 스케일링

### 수평 확장 (Receiver Replicas 증가)

```yaml
# StatefulSet Replicas 변경
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-receive
spec:
  replicas: 5  # 3 → 5로 증가
```

```bash
# Kubectl로 Scale
kubectl scale statefulset/thanos-receive --replicas=5 -n monitoring

# 새 Pod 확인
kubectl get pods -n monitoring -l app=thanos-receive -w

# 출력:
# thanos-receive-3   0/1   Pending
# thanos-receive-3   1/1   Running
# thanos-receive-4   0/1   Pending
# thanos-receive-4   1/1   Running
```

### Hashring 업데이트 (새 Endpoint 추가)

```yaml
# ConfigMap 업데이트
data:
  hashrings.json: |
    [
      {
        "hashring": "default",
        "endpoints": [
          "thanos-receive-0.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-1.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-2.thanos-receive.monitoring.svc.cluster.local:10901",
          "thanos-receive-3.thanos-receive.monitoring.svc.cluster.local:10901",  # 추가
          "thanos-receive-4.thanos-receive.monitoring.svc.cluster.local:10901"   # 추가
        ]
      }
    ]
```

```bash
# ConfigMap 적용
kubectl apply -f thanos-receive-hashring.yaml

# 모든 Receiver 재시작 (순차적)
kubectl rollout restart statefulset/thanos-receive -n monitoring
```

### 수직 확장 (리소스 증가)

```yaml
# Resources 증가
spec:
  template:
    spec:
      containers:
      - name: thanos-receive
        resources:
          requests:
            cpu: 2000m      # 1000m → 2000m
            memory: 4Gi     # 2Gi → 4Gi
          limits:
            cpu: 4000m
            memory: 8Gi
```

```bash
# 적용 (순차 재시작)
kubectl apply -f thanos-receiver.yaml

# 재시작 확인
kubectl rollout status statefulset/thanos-receive -n monitoring
```

---

## 6️⃣ S3 업로드 관리

### S3 Uploader 상태

```bash
# Receiver 로그에서 S3 업로드 확인
kubectl logs -n monitoring thanos-receive-0 | grep "uploaded"

# 로그 예시:
# level=info ts=... msg="uploaded block to s3"
#   id=01HJXXX... bucket=thanos-cluster-01 duration=8.5s
```

### S3 업로드 메트릭

```promql
# 업로드된 블록 수
thanos_shipper_uploads_total{instance=~"thanos-receive.*"}

# 업로드 실패
thanos_shipper_upload_failures_total{instance=~"thanos-receive.*"}

# 업로드 Duration
histogram_quantile(0.99,
  rate(thanos_shipper_upload_duration_seconds_bucket{instance=~"thanos-receive.*"}[1h])
)
```

### S3 연결 문제 해결

```bash
# objstore.yml Secret 확인
kubectl get secret -n monitoring thanos-objstore-secret -o yaml

# Receiver에서 S3 연결 테스트
kubectl exec -it -n monitoring thanos-receive-0 -- sh

# curl로 MinIO 연결
curl -v http://s3.minio.miribit.lab:9000

# 출력:
# HTTP/1.1 403 Forbidden (인증 필요, 정상)

# mc로 버킷 확인
mc ls minio/thanos-cluster-01/

# 출력:
# [2025-10-20] thanos/01HJXXX.../
```

---

## 7️⃣ 로그 분석

### Receiver 로그 패턴

```bash
# Remote Write 요청
kubectl logs -n monitoring thanos-receive-0 | grep "handling remote write"

# 로그 예시:
# level=info ts=... msg="handling remote write request"
#   tenant=default cluster=cluster-03 samples=1250

# Replication 로그
kubectl logs -n monitoring thanos-receive-0 | grep "replication"

# 로그 예시:
# level=info msg="replication succeeded" replicas=3 quorum=2

# 에러 로그
kubectl logs -n monitoring thanos-receive-0 | grep "level=error"

# S3 업로드 로그
kubectl logs -n monitoring thanos-receive-0 | grep "shipper"
```

### 문제 진단용 로그

```bash
# TSDB Corruption
kubectl logs -n monitoring thanos-receive-0 | grep "corruption"

# Out of Memory
kubectl logs -n monitoring thanos-receive-0 | grep -i "OOM\|memory"

# Network 문제
kubectl logs -n monitoring thanos-receive-0 | grep "connection refused\|timeout"

# Hashring 문제
kubectl logs -n monitoring thanos-receive-0 | grep "hashring.*error"
```

---

## 8️⃣ Alert Rules

### Thanos Receiver Alerts

```yaml
# PrometheusRule CRD
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: thanos-receive-alerts
  namespace: monitoring
spec:
  groups:
  - name: thanos-receive
    interval: 30s
    rules:
    # Receiver Down
    - alert: ThanosReceiverDown
      expr: up{job="thanos-receive"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Thanos Receiver {{ $labels.instance }} is down"
        description: "Receiver has been down for more than 5 minutes"

    # Replication 실패
    - alert: ThanosReceiverReplicationFailing
      expr: |
        rate(thanos_receive_replication_requests_total{result="error"}[5m])
        / rate(thanos_receive_replication_requests_total[5m])
        > 0.05
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Receiver replication failure rate > 5%"

    # TSDB 용량 부족
    - alert: ThanosReceiverDiskSpaceRunningOut
      expr: |
        (1 - (node_filesystem_avail_bytes{mountpoint="/data"}
        / node_filesystem_size_bytes{mountpoint="/data"}))
        > 0.85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Receiver disk space > 85% used"
        description: "Instance {{ $labels.instance }} disk at {{ $value | humanizePercentage }}"

    # 높은 메모리 사용
    - alert: ThanosReceiverHighMemory
      expr: |
        container_memory_usage_bytes{pod=~"thanos-receive.*"}
        / container_spec_memory_limit_bytes{pod=~"thanos-receive.*"}
        > 0.9
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Receiver memory usage > 90%"

    # Hashring 불일치
    - alert: ThanosReceiverHashringInconsistent
      expr: |
        count(thanos_receive_hashring_nodes{state="active"})
        != count(up{job="thanos-receive"} == 1)
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Receiver hashring inconsistent with actual pods"

    # S3 업로드 실패
    - alert: ThanosReceiverS3UploadFailing
      expr: |
        rate(thanos_shipper_upload_failures_total{instance=~"thanos-receive.*"}[10m])
        > 0
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "Receiver S3 upload failing"
```

---

## 9️⃣ 트러블슈팅

### 문제: Remote Write 요청 실패

**증상**:
```bash
kubectl logs -n monitoring thanos-receive-0 | grep "level=error"

# 로그:
# level=error msg="error handling request" err="replica write failed"
```

**원인**:
1. Replication Factor를 만족하지 못함 (2/3 실패)
2. Receiver Pod Down
3. TSDB 디스크 Full

**해결**:
```bash
# 1. Pod 상태 확인
kubectl get pods -n monitoring -l app=thanos-receive

# 2. 디스크 용량 확인
kubectl exec -it -n monitoring thanos-receive-0 -- df -h /data

# 3. Receiver 재시작
kubectl rollout restart statefulset/thanos-receive -n monitoring
```

### 문제: Hashring 불일치

**증상**:
```bash
# Receiver 로그
level=error msg="endpoint not in hashring" endpoint="receive-3:10901"
```

**원인**:
- ConfigMap 업데이트 후 Receiver 재시작 안 됨

**해결**:
```bash
# ConfigMap 확인
kubectl get cm -n monitoring thanos-receive-hashring -o yaml

# Receiver 전체 재시작
kubectl rollout restart statefulset/thanos-receive -n monitoring

# 재시작 확인
kubectl rollout status statefulset/thanos-receive -n monitoring
```

### 문제: S3 업로드 실패

**증상**:
```promql
rate(thanos_shipper_upload_failures_total[5m]) > 0
```

**원인**:
1. objstore.yml Secret 오류
2. S3 연결 실패
3. 권한 부족

**해결**:
```bash
# 1. Secret 확인
kubectl get secret -n monitoring thanos-objstore-secret -o jsonpath='{.data.objstore\.yml}' | base64 -d

# 2. MinIO 연결 테스트
mc ls minio/thanos-cluster-01/

# 3. Secret 재생성
kubectl delete secret -n monitoring thanos-objstore-secret
kubectl apply -f thanos-objstore-secret.yaml

# 4. Receiver 재시작
kubectl rollout restart statefulset/thanos-receive -n monitoring
```

---

## 🎯 Receiver 운영 체크리스트

### 일일 점검
- [x] Receiver Pod Running (3/3)
- [x] Replication 성공률 > 99.9%
- [x] TSDB 용량 < 70%
- [x] 메모리 사용량 < 3.5Gi
- [x] S3 업로드 정상

### 주간 점검
- [x] PVC 용량 확인 (85% 미만)
- [x] Hashring 설정 검증
- [x] Receiver 로그 에러 검토
- [x] S3 버킷 블록 수 확인

### 월간 점검
- [x] Thanos 버전 업데이트 확인
- [x] 리소스 Right-Sizing
- [x] Hashring Rebalancing 검토
- [x] 백업 테스트

---

## 🔗 관련 문서

- **Agent 관리** → [Agent-관리.md](./Agent-관리.md)
- **스케일링** → [스케일링.md](./스케일링.md)
- **백업 및 복구** → [백업-및-복구.md](./백업-및-복구.md)
- **트러블슈팅** → [일반-트러블슈팅.md](./일반-트러블슈팅.md)

---

**최종 업데이트**: 2025-10-20
