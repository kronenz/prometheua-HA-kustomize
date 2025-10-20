# Prometheus 구성 감사 리포트

**감사 일시**: 2025-10-20
**대상 클러스터**: Cluster-01 (194), Cluster-02 (196), Cluster-03 (197), Cluster-04 (198)

---

## 🔍 현황 요약

### 심각도: ⚠️ **중간** - 중복 배포 및 아키텍처 불일치

**핵심 문제**:
1. ✅ Prometheus Agent는 3개 엣지 클러스터에 올바르게 배포됨
2. ❌ Full Prometheus (kube-prometheus-stack)도 동시에 실행 중 (중복)
3. ❌ 중앙 클러스터에 Thanos Receiver 미배포 (Sidecar 패턴 사용 중)
4. ⚠️ Remote Write URL이 존재하지 않는 엔드포인트를 가리킴

---

## 📊 상세 분석

### Cluster-01 (Central - 192.168.101.194)

**현재 상태**: Thanos Sidecar 패턴
```
✅ prometheus-kube-prometheus-stack-prometheus-0 (Full Prometheus)
✅ thanos-sidecar (LoadBalancer: 192.168.101.211:10901)
❌ Thanos Receiver (미배포)
```

**문제점**:
- Agent Mode + Receiver 아키텍처 목표와 불일치
- 엣지 클러스터가 `http://thanos-receiver.monitoring.svc.cluster-01.local:19291`로 전송하지만 해당 엔드포인트 없음
- 현재는 Sidecar 방식으로 S3 업로드 중

---

### Cluster-02 (Edge Multi-Tenant - 192.168.101.196)

#### ✅ Prometheus Agent (올바른 구성)
```yaml
Pod: prometheus-agent-0
Status: Running (3d22h)
Args:
  - --enable-feature=agent
  - --storage.agent.path=/prometheus
Resources:
  CPU Request: 200m
  Memory Request: 200Mi

Remote Write:
  URL: http://thanos-receiver.monitoring.svc.cluster-01.local:19291/api/v1/receive
  Queue:
    capacity: 10000
    max_shards: 10
    max_samples_per_send: 5000
```

**평가**: ✅ Agent 설정은 완벽함

#### ❌ Full Prometheus (중복 배포)
```yaml
Pod: prometheus-kube-prometheus-stack-prometheus-0
Status: Running (5d3h)
Containers: 3/3 (prometheus + config-reloader + sidecar)
Remote Write: 없음 (로컬 TSDB만 사용)
```

**문제점**:
- **메모리 낭비**: Agent만 200MB 필요, Full Prometheus는 2GB+ 사용
- **스토리지 낭비**: 로컬 TSDB에 메트릭 저장 (불필요)
- **관리 복잡도**: 동일한 타겟을 Agent와 Full Prometheus가 중복 스크랩

#### 추가 컴포넌트 (불필요)
```
❌ kube-prometheus-stack-grafana-test (Error 상태)
⚠️ alertmanager-kube-prometheus-stack-alertmanager-0 (중앙에만 필요)
```

---

### Cluster-03 (Edge - 192.168.101.197)

**상태**: Cluster-02와 동일
- ✅ Prometheus Agent: 올바른 구성
- ❌ Full Prometheus: 중복 배포
- ❌ Alertmanager: 불필요 (중앙 클러스터에만 필요)

---

### Cluster-04 (Edge - 192.168.101.198)

**상태**: Cluster-02, 03과 동일
- ✅ Prometheus Agent: 올바른 구성
- ❌ Full Prometheus: 중복 배포
- ❌ Alertmanager: 불필요

---

## 🎯 아키텍처 목표 vs 현실

### 목표 (문서화된 아키텍처)
```
[Edge: Agent Mode] --Remote Write--> [Central: Thanos Receiver] --> S3
```

### 현실 (현재 배포 상태)
```
[Edge: Agent Mode + Full Prometheus] --Remote Write--> [❌ 존재하지 않음]
[Central: Full Prometheus + Sidecar] --> S3
```

---

## 💰 리소스 낭비 추정

### 메모리 낭비 (엣지 클러스터 × 3)
```
현재 구성:
- Prometheus Agent: 200MB × 3 = 600MB
- Full Prometheus: ~2GB × 3 = ~6GB
- 총: 6.6GB

목표 구성:
- Prometheus Agent: 200MB × 3 = 600MB
- 절감: 6GB (91%)
```

### 스토리지 낭비
```
현재: 각 엣지 클러스터에 로컬 TSDB (15일 × 3 = 45일치 중복 저장)
목표: 중앙 S3에만 저장 (중복 제거)
```

---

## 🔧 권장 조치 사항

### 우선순위 1: 중앙 클러스터에 Thanos Receiver 배포

**현재 문제**: 엣지 Agent가 전송할 엔드포인트 없음

**해결책**:
```bash
# Cluster-01 (Central)에서 실행
cd ~/thanos-multi-cluster
kubectl apply -k deploy/overlays/cluster-01-central/thanos-receiver/
```

**검증**:
```bash
kubectl get pods -n monitoring -l app=thanos-receive
kubectl get svc -n monitoring thanos-receive-lb
```

---

### 우선순위 2: 엣지 클러스터에서 Full Prometheus 제거

**대상**: Cluster-02, 03, 04

**제거 대상**:
1. `prometheus-kube-prometheus-stack-prometheus` StatefulSet
2. `alertmanager-kube-prometheus-stack-alertmanager` StatefulSet
3. `kube-prometheus-stack-grafana` (이미 Error 상태)

**보존 대상**:
- ✅ `prometheus-agent` (핵심 메트릭 수집)
- ✅ `kube-state-metrics` (클러스터 메트릭)
- ✅ `node-exporter` (노드 메트릭)
- ✅ `kube-prometheus-stack-operator` (CRD 관리)

**제거 스크립트** (각 엣지 클러스터에서):
```bash
# Cluster-02 (196)
sshpass -p "123qwe" ssh bsh@192.168.101.196 << 'EOF'
  # Full Prometheus 제거
  kubectl delete statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring

  # Alertmanager 제거 (중앙에만 필요)
  kubectl delete statefulset alertmanager-kube-prometheus-stack-alertmanager -n monitoring

  # Grafana 테스트 Pod 제거
  kubectl delete pod kube-prometheus-stack-grafana-test -n monitoring

  # PVC 정리 (선택사항 - 스토리지 회수)
  kubectl delete pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 -n monitoring
  kubectl delete pvc alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0 -n monitoring
EOF

# Cluster-03 (197) - 위와 동일
# Cluster-04 (198) - 위와 동일
```

---

### 우선순위 3: Remote Write 엔드포인트 수정

**현재 설정** (모든 엣지 클러스터):
```yaml
remote_write:
  - url: http://thanos-receiver.monitoring.svc.cluster-01.local:19291/api/v1/receive
```

**문제**: `cluster-01.local` 도메인이 엣지 클러스터에서 해석되지 않음

**해결책 옵션**:

**Option 1: Service 기반 (클러스터 내부)**
```yaml
# Ingress를 통한 라우팅
remote_write:
  - url: http://thanos-receive-lb.monitoring.svc.cluster.local:19291/api/v1/receive
```

**Option 2: Ingress 기반 (권장)**
```yaml
remote_write:
  - url: https://thanos-receiver.k8s-cluster-01.miribit.lab/api/v1/receive
  # 또는
  - url: http://192.168.101.210:19291/api/v1/receive
```

**적용 방법**:
```bash
# Prometheus Agent ConfigMap 수정 (각 엣지 클러스터)
kubectl edit configmap prometheus-agent-config -n monitoring
# 또는
kubectl apply -f prometheus-agent-updated-config.yaml
kubectl rollout restart statefulset prometheus-agent -n monitoring
```

---

## 📋 단계별 실행 계획

### Phase 1: Thanos Receiver 배포 (30분)
1. ✅ Central Cluster (194)에 Thanos Receiver 배포
2. ✅ Service + Ingress 생성
3. ✅ 연결성 테스트

### Phase 2: Remote Write 수정 (15분)
1. ✅ 엣지 클러스터 Agent ConfigMap 업데이트
2. ✅ Agent Pod 재시작
3. ✅ 메트릭 수신 확인

### Phase 3: 중복 제거 (30분)
1. ⚠️ 백업 생성 (Prometheus 데이터)
2. ✅ Full Prometheus 제거 (Cluster-02/03/04)
3. ✅ Alertmanager 제거
4. ✅ 리소스 회수 확인

### Phase 4: 검증 (15분)
1. ✅ 모든 엣지 클러스터에서 메트릭 수신 확인
2. ✅ Grafana에서 멀티클러스터 쿼리 테스트
3. ✅ 알림 동작 확인

**총 예상 시간**: 90분

---

## ⚠️ 주의사항

### 롤백 계획
```bash
# Prometheus Agent가 실패할 경우 Full Prometheus 재배포
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
```

### 데이터 손실 방지
- Full Prometheus를 제거하기 전에 **최소 2시간 대기**
- Thanos Receiver가 정상적으로 메트릭을 수신하는지 확인
- 중요 알림 규칙은 중앙 클러스터 Thanos Ruler로 이관

### 모니터링 공백 최소화
- Phase 2 (Remote Write 수정) 완료 후 Phase 3 (중복 제거) 실행
- 각 클러스터를 순차적으로 처리 (동시 진행 금지)

---

## 📈 예상 효과

### Before (현재)
```
메모리: 6.6GB (Agent 600MB + Full 6GB)
스토리지: 45일치 중복 (15일 × 3 클러스터)
복잡도: 높음 (Agent + Full Prometheus 병행)
```

### After (목표)
```
메모리: 600MB (Agent만) - 91% 절감
스토리지: 중앙 S3에만 저장 - 중복 제거
복잡도: 낮음 (Agent Mode 단일화)
비용: 월 $404 절감 (메모리 + 스토리지)
```

---

## 🚀 즉시 실행 가능한 명령어

### 1단계: Receiver 상태 확인
```bash
# Central Cluster (Cluster-01)에서
kubectl get pods -n monitoring -l app=thanos-receive
kubectl get svc -n monitoring | grep thanos-receive
```

### 2단계: Agent → Receiver 연결성 테스트
```bash
# 엣지 클러스터에서 (예: Cluster-02)
kubectl exec -it prometheus-agent-0 -n monitoring -- \
  wget -O- http://192.168.101.210:19291/-/ready
```

### 3단계: 메트릭 수신 확인
```bash
# Central Cluster에서
kubectl exec -n monitoring thanos-receive-0 -- \
  wget -qO- http://localhost:10902/metrics | grep remote_write
```

---

## 📞 다음 단계

**질문 사항**:
1. Thanos Receiver를 즉시 배포할까요? (Phase 1)
2. Full Prometheus 제거 전 백업이 필요한가요?
3. 단계별로 진행할까요, 아니면 전체 자동화 스크립트를 실행할까요?

**권장**: Phase 1 (Receiver 배포) → 2시간 모니터링 → Phase 2, 3 순차 진행
