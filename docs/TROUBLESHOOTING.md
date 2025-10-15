# Thanos 멀티클러스터 모니터링 트러블슈팅 가이드

## 목차

1. [일반적인 문제](#일반적인-문제)
2. [Prometheus 관련 문제](#prometheus-관련-문제)
3. [Thanos 컴포넌트 문제](#thanos-컴포넌트-문제)
4. [네트워크 및 연결 문제](#네트워크-및-연결-문제)
5. [스토리지 문제](#스토리지-문제)
6. [성능 문제](#성능-문제)
7. [로그 분석 방법](#로그-분석-방법)

---

## 일반적인 문제

### Pod가 Pending 상태

**증상**:
```bash
kubectl get pods -n monitoring
NAME                        READY   STATUS    RESTARTS   AGE
prometheus-xxx-0            0/3     Pending   0          5m
```

**원인**:
- PVC가 Bound 되지 않음
- 노드에 충분한 리소스 부족
- PodDisruptionBudget에 의한 제약

**해결 방법**:

1. PVC 상태 확인:
```bash
kubectl get pvc -n monitoring
```

PVC가 `Pending` 상태인 경우:
```bash
# Longhorn 상태 확인
kubectl get pods -n longhorn-system
kubectl get storageclass longhorn
```

2. 노드 리소스 확인:
```bash
kubectl describe node | grep -A 5 "Allocated resources"
```

3. Pod 상세 정보 확인:
```bash
kubectl describe pod -n monitoring <pod-name>
```

### Pod가 CrashLoopBackOff 상태

**증상**:
```bash
NAME                        READY   STATUS             RESTARTS   AGE
thanos-query-xxx            0/1     CrashLoopBackOff   5          10m
```

**해결 방법**:

1. 로그 확인:
```bash
kubectl logs -n monitoring <pod-name> --previous
```

2. 일반적인 원인별 해결:
   - **설정 오류**: ConfigMap/Secret 확인
   - **리소스 부족**: 메모리/CPU limits 조정
   - **의존성 문제**: 필요한 서비스가 실행 중인지 확인

---

## Prometheus 관련 문제

### Prometheus가 메트릭을 수집하지 않음

**증상**:
- Grafana에서 "No data" 표시
- Prometheus UI에서 타겟이 Down 상태

**해결 방법**:

1. Prometheus 타겟 상태 확인:
```bash
# Prometheus UI 접속
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# 브라우저에서 http://localhost:9090/targets 접속
```

2. ServiceMonitor 확인:
```bash
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor -n monitoring <servicemonitor-name>
```

3. 네트워크 정책 확인:
```bash
kubectl get networkpolicy -n monitoring
```

### Prometheus TSDB 손상

**증상**:
```
level=error msg="opening storage failed" err="open DB: bad block"
```

**해결 방법**:

1. 문제가 있는 Prometheus Pod 삭제:
```bash
kubectl delete pod -n monitoring prometheus-kube-prometheus-stack-prometheus-0
```

2. PVC 데이터 백업 (선택사항):
```bash
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  tar czf /tmp/tsdb-backup.tar.gz /prometheus
kubectl cp monitoring/prometheus-kube-prometheus-stack-prometheus-0:/tmp/tsdb-backup.tar.gz ./tsdb-backup.tar.gz
```

3. 심각한 경우 PVC 재생성:
```bash
# ⚠️ 주의: 로컬 데이터 손실
kubectl delete pvc -n monitoring prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
# StatefulSet이 자동으로 새 PVC 생성
```

### Prometheus OOMKilled

**증상**:
```bash
kubectl get pods -n monitoring
NAME                        READY   STATUS      RESTARTS   AGE
prometheus-xxx-0            2/3     OOMKilled   5          10m
```

**해결 방법**:

1. 현재 메모리 사용량 확인:
```bash
kubectl top pod -n monitoring prometheus-kube-prometheus-stack-prometheus-0
```

2. 메모리 limits 증가:
```yaml
# deploy/overlays/cluster-01-central/kube-prometheus-stack/kustomization.yaml
prometheus:
  prometheusSpec:
    resources:
      limits:
        memory: 4Gi  # 2Gi에서 증가
      requests:
        memory: 2Gi  # 1Gi에서 증가
```

3. 재배포:
```bash
kustomize build . --enable-helm | kubectl apply -f -
```

---

## Thanos 컴포넌트 문제

### Thanos Query가 Sidecar에 연결되지 않음

**증상**:
```bash
kubectl logs -n monitoring deployment/thanos-query | grep "no store"
```

**해결 방법**:

1. Thanos Query 설정 확인:
```bash
kubectl get deployment -n monitoring thanos-query -o yaml | grep -A 20 "args:"
```

2. Sidecar 엔드포인트 연결 테스트:
```bash
# 중앙 클러스터 내부
kubectl exec -n monitoring deployment/thanos-query -- \
  wget -qO- http://prometheus-operated.monitoring.svc.cluster.local:10901/metrics

# Edge 클러스터 외부
kubectl exec -n monitoring deployment/thanos-query -- \
  wget -qO- http://192.168.101.211:10901/metrics
```

3. DNS 해결 확인 (SRV 레코드):
```bash
kubectl exec -n monitoring deployment/thanos-query -- \
  nslookup _grpc._tcp.prometheus-operated.monitoring.svc.cluster.local
```

### Thanos Sidecar가 S3에 업로드하지 않음

**증상**:
```bash
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 thanos-sidecar | \
  grep -i "upload"
# 출력 없음 또는 에러 메시지
```

**일반적인 원인과 해결**:

#### 1. S3 접근 오류

**에러 메시지**:
```
err="dial tcp 172.16.203.1:443: connect: connection refused"
```

**원인**: HTTPS로 연결 시도하지만 MinIO가 HTTP만 지원

**해결**:
```yaml
# thanos-s3-secret.yaml
config:
  endpoint: s3.minio.miribit.lab:80  # 포트 명시
  insecure: true
  http_config:
    insecure_skip_verify: true
```

#### 2. S3 인증 오류

**에러 메시지**:
```
The Access Key Id you provided does not exist in our records
```

**해결**:
```bash
# MinIO Console에서 액세스 키 확인
# console.minio.miribit.lab

# Secret 업데이트
kubectl delete secret -n monitoring thanos-s3-config
kubectl create secret generic thanos-s3-config -n monitoring \
  --from-file=objstore.yml=thanos-s3-secret.yaml
```

#### 3. 버킷이 존재하지 않음

**에러 메시지**:
```
NoSuchBucket: The specified bucket does not exist
```

**해결**:
```bash
# MinIO Console에서 버킷 생성
# 또는 mc CLI 사용
mc alias set myminio http://s3.minio.miribit.lab:80 $ACCESS_KEY $SECRET_KEY
mc mb myminio/thanos-bucket
```

### Thanos Compactor가 동작하지 않음

**증상**:
```bash
kubectl logs -n monitoring statefulset/thanos-compactor
# 로그에 compaction 활동 없음
```

**해결 방법**:

1. Compactor 상태 확인:
```bash
kubectl exec -n monitoring thanos-compactor-0 -- \
  wget -qO- http://localhost:10902/-/healthy
```

2. S3 버킷 읽기 권한 확인:
```bash
kubectl logs -n monitoring thanos-compactor-0 | grep -i "bucket"
```

3. Compactor 재시작:
```bash
kubectl delete pod -n monitoring thanos-compactor-0
```

### Thanos Store가 S3 데이터를 조회하지 못함

**증상**:
- Grafana에서 Historical 데이터 조회 안됨
- 최근 2시간 데이터만 표시

**해결 방법**:

1. Store 로그 확인:
```bash
kubectl logs -n monitoring statefulset/thanos-store --tail=100
```

2. S3 버킷 내용 확인:
```bash
# MinIO Console에서 thanos-bucket 확인
# 블록 디렉토리가 존재하는지 확인
```

3. Store 캐시 디렉토리 확인:
```bash
kubectl exec -n monitoring thanos-store-0 -- ls -la /var/thanos/store
```

---

## 네트워크 및 연결 문제

### LoadBalancer가 External-IP를 할당받지 못함

**증상**:
```bash
kubectl get svc -n monitoring thanos-sidecar-external
NAME                      TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
thanos-sidecar-external   LoadBalancer   10.96.10.20    <pending>     10901/TCP
```

**해결 방법**:

1. Cilium LoadBalancer IP Pool 확인:
```bash
kubectl get ciliumloadbalancerippool
kubectl describe ciliumloadbalancerippool cluster-02-pool
```

2. IP Pool에 사용 가능한 IP 확인:
```yaml
# pool이 비어있는 경우
status:
  conditions:
  - message: "IPS AVAILABLE: 0"
```

해결:
```bash
# 다른 LoadBalancer 서비스 제거 또는
# IP Pool 범위 확장
kubectl edit ciliumloadbalancerippool cluster-02-pool
```

3. Cilium 컴포넌트 재시작:
```bash
kubectl rollout restart deployment/cilium-operator -n kube-system
kubectl rollout restart daemonset/cilium -n kube-system
```

### Cilium Ingress 외부 접속 불가

**증상**:
- nslookup으로 IP 확인은 되지만 HTTP 접속 불가
- `curl http://grafana.k8s-cluster-01.miribit.lab` 타임아웃

**해결 방법**:

1. LoadBalancer 서비스 상태 확인:
```bash
kubectl get svc -n kube-system cilium-ingress
```

2. 엔드포인트 확인:
```bash
kubectl get endpoints -n kube-system cilium-ingress
```

엔드포인트가 없는 경우 (`<none>`):
```bash
# Cilium Ingress Controller가 초기화되지 않음
# Cilium 재시작
kubectl rollout restart daemonset/cilium-envoy -n kube-system
kubectl rollout restart daemonset/cilium -n kube-system
```

3. ARP 테이블 확인:
```bash
ip neigh show | grep <EXTERNAL-IP>
```

### 멀티클러스터 통신 실패

**증상**:
- Thanos Query가 Edge 클러스터 Sidecar에 연결 불가
- 에러: `dial tcp 192.168.101.211:10901: i/o timeout`

**해결 방법**:

1. 방화벽 확인:
```bash
# Edge 노드에서
sudo iptables -L -n | grep 10901
```

2. 네트워크 연결 테스트:
```bash
# 중앙 클러스터 노드에서
telnet 192.168.101.211 10901
# 또는
nc -zv 192.168.101.211 10901
```

3. Thanos Sidecar LoadBalancer 포트 확인:
```bash
kubectl get svc -n monitoring thanos-sidecar-external -o yaml
```

---

## 스토리지 문제

### Longhorn Volume Attach 실패

**증상**:
```
Warning  FailedAttachVolume  pod/prometheus-xxx-0  AttachVolume.Attach failed
```

**해결 방법**:

1. Longhorn Manager 로그 확인:
```bash
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100
```

2. Volume 상태 확인:
```bash
kubectl get volumes -n longhorn-system
```

3. iSCSI 서비스 확인 (노드에서):
```bash
sudo systemctl status iscsid
sudo systemctl restart iscsid
```

### PVC가 Bound 되지 않음

**증상**:
```bash
kubectl get pvc -n monitoring
NAME                  STATUS    VOLUME   CAPACITY
prometheus-data-0     Pending
```

**해결 방법**:

1. PVC 상세 정보 확인:
```bash
kubectl describe pvc -n monitoring prometheus-data-0
```

2. StorageClass 확인:
```bash
kubectl get storageclass
kubectl describe storageclass longhorn
```

3. Longhorn Provisioner 로그:
```bash
kubectl logs -n longhorn-system -l app=longhorn-manager | grep -i provision
```

### 디스크 공간 부족

**증상**:
```
Warning  EvictionThresholdMet  node  ephemeral-storage usage (95%) exceeds threshold (85%)
```

**해결 방법**:

1. 노드 디스크 사용량 확인:
```bash
df -h
```

2. Prometheus 데이터 정리:
```bash
# Prometheus retention 줄이기
kubectl edit prometheus -n monitoring kube-prometheus-stack-prometheus
# spec.retention: 2h (기본값 유지)
```

3. Docker/containerd 이미지 정리:
```bash
sudo docker system prune -a
# 또는
sudo crictl rmi --prune
```

---

## 성능 문제

### Grafana 대시보드 로딩 느림

**원인**:
- 너무 큰 시간 범위 쿼리
- 복잡한 PromQL 쿼리
- Thanos Query 리소스 부족

**해결 방법**:

1. Thanos Query 리소스 증가:
```yaml
# thanos-query.yaml
resources:
  limits:
    cpu: 1000m    # 500m에서 증가
    memory: 2Gi   # 1Gi에서 증가
```

2. 쿼리 캐싱 활성화:
```yaml
# Thanos Query에 캐싱 추가
args:
  - --query.timeout=5m
  - --query.max-concurrent=20
  - --query.lookback-delta=5m
```

3. 대시보드 쿼리 최적화:
```promql
# 나쁜 예: 모든 클러스터의 모든 시계열
rate(container_cpu_usage_seconds_total[5m])

# 좋은 예: 필요한 라벨만 선택
rate(container_cpu_usage_seconds_total{cluster="cluster-01",namespace="monitoring"}[5m])
```

### Thanos Compactor 느린 압축

**증상**:
- Compactor가 오랜 시간 실행
- S3에 압축되지 않은 블록이 많이 쌓임

**해결 방법**:

1. Compactor 리소스 증가:
```yaml
# thanos-compactor.yaml
resources:
  limits:
    cpu: 1000m    # 500m에서 증가
    memory: 2Gi   # 1Gi에서 증가
```

2. 동시 실행 수 조정:
```yaml
args:
  - --compact.concurrency=2  # 1에서 증가
```

3. 작업 간격 조정:
```yaml
args:
  - --wait-interval=5m  # 3m에서 증가 (CPU 부하 감소)
```

### 높은 메모리 사용률

**해결 방법**:

1. 각 컴포넌트 메모리 사용량 확인:
```bash
kubectl top pod -n monitoring
```

2. Prometheus 메모리 최적화:
```yaml
# Scrape interval 증가
scrapeInterval: 60s  # 30s에서 증가

# 보존 기간 단축
retention: 1h  # 2h에서 단축
```

3. Thanos Store 캐시 크기 조정:
```yaml
# thanos-store.yaml
args:
  - --index-cache-size=250MB     # 기본값
  - --chunk-pool-size=2GB        # 기본값
```

---

## 로그 분석 방법

### 유용한 로그 필터링 명령어

#### Prometheus 로그
```bash
# Scrape 에러 확인
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 prometheus | \
  grep -i "error.*scrape"

# TSDB 문제 확인
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 prometheus | \
  grep -i "tsdb"
```

#### Thanos Sidecar 로그
```bash
# S3 업로드 상태
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 thanos-sidecar | \
  grep -E "uploaded|shipper"

# S3 오류
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 thanos-sidecar | \
  grep -i "s3\|bucket\|objstore" | grep -i error
```

#### Thanos Query 로그
```bash
# Store 연결 상태
kubectl logs -n monitoring deployment/thanos-query | \
  grep -E "adding new|removing"

# 쿼리 에러
kubectl logs -n monitoring deployment/thanos-query | \
  grep -i "error.*query"
```

#### Thanos Compactor 로그
```bash
# 압축 작업 진행
kubectl logs -n monitoring statefulset/thanos-compactor | \
  grep -E "compact|downsample"

# 데이터 삭제
kubectl logs -n monitoring statefulset/thanos-compactor | \
  grep "retention"
```

### 실시간 로그 모니터링

```bash
# 모든 Thanos 컴포넌트 로그 통합
kubectl logs -n monitoring -l app.kubernetes.io/component=thanos -f --prefix=true

# 에러만 필터링
kubectl logs -n monitoring -l app=thanos-query -f | grep -i error

# 특정 시간 이후 로그
kubectl logs -n monitoring deployment/thanos-query --since=1h
```

### 로그 수집 및 분석 (트러블슈팅용)

```bash
# 모든 monitoring 네임스페이스 로그 수집
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGDIR="monitoring-logs-$TIMESTAMP"
mkdir -p $LOGDIR

for pod in $(kubectl get pods -n monitoring -o name); do
  pod_name=$(basename $pod)
  echo "Collecting logs from $pod_name..."
  kubectl logs -n monitoring $pod_name --all-containers > $LOGDIR/$pod_name.log 2>&1
done

# 압축
tar czf $LOGDIR.tar.gz $LOGDIR
echo "Logs collected: $LOGDIR.tar.gz"
```

---

## 긴급 복구 절차

### 전체 시스템 장애

1. **우선순위 확인**:
   - Prometheus (메트릭 수집)
   - Thanos Sidecar (실시간 쿼리)
   - Thanos Store (Historical 데이터)
   - Grafana (시각화)

2. **단계별 복구**:

```bash
# 1. Prometheus 복구
kubectl rollout restart statefulset/prometheus-kube-prometheus-stack-prometheus -n monitoring

# 2. Thanos 컴포넌트 복구
kubectl rollout restart deployment/thanos-query -n monitoring
kubectl rollout restart statefulset/thanos-store -n monitoring
kubectl rollout restart statefulset/thanos-compactor -n monitoring

# 3. Grafana 복구
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring

# 4. 상태 확인
kubectl get pods -n monitoring -w
```

### 데이터 백업 및 복구

#### S3 데이터 백업
```bash
# mc CLI 사용
mc alias set myminio http://s3.minio.miribit.lab:80 $ACCESS_KEY $SECRET_KEY
mc mirror myminio/thanos-bucket ./thanos-backup/
```

#### Prometheus PVC 백업
```bash
# Velero 사용 (권장)
velero backup create prometheus-backup --include-namespaces monitoring

# 수동 백업
for i in 0 1; do
  kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-$i -c prometheus -- \
    tar czf /tmp/prometheus-$i-backup.tar.gz /prometheus
  kubectl cp monitoring/prometheus-kube-prometheus-stack-prometheus-$i:/tmp/prometheus-$i-backup.tar.gz \
    ./prometheus-$i-backup.tar.gz
done
```

---

## 도움 받기

문제가 해결되지 않으면:

1. **로그 수집**: 위의 로그 수집 스크립트 실행
2. **상태 정보 수집**:
```bash
kubectl get all -n monitoring > cluster-state.txt
kubectl describe pods -n monitoring >> cluster-state.txt
```
3. **커뮤니티**:
   - [Thanos GitHub Issues](https://github.com/thanos-io/thanos/issues)
   - [Prometheus Community](https://prometheus.io/community/)
   - [CNCF Slack #thanos](https://cloud-native.slack.com/)

---

## 예방적 모니터링

문제를 사전에 방지하기 위한 알럿:

```yaml
# PrometheusRule 예제
groups:
  - name: thanos-alerts
    rules:
      - alert: ThanosSidecarNoUpload
        expr: |
          (time() - thanos_shipper_last_successful_upload_time) > 7200
        for: 30m
        annotations:
          summary: "Thanos Sidecar hasn't uploaded blocks for 2 hours"

      - alert: ThanosQueryDown
        expr: up{job="thanos-query"} == 0
        for: 5m
        annotations:
          summary: "Thanos Query is down"

      - alert: ThanosCompactorFailed
        expr: |
          rate(thanos_compact_iterations_total{result="error"}[5m]) > 0
        for: 15m
        annotations:
          summary: "Thanos Compactor is failing"
```
