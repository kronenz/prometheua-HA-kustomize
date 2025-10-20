# 03. 운영 가이드

## 📋 개요

Prometheus Agent + Thanos Receiver 환경의 일상 운영 작업, 모니터링, 문제 해결 방법을 제공합니다.

---

## 📂 문서 목록

### GitOps-워크플로우.md
**목적**: Git 기반 운영 프로세스

**주요 내용**:
- 설정 변경 프로세스
- PR 리뷰 및 승인
- 자동 Sync vs 수동 Sync
- 변경 이력 추적
- 롤백 절차

**대상 독자**: 모든 운영자

---

### Agent-관리.md
**목적**: Prometheus Agent 운영

**주요 내용**:
- Agent 상태 모니터링
- WAL 관리
- Remote Write 큐 모니터링
- 재시작 및 복구
- 로그 분석

**대상 독자**: SRE, 운영 담당자

---

### Receiver-관리.md
**목적**: Thanos Receiver 운영

**주요 내용**:
- Receiver 상태 확인
- Hashring 관리
- Replication 모니터링
- 스케일링
- 트러블슈팅

**대상 독자**: SRE, Thanos 운영자

---

### 백업-및-복구.md
**목적**: 데이터 백업 및 재해 복구

**주요 내용**:
- Prometheus TSDB 백업
- S3 스냅샷
- OpenSearch 백업
- 재해 복구 시나리오
- RTO/RPO 목표

**대상 독자**: SRE, 백업 담당자

---

### 스케일링.md
**목적**: 수평/수직 스케일링 전략

**주요 내용**:
- Prometheus Agent 스케일링
- Thanos Receiver 수평 확장
- Prometheus HA Replica 증가
- 리소스 튜닝
- 비용 최적화

**대상 독자**: 아키텍트, SRE

---

### 업데이트-및-패치.md
**목적**: 컴포넌트 업그레이드 및 패치 관리

**주요 내용**:
- Helm Chart 업그레이드
- Prometheus 버전 업데이트
- Thanos 버전 업데이트
- 보안 패치 적용
- 마이그레이션 가이드

**대상 독자**: DevOps 엔지니어

---

### 일반-트러블슈팅.md
**목적**: 일반적인 문제 해결

**주요 내용**:
- Remote Write 실패
- Receiver 연결 끊김
- 메트릭 누락
- 디스크 공간 부족
- 네트워크 문제

**대상 독자**: 모든 운영자

---

### 빠른-참조.md
**목적**: 자주 사용하는 명령어 모음

**주요 내용**:
- kubectl 명령어
- ArgoCD 명령어
- Prometheus 쿼리
- Thanos CLI
- 디버깅 명령어

**대상 독자**: 모든 운영자

---

## 🎯 일상 체크리스트

### 매일
- [ ] ArgoCD Application 상태 확인
- [ ] Prometheus Agent Remote Write 상태
- [ ] Thanos Receiver 메트릭 수신 확인
- [ ] Grafana 대시보드 정상 조회
- [ ] 디스크 사용량 모니터링

### 매주
- [ ] S3 버킷 사용량 확인
- [ ] Prometheus TSDB 용량 확인
- [ ] Alertmanager 알림 히스토리 검토
- [ ] WAL 크기 모니터링
- [ ] 로그 인덱스 정리

### 매월
- [ ] Helm Chart 업데이트 확인
- [ ] 보안 패치 적용
- [ ] 리소스 사용량 분석
- [ ] 문서 업데이트
- [ ] 백업 검증

---

## 🚨 긴급 대응

### 1. Receiver 다운
```bash
# 상태 확인
kubectl get pods -n monitoring -l app=thanos-receive

# 로그 확인
kubectl logs -n monitoring deployment/thanos-receive --tail=100

# 재시작
kubectl rollout restart deployment/thanos-receive -n monitoring
```

### 2. Remote Write 실패
```bash
# Agent 로그 확인
kubectl logs -n monitoring prometheus-agent-0 --tail=100

# Receiver endpoint 확인
kubectl get svc -n monitoring thanos-receive

# 네트워크 테스트
kubectl exec -it prometheus-agent-0 -n monitoring -- \
  curl -v http://thanos-receive.monitoring:19291/-/ready
```

### 3. 메트릭 누락
```bash
# Thanos Query에서 확인
curl "http://thanos-query.k8s-cluster-01.miribit.lab/api/v1/query?query=up"

# Receiver Stats 확인
curl "http://thanos-receive.monitoring:19291/api/v1/status/tsdb"
```

---

## 📊 주요 모니터링 대시보드

### Grafana 대시보드
- **Thanos Receive Overview**: Receiver 상태 및 메트릭
- **Prometheus Agent**: Agent별 Remote Write 상태
- **Multi-Cluster Summary**: 전체 클러스터 요약

### Prometheus Queries
```promql
# Remote Write 성공률
rate(prometheus_remote_storage_succeeded_samples_total[5m])

# Remote Write 실패
rate(prometheus_remote_storage_failed_samples_total[5m])

# Receiver 수신 메트릭
rate(thanos_receive_replication_requests_total[5m])
```

---

## 🔗 관련 섹션

- **아키텍처** → [01-아키텍처](../01-아키텍처/)
- **배포** → [02-Kustomize-Helm-GitOps-배포](../02-Kustomize-Helm-GitOps-배포/)
- **모니터링** → [04-모니터링-가이드](../04-모니터링-가이드/)

---

**최종 업데이트**: 2025-10-20
