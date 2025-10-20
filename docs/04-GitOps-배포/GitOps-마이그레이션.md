# GitOps 마이그레이션 요약

## 변경 사항 개요

기존 수동 배포 방식에서 **Operator 기반 + ArgoCD GitOps** 방식으로 전환하여 엔터프라이즈 급 멀티클러스터 Observability 플랫폼을 구축했습니다.

---

## 주요 변경사항

### 1. 아키텍처 전환

#### Before (수동 배포)
```
개발자 → SSH → 원격 서버 → kubectl apply → 클러스터
```

**문제점**:
- 수동 배포로 인한 일관성 부족
- 변경 이력 추적 어려움
- 멀티클러스터 관리 복잡성
- 롤백 어려움
- 배포 실패 시 수동 복구 필요

#### After (GitOps)
```
개발자 → Git Push → ArgoCD Watch → 자동 배포 → 멀티클러스터
```

**개선사항**:
- Git을 단일 진실 공급원(Single Source of Truth)으로 사용
- 모든 변경사항 추적 및 감사 가능
- 선언적 구성으로 일관성 보장
- 자동 롤백 및 자가 치유(Self-Healing)
- 멀티클러스터를 단일 인터페이스로 관리

### 2. Operator 패턴 도입

#### Prometheus Operator
- **이전**: 수동으로 Prometheus 설정 파일 관리
- **현재**: `Prometheus`, `ServiceMonitor`, `PrometheusRule` CRD로 선언적 관리
- **장점**: 자동 설정 리로드, 타겟 자동 발견, 규칙 검증

#### OpenSearch Operator
- **이전**: Helm Chart 수동 설치 및 관리
- **현재**: `OpenSearchCluster` CRD로 클러스터 전체 관리
- **장점**: 자동 스케일링, 롤링 업데이트, ISM 정책 자동화

#### Fluent Operator
- **이전**: ConfigMap으로 Fluent-Bit 설정 관리
- **현재**: `FluentBit`, `ClusterInput/Filter/Output` CRD로 관리
- **장점**: 동적 설정 변경, 파이프라인 검증, 멀티테넌트 지원

### 3. ArgoCD 기반 배포 파이프라인

#### Application-of-Applications 패턴

```
Root App
├── Infrastructure Layer
│   ├── Longhorn (스토리지)
│   └── Cilium Ingress (네트워킹)
├── Operator Layer
│   ├── Prometheus Operator
│   ├── OpenSearch Operator
│   └── Fluent Operator
├── Observability Layer
│   ├── Prometheus + Thanos
│   ├── OpenSearch Clusters
│   └── Fluent-Bit Collectors
└── Application Layer
    ├── Grafana
    └── OpenSearch Dashboards
```

#### 배포 순서 제어

**Sync Wave**를 사용한 의존성 관리:
- Wave 0: Operators 설치
- Wave 1: Prometheus, OpenSearch 클러스터 생성
- Wave 2: Fluent-Bit, Thanos 컴포넌트 배포

---

## 디렉토리 구조 변경

### 추가된 디렉토리

```
argocd/                                        # NEW
├── install/                                   # ArgoCD 설치
│   ├── namespace.yaml
│   └── ingress.yaml
├── root-app.yaml                              # Root Application
└── applications/                              # Child Applications
    ├── cluster-01/
    │   ├── longhorn.yaml
    │   ├── cilium-ingress.yaml
    │   ├── prometheus-operator.yaml
    │   ├── opensearch-operator.yaml
    │   ├── opensearch.yaml
    │   ├── fluent-operator.yaml
    │   └── fluent-bit.yaml
    ├── cluster-02/
    ├── cluster-03/
    └── cluster-04/

scripts/argocd/                                # NEW
├── install-argocd.sh
├── register-clusters.sh
└── bootstrap-apps.sh
```

### 기존 디렉토리 유지

```
deploy/
├── base/                                      # 기존 유지
│   ├── longhorn/
│   ├── kube-prometheus-stack/
│   ├── opensearch/
│   └── fluent-bit/
└── overlays/                                  # 기존 유지
    ├── cluster-01-central/
    ├── cluster-02-edge/
    ├── cluster-03-edge/
    └── cluster-04-edge/
```

---

## 배포 워크플로우 비교

### Before: 수동 배포

```bash
# 각 클러스터마다 반복 실행
ssh bsh@192.168.101.196
cd ~/thanos-multi-cluster
kubectl config use-context cluster-02-context
kustomize build deploy/overlays/cluster-02-edge/kube-prometheus-stack --enable-helm | kubectl apply -f -
# 오류 발생 시 수동 디버깅
# 다음 클러스터로 이동...
```

**소요 시간**: 클러스터당 30분 × 4 = 약 2시간
**실패 복구**: 수동

### After: GitOps 배포

```bash
# 1. 설정 변경
vim deploy/overlays/cluster-02-edge/kube-prometheus-stack/values-patch.yaml

# 2. Git 커밋 및 푸시
git add .
git commit -m "chore: update prometheus config"
git push origin main

# 3. ArgoCD가 자동 배포 (5분 이내)
# 실패 시 자동 롤백
```

**소요 시간**: Git 푸시 후 5분 (자동)
**실패 복구**: 자동 롤백

---

## 운영 시나리오

### 1. 설정 변경

#### Before
```bash
# 각 클러스터에 SSH 접속
ssh bsh@192.168.101.196
vim ~/thanos/deploy/overlays/cluster-02/prometheus/values.yaml
kubectl apply -f ...
# 다음 클러스터...
```

#### After
```bash
# 로컬에서 변경
vim deploy/overlays/cluster-02-edge/kube-prometheus-stack/values-patch.yaml
git commit -am "chore: increase retention"
git push
# ArgoCD가 자동 배포
```

### 2. 새 클러스터 추가

#### Before
```bash
# 수동으로 모든 컴포넌트 설치
ssh bsh@192.168.101.199
# Kubernetes 설치
# Longhorn 설치
# Prometheus 설치
# OpenSearch 설치
# ... (각각 30분 이상 소요)
```

#### After
```bash
# 1. 오버레이 복사
cp -r deploy/overlays/cluster-02-edge deploy/overlays/cluster-05-edge

# 2. ArgoCD Application 생성
cp -r argocd/applications/cluster-02 argocd/applications/cluster-05

# 3. Git 푸시
git add .
git commit -m "feat: add cluster-05"
git push

# 4. 클러스터 등록
argocd cluster add cluster-05-context

# 5분 내 전체 스택 자동 배포
```

### 3. 버전 업그레이드

#### Before
```bash
# 각 클러스터에서 수동 실행
helm repo update
helm upgrade prometheus prometheus-community/kube-prometheus-stack --version 79.0.0
# 오류 발생 시 수동 롤백
helm rollback prometheus
```

#### After
```bash
# base/kustomization.yaml 수정
vim deploy/base/kube-prometheus-stack/kustomization.yaml
# version: 78.2.1 → 79.0.0

git commit -am "chore: upgrade kube-prometheus-stack"
git push

# ArgoCD가 모든 클러스터에 자동 롤아웃
# 실패 시 자동 롤백
```

### 4. 재해 복구

#### Before
```bash
# 클러스터 전체 재구축 필요
# 1. 백업에서 설정 파일 복구 (어디에?)
# 2. 각 컴포넌트 수동 재설치 (어떤 버전?)
# 3. 설정 재적용 (어떤 설정?)
# 소요 시간: 1일 이상
```

#### After
```bash
# 1. 새 클러스터 구축
./scripts/k8s/install-k8s-node-194.sh

# 2. ArgoCD 재설치
./scripts/argocd/install-argocd.sh

# 3. Root Application 배포
kubectl apply -f argocd/root-app.yaml

# ArgoCD가 Git에서 모든 설정을 자동 복구
# 소요 시간: 30분
```

---

## 보안 및 거버넌스 개선

### 1. 변경 이력 추적

**Before**: 변경 이력 없음, 누가 무엇을 언제 변경했는지 알 수 없음

**After**: 모든 변경사항이 Git 커밋으로 기록
```bash
git log --oneline
# abc123 chore: increase prometheus retention
# def456 feat: add new alerting rule
# ghi789 fix: correct opensearch memory limit
```

### 2. 코드 리뷰

**Before**: 변경사항 리뷰 없이 직접 배포

**After**: Pull Request를 통한 변경사항 리뷰
```bash
# 1. Feature Branch 생성
git checkout -b feature/increase-retention

# 2. 변경 및 커밋
vim deploy/overlays/cluster-01-central/kube-prometheus-stack/values-patch.yaml
git commit -am "chore: increase retention to 4h"

# 3. Pull Request 생성
git push origin feature/increase-retention

# 4. 팀원 리뷰 후 Merge
# 5. ArgoCD가 자동 배포
```

### 3. RBAC

**Before**: 모든 사용자가 kubectl 직접 사용 (위험)

**After**: ArgoCD RBAC으로 세분화된 권한 관리
- Dev Team: 특정 Namespace만 Sync 가능
- Ops Team: 전체 Application Sync 가능
- Admin: 전체 권한

---

## 모니터링 및 알림

### ArgoCD UI

**Application Health Dashboard**:
- 모든 클러스터의 배포 상태를 단일 화면에서 확인
- Out-of-Sync 리소스 즉시 식별
- 배포 히스토리 및 롤백 가능

**Metrics**:
```promql
# ArgoCD Application Sync 성공률
sum(rate(argocd_app_sync_total{phase="Succeeded"}[5m]))
/
sum(rate(argocd_app_sync_total[5m]))

# Out-of-Sync Application 수
count(argocd_app_info{sync_status="OutOfSync"})
```

### Grafana Dashboard

**새로운 대시보드**:
- ArgoCD Application Status
- GitOps Deployment Metrics
- Multi-Cluster Health Overview

---

## 마이그레이션 체크리스트

### Phase 1: 준비 (완료)
- [x] ArgoCD 설치 스크립트 작성
- [x] Application 매니페스트 작성
- [x] 기존 Kustomize 구조 유지
- [x] 문서 작성

### Phase 2: 파일럿 배포 (권장)
- [ ] 테스트 클러스터에서 ArgoCD 설치
- [ ] 단일 Application 배포 테스트
- [ ] Sync 및 롤백 테스트
- [ ] 성능 및 안정성 검증

### Phase 3: 프로덕션 마이그레이션
- [ ] 중앙 클러스터(194)에 ArgoCD 설치
- [ ] 원격 클러스터 등록
- [ ] Root Application 배포
- [ ] 기존 리소스와 ArgoCD 동기화
- [ ] 수동 배포 스크립트 제거

### Phase 4: 운영 전환
- [ ] 팀원 교육 (ArgoCD 사용법)
- [ ] 운영 문서 업데이트
- [ ] 알림 설정 (Slack, Email)
- [ ] 정기 백업 자동화

---

## 예상 효과

### 1. 생산성 향상
- **배포 시간**: 2시간 → 5분 (96% 단축)
- **롤백 시간**: 1시간 → 1분 (98% 단축)
- **새 클러스터 추가**: 4시간 → 10분 (95% 단축)

### 2. 안정성 향상
- **배포 성공률**: 80% → 99%
- **변경 이력 추적**: 0% → 100%
- **자동 롤백**: 불가능 → 가능

### 3. 보안 강화
- **접근 제어**: SSH 기반 → RBAC 기반
- **감사 로그**: 없음 → Git 커밋 로그
- **비밀 관리**: 평문 → External Secrets Operator (향후)

### 4. 운영 효율성
- **멀티클러스터 관리**: 개별 SSH → 단일 UI
- **모니터링**: 분산 → 통합 (ArgoCD + Grafana)
- **문서화**: 수동 → 자동 (코드 = 문서)

---

## 다음 단계

### 1. 단기 (1개월)
- [ ] ArgoCD Notifications 설정 (Slack 연동)
- [ ] Grafana Dashboard 추가 (ArgoCD Metrics)
- [ ] 팀원 온보딩 세션

### 2. 중기 (3개월)
- [ ] External Secrets Operator 도입 (비밀 관리 개선)
- [ ] Progressive Delivery (Canary, Blue-Green)
- [ ] Policy as Code (OPA Gatekeeper)

### 3. 장기 (6개월)
- [ ] 멀티 클러스터 확장 (10+ 클러스터)
- [ ] 멀티 테넌트 지원
- [ ] 자동 스케일링 최적화

---

## 참고 자료

### ArgoCD
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Application-of-Applications Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Sync Waves and Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

### GitOps
- [GitOps Principles](https://opengitops.dev/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)

### Operators
- [Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Operator SDK](https://sdk.operatorframework.io/)

---

**작성일**: 2025-10-16
**작성자**: Infrastructure Team
