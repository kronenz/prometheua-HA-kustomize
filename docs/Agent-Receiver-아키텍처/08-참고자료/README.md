# 08. 참고자료

## 📋 개요

Prometheus Agent + Thanos Receiver 아키텍처 구축 및 운영에 필요한 공식 문서, 커뮤니티 리소스, 도구, FAQ를 모아둔 참고 자료집입니다.

---

## 📂 문서 목록

### 공식-문서-링크.md
**목적**: 공식 문서 및 가이드 모음

**주요 내용**:
- Prometheus 공식 문서
- Thanos 공식 문서
- Kubernetes 공식 문서
- ArgoCD 문서
- Grafana 문서
- OpenSearch 문서

**대상 독자**: 모든 사용자

---

### Helm-Chart-Reference.md
**목적**: 사용 중인 Helm Chart 버전 및 참조

**주요 내용**:
- kube-prometheus-stack Chart
- prometheus-community/prometheus Chart
- opensearch Helm Chart
- fluent/fluent-bit Chart
- ArgoCD Chart
- values.yaml 주요 옵션

**대상 독자**: DevOps 엔지니어

---

### Kustomize-패턴.md
**목적**: Kustomize 베스트 프랙티스 및 패턴

**주요 내용**:
- Base vs Overlay 전략
- Helm Chart 통합
- 환경별 패치
- ConfigMap/Secret Generator
- 재사용 가능한 컴포넌트

**대상 독자**: Kustomize 사용자

---

### 커뮤니티-리소스.md
**목적**: 유용한 커뮤니티 블로그, GitHub 예제

**주요 내용**:
- Thanos GitHub Issues/Discussions
- CNCF Slack 채널
- Medium/Dev.to 블로그 포스트
- GitHub Example Repos
- Conference Talks (KubeCon 등)

**대상 독자**: 학습자, 문제 해결자

---

### FAQ.md
**목적**: 자주 묻는 질문과 답변

**주요 내용**:
- Remote Write가 실패하는 경우
- Grafana에서 메트릭이 보이지 않는 경우
- ArgoCD Sync 실패 해결
- S3 연결 문제
- 성능 튜닝 질문

**대상 독자**: 모든 운영자

---

### 용어-사전.md
**목적**: 주요 용어 및 개념 정의

**주요 내용**:
- Prometheus Agent Mode
- Thanos Receiver, Query, Store, Compactor
- Remote Write, WAL
- Hashring, Replication Factor
- TSDB, Exemplar

**대상 독자**: 초보자, 신규 팀원

---

### 버전-이력.md
**목적**: 사용 중인 컴포넌트 버전 및 변경 이력

**주요 내용**:
- Prometheus 버전
- Thanos 버전
- Grafana 버전
- Kubernetes 버전
- 주요 업그레이드 노트

**대상 독자**: 버전 관리자

---

### 트러블슈팅-가이드.md
**목적**: 일반적인 문제 및 해결책 모음

**주요 내용**:
- Remote Write 타임아웃
- Receiver OOMKilled
- Grafana 느린 쿼리
- ArgoCD Application OutOfSync
- 디버깅 팁

**대상 독자**: 운영자, SRE

---

## 📚 공식 문서

### Prometheus
- **공식 사이트**: https://prometheus.io
- **Agent Mode**: https://prometheus.io/docs/prometheus/latest/feature_flags/#prometheus-agent
- **Remote Write**: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write

### Thanos
- **공식 사이트**: https://thanos.io
- **Receiver**: https://thanos.io/tip/components/receive.md/
- **Query**: https://thanos.io/tip/components/query.md/
- **Store**: https://thanos.io/tip/components/store.md/
- **Compactor**: https://thanos.io/tip/components/compact.md/

### Kubernetes
- **공식 사이트**: https://kubernetes.io
- **Kustomize**: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/
- **NetworkPolicy**: https://kubernetes.io/docs/concepts/services-networking/network-policies/

### ArgoCD
- **공식 사이트**: https://argo-cd.readthedocs.io
- **Application of Applications**: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/

### Grafana
- **공식 사이트**: https://grafana.com/docs/grafana/latest/
- **Datasources**: https://grafana.com/docs/grafana/latest/datasources/prometheus/

---

## 🎯 Helm Chart 버전

### kube-prometheus-stack
- **Chart 버전**: 58.0.0
- **Artifact Hub**: https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack
- **Repository**: https://github.com/prometheus-community/helm-charts

### prometheus (Agent Mode)
- **Chart 버전**: 25.11.0
- **Artifact Hub**: https://artifacthub.io/packages/helm/prometheus-community/prometheus
- **values.yaml 옵션**: `server.enableAgentMode: true`

### opensearch
- **Chart 버전**: 2.18.0
- **Artifact Hub**: https://artifacthub.io/packages/helm/opensearch-project-helm-charts/opensearch
- **Repository**: https://github.com/opensearch-project/helm-charts

### fluent-bit
- **Chart 버전**: 0.43.0
- **Artifact Hub**: https://artifacthub.io/packages/helm/fluent/fluent-bit
- **Repository**: https://github.com/fluent/helm-charts

---

## 💡 Kustomize 패턴

### Base + Overlay 구조
```
deploy/
├── base/
│   ├── kube-prometheus-stack/
│   │   ├── kustomization.yaml
│   │   └── values.yaml
│   └── prometheus-agent/
│       ├── kustomization.yaml
│       └── values.yaml
└── overlays/
    ├── cluster-01-central/
    │   └── kube-prometheus-stack/
    │       ├── kustomization.yaml
    │       ├── thanos-receiver.yaml
    │       └── patches.yaml
    └── cluster-02-edge/
        └── prometheus-agent/
            ├── kustomization.yaml
            └── remote-write-patch.yaml
```

### Helm Chart 통합 예시
```yaml
# kustomization.yaml
helmCharts:
- name: kube-prometheus-stack
  repo: https://prometheus-community.github.io/helm-charts
  version: 58.0.0
  releaseName: kube-prometheus-stack
  namespace: monitoring
  valuesFile: values.yaml
```

---

## 🌐 커뮤니티 리소스

### GitHub Repositories
- **Thanos Examples**: https://github.com/thanos-io/thanos/tree/main/examples
- **Prometheus Operator**: https://github.com/prometheus-operator/prometheus-operator
- **ArgoCD Examples**: https://github.com/argoproj/argocd-example-apps

### CNCF Slack
- **#thanos**: https://cloud-native.slack.com/archives/CL25937SP
- **#prometheus**: https://cloud-native.slack.com/archives/C01LC3TCV1B
- **#argocd**: https://cloud-native.slack.com/archives/C0134KT6HSR

### 블로그 포스트
- **Thanos Receiver Tutorial**: https://www.infracloud.io/blogs/thanos-ha-scalable-prometheus/
- **Prometheus Agent Mode**: https://prometheus.io/blog/2021/11/16/agent/
- **GitOps with ArgoCD**: https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/

---

## ❓ FAQ

### Q1: Remote Write가 계속 실패합니다
**A**: 다음을 확인하세요:
1. Thanos Receiver endpoint가 정확한지 (`kubectl get svc -n monitoring`)
2. NetworkPolicy가 차단하고 있지 않은지
3. TLS 설정이 맞는지 (self-signed 인증서 사용 시 `insecure_skip_verify`)
4. Receiver 로그 확인 (`kubectl logs -n monitoring deployment/thanos-receive`)

### Q2: Grafana에서 특정 클러스터 메트릭이 보이지 않습니다
**A**:
1. Prometheus Agent가 Remote Write 중인지 확인:
   ```bash
   kubectl logs -n monitoring prometheus-agent-0 | grep "remote_write"
   ```
2. Thanos Query에서 해당 클러스터 메트릭 확인:
   ```promql
   up{cluster="cluster-02"}
   ```
3. 클러스터 레이블이 올바르게 설정되었는지 확인

### Q3: ArgoCD Application이 OutOfSync 상태입니다
**A**:
1. Git 저장소 변경사항 확인
2. `argocd app diff <app-name>`로 차이점 확인
3. 수동 Sync: `argocd app sync <app-name>`
4. Sync 정책이 Auto로 설정되어 있는지 확인

### Q4: Thanos Receiver가 OOMKilled 됩니다
**A**:
1. Memory 리소스 증설 (2Gi → 4Gi)
2. Remote Write rate 제한 설정
3. Receiver replica 증가 (Hashring 활용)
4. 메트릭 필터링으로 불필요한 메트릭 제외

---

## 📖 용어 사전

### Prometheus Agent Mode
Prometheus의 경량 모드로, 로컬 쿼리 및 알림 평가를 비활성화하고 Remote Write만 수행. 메모리 사용량 ~80% 감소.

### Thanos Receiver
Remote Write 프로토콜로 메트릭을 수신하고 Prometheus TSDB 형식으로 저장하는 Thanos 컴포넌트.

### Hashring
Thanos Receiver의 수평 확장을 위한 Consistent Hashing 메커니즘. 테넌트 또는 시계열을 여러 Receiver에 분산.

### Remote Write
Prometheus가 메트릭을 외부 시스템으로 전송하는 프로토콜 (HTTP/HTTPS).

### WAL (Write-Ahead Log)
Prometheus가 메트릭을 디스크에 쓰기 전에 임시 저장하는 로그. Remote Write 실패 시 재전송에 사용.

### Replication Factor
Thanos Receiver에서 메트릭을 여러 replica에 복제하는 수. 기본값 1, HA 구성 시 3 권장.

### TSDB (Time Series Database)
시계열 데이터 저장에 최적화된 데이터베이스. Prometheus가 사용하는 스토리지 엔진.

---

## 🔧 주요 도구

### kubectl Plugins
```bash
# krew 설치
kubectl krew install ctx ns view-secret tail

# 사용 예시
kubectl ctx cluster-01
kubectl ns monitoring
kubectl view-secret grafana-admin-secret -a
kubectl tail -l app=thanos-receive
```

### promtool
```bash
# Prometheus config 검증
promtool check config prometheus.yml

# PromQL 쿼리 테스트
promtool query instant http://localhost:9090 'up'
```

### thanos CLI
```bash
# TSDB 검사
thanos tools bucket inspect --objstore.config-file=s3.yml

# Compactor 실행 (수동)
thanos compact --objstore.config-file=s3.yml --data-dir=/data
```

---

## 🔗 관련 섹션

- **아키텍처** → [01-아키텍처](../01-아키텍처/)
- **배포** → [02-Kustomize-Helm-GitOps-배포](../02-Kustomize-Helm-GitOps-배포/)
- **운영 가이드** → [03-운영-가이드](../03-운영-가이드/)

---

**최종 업데이트**: 2025-10-20
