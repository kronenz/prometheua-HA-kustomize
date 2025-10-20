# 01. 아키텍처

## 📋 개요

Prometheus Agent + Thanos Receiver 패턴의 전체 시스템 아키텍처를 설명합니다.

---

## 📂 문서 목록

### 전체-시스템-아키텍처.md
**목적**: 4개 클러스터 전체 구성 및 컴포넌트 역할 이해

**주요 내용**:
- 시스템 전체 다이어그램
- 클러스터별 역할 분담
- Thanos 컴포넌트 설명
- 데이터 흐름도
- 고가용성 구성

**대상 독자**: 아키텍트, 시스템 설계자

---

### Agent-vs-Full-Prometheus.md
**목적**: Prometheus Agent Mode와 Full Prometheus 비교

**주요 내용**:
- Agent Mode란?
- Full Prometheus와의 차이
- 리소스 사용량 비교
- 기능 비교 (쿼리, 알림, 저장)
- 선택 기준

**대상 독자**: 아키텍트, DevOps 엔지니어

---

### Thanos-Receiver-패턴.md
**목적**: Thanos Receiver 아키텍처 심층 분석

**주요 내용**:
- Thanos Receiver란?
- Hashring 구성
- Replication Factor
- Multi-Tenancy 지원
- HA 구성
- S3 업로드 메커니즘

**대상 독자**: 아키텍트, Thanos 전문가

---

### 데이터-흐름.md
**목적**: 메트릭 데이터의 전체 여정 추적

**주요 내용**:
- Scrape → Agent → Remote Write → Receiver
- Receiver → Prometheus → S3
- Query 경로 (실시간 vs 히스토리컬)
- WAL 버퍼링 및 재전송
- 압축 및 Downsampling

**대상 독자**: 아키텍트, SRE

---

### 고가용성-설계.md
**목적**: HA 구성 전략

**주요 내용**:
- Prometheus HA (Replica)
- Thanos Receiver HA (Hashring)
- Alertmanager HA (Gossip)
- 중복 제거 (Deduplication)
- 장애 시나리오 및 복구

**대상 독자**: SRE, 아키텍트

---

### 멀티테넌시-아키텍처.md
**목적**: 가 클러스터의 노드 멀티테넌시 설계

**주요 내용**:
- 노드 라벨링 전략
- Tenant별 Prometheus Agent 분리
- 메트릭 격리 및 레이블링
- ResourceQuota 및 LimitRange
- NetworkPolicy 격리

**대상 독자**: 멀티테넌시 담당자, 클러스터 관리자

---

## 🎯 학습 경로

### 초급
1. **전체-시스템-아키텍처.md** - 전체 그림 파악
2. **Agent-vs-Full-Prometheus.md** - Agent Mode 이해
3. **데이터-흐름.md** - 메트릭 여정 추적

### 중급
1. **Thanos-Receiver-패턴.md** - Receiver 심화 학습
2. **고가용성-설계.md** - HA 구성 이해

### 고급
1. **멀티테넌시-아키텍처.md** - 멀티테넌시 설계
2. **[07-확장-아키텍처](../07-확장-아키텍처/)** - 대규모 확장

---

## 🔗 관련 섹션

- **배포** → [02-Kustomize-Helm-GitOps-배포](../02-Kustomize-Helm-GitOps-배포/)
- **운영** → [03-운영-가이드](../03-운영-가이드/)
- **모니터링** → [04-모니터링-가이드](../04-모니터링-가이드/)
- **멀티테넌시** → [05-멀티테넌시-구성](../05-멀티테넌시-구성/)

---

**최종 업데이트**: 2025-10-20
