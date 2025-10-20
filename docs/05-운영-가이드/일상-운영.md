# Thanos 멀티클러스터 모니터링 운영 매뉴얼

## 목차

1. [일상 운영 작업](#일상-운영-작업)
2. [모니터링 체크리스트](#모니터링-체크리스트)
3. [정기 유지보수](#정기-유지보수)
4. [스케일링](#스케일링)
5. [업그레이드 절차](#업그레이드-절차)
6. [백업 및 복구](#백업-및-복구)
7. [보안 관리](#보안-관리)
8. [용량 관리](#용량-관리)

---

## 일상 운영 작업

### 매일 수행 작업

#### 1. 시스템 상태 확인 (5분)

```bash
#!/bin/bash
# daily-check.sh

echo "=== Daily Thanos Health Check ==="
echo "Date: $(date)"
echo

# 모든 클러스터의 Pod 상태
for config in cluster-01 cluster-02 cluster-03 cluster-04; do
  echo "--- $config ---"
  export KUBECONFIG=~/.kube/configs/$config.conf
  kubectl get pods -n monitoring | grep -v "Running\|Completed" || echo "All pods running"
  echo
done

# S3 업로드 상태 (cluster-01)
export KUBECONFIG=~/.kube/configs/cluster-01.conf
echo "--- S3 Upload Status ---"
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 thanos-sidecar --tail=5 | \
  grep -E "uploaded|error"

# Thanos Query 연결 상태
echo "--- Thanos Query Store Connections ---"
kubectl exec -n monitoring deployment/thanos-query -- \
  wget -qO- http://localhost:10902/api/v1/stores | \
  jq '.data[] | {name: .name, lastCheck: .lastCheck}'
```

#### 2. 알럿 확인

```bash
# Grafana에서 확인
# http://grafana.k8s-cluster-01.miribit.lab/alerting/list

# 또는 Prometheus API 사용
export KUBECONFIG=~/.kube/configs/cluster-01.conf
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.state=="firing")'
```

#### 3. 디스크 사용량 확인

```bash
# 각 노드의 디스크 사용률
for node in 192.168.101.194 192.168.101.196 192.168.101.197 192.168.101.198; do
  echo "=== Node $node ==="
  ssh bsh@$node "df -h | grep -E 'Filesystem|/$|longhorn'"
done

# S3 버킷 사용량
# MinIO Console에서 확인: console.minio.miribit.lab
```

---

## 모니터링 체크리스트

### 주요 메트릭 모니터링

#### Prometheus 헬스 메트릭

| 메트릭 | 정상 범위 | 알럿 임계값 | 조치 |
|--------|----------|------------|------|
| `up{job="prometheus"}` | 1 | 0 | Prometheus 재시작 |
| `prometheus_tsdb_storage_blocks_bytes` | - | > 90% | 데이터 정리 또는 retention 조정 |
| `prometheus_target_scrapes_exceeded_sample_limit_total` | 0 | > 0 | 샘플 limit 증가 |
| `prometheus_rule_evaluation_failures_total` | 0 | > 10 | Rule 확인 |

#### Thanos Sidecar 메트릭

| 메트릭 | 정상 범위 | 알럿 임계값 | 조치 |
|--------|----------|------------|------|
| `thanos_sidecar_prometheus_up` | 1 | 0 | Prometheus 연결 확인 |
| `thanos_objstore_bucket_operations_total{operation="upload"}` | 증가 | 2시간 동안 0 | S3 연결 확인 |
| `thanos_objstore_bucket_operation_failures_total` | 0 | > 10 | S3 인증 또는 네트워크 확인 |

#### Thanos Query 메트릭

| 메트릭 | 정상 범위 | 알럿 임계값 | 조치 |
|--------|----------|------------|------|
| `thanos_store_nodes_grpc_connections` | 7 (2 중앙 + 3 edge + 1 store + 1 ruler) | < 5 | Store 연결 확인 |
| `thanos_query_concurrent_selects` | - | > 100 | 리소스 증가 또는 쿼리 최적화 |
| `thanos_query_duration_seconds{quantile="0.99"}` | < 5s | > 30s | 성능 튜닝 필요 |

#### Thanos Store 메트릭

| 메트릭 | 정상 범위 | 알럿 임계값 | 조치 |
|--------|----------|------------|------|
| `thanos_objstore_bucket_operations_total{operation="get"}` | 증가 | 1시간 동안 0 | S3 연결 확인 |
| `thanos_bucket_store_series_data_touched` | - | > 10M | 쿼리 최적화 필요 |
| `thanos_bucket_store_cached_postings_hits_total` | 높음 | 낮음 | 캐시 크기 증가 |

#### Thanos Compactor 메트릭

| 메트릭 | 정상 범위 | 알럿 임계값 | 조치 |
|--------|----------|------------|------|
| `thanos_compact_group_compactions_total` | 증가 | 24시간 동안 0 | Compactor 확인 |
| `thanos_compact_iterations_total{result="error"}` | 0 | > 0 | 로그 확인 |
| `thanos_compact_downsample_total` | 증가 | 24시간 동안 0 | Downsampling 설정 확인 |

### Grafana 대시보드

다음 대시보드를 생성하여 모니터링합니다:

1. **Thanos Overview Dashboard**
   - Store 연결 상태
   - 쿼리 응답 시간
   - S3 업로드 상태
   - 데이터 보존 현황

2. **Multi-Cluster Resource Dashboard**
   - 클러스터별 CPU/Memory 사용률
   - 클러스터별 Pod 수
   - 클러스터별 노드 상태

3. **Storage Dashboard**
   - Longhorn 볼륨 사용량
   - S3 버킷 사용량
   - 디스크 I/O

---

## 정기 유지보수

### 주간 작업 (30분)

#### 1. 로그 리뷰

```bash
# 지난 주 에러 로그 확인
export KUBECONFIG=~/.kube/configs/cluster-01.conf

kubectl logs -n monitoring deployment/thanos-query --since=168h | \
  grep -i error > query-errors-weekly.log

kubectl logs -n monitoring statefulset/thanos-compactor --since=168h | \
  grep -i error > compactor-errors-weekly.log
```

#### 2. 메트릭 보존 확인

```bash
# S3 버킷 블록 구조 확인
# MinIO Console에서 thanos-bucket 확인

# 각 resolution별 데이터 존재 여부
# - Raw (7일)
# - 5m (30일)
# - 1h (90일)
```

#### 3. 리소스 사용량 트렌드 분석

```bash
# Grafana에서 확인
# - CPU 사용률 트렌드
# - Memory 사용률 트렌드
# - 디스크 사용률 트렌드
# - 네트워크 사용률 트렌드
```

### 월간 작업 (2시간)

#### 1. 전체 시스템 백업

```bash
#!/bin/bash
# monthly-backup.sh

BACKUP_DATE=$(date +%Y%m)
BACKUP_DIR="/backup/thanos-$BACKUP_DATE"
mkdir -p $BACKUP_DIR

# 1. Kubernetes 리소스 백업
for config in cluster-01 cluster-02 cluster-03 cluster-04; do
  export KUBECONFIG=~/.kube/configs/$config.conf
  kubectl get all,pvc,secret,configmap -n monitoring -o yaml > \
    $BACKUP_DIR/$config-resources.yaml
done

# 2. S3 데이터 백업 (선택사항 - 스냅샷 또는 복제)
# mc alias set myminio http://s3.minio.miribit.lab:80 $ACCESS_KEY $SECRET_KEY
# mc mirror myminio/thanos-bucket $BACKUP_DIR/s3-backup/

# 3. Grafana 대시보드 백업
export KUBECONFIG=~/.kube/configs/cluster-01.conf
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- \
  tar czf /tmp/grafana-backup.tar.gz /var/lib/grafana
kubectl cp monitoring/$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o name | head -1 | cut -d/ -f2):/tmp/grafana-backup.tar.gz \
  $BACKUP_DIR/grafana-backup.tar.gz

echo "Backup completed: $BACKUP_DIR"
```

#### 2. 보안 업데이트 확인

```bash
# 각 노드에서 보안 업데이트 확인
for node in 192.168.101.194 192.168.101.196 192.168.101.197 192.168.101.198; do
  echo "=== $node ==="
  ssh bsh@$node "sudo apt update && sudo apt list --upgradable | grep -i security"
done
```

#### 3. 용량 계획 리뷰

- S3 스토리지 증가율 분석
- Prometheus PVC 사용률 확인
- 향후 3개월 용량 예측

### 분기별 작업 (4시간)

#### 1. 재해 복구 테스트

```bash
# 시나리오 1: Prometheus 장애
# 1. Prometheus Pod 강제 삭제
# 2. 자동 복구 확인
# 3. 데이터 손실 여부 확인

# 시나리오 2: S3 연결 장애
# 1. S3 endpoint 임시 변경 (장애 시뮬레이션)
# 2. Thanos Sidecar 동작 확인
# 3. 복구 후 데이터 업로드 확인
```

#### 2. 성능 벤치마크

```bash
# Grafana에서 대규모 쿼리 실행
# - 90일 데이터 조회
# - 모든 클러스터 aggregate 쿼리
# - 응답 시간 기록 및 이전 분기와 비교
```

#### 3. 문서 업데이트

- 아키텍처 변경사항 반영
- 트러블슈팅 사례 추가
- 운영 절차 개선사항 반영

---

## 스케일링

### Prometheus 스케일 업

#### 수평 스케일링 (Replica 증가)

```yaml
# deploy/overlays/cluster-01-central/kube-prometheus-stack/kustomization.yaml
prometheus:
  prometheusSpec:
    replicas: 3  # 2에서 3으로 증가
```

재배포:
```bash
export KUBECONFIG=~/.kube/configs/cluster-01.conf
cd /root/develop/thanos/deploy/overlays/cluster-01-central/kube-prometheus-stack
kustomize build . --enable-helm | kubectl apply -f -
```

#### 수직 스케일링 (리소스 증가)

```yaml
prometheus:
  prometheusSpec:
    resources:
      limits:
        cpu: 2000m     # 1000m에서 증가
        memory: 4Gi    # 2Gi에서 증가
      requests:
        cpu: 1000m     # 500m에서 증가
        memory: 2Gi    # 1Gi에서 증가
```

### Thanos Query 스케일 아웃

```yaml
# deploy/overlays/cluster-01-central/kube-prometheus-stack/thanos-query.yaml
spec:
  replicas: 2  # 1에서 2로 증가
```

Query Frontend 추가 (선택사항):
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-query-frontend
  namespace: monitoring
spec:
  type: ClusterIP
  ports:
    - port: 9090
      targetPort: 9090
  selector:
    app: thanos-query-frontend

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query-frontend
  namespace: monitoring
spec:
  replicas: 2
  selector:
    matchLabels:
      app: thanos-query-frontend
  template:
    metadata:
      labels:
        app: thanos-query-frontend
    spec:
      containers:
        - name: query-frontend
          image: quay.io/thanos/thanos:v0.37.2
          args:
            - query-frontend
            - --http-address=0.0.0.0:9090
            - --query-frontend.downstream-url=http://thanos-query:9090
            - --query-range.split-interval=24h
            - --query-range.max-retries-per-request=5
            - --query-frontend.log-queries-longer-than=10s
          ports:
            - containerPort: 9090
          resources:
            limits:
              cpu: 500m
              memory: 512Mi
            requests:
              cpu: 250m
              memory: 256Mi
```

### 새 클러스터 추가

#### cluster-05 추가 예제

1. **Kubernetes 클러스터 준비** (192.168.101.199)

2. **Longhorn 설치**

3. **Prometheus Stack 배포**:
```bash
# 새 overlay 생성
cp -r deploy/overlays/cluster-04-edge deploy/overlays/cluster-05-edge

# 설정 수정
# - IP: 192.168.101.199
# - cluster label: cluster-05
# - LoadBalancer IP: 192.168.101.214
```

4. **Thanos Query 업데이트**:
```yaml
# thanos-query.yaml에 추가
- --store=192.168.101.214:10901  # cluster-05
```

---

## 업그레이드 절차

### Thanos 버전 업그레이드

현재 버전: v0.37.2 → 신규 버전: v0.38.0 (예제)

#### 업그레이드 전 체크리스트

- [ ] 릴리스 노트 확인
- [ ] Breaking changes 확인
- [ ] 백업 수행
- [ ] 테스트 환경에서 검증

#### 업그레이드 순서

1. **Thanos Store 업그레이드** (Historical 데이터만 영향)
```yaml
# thanos-store.yaml
image: quay.io/thanos/thanos:v0.38.0
```

2. **Thanos Compactor 업그레이드**
```yaml
# thanos-compactor.yaml
image: quay.io/thanos/thanos:v0.38.0
```

3. **Thanos Ruler 업그레이드**
```yaml
# thanos-ruler.yaml
image: quay.io/thanos/thanos:v0.38.0
```

4. **Thanos Query 업그레이드**
```yaml
# thanos-query.yaml
image: quay.io/thanos/thanos:v0.38.0
```

5. **Thanos Sidecar 업그레이드** (모든 클러스터)
```yaml
# kustomization.yaml
prometheus:
  prometheusSpec:
    thanos:
      image: quay.io/thanos/thanos:v0.38.0
      version: v0.38.0
```

#### 롤백 절차

```bash
# 문제 발생 시 이전 버전으로 롤백
kubectl rollout undo deployment/thanos-query -n monitoring
kubectl rollout undo statefulset/thanos-store -n monitoring
kubectl rollout undo statefulset/thanos-compactor -n monitoring
```

### kube-prometheus-stack 업그레이드

현재: v78.2.1 → 신규: v79.0.0 (예제)

```yaml
# kustomization.yaml
helmCharts:
  - name: kube-prometheus-stack
    version: 79.0.0  # 버전 변경
```

주의사항:
- CRD 업데이트 필요 여부 확인
- Grafana 대시보드 호환성 확인
- AlertManager 설정 migration 확인

---

## 백업 및 복구

### 백업 전략

| 대상 | 백업 주기 | 보존 기간 | 우선순위 |
|------|----------|----------|---------|
| Kubernetes 리소스 | 매일 | 30일 | 높음 |
| Grafana 대시보드/설정 | 매일 | 90일 | 높음 |
| Prometheus 로컬 데이터 | 불필요 | - | 낮음 (S3에 백업됨) |
| S3 버킷 (Thanos) | 매주 (스냅샷) | 90일 | 중간 |
| AlertManager 설정 | 매주 | 90일 | 중간 |

### 자동 백업 스크립트

```bash
#!/bin/bash
# /opt/thanos/scripts/auto-backup.sh

BACKUP_ROOT="/backup/thanos"
DATE=$(date +%Y%m%d)
BACKUP_DIR="$BACKUP_ROOT/$DATE"

mkdir -p $BACKUP_DIR

# Kubernetes 리소스 백업
for config in cluster-01 cluster-02 cluster-03 cluster-04; do
  export KUBECONFIG=~/.kube/configs/$config.conf
  kubectl get all,pvc,secret,configmap,prometheusrule -n monitoring -o yaml | \
    gzip > $BACKUP_DIR/$config-resources.yaml.gz
done

# 30일 이상 된 백업 삭제
find $BACKUP_ROOT -type d -mtime +30 -exec rm -rf {} \;

# 백업 성공 알림
echo "Backup completed: $BACKUP_DIR" | mail -s "Thanos Backup Success" admin@example.com
```

Crontab 설정:
```bash
# 매일 03:00 AM 실행
0 3 * * * /opt/thanos/scripts/auto-backup.sh >> /var/log/thanos-backup.log 2>&1
```

### 복구 시나리오

#### 시나리오 1: Prometheus 데이터 손실

**상황**: Prometheus Pod 장애로 로컬 TSDB 손실

**복구**:
1. S3에 데이터가 있으므로 복구 불필요
2. Prometheus Pod 재시작하면 새로운 메트릭 수집 시작
3. Historical 데이터는 Thanos Store에서 조회 가능

#### 시나리오 2: Grafana 대시보드 손실

**복구**:
```bash
# 백업에서 복구
cd /backup/thanos/20250115
export KUBECONFIG=~/.kube/configs/cluster-01.conf

# Grafana PVC 마운트하여 데이터 복원
kubectl cp ./grafana-backup.tar.gz monitoring/<grafana-pod>:/tmp/
kubectl exec -n monitoring <grafana-pod> -- \
  tar xzf /tmp/grafana-backup.tar.gz -C /var/lib/grafana

# Grafana 재시작
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

#### 시나리오 3: S3 버킷 손상

**복구**:
```bash
# S3 스냅샷에서 복구
mc alias set myminio http://s3.minio.miribit.lab:80 $ACCESS_KEY $SECRET_KEY
mc mirror /backup/thanos/s3-snapshot/ myminio/thanos-bucket/

# Thanos Store 캐시 초기화
kubectl delete pod -n monitoring -l app=thanos-store
```

---

## 보안 관리

### 접근 제어

#### Grafana 사용자 관리

```bash
# Admin 비밀번호 변경
export KUBECONFIG=~/.kube/configs/cluster-01.conf
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- \
  grafana-cli admin reset-admin-password <new-password>

# 새 사용자 추가 (Grafana UI에서)
# Settings → Users → Invite
```

#### Kubernetes RBAC

```yaml
# monitoring-viewer-role.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: monitoring-viewer
  namespace: monitoring
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: monitoring-viewer-binding
  namespace: monitoring
subjects:
  - kind: User
    name: viewer@example.com
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: monitoring-viewer
  apiGroup: rbac.authorization.k8s.io
```

### 보안 감사

#### 월간 보안 체크리스트

- [ ] Grafana 사용자 및 권한 리뷰
- [ ] S3 액세스 키 로테이션 검토
- [ ] 미사용 ServiceAccount 확인
- [ ] Pod Security Policy 준수 확인
- [ ] 네트워크 정책 리뷰
- [ ] 취약점 스캔 수행

```bash
# Trivy로 이미지 스캔
trivy image quay.io/thanos/thanos:v0.37.2
trivy image quay.io/prometheus-operator/prometheus-operator:v0.78.2
```

---

## 용량 관리

### 용량 모니터링

#### S3 스토리지 사용량

```bash
# mc CLI로 확인
mc alias set myminio http://s3.minio.miribit.lab:80 $ACCESS_KEY $SECRET_KEY
mc du myminio/thanos-bucket
```

#### Prometheus PVC 사용량

```bash
for config in cluster-01 cluster-02 cluster-03 cluster-04; do
  echo "=== $config ==="
  export KUBECONFIG=~/.kube/configs/$config.conf
  kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
    df -h /prometheus
done
```

### 용량 최적화

#### 1. Scrape Interval 조정

```yaml
# 메트릭 수집 빈도 감소
scrapeInterval: 60s  # 30s에서 증가
```

#### 2. Metric Relabeling

불필요한 메트릭 필터링:
```yaml
# kustomization.yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'kubernetes-pods'
        metric_relabel_configs:
          # 높은 cardinality 메트릭 제거
          - source_labels: [__name__]
            regex: 'container_memory_failures_total'
            action: drop
```

#### 3. Retention 정책 조정

```yaml
# Prometheus 로컬 retention 단축
retention: 1h  # 2h에서 단축 (S3에 더 빨리 업로드)

# Thanos Compactor retention 조정
--retention.resolution-raw=5d  # 7d에서 단축
```

### 용량 예측

월간 데이터 증가량을 기반으로 예측:

```
현재 S3 사용량: 140GB
월간 증가율: 20GB/월
향후 6개월 예상 사용량: 140GB + (20GB × 6) = 260GB
```

용량 알럿 설정:
- 80% 도달 시 경고
- 90% 도달 시 긴급 조치 필요

---

## 알럿 정책

### 주요 알럿 룰

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: thanos-monitoring-rules
  namespace: monitoring
spec:
  groups:
    - name: thanos.rules
      interval: 30s
      rules:
        # Thanos Sidecar 업로드 실패
        - alert: ThanosSidecarNoUpload
          expr: |
            (time() - thanos_shipper_last_successful_upload_time) > 7200
          for: 30m
          labels:
            severity: warning
          annotations:
            summary: "Thanos Sidecar {{ $labels.instance }} hasn't uploaded blocks for 2 hours"

        # Thanos Query Store 연결 부족
        - alert: ThanosQueryStoreUnhealthy
          expr: |
            thanos_store_nodes_grpc_connections < 5
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Thanos Query has only {{ $value }} store connections (expected >= 5)"

        # Prometheus 타겟 Down
        - alert: PrometheusTargetDown
          expr: up{job=~"prometheus|node-exporter|kube-state-metrics"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Target {{ $labels.job }} on {{ $labels.instance }} is down"

        # S3 스토리지 사용량
        - alert: S3StorageNearFull
          expr: |
            (s3_bucket_size_bytes / s3_bucket_quota_bytes) > 0.8
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "S3 bucket usage is above 80%"

        # PVC 사용량
        - alert: PVCNearFull
          expr: |
            (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.85
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "PVC {{ $labels.persistentvolumeclaim }} in {{ $labels.namespace }} is {{ $value | humanizePercentage }} full"
```

---

## 연락처 및 에스컬레이션

### 운영 팀

| 역할 | 담당자 | 연락처 | 대응 시간 |
|------|--------|--------|----------|
| Primary On-call | - | - | 24/7 |
| Secondary On-call | - | - | 24/7 |
| Team Lead | - | - | 업무 시간 |
| Kubernetes Admin | - | - | 업무 시간 |

### 에스컬레이션 절차

1. **Level 1** (5분 내): Primary On-call
   - Pod CrashLoop
   - 메트릭 수집 중단

2. **Level 2** (15분 내): Secondary On-call + Team Lead
   - 전체 클러스터 장애
   - S3 연결 장애

3. **Level 3** (30분 내): 전체 팀 + 외부 지원
   - 데이터 손실
   - 보안 침해

---

## 문서 개정 이력

| 버전 | 날짜 | 변경 내용 | 작성자 |
|------|------|----------|--------|
| 1.0 | 2025-01-15 | 초안 작성 | - |

---

## 참고 자료

- [Thanos 운영 가이드](https://thanos.io/tip/thanos/operating/)
- [Prometheus 베스트 프랙티스](https://prometheus.io/docs/practices/)
- [Kubernetes 모니터링 가이드](https://kubernetes.io/docs/tasks/debug-application-cluster/)
