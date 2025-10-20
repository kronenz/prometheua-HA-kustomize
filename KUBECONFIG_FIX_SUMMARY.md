# Kubernetes 멀티클러스터 Kubeconfig 수정 완료 보고서

## 문제 상황

4개의 Kubernetes 클러스터(cluster-01~04)에 대한 kubeconfig가 구성되어 있었으나, **cluster-01**에서 인증서 경로 오류가 발생하여 접근이 불가능한 상태였습니다.

### 오류 내용
```
Error in configuration:
* unable to read client-cert /etc/kubernetes/pki/apiserver-kubelet-client.crt
* unable to read client-key /etc/kubernetes/pki/apiserver-kubelet-client.key
* unable to read certificate-authority /etc/kubernetes/pki/ca.crt
```

**원인**: cluster-01의 kubeconfig가 로컬 파일 시스템의 인증서 경로를 참조하고 있었으나, 실제 인증서는 원격 노드(192.168.101.194)에만 존재

---

## 수행 작업

### 1. 문제 진단 (2025-10-17)

```bash
# 현재 컨텍스트 확인
kubectl config get-contexts

# 각 클러스터 접근 테스트
kubectl --context cluster-01 get nodes  # ❌ 실패 (인증서 경로 오류)
kubectl --context cluster-02 get nodes  # ✅ 성공
kubectl --context cluster-03 get nodes  # ✅ 성공
kubectl --context cluster-04 get nodes  # ✅ 성공
```

**결과**: cluster-02, 03, 04는 정상 작동, cluster-01만 접근 불가

### 2. 원격 노드에서 Kubeconfig 재수집

```bash
# 모든 클러스터의 kubeconfig를 원격 노드에서 가져옴
sshpass -p "123qwe" ssh bsh@192.168.101.194 \
  "echo '123qwe' | sudo -S cat /etc/kubernetes/admin.conf" > ~/.kube/configs/cluster-01.conf

sshpass -p "123qwe" ssh bsh@192.168.101.196 \
  "echo '123qwe' | sudo -S cat /etc/kubernetes/admin.conf" > ~/.kube/configs/cluster-02.conf

sshpass -p "123qwe" ssh bsh@192.168.101.197 \
  "echo '123qwe' | sudo -S cat /etc/kubernetes/admin.conf" > ~/.kube/configs/cluster-03.conf

sshpass -p "123qwe" ssh bsh@192.168.101.198 \
  "echo '123qwe' | sudo -S cat /etc/kubernetes/admin.conf" > ~/.kube/configs/cluster-04.conf
```

### 3. Python 스크립트를 이용한 Kubeconfig 병합

`kubectl config` 명령어의 플래그 이슈로 인해 Python 스크립트를 작성하여 kubeconfig를 병합했습니다.

**스크립트**: `/tmp/merge_kubeconfig.py`

```python
#!/usr/bin/env python3
import yaml
from pathlib import Path

# 4개 클러스터의 kubeconfig를 읽어서
# clusters, contexts, users를 각각 고유한 이름으로 병합
# 최종 파일: ~/.kube/config
```

**실행 결과**:
```
✅ cluster-01 추가됨
✅ cluster-02 추가됨
✅ cluster-03 추가됨
✅ cluster-04 추가됨
✅ 병합된 kubeconfig 저장: /root/.kube/config
총 4개 클러스터 구성됨
```

### 4. Bash Aliases 추가

사용 편의성을 위해 `~/.bashrc`에 다음 alias를 추가했습니다.

```bash
# 축약 명령어
alias k='kubectl'
alias k1='kubectl --context cluster-01'
alias k2='kubectl --context cluster-02'
alias k3='kubectl --context cluster-03'
alias k4='kubectl --context cluster-04'
alias kc='kubectl config get-contexts'
alias kcc='kubectl config current-context'

# 빠른 컨텍스트 전환
alias use1='kubectl config use-context cluster-01'
alias use2='kubectl config use-context cluster-02'
alias use3='kubectl config use-context cluster-03'
alias use4='kubectl config use-context cluster-04'

# 전체 클러스터 상태 확인
alias kall='...'  # 모든 클러스터의 노드 정보 출력
```

---

## 최종 검증 결과

### ✅ 모든 클러스터 정상 접근 확인

```
CURRENT   NAME         CLUSTER      AUTHINFO                      NAMESPACE
*         cluster-01   cluster-01   kubernetes-admin-cluster-01
          cluster-02   cluster-02   kubernetes-admin-cluster-02
          cluster-03   cluster-03   kubernetes-admin-cluster-03
          cluster-04   cluster-04   kubernetes-admin-cluster-04
```

### ✅ 노드 상태 확인

| 클러스터 | IP | 노드명 | 상태 | 버전 | 역할 |
|---------|-----|--------|------|------|------|
| cluster-01 | 192.168.101.194 | k8s-cluster-01 | ✅ Ready | v1.34.1 | 중앙 (Central) |
| cluster-02 | 192.168.101.196 | k8s-cluster-02 | ✅ Ready | v1.34.1 | 엣지 (Edge) |
| cluster-03 | 192.168.101.197 | k8s-cluster-03 | ✅ Ready | v1.34.1 | 엣지 (Edge) |
| cluster-04 | 192.168.101.198 | k8s-cluster-04 | ✅ Ready | v1.34.1 | 엣지 (Edge) |

### ✅ 네임스페이스 현황

**Cluster-01 (중앙 클러스터)**:
- argocd
- cilium-secrets
- default
- fluent-operator-system
- gitlab
- kube-node-lease
- kube-public
- kube-system
- longhorn-system
- monitoring
- opensearch-operator-system

**Cluster-02, 03, 04 (엣지 클러스터)**:
- cilium-secrets
- default
- fluent-operator-system
- kube-node-lease
- kube-public
- kube-system
- logging
- longhorn-system
- monitoring

---

## 파일 위치

| 파일 | 경로 | 설명 |
|------|------|------|
| 통합 kubeconfig | `~/.kube/config` | 4개 클러스터 통합 설정 |
| 개별 kubeconfig | `~/.kube/configs/cluster-*.conf` | 각 클러스터별 원본 |
| 백업 파일 | `~/.kube/config.backup-*` | 이전 설정 백업 |
| 병합 스크립트 | `/tmp/merge_kubeconfig.py` | kubeconfig 병합 Python 스크립트 |
| 사용 가이드 | `~/CLUSTER_ACCESS.md` | 멀티클러스터 접근 가이드 |

---

## 사용 예시

### 1. 컨텍스트 전환

```bash
# 방법 1: kubectl 명령어
kubectl config use-context cluster-01

# 방법 2: alias 사용
use1  # cluster-01로 전환
use2  # cluster-02로 전환
```

### 2. 특정 클러스터에서 명령 실행

```bash
# 방법 1: --context 플래그
kubectl --context cluster-01 get pods -n monitoring

# 방법 2: alias 사용
k1 get pods -n monitoring  # cluster-01
k2 get pods -n monitoring  # cluster-02
```

### 3. 모든 클러스터에서 동시 확인

```bash
# 모든 클러스터의 네임스페이스 확인
for cluster in cluster-01 cluster-02 cluster-03 cluster-04; do
  echo "[$cluster]"
  kubectl --context $cluster get namespaces
done

# alias 사용
kall  # 모든 클러스터의 노드 상태
```

---

## 트러블슈팅

### 문제 1: 특정 클러스터 접근 불가

**해결**:
```bash
# 해당 클러스터의 kubeconfig 재수집
sshpass -p "123qwe" ssh -o StrictHostKeyChecking=no bsh@192.168.101.194 \
  "echo '123qwe' | sudo -S cat /etc/kubernetes/admin.conf" > ~/.kube/configs/cluster-01.conf

# kubeconfig 재병합
python3 /tmp/merge_kubeconfig.py
```

### 문제 2: 인증서 만료

**확인**:
```bash
# 인증서 유효기간 확인
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | \
  base64 -d | openssl x509 -noout -dates
```

**해결**: 원격 노드에서 kubeconfig 재수집 (위와 동일)

---

## 다음 단계

1. ✅ **완료**: 모든 클러스터 kubeconfig 구성 및 접근 테스트
2. ⏭️  **권장**: ArgoCD를 통한 멀티클러스터 애플리케이션 배포 확인
3. ⏭️  **권장**: Thanos Query에서 모든 클러스터 메트릭 조회 테스트
4. ⏭️  **권장**: OpenSearch에서 멀티클러스터 로그 수집 확인

---

## 참고 문서

- [CLUSTER_ACCESS.md](~/CLUSTER_ACCESS.md) - 멀티클러스터 접근 가이드
- [README.md](README.md) - 프로젝트 개요
- [DEPLOYMENT_COMPLETE.md](DEPLOYMENT_COMPLETE.md) - 배포 완료 현황

---

**작업 완료 시간**: 2025-10-17
**작업자**: Infrastructure Team
**상태**: ✅ 완료
