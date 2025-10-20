# Thanos 멀티클러스터 모니터링 시스템 문서

## 개요

이 문서는 4개의 Kubernetes 클러스터에 배포된 Thanos 멀티클러스터 모니터링 시스템에 대한 완전한 가이드를 제공합니다.

## 시스템 구성

- **중앙 클러스터 (cluster-01)**: 192.168.101.194
  - Prometheus HA (2 replicas)
  - Thanos Query, Store, Compactor, Ruler
  - Grafana
  - AlertManager HA

- **Edge 클러스터 (cluster-02/03/04)**: 192.168.101.196/197/198
  - Prometheus (1 replica per cluster)
  - Thanos Sidecar

- **S3 스토리지**: MinIO (s3.minio.miribit.lab)
  - 모든 메트릭 데이터 장기 저장
  - 데이터 보존: Raw 7일, 5m 30일, 1h 90일

## 문서 구조

### 1. [아키텍처 문서](./ARCHITECTURE.md)

시스템의 전체 아키텍처, 컴포넌트 설명, 데이터 흐름을 이해하기 위한 문서입니다.

**주요 내용**:
- 전체 아키텍처 다이어그램 (Mermaid)
- 각 Thanos 컴포넌트 상세 설명
- 데이터 흐름 및 보존 정책
- 네트워크 구성 및 LoadBalancer IP 할당
- 고가용성 (HA) 구성
- 외부 라벨 및 멀티클러스터 쿼리

**대상 독자**: 시스템 아키텍트, 신규 팀원

### 2. [배포 가이드](./DEPLOYMENT_GUIDE.md)

시스템을 처음부터 설치하고 배포하는 단계별 가이드입니다.

**주요 내용**:
- 사전 요구사항 및 준비 작업
- Longhorn 스토리지 설치
- Cilium LoadBalancer 설정
- Prometheus Stack 배포 (중앙 + Edge)
- Thanos 컴포넌트 배포
- 검증 및 확인 절차
- 배포 플로우차트

**대상 독자**: DevOps 엔지니어, 시스템 관리자

### 3. [트러블슈팅 가이드](./TROUBLESHOOTING.md)

시스템 운영 중 발생할 수 있는 문제와 해결 방법을 다룹니다.

**주요 내용**:
- 일반적인 문제 (Pod Pending, CrashLoopBackOff)
- Prometheus 관련 문제 (메트릭 수집 실패, TSDB 손상)
- Thanos 컴포넌트 문제 (Sidecar 업로드 실패, Query 연결 문제)
- 네트워크 및 연결 문제 (LoadBalancer, Ingress)
- 스토리지 문제 (Longhorn, PVC)
- 성능 문제 및 최적화
- 로그 분석 방법
- 긴급 복구 절차

**대상 독자**: 운영 팀, On-call 엔지니어

### 4. [운영 매뉴얼](./OPERATIONS.md)

일상적인 운영 작업과 유지보수 절차를 설명합니다.

**주요 내용**:
- 일상 운영 작업 (매일/주간/월간/분기별)
- 모니터링 체크리스트 및 주요 메트릭
- 정기 유지보수 절차
- 스케일링 방법 (수평/수직)
- 업그레이드 절차 (Thanos, kube-prometheus-stack)
- 백업 및 복구 전략
- 보안 관리 및 접근 제어
- 용량 관리 및 최적화
- 알럿 정책

**대상 독자**: 시스템 운영자, SRE

## 빠른 시작

### 새로운 배포

시스템을 처음 설치하는 경우:

1. [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) 읽기
2. 사전 요구사항 확인
3. 단계별 배포 수행
4. 검증 체크리스트 완료

### 문제 해결

시스템에 문제가 발생한 경우:

1. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)에서 증상 검색
2. 해당 섹션의 해결 방법 따라하기
3. 로그 수집 및 분석
4. 필요 시 에스컬레이션

### 일상 운영

시스템을 운영하는 경우:

1. [OPERATIONS.md](./OPERATIONS.md)의 체크리스트 사용
2. 정기 유지보수 스케줄 준수
3. 알럿 및 메트릭 모니터링
4. 백업 정책 유지

## 주요 접속 정보

### 웹 인터페이스

| 서비스 | URL | 사용자명 | 비밀번호 |
|--------|-----|----------|----------|
| Grafana | http://grafana.k8s-cluster-01.miribit.lab | admin | admin123 |
| MinIO Console | http://console.minio.miribit.lab | minio | minio123 |

### 클러스터 접속

```bash
# cluster-01 (중앙)
ssh bsh@192.168.101.194
export KUBECONFIG=~/.kube/configs/cluster-01.conf

# cluster-02 (edge)
ssh bsh@192.168.101.196
export KUBECONFIG=~/.kube/configs/cluster-02.conf

# cluster-03 (edge)
ssh bsh@192.168.101.197
export KUBECONFIG=~/.kube/configs/cluster-03.conf

# cluster-04 (edge)
ssh bsh@192.168.101.198
export KUBECONFIG=~/.kube/configs/cluster-04.conf
```

### 주요 네임스페이스

- `monitoring`: 모든 Prometheus 및 Thanos 컴포넌트
- `longhorn-system`: Longhorn 스토리지 시스템
- `kube-system`: Kubernetes 시스템 컴포넌트 (Cilium 포함)

## 빠른 상태 확인

### 모든 클러스터 Pod 상태

```bash
for config in cluster-01 cluster-02 cluster-03 cluster-04; do
  echo "=== $config ==="
  export KUBECONFIG=~/.kube/configs/$config.conf
  kubectl get pods -n monitoring
done
```

### Thanos Query Store 연결

```bash
export KUBECONFIG=~/.kube/configs/cluster-01.conf
kubectl logs -n monitoring deployment/thanos-query --tail=50 | grep "adding new"
```

예상 출력: 7개 연결 (중앙 2 + edge 3 + store 1 + ruler 1)

### S3 업로드 확인

```bash
export KUBECONFIG=~/.kube/configs/cluster-01.conf
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 thanos-sidecar --tail=10 | \
  grep -E "uploaded|shipper"
```

### Grafana 접속 테스트

```bash
curl -I http://grafana.k8s-cluster-01.miribit.lab
# HTTP/1.1 200 OK 예상
```

## 주요 디렉토리 구조

```
/root/develop/thanos/
├── deploy/
│   ├── base/
│   │   └── kube-prometheus-stack/
│   │       ├── thanos-s3-secret.yaml
│   │       └── ...
│   └── overlays/
│       ├── cluster-01-central/
│       │   ├── longhorn/
│       │   └── kube-prometheus-stack/
│       │       ├── kustomization.yaml
│       │       ├── thanos-query.yaml
│       │       ├── thanos-store.yaml
│       │       ├── thanos-compactor.yaml
│       │       └── thanos-ruler.yaml
│       ├── cluster-02-edge/
│       ├── cluster-03-edge/
│       └── cluster-04-edge/
├── docs/
│   ├── README.md (이 파일)
│   ├── ARCHITECTURE.md
│   ├── DEPLOYMENT_GUIDE.md
│   ├── TROUBLESHOOTING.md
│   └── OPERATIONS.md
└── scripts/
    ├── deploy-component.sh
    ├── validate-deployment.sh
    └── ...
```

## 유용한 명령어

### Prometheus PromQL 쿼리

```bash
# Prometheus UI 포트 포워딩
export KUBECONFIG=~/.kube/configs/cluster-01.conf
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# 브라우저에서 http://localhost:9090 접속
```

### Thanos Query API

```bash
# Thanos Query UI 포트 포워딩
kubectl port-forward -n monitoring svc/thanos-query 9090:9090

# Store 엔드포인트 확인
curl http://localhost:9090/api/v1/stores | jq .
```

### 로그 스트리밍

```bash
# 모든 Thanos 컴포넌트 로그
kubectl logs -n monitoring -l app.kubernetes.io/component=thanos -f --prefix=true

# Prometheus 로그
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 prometheus -f

# Thanos Sidecar 로그
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 thanos-sidecar -f
```

### 메트릭 확인

```bash
# Thanos Query 메트릭
kubectl exec -n monitoring deployment/thanos-query -- \
  wget -qO- http://localhost:10902/metrics | grep thanos_store_nodes

# Prometheus 메트릭
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  wget -qO- http://localhost:9090/metrics | grep prometheus_tsdb
```

## 시스템 요구사항 요약

| 구분 | 사양 |
|------|------|
| **Kubernetes** | v1.34.1 |
| **CNI** | Cilium v1.18.2 |
| **스토리지** | Longhorn v1.7.2 |
| **Prometheus** | kube-prometheus-stack v78.2.1 |
| **Thanos** | v0.37.2 |
| **S3** | MinIO (HTTP) |
| **총 클러스터 수** | 4개 |
| **총 노드 수** | 4개 (각 클러스터 1노드) |

## 데이터 보존 정책

| Resolution | 보존 기간 | 저장 위치 |
|------------|----------|----------|
| Raw (15s) | 2시간 | Prometheus 로컬 TSDB |
| Raw (15s) | 7일 | S3 (Thanos) |
| 5분 | 30일 | S3 (Thanos Compactor) |
| 1시간 | 90일 | S3 (Thanos Compactor) |

## 주요 메트릭 및 알럿

### 핵심 메트릭

1. `up{job="prometheus"}` - Prometheus 상태
2. `thanos_store_nodes_grpc_connections` - Thanos Query 연결 수
3. `thanos_objstore_bucket_operations_total` - S3 작업 수
4. `prometheus_tsdb_storage_blocks_bytes` - TSDB 스토리지 사용량

### 중요 알럿

1. **ThanosSidecarNoUpload** - 2시간 동안 S3 업로드 없음
2. **ThanosQueryStoreUnhealthy** - Store 연결 수 부족
3. **PrometheusTargetDown** - 메트릭 수집 타겟 Down
4. **PVCNearFull** - PVC 사용량 85% 이상

## 성능 지표

### 정상 운영 시 예상 값

- **Prometheus Scrape Duration**: < 1s (p99)
- **Thanos Query Response Time**: < 5s (p99)
- **S3 Upload Interval**: 2시간마다
- **Compaction Interval**: 3분마다
- **Store gRPC Connections**: 7개

## 라이선스 및 저작권

이 문서는 내부 사용을 위한 것입니다.

## 기여 및 피드백

문서 개선 사항이나 오류 발견 시:
1. Issue 생성 (내부 이슈 트래커)
2. Pull Request 제출
3. 팀 미팅에서 논의

## 버전 정보

- **문서 버전**: 1.0
- **작성일**: 2025-01-15
- **최종 업데이트**: 2025-01-15
- **작성자**: DevOps Team

## 추가 리소스

### 공식 문서

- [Thanos Documentation](https://thanos.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Cilium Documentation](https://docs.cilium.io/)

### 커뮤니티

- [Thanos Slack](https://cloud-native.slack.com/) - #thanos 채널
- [Prometheus Community](https://prometheus.io/community/)
- [CNCF Slack](https://slack.cncf.io/)

### 블로그 및 가이드

- [Thanos Architecture Overview](https://thanos.io/tip/thanos/design.md/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Kubernetes Monitoring with Prometheus](https://sysdig.com/blog/kubernetes-monitoring-prometheus/)

---

**문서를 읽어주셔서 감사합니다!**

문제가 발생하거나 도움이 필요하시면 [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)를 참조하거나 운영 팀에 문의하세요.
