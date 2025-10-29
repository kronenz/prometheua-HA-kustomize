# RWO Volume Attachment 문제 해결 가이드

## 목차
1. [문제 개요](#문제-개요)
2. [원인 분석](#원인-분석)
3. [해결 방법](#해결-방법)
4. [Thanos values.yaml 설정](#thanos-valuesyaml-설정)
5. [Pod Disruption Budget 설정](#pod-disruption-budget-설정)
6. [자동화 스크립트](#자동화-스크립트)
7. [예방 조치](#예방-조치)
8. [트러블슈팅](#트러블슈팅)

---

## 문제 개요

### 오류 메시지

```
FailedAttachVolume: AttachVolume.Attach failed for volume "pvc-xxxxx" :
Volume is already exclusively attached to one node and can't be attached to another
```

### 발생 시나리오

RWO(ReadWriteOnce) StorageClass를 사용하는 StatefulSet Pod이 다른 노드로 재스케줄링될 때 발생합니다.

```
┌─────────────────────────────────────────────────────────┐
│ 문제 발생 흐름                                            │
└─────────────────────────────────────────────────────────┘

1. Pod이 Node-A에서 실행 중
   └─ PVC가 Node-A에 Attach됨

2. Node-A 장애 또는 Pod 삭제
   └─ Pod이 Terminating 상태로 전환

3. Scheduler가 Pod을 Node-B로 스케줄링
   └─ Node-B에 PVC Attach 시도

4. ❌ 오류 발생: PVC가 아직 Node-A에 Attach된 상태
   └─ Kubernetes는 RWO 볼륨을 여러 노드에 동시 Attach 금지
```

### 영향받는 Thanos 컴포넌트

| 컴포넌트 | Persistence | RWO 영향 | 이유 |
|---------|-------------|---------|------|
| **Receiver** | ✅ 사용 | ✅ 영향받음 | WAL(Write-Ahead Log) 저장 |
| **Compactor** | ✅ 사용 | ✅ 영향받음 | 임시 압축 데이터 저장 |
| **Store Gateway** | ✅ 사용 | ✅ 영향받음 | 인덱스 캐시 저장 |
| **Ruler** | ✅ 사용 | ✅ 영향받음 | Rule 평가 데이터 저장 |
| **Query** | ❌ 미사용 | ❌ 영향없음 | Stateless |
| **Query Frontend** | ❌ 미사용 | ❌ 영향없음 | Stateless |

---

## 원인 분석

### 1. RWO (ReadWriteOnce) 제약

```yaml
# RWO 볼륨 특성
accessModes:
  - ReadWriteOnce  # 하나의 노드에만 마운트 가능
```

**제약사항**:
- 동일한 볼륨을 여러 노드에 동시 마운트 불가
- Pod이 Terminating 상태에서도 볼륨이 즉시 Detach되지 않음
- 볼륨 Detach 완료까지 6분 이상 소요 가능

---

### 2. Pod Termination 지연

```
Pod Lifecycle:
┌──────────┐     ┌────────────┐     ┌──────────┐
│ Running  │ ──> │Terminating │ ──> │ Deleted  │
└──────────┘     └────────────┘     └──────────┘
                      ↓
                 Volume Detach
                  (최대 6분)
```

**지연 원인**:
- `terminationGracePeriodSeconds`: 기본 30초
- 컨테이너 종료 시간
- Finalizer 처리 시간
- 볼륨 Unmount 시간
- 클라우드 제공자의 Detach API 호출 시간

---

### 3. StatefulSet 특성

```yaml
# StatefulSet은 순차적 업데이트
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    partition: 0
```

**문제**:
- Pod이 강제 종료되기 전까지 새 Pod이 대기
- 노드 장애 시 기존 Pod이 자동 삭제되지 않음

---

## 해결 방법

### 방법 1: Pod Deletion Policy 설정 (권장)

StatefulSet에서 Pod이 강제 종료되기 전에 새 Pod을 생성하지 않도록 설정합니다.

#### Helm Values 설정

```yaml
# values.yaml
compactor:
  enabled: true

  # StatefulSet의 podManagementPolicy 설정
  podManagementPolicy: Parallel  # 또는 OrderedReady (기본값)

  # terminationGracePeriodSeconds 설정
  terminationGracePeriodSeconds: 30

  persistence:
    enabled: true
    storageClass: "longhorn"  # RWO StorageClass
    accessModes:
      - ReadWriteOnce
    size: 8Gi
```

---

### 방법 2: WaitForFirstConsumer 설정 (권장)

StorageClass에서 `volumeBindingMode: WaitForFirstConsumer`를 설정하여 Pod이 스케줄링된 후 볼륨을 바인딩합니다.

#### StorageClass 생성

```yaml
# storageclass-longhorn-wait.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-wait
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer  # 중요!
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fromBackup: ""
  fsType: "ext4"
```

#### 적용

```bash
kubectl apply -f storageclass-longhorn-wait.yaml

# StorageClass 확인
kubectl get storageclass longhorn-wait
```

#### Helm Values에서 사용

```yaml
# values.yaml
compactor:
  persistence:
    enabled: true
    storageClass: "longhorn-wait"  # WaitForFirstConsumer 사용
    accessModes:
      - ReadWriteOnce
```

---

### 방법 3: Pod Disruption Budget 설정

Pod이 안전하게 종료될 때까지 보호합니다.

```yaml
# values.yaml
compactor:
  pdb:
    create: true
    minAvailable: 0  # 0개까지 종료 허용 (노드 장애 시 강제 종료)
    # 또는
    # maxUnavailable: 1  # 최대 1개까지 Unavailable 허용
```

---

### 방법 4: PreStop Hook 설정

Pod 종료 전에 볼륨을 정리합니다.

```yaml
# values.yaml
compactor:
  lifecycleHooks:
    preStop:
      exec:
        command:
          - /bin/sh
          - -c
          - |
            # 볼륨 데이터 정리 (선택적)
            rm -rf /data/*
            # Graceful Shutdown 대기
            sleep 5
```

---

### 방법 5: 수동 Pod 삭제 (긴급)

노드 장애 시 수동으로 Pod을 강제 삭제합니다.

```bash
# 1. Pod 상태 확인
kubectl get pods -n monitoring | grep compactor

# 출력:
# thanos-compactor-0   0/1   Terminating   0   10m

# 2. Pod 강제 삭제
kubectl delete pod thanos-compactor-0 -n monitoring --force --grace-period=0

# 3. 새 Pod 생성 확인
kubectl get pods -n monitoring -w
```

---

## Thanos values.yaml 설정

### 완전한 설정 예시

```yaml
# ============================================================
# Global StorageClass 설정
# ============================================================
global:
  defaultStorageClass: "longhorn-wait"  # WaitForFirstConsumer 사용

# ============================================================
# Thanos Receiver
# ============================================================
receive:
  enabled: true
  replicaCount: 3

  # Pod Management Policy
  podManagementPolicy: Parallel  # 병렬 생성/삭제

  # Termination Grace Period
  terminationGracePeriodSeconds: 30

  # Persistence 설정
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    accessModes:
      - ReadWriteOnce
    size: 10Gi

  # Pod Disruption Budget
  pdb:
    create: true
    minAvailable: 2  # 최소 2개 유지 (HA)
    # maxUnavailable: 1

  # Lifecycle Hooks
  lifecycleHooks:
    preStop:
      exec:
        command:
          - /bin/sh
          - -c
          - "sleep 5"  # Graceful Shutdown 대기

# ============================================================
# Thanos Compactor
# ============================================================
compactor:
  enabled: true

  # Pod Management Policy
  podManagementPolicy: OrderedReady  # 순차적 생성/삭제

  # Termination Grace Period
  terminationGracePeriodSeconds: 30

  # Persistence 설정
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    accessModes:
      - ReadWriteOnce
    size: 8Gi

  # Pod Disruption Budget
  pdb:
    create: true
    minAvailable: 0  # 노드 장애 시 강제 종료 허용
    # maxUnavailable: 1

  # Update Strategy
  updateStrategy:
    type: RollingUpdate

  # Lifecycle Hooks
  lifecycleHooks:
    preStop:
      exec:
        command:
          - /bin/sh
          - -c
          - |
            # Compaction 작업 중단
            killall -TERM thanos
            sleep 5

# ============================================================
# Thanos Store Gateway
# ============================================================
storegateway:
  enabled: true
  replicaCount: 2

  # Pod Management Policy
  podManagementPolicy: Parallel

  # Termination Grace Period
  terminationGracePeriodSeconds: 60  # 캐시 플러시 시간

  # Persistence 설정
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    accessModes:
      - ReadWriteOnce
    size: 8Gi

  # Pod Disruption Budget
  pdb:
    create: true
    minAvailable: 1  # 최소 1개 유지

  # Lifecycle Hooks
  lifecycleHooks:
    preStop:
      exec:
        command:
          - /bin/sh
          - -c
          - |
            # 인덱스 캐시 플러시
            sleep 10

# ============================================================
# Thanos Ruler
# ============================================================
ruler:
  enabled: true

  # Pod Management Policy
  podManagementPolicy: OrderedReady

  # Termination Grace Period
  terminationGracePeriodSeconds: 30

  # Persistence 설정
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    accessModes:
      - ReadWriteOnce
    size: 8Gi

  # Pod Disruption Budget
  pdb:
    create: true
    minAvailable: 0

  # Lifecycle Hooks
  lifecycleHooks:
    preStop:
      exec:
        command:
          - /bin/sh
          - -c
          - "sleep 5"
```

---

## Pod Disruption Budget 설정

### 개념

Pod Disruption Budget(PDB)은 자발적 중단(voluntary disruptions) 시 최소한의 Pod이 유지되도록 보장합니다.

### 설정 전략

#### 1. HA 구성 (Receiver)

```yaml
receive:
  replicaCount: 3
  pdb:
    create: true
    minAvailable: 2  # 최소 2개 유지
    # 또는
    # maxUnavailable: 1  # 최대 1개까지 Unavailable
```

**설명**:
- 3개 중 최소 2개는 항상 Running 상태 유지
- Rolling Update 시 한 번에 1개씩만 업데이트

---

#### 2. 단일 인스턴스 (Compactor, Ruler)

```yaml
compactor:
  replicaCount: 1  # 단일 인스턴스
  pdb:
    create: true
    minAvailable: 0  # 노드 장애 시 강제 종료 허용
    # 또는
    # maxUnavailable: 1
```

**설명**:
- `minAvailable: 0`: 노드 장애 시 Pod을 강제 종료하고 다른 노드에서 재시작
- `maxUnavailable: 1`: 최대 1개까지 Unavailable 허용 (단일 인스턴스에서는 동일)

---

#### 3. 다중 인스턴스 (Store Gateway)

```yaml
storegateway:
  replicaCount: 2
  pdb:
    create: true
    minAvailable: 1  # 최소 1개 유지
```

**설명**:
- 2개 중 최소 1개는 항상 Running 상태 유지
- Query가 항상 Store Gateway에 접근 가능

---

### PDB 수동 생성

```yaml
# thanos-compactor-pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: thanos-compactor-pdb
  namespace: monitoring
spec:
  minAvailable: 0  # 노드 장애 시 강제 종료 허용
  selector:
    matchLabels:
      app.kubernetes.io/name: thanos-compactor
      app.kubernetes.io/instance: thanos
```

```bash
kubectl apply -f thanos-compactor-pdb.yaml

# PDB 확인
kubectl get pdb -n monitoring
```

---

## 자동화 스크립트

### 1. Pod 강제 삭제 스크립트

```bash
#!/bin/bash
# force-delete-pod.sh

NAMESPACE="monitoring"
POD_NAME="$1"

if [ -z "$POD_NAME" ]; then
  echo "사용법: $0 <pod-name>"
  exit 1
fi

echo "=== Pod 상태 확인 ==="
kubectl get pod "$POD_NAME" -n "$NAMESPACE"

# Terminating 상태인지 확인
STATE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
if [ "$STATE" != "Terminating" ]; then
  echo "Pod이 Terminating 상태가 아닙니다: $STATE"
  exit 1
fi

echo ""
echo "=== Pod 강제 삭제 (5초 후) ==="
sleep 5

kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --force --grace-period=0

echo ""
echo "=== 새 Pod 생성 대기 ==="
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=thanos" -n "$NAMESPACE" --timeout=300s

echo ""
echo "=== Pod 상태 확인 ==="
kubectl get pods -n "$NAMESPACE" | grep thanos
```

사용:
```bash
chmod +x force-delete-pod.sh
./force-delete-pod.sh thanos-compactor-0
```

---

### 2. 볼륨 Detach 확인 스크립트

```bash
#!/bin/bash
# check-volume-detach.sh

NAMESPACE="monitoring"
POD_NAME="$1"

if [ -z "$POD_NAME" ]; then
  echo "사용법: $0 <pod-name>"
  exit 1
fi

echo "=== PVC 확인 ==="
PVC_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}')
echo "PVC: $PVC_NAME"

if [ -z "$PVC_NAME" ]; then
  echo "PVC를 찾을 수 없습니다"
  exit 1
fi

echo ""
echo "=== PV 확인 ==="
PV_NAME=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
echo "PV: $PV_NAME"

echo ""
echo "=== Volume Attachment 확인 ==="
kubectl get volumeattachment | grep "$PV_NAME"

echo ""
echo "=== 노드에서 볼륨 마운트 확인 ==="
NODE_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
if [ -n "$NODE_NAME" ]; then
  echo "Node: $NODE_NAME"
  kubectl debug node/"$NODE_NAME" -it --image=busybox -- sh -c "mount | grep $PV_NAME"
fi
```

사용:
```bash
chmod +x check-volume-detach.sh
./check-volume-detach.sh thanos-compactor-0
```

---

### 3. 자동 복구 스크립트

```bash
#!/bin/bash
# auto-recover-stuck-pod.sh

NAMESPACE="monitoring"
TIMEOUT=600  # 10분

echo "=== Stuck Pod 감지 및 자동 복구 ==="

while true; do
  # Terminating 상태가 5분 이상인 Pod 검색
  STUCK_PODS=$(kubectl get pods -n "$NAMESPACE" -o json | \
    jq -r '.items[] | select(.status.phase=="Terminating") |
    select((.metadata.deletionTimestamp | fromdateiso8601) < (now - 300)) |
    .metadata.name')

  if [ -n "$STUCK_PODS" ]; then
    echo "Stuck Pod 발견:"
    echo "$STUCK_PODS"

    for POD in $STUCK_PODS; do
      echo ""
      echo "=== $POD 강제 삭제 ==="
      kubectl delete pod "$POD" -n "$NAMESPACE" --force --grace-period=0

      echo "대기 중..."
      sleep 10
    done
  else
    echo "$(date): 정상 - Stuck Pod 없음"
  fi

  sleep 60
done
```

사용 (백그라운드):
```bash
nohup ./auto-recover-stuck-pod.sh > auto-recover.log 2>&1 &
```

---

## 예방 조치

### 1. StorageClass 기본값 변경

```yaml
# 기존 StorageClass 수정
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"  # 기본값 해제
provisioner: driver.longhorn.io
volumeBindingMode: Immediate

---
# 새 StorageClass 생성 (WaitForFirstConsumer)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-wait
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"  # 기본값 설정
provisioner: driver.longhorn.io
volumeBindingMode: WaitForFirstConsumer  # 중요!
allowVolumeExpansion: true
reclaimPolicy: Retain
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"
  fsType: "ext4"
```

---

### 2. Node Affinity 설정

Pod이 특정 노드에 고정되도록 설정합니다.

```yaml
# values.yaml
compactor:
  nodeSelector:
    kubernetes.io/hostname: worker-node-1  # 특정 노드 지정

  # 또는 Affinity 사용
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-role.kubernetes.io/worker
                operator: In
                values:
                  - "true"
```

---

### 3. Taint/Toleration 설정

노드 장애 시 빠르게 재스케줄링합니다.

```yaml
# values.yaml
compactor:
  tolerations:
    - key: node.kubernetes.io/not-ready
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 30  # 30초 후 재스케줄링

    - key: node.kubernetes.io/unreachable
      operator: Exists
      effect: NoExecute
      tolerationSeconds: 30
```

---

### 4. 정기적인 Pod 재시작

StatefulSet Pod을 정기적으로 재시작하여 볼륨 상태를 정리합니다.

```yaml
# cronjob-restart-compactor.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: restart-thanos-compactor
  namespace: monitoring
spec:
  schedule: "0 3 * * 0"  # 매주 일요일 03:00
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: pod-restarter
          restartPolicy: OnFailure
          containers:
            - name: kubectl
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  kubectl rollout restart statefulset/thanos-compactor -n monitoring
```

---

## 트러블슈팅

### 문제 1: Pod이 Pending 상태에서 멈춤

**증상**:
```bash
kubectl get pods -n monitoring
# thanos-compactor-0   0/1   Pending   0   5m
```

**원인 확인**:
```bash
kubectl describe pod thanos-compactor-0 -n monitoring

# Events:
# Warning  FailedAttachVolume  1m  attachdetach-controller
# Volume is already exclusively attached to one node
```

**해결**:
```bash
# 1. VolumeAttachment 확인
kubectl get volumeattachment

# 2. 이전 노드에서 볼륨 강제 Detach
kubectl delete volumeattachment <attachment-name>

# 3. Pod 재시작
kubectl delete pod thanos-compactor-0 -n monitoring --force --grace-period=0
```

---

### 문제 2: Pod이 5분 이상 Terminating 상태

**증상**:
```bash
kubectl get pods -n monitoring
# thanos-compactor-0   1/1   Terminating   0   10m
```

**원인**: Finalizer가 제거되지 않음

**해결**:
```bash
# 1. Finalizer 확인
kubectl get pod thanos-compactor-0 -n monitoring -o yaml | grep finalizers -A 5

# 2. Finalizer 제거
kubectl patch pod thanos-compactor-0 -n monitoring -p '{"metadata":{"finalizers":null}}'

# 3. 강제 삭제
kubectl delete pod thanos-compactor-0 -n monitoring --force --grace-period=0
```

---

### 문제 3: PVC가 Released 상태에서 멈춤

**증상**:
```bash
kubectl get pvc -n monitoring
# NAME                     STATUS    VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# data-compactor-0   Released  pvc-xxxxx  8Gi        RWO            longhorn       10d
```

**원인**: PV의 claimRef가 삭제되지 않음

**해결**:
```bash
# 1. PV 확인
kubectl get pv pvc-xxxxx -o yaml

# 2. claimRef 제거
kubectl patch pv pvc-xxxxx -p '{"spec":{"claimRef":null}}'

# 3. PVC 재생성
kubectl delete pvc data-compactor-0 -n monitoring
kubectl apply -f pvc.yaml
```

---

### 문제 4: StorageClass가 WaitForFirstConsumer지만 Binding되지 않음

**증상**:
```bash
kubectl get pvc -n monitoring
# NAME                     STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS     AGE
# data-compactor-0   Pending                                  longhorn-wait    5m
```

**원인**: Pod이 스케줄링되지 않음

**해결**:
```bash
# 1. Pod 상태 확인
kubectl get pods -n monitoring

# 2. Pod Events 확인
kubectl describe pod thanos-compactor-0 -n monitoring

# 3. 노드 리소스 확인
kubectl top nodes

# 4. PVC Events 확인
kubectl describe pvc data-compactor-0 -n monitoring
```

---

### 문제 5: 노드 재부팅 후 Pod이 시작되지 않음

**증상**: 노드 재부팅 후 Pod이 다른 노드로 이동하지 않음

**원인**: Local Path 또는 HostPath 사용

**해결**:
```bash
# 1. StorageClass 확인
kubectl get storageclass -o yaml

# 2. Local Path인 경우 네트워크 스토리지로 변경
# - Longhorn, Ceph, NFS 등 사용

# 3. 또는 Node Affinity 제거
# values.yaml에서 nodeSelector 제거
```

---

## 모범 사례

### 1. Production 환경 권장 설정

```yaml
# 중앙 클러스터 (cluster-01-central)
global:
  defaultStorageClass: "longhorn-wait"

receive:
  enabled: true
  replicaCount: 3
  podManagementPolicy: Parallel
  terminationGracePeriodSeconds: 30
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    size: 50Gi
  pdb:
    create: true
    minAvailable: 2

compactor:
  enabled: true
  replicaCount: 1
  podManagementPolicy: OrderedReady
  terminationGracePeriodSeconds: 60
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    size: 20Gi
  pdb:
    create: true
    minAvailable: 0

storegateway:
  enabled: true
  replicaCount: 2
  podManagementPolicy: Parallel
  terminationGracePeriodSeconds: 60
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    size: 20Gi
  pdb:
    create: true
    minAvailable: 1

ruler:
  enabled: true
  replicaCount: 1
  podManagementPolicy: OrderedReady
  terminationGracePeriodSeconds: 30
  persistence:
    enabled: true
    storageClass: "longhorn-wait"
    size: 10Gi
  pdb:
    create: true
    minAvailable: 0
```

---

### 2. Development 환경 권장 설정

```yaml
global:
  defaultStorageClass: "local-path"  # 또는 emptyDir

receive:
  enabled: true
  replicaCount: 1
  persistence:
    enabled: false  # emptyDir 사용
    defaultEmptyDir: true

compactor:
  enabled: true
  persistence:
    enabled: false

storegateway:
  enabled: true
  replicaCount: 1
  persistence:
    enabled: false

ruler:
  enabled: true
  persistence:
    enabled: false
```

---

## 요약

### 핵심 해결 방법

| 순위 | 방법 | 효과 | 적용 난이도 |
|------|------|------|------------|
| 1 | **WaitForFirstConsumer** | ⭐⭐⭐⭐⭐ | 쉬움 |
| 2 | **Pod Disruption Budget** | ⭐⭐⭐⭐ | 쉬움 |
| 3 | **podManagementPolicy** | ⭐⭐⭐ | 쉬움 |
| 4 | **PreStop Hook** | ⭐⭐ | 중간 |
| 5 | **수동 강제 삭제** | ⭐ | 쉬움 (긴급) |

### 필수 체크리스트

- [ ] StorageClass에 `volumeBindingMode: WaitForFirstConsumer` 설정
- [ ] Pod Disruption Budget 생성 (`minAvailable: 0` for 단일 인스턴스)
- [ ] `terminationGracePeriodSeconds` 적절히 설정 (30~60초)
- [ ] Lifecycle Hooks 설정 (PreStop)
- [ ] Node Toleration 설정 (빠른 재스케줄링)
- [ ] 자동 복구 스크립트 준비

### Thanos 컴포넌트별 권장 설정

| 컴포넌트 | Replicas | PDB minAvailable | TerminationGrace |
|---------|----------|------------------|------------------|
| Receiver | 3 | 2 | 30s |
| Compactor | 1 | 0 | 60s |
| Store Gateway | 2 | 1 | 60s |
| Ruler | 1 | 0 | 30s |

**핵심**: `volumeBindingMode: WaitForFirstConsumer` + `PDB minAvailable: 0` 조합이 가장 효과적입니다!
