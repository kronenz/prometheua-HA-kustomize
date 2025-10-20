# 07. 참고자료

## 📋 개요

이 섹션에는 **구현 요약, 배포 히스토리, Operator 기반 아키텍처** 등의 참고 자료가 포함되어 있습니다.

주로 기술적 세부사항, 마이그레이션 히스토리, 대안 접근법 등을 다룹니다.

---

## 📂 문서 목록

### [구현-요약.md](./구현-요약.md)
**목적**: 초기 구현 과정 및 결정 사항 요약

**주요 내용**:
- 프로젝트 배경 및 목표
- 초기 구현 단계
- 기술 선택 이유
- 주요 이슈 및 해결 방법

**대상 독자**: 프로젝트 이해가 필요한 신규 팀원

---

### [노드-배포-요약.md](./노드-배포-요약.md)
**목적**: 각 노드별 배포 상세 내역

**주요 내용**:
- 노드별 구성 요소
- 배포 순서
- 검증 체크리스트
- 배포 후 확인 사항

**대상 독자**: 배포 담당자, 인프라 엔지니어

---

### [Operator-배포-가이드.md](./Operator-배포-가이드.md)
**목적**: Kubernetes Operator 패턴 기반 배포 가이드

**주요 내용**:
- Prometheus Operator 사용법
- OpenSearch Operator 구성
- Fluent Operator 설정
- CRD 기반 리소스 관리

**대상 독자**: Operator 패턴을 선호하는 엔지니어

---

### [Operator-배포-요약.md](./Operator-배포-요약.md)
**목적**: Operator 기반 배포 완료 후 요약 정보

**주요 내용**:
- 배포된 Operator 목록
- CRD 목록
- 주요 CR 인스턴스
- 운영 명령어

**대상 독자**: Operator 환경 운영자

---

### [Operator-멀티클러스터.md](./Operator-멀티클러스터.md)
**목적**: Operator 기반 멀티클러스터 Observability 플랫폼 전체 설명

**주요 내용**:
- Operator 아키텍처 개요
- Prometheus Operator CRD
- OpenSearch Operator CRD
- Fluent Operator CRD
- GitOps 배포 파이프라인
- 운영 가이드

**대상 독자**: Operator 패턴 심화 학습자

---

### [상세-설명.md](./상세-설명.md)
**목적**: 프로젝트의 모든 기술적 세부사항을 포함한 완전한 설명서

**주요 내용**:
- 전체 시스템 상세 아키텍처
- 각 컴포넌트 심층 분석
- 설정 파일 상세 해설
- 고급 커스터마이징 방법

**대상 독자**: 시스템 전문가, 커스터마이징 필요자

---

## 🎯 Operator 패턴 vs Helm 패턴

### Helm 기반 (현재 주 구성)
```yaml
# kustomization.yaml
helmCharts:
  - name: kube-prometheus-stack
    repo: https://prometheus-community.github.io/helm-charts
    version: 78.2.1
    valuesFile: values.yaml
```

**장점**:
- ✅ 빠른 배포
- ✅ 검증된 차트 사용
- ✅ 버전 관리 용이

**단점**:
- ❌ 세밀한 제어 제한적
- ❌ 리소스 간 의존성 관리 복잡

---

### Operator 기반
```yaml
# PrometheusRule CRD
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
spec:
  groups:
    - name: custom
      rules:
        - alert: HighCPU
          expr: rate(cpu[5m]) > 0.8
```

**장점**:
- ✅ 선언적 리소스 관리
- ✅ 자동 롤아웃 및 복구
- ✅ Kubernetes 네이티브

**단점**:
- ❌ 초기 학습 곡선
- ❌ Operator 자체 관리 필요

---

## 📊 문서 활용 가이드

### 시나리오 1: Operator 패턴으로 전환하고 싶다
1. [Operator-멀티클러스터.md](./Operator-멀티클러스터.md) 읽기
2. [Operator-배포-가이드.md](./Operator-배포-가이드.md) 따라하기
3. 기존 Helm 구성과 비교 분석

### 시나리오 2: 구현 히스토리 파악
1. [구현-요약.md](./구현-요약.md) 읽기
2. [노드-배포-요약.md](./노드-배포-요약.md)로 세부사항 확인

### 시나리오 3: 시스템 전문가 되기
1. [상세-설명.md](./상세-설명.md) 정독
2. 각 컴포넌트 소스 코드 분석
3. 커스텀 컴포넌트 개발

---

## 🔗 관련 문서

- **메인 아키텍처** → [01-아키텍처-개요](../01-아키텍처-개요/)
- **배포 가이드** → [02-프로메테우스-사이드카-패턴](../02-프로메테우스-사이드카-패턴/), [03-프로메테우스-에이전트-패턴](../03-프로메테우스-에이전트-패턴/)
- **GitOps** → [04-GitOps-배포](../04-GitOps-배포/)

---

## 📚 외부 리소스

- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [Thanos Documentation](https://thanos.io/)
- [OpenSearch Operator](https://github.com/Opster/opensearch-k8s-operator)
- [Fluent Operator](https://github.com/fluent/fluent-operator)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

---

**최종 업데이트**: 2025-10-20
