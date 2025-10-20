# 05. 운영 가이드

## 📋 개요

이 섹션에서는 Thanos 멀티클러스터 Observability 플랫폼의 **일상 운영, 모니터링, 문제 해결 방법**을 제공합니다.

---

## 📂 문서 목록

### [일상-운영.md](./일상-운영.md)
**목적**: 매일 수행해야 하는 운영 작업 및 프로세스

**주요 내용**:
- GitOps 워크플로우
- 설정 변경 프로세스
- 새 클러스터 추가
- 업데이트 전략
- 모니터링 및 알림
- 백업 및 복구
- 스케일링

**대상 독자**: SRE, DevOps 엔지니어, 운영 담당자

---

### [모범-사례.md](./모범-사례.md)
**목적**: 운영 효율성과 안정성을 위한 권장 사항

**주요 내용**:
- 리소스 할당 가이드
- 보안 설정
- 성능 최적화
- 고가용성 구성
- 모니터링 전략
- 알림 규칙 설계

**대상 독자**: 아키텍트, 시니어 엔지니어

---

### [빠른-참조.md](./빠른-참조.md)
**목적**: 자주 사용하는 명령어와 절차 빠른 검색

**주요 내용**:
- kubectl 명령어 모음
- ArgoCD 명령어
- Prometheus 쿼리 예시
- Thanos 관련 작업
- 로그 확인 방법
- 네트워크 디버깅

**대상 독자**: 모든 운영자

---

### [트러블슈팅.md](./트러블슈팅.md)
**목적**: 일반적인 문제 해결 방법

**주요 내용**:
- ArgoCD Application 문제
- Thanos Query 문제
- Prometheus 스크래핑 실패
- Fluent-Bit 로그 전송 문제
- OpenSearch 클러스터 문제
- S3 연동 문제
- 네트워크 및 인증 문제

**대상 독자**: 모든 운영자, 트러블슈팅 담당자

---

## 🎯 일상 운영 체크리스트

### 매일
- [ ] ArgoCD Application 상태 확인
- [ ] Prometheus Target 상태 확인
- [ ] Thanos Query 정상 작동 확인
- [ ] 디스크 사용량 모니터링

### 매주
- [ ] S3 버킷 사용량 확인
- [ ] Alertmanager 알림 히스토리 검토
- [ ] 로그 인덱스 상태 확인
- [ ] 백업 상태 검증

### 매월
- [ ] Helm Chart 업데이트 확인
- [ ] 보안 패치 적용
- [ ] 리소스 사용량 분석 및 최적화
- [ ] 문서 업데이트

---

## 📊 주요 모니터링 대시보드

### Grafana 대시보드
- **Thanos Overview**: 전체 Thanos 컴포넌트 상태
- **Cluster Metrics**: 클러스터별 리소스 사용량
- **Multi-Cluster Summary**: 모든 클러스터 요약 뷰

### OpenSearch Dashboards
- **로그 인덱스**: `fluent-bit-*`
- **클러스터별 필터링**: `cluster: cluster-01`

---

## 🚨 긴급 대응 절차

### 1. Prometheus 다운
```bash
# 상태 확인
kubectl get pods -n monitoring -l app=prometheus

# 재시작
kubectl rollout restart statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring
```

### 2. Thanos Query 응답 없음
```bash
# 로그 확인
kubectl logs -n monitoring deployment/thanos-query --tail=100

# Store 엔드포인트 확인
kubectl port-forward -n monitoring svc/thanos-query 10901:10901
grpcurl -plaintext localhost:10901 thanos.Store/Info
```

### 3. S3 연동 실패
```bash
# Secret 확인
kubectl get secret thanos-s3-secret -n monitoring -o yaml

# 연결 테스트
kubectl run -it --rm s3-test --image=amazon/aws-cli --restart=Never -- \
  s3 ls s3://thanos-metrics --endpoint-url=http://s3.minio.miribit.lab
```

---

## 🔗 관련 문서

- **아키텍처** → [01-아키텍처-개요](../01-아키텍처-개요/)
- **GitOps 배포** → [04-GitOps-배포](../04-GitOps-배포/)
- **확장 아키텍처** → [06-확장-아키텍처](../06-확장-아키텍처/)

---

## 📞 지원 채널

- **이슈 트래킹**: GitHub Issues
- **긴급 문의**: Infrastructure Team
- **문서 기여**: Pull Request 환영

---

**최종 업데이트**: 2025-10-20
