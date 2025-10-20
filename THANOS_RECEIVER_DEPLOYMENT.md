# Thanos Receiver 배포 완료 보고서

배포 일시: 2025-10-20
상태: ✅ **성공**

---

## 1. 배포 개요

**목적**: Prometheus Agent Mode에서 수집한 메트릭을 중앙 집중식으로 수신하는 Thanos Receiver 배포

**아키텍처**:
```
[Edge Clusters: Prometheus Agent]
          ↓ Remote Write
[Central: Thanos Receiver (RF=3)]
          ↓ Upload
[S3 Object Storage]
```

---

## 2. 주요 해결 사항

### ❌ 문제: Permission Denied on TSDB Path

**에러 로그**:
```
ts=2025-10-20T11:22:40.017663919Z caller=main.go:145 level=error
err="mkdir /var/thanos/receive/default-tenant: permission denied
```

**원인**: Container가 filesystem에 대한 적절한 권한 없이 실행됨

### ✅ 해결: securityContext 추가

**적용 설정** ([thanos-receiver.yaml:68-71](deploy/overlays/cluster-01-central/thanos-receiver/thanos-receiver.yaml#L68-L71)):
```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 65534        # nobody group
        runAsUser: 65534      # nobody user
        runAsNonRoot: true    # security best practice
```

**결과**:
- ✅ All 3 replicas running successfully
- ✅ TSDB 디렉토리 쓰기 권한 확보
- ✅ No CrashLoopBackOff errors

---

## 3. 배포 결과

### 3.1 Thanos Receiver Pods

```bash
$ kubectl get pods -n monitoring -l app=thanos-receiver

NAME                READY   STATUS    RESTARTS   AGE
thanos-receiver-0   1/1     Running   0          20m
thanos-receiver-1   1/1     Running   0          20m
thanos-receiver-2   1/1     Running   0          19m
```

**Configuration**:
- **Replicas**: 3
- **Replication Factor**: 3
- **TSDB Retention**: 2h (before upload to S3)
- **Image**: quay.io/thanos/thanos:v0.37.2

### 3.2 Services

```bash
$ kubectl get svc -n monitoring -l app=thanos-receiver

NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
thanos-receiver            LoadBalancer   10.99.220.167   192.168.101.210   10902:32488/TCP,10901:30139/TCP,19291:31820/TCP
thanos-receiver-headless   ClusterIP      None            <none>            10902/TCP,10901/TCP,19291/TCP
```

**Ports**:
- **10902**: HTTP (metrics, health checks)
- **10901**: gRPC (Store API, inter-component communication)
- **19291**: Remote Write (Prometheus Agent endpoint)

### 3.3 Cilium LoadBalancer

```bash
$ kubectl get ciliumloadbalancerippool cluster-01-central-pool

NAME                      DISABLED   CONFLICTING   IPS AVAILABLE   AGE
cluster-01-central-pool   false      False         0               16m
```

**VIP Configuration**:
- **IP Pool**: 192.168.101.210/32
- **Status**: ✅ Assigned to Service EXTERNAL-IP
- **L2 Announcement**: Enabled

### 3.4 Hashring Configuration

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

**Consistent Hashing**:
- ✅ 3 endpoints in hashring
- ✅ Automatic data distribution across replicas
- ✅ Replication Factor 3 (모든 데이터 3중 복제)

---

## 4. Endpoint 테스트 결과

### ✅ Service ClusterIP (Internal)

```bash
$ kubectl run test-curl --rm -it --image=curlimages/curl:latest -- \
    curl -X POST http://thanos-receiver.monitoring.svc.cluster.local:19291/api/v1/receive

HTTP/1.1 400 Bad Request
snappy decode error: s2: corrupt input
```

**결과**: ✅ **정상** (빈 POST에 대해 예상된 400 에러 반환)

### ✅ LoadBalancer External-IP (External)

```bash
$ curl -X POST http://192.168.101.210:19291/api/v1/receive

HTTP/1.1 400 Bad Request
snappy decode error: s2: corrupt input
```

**결과**: ✅ **정상** (VIP를 통한 외부 접근 가능)

### ⚠️ Cilium Ingress (HTTP Path-based Routing)

```bash
$ kubectl get ingress -n monitoring thanos-receiver-ingress

NAME                      CLASS    HOSTS                                        ADDRESS   PORTS   AGE
thanos-receiver-ingress   cilium   thanos-receiver.k8s-cluster-01.miribit.lab             80      43m
```

**Status**: ⚠️ **Ingress ADDRESS 미할당**
- Cilium Ingress 리소스는 생성되었으나 ADDRESS 필드가 비어있음
- VIP 192.168.101.210은 Service LoadBalancer에만 할당됨
- HTTP path-based routing (`/api/v1/receive`)은 현재 미동작

**권장사항**:
- Ingress 대신 **LoadBalancer Service VIP 사용** (더 간단하고 안정적)
- Prometheus Agent Remote Write URL: `http://192.168.101.210:19291/api/v1/receive`

---

## 5. Git Commit & Push

```bash
$ git commit -m "fix: Add securityContext to Thanos Receiver for TSDB write permissions"
$ git push origin main
```

**Commit SHA**: `723956b`

**변경 파일**:
- [`deploy/overlays/cluster-01-central/thanos-receiver/thanos-receiver.yaml`](deploy/overlays/cluster-01-central/thanos-receiver/thanos-receiver.yaml)

---

## 6. 다음 단계 (Next Steps)

### 6.1 ✅ 완료된 작업

1. ✅ Thanos Receiver 배포 (3 replicas, RF=3)
2. ✅ securityContext 설정으로 permission 문제 해결
3. ✅ Cilium LoadBalancer VIP 할당 및 테스트
4. ✅ Hashring 설정 및 확인
5. ✅ Remote Write endpoint 동작 확인

### 6.2 📋 남은 작업

#### Step 1: Edge Cluster Prometheus Agent Remote Write 설정 업데이트

**파일**: `deploy/overlays/cluster-{02,03,04}-edge/prometheus-agent/prometheus-agent-config.yaml`

**현재 설정**:
```yaml
remote_write:
  - url: http://192.168.101.210:19291/api/v1/receive
```

**Action**: ✅ **이미 올바른 URL로 설정됨** - 추가 작업 불필요

#### Step 2: Full Prometheus 정리 (Edge Clusters)

**실행 스크립트**: [`scripts/cleanup-full-prometheus.sh`](scripts/cleanup-full-prometheus.sh)

```bash
$ ./scripts/cleanup-full-prometheus.sh
```

**정리 대상** (Cluster-02, 03, 04):
- ❌ Full Prometheus StatefulSet → 삭제
- ❌ Alertmanager StatefulSet → 삭제 (Central에서만 필요)
- ❌ Grafana Test Pod → 삭제
- ✅ Prometheus Agent → **유지**
- ✅ Node Exporter → **유지**
- ✅ Kube-State-Metrics → **유지**

**예상 효과**:
- 메모리 사용량: 6GB → 600MB per cluster (-91%)
- 스토리지: 로컬 300GB → S3 중앙 집중식

#### Step 3: ArgoCD GitOps 배포 (Optional)

**생성된 ArgoCD Applications**:
- [`argocd-apps/cluster-01-central/thanos-receiver.yaml`](argocd-apps/cluster-01-central/thanos-receiver.yaml)
- [`argocd-apps/cluster-02-edge/prometheus-agent.yaml`](argocd-apps/cluster-02-edge/prometheus-agent.yaml)
- [`argocd-apps/cluster-03-edge/prometheus-agent.yaml`](argocd-apps/cluster-03-edge/prometheus-agent.yaml)
- [`argocd-apps/cluster-04-edge/prometheus-agent.yaml`](argocd-apps/cluster-04-edge/prometheus-agent.yaml)

**ArgoCD 설치 및 Application 배포**:
```bash
$ kubectl apply -k argocd-apps/cluster-01-central/
$ kubectl apply -k argocd-apps/cluster-02-edge/
$ kubectl apply -k argocd-apps/cluster-03-edge/
$ kubectl apply -k argocd-apps/cluster-04-edge/
```

#### Step 4: End-to-End 검증

```bash
# 1. Edge Cluster에서 메트릭 전송 확인
$ kubectl exec -n monitoring prometheus-agent-0 -- \
    wget -O- http://192.168.101.210:19291/-/ready

# 2. Thanos Receiver 로그에서 수신 확인
$ kubectl logs -n monitoring thanos-receiver-0 --tail=50 | grep -E "receive|uploaded"

# 3. S3에 메트릭 업로드 확인
$ mc ls s3.minio.miribit.lab/thanos-metrics/

# 4. Grafana에서 Edge Cluster 메트릭 쿼리 테스트
# Query: up{job="prometheus-agent", cluster="cluster-02"}
```

---

## 7. 트러블슈팅 가이드

### 문제 1: Pod CrashLoopBackOff

**증상**:
```
NAME                READY   STATUS             RESTARTS
thanos-receiver-0   0/1     CrashLoopBackOff   5
```

**해결**:
1. 로그 확인: `kubectl logs -n monitoring thanos-receiver-0 --tail=50`
2. securityContext 설정 확인: `kubectl get pod thanos-receiver-0 -n monitoring -o yaml | grep -A 10 securityContext`
3. PVC 권한 확인: `kubectl exec -n monitoring thanos-receiver-0 -- ls -la /var/thanos/receive`

### 문제 2: Remote Write Connection Refused

**증상**:
```
caller=dedupe.go:112 component=remote level=error
url=http://192.168.101.210:19291/api/v1/receive
msg="non-recoverable error" err="Post...: dial tcp 192.168.101.210:19291: connect: connection refused"
```

**해결**:
1. Service EXTERNAL-IP 확인: `kubectl get svc -n monitoring thanos-receiver`
2. Cilium LoadBalancer IP Pool 확인: `kubectl get ciliumloadbalancerippool -A`
3. L2 Announcement Policy 확인: `kubectl get ciliuml2announcementpolicy -A`
4. VIP 네트워크 연결 테스트: `curl -v http://192.168.101.210:19291/-/healthy`

### 문제 3: Hashring Endpoint Not Found

**증상**:
```
caller=handler.go:xxx level=error msg="cannot get endpoint"
err="hashring: no such tenant: default-tenant"
```

**해결**:
1. Hashring ConfigMap 확인: `kubectl get cm -n monitoring thanos-receiver-hashrings -o yaml`
2. StatefulSet에 ConfigMap mount 확인:
   ```bash
   kubectl get sts -n monitoring thanos-receiver -o yaml | grep -A 10 hashring-config
   ```
3. Container 내부에서 파일 확인:
   ```bash
   kubectl exec -n monitoring thanos-receiver-0 -- cat /etc/thanos-hashrings/hashrings.json
   ```

---

## 8. 참고 자료

### 공식 문서
- [Thanos Receive Documentation](https://thanos.io/tip/components/receive.md/)
- [Prometheus Remote Write](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write)
- [Cilium LoadBalancer IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/)

### 프로젝트 문서
- [아키텍처 가이드](docs/Agent-Receiver-아키텍처/01-아키텍처/)
- [트러블슈팅 가이드](docs/Agent-Receiver-아키텍처/03-운영/일반-트러블슈팅.md)
- [감사 보고서](PROMETHEUS_AUDIT_REPORT.md)
- [스펙 문서 v2.0](SPEC.md)

---

## 9. 결론

✅ **Thanos Receiver 배포 성공**

**핵심 성과**:
1. ✅ securityContext 설정으로 permission 문제 완전 해결
2. ✅ Replication Factor 3로 고가용성 확보
3. ✅ Cilium LoadBalancer VIP (192.168.101.210) 정상 동작
4. ✅ Remote Write endpoint 검증 완료
5. ✅ Git 변경사항 commit & push 완료

**다음 세션 작업**:
- Edge Cluster Full Prometheus 정리 (`cleanup-full-prometheus.sh` 실행)
- End-to-end 메트릭 흐름 검증
- Grafana 대시보드 구성 및 테스트

---

**배포 담당**: Claude Code Agent
**검증 완료**: 2025-10-20 11:46 KST
**문서 버전**: 1.0
