# Agent vs Full Prometheus 비교

## 📋 개요

Prometheus Agent Mode와 Full Prometheus의 차이점, 사용 사례, 성능 비교를 통해 엣지 클러스터에 Agent Mode를 선택한 이유를 설명합니다.

---

## 🔍 주요 차이점

| 기능 | **Prometheus Agent** | **Full Prometheus** |
|------|---------------------|-------------------|
| **로컬 쿼리 API** | ❌ 비활성화 | ✅ 활성화 (`:9090/api/v1/query`) |
| **Alert Rules** | ❌ 비활성화 | ✅ 활성화 |
| **Recording Rules** | ❌ 비활성화 | ✅ 활성화 |
| **Remote Write** | ✅ 활성화 (주 기능) | ✅ 활성화 (선택적) |
| **TSDB 보존** | ❌ 로컬 저장 없음 (WAL만) | ✅ 로컬 TSDB (기본 15d) |
| **메모리 사용량** | ~200MB | ~2GB (10x) |
| **디스크 사용량** | ~5GB (WAL) | ~50GB (TSDB) |
| **CPU 사용량** | ~0.2 cores | ~1 core |
| **사용 사례** | 엣지, IoT, Remote Write 전용 | 중앙 모니터링, 로컬 쿼리 |

---

## 🎯 Prometheus Agent Mode

### 개념
- Prometheus v2.32.0부터 도입된 **경량 모드**
- `--enable-feature=agent` 플래그로 활성화
- **목적**: Remote Write 전용, 로컬 쿼리/저장 제거

### 활성화된 기능
- ✅ **Service Discovery**: Kubernetes SD, File SD 등
- ✅ **Scraping**: Target 메트릭 수집
- ✅ **Remote Write**: 외부 시스템으로 전송
- ✅ **WAL (Write-Ahead Log)**: 재전송 보장

### 비활성화된 기능
- ❌ HTTP Query API (`/api/v1/query`)
- ❌ Alert Rules 평가
- ❌ Recording Rules 평가
- ❌ 로컬 TSDB 저장
- ❌ Admin API

### 설정 예시
```yaml
# values.yaml (prometheus chart)
server:
  enableAgentMode: true
  remoteWrite:
    - url: https://thanos-receive.monitoring.svc.cluster.local:19291/api/v1/receive
      queueConfig:
        capacity: 10000
        maxShards: 50
        minShards: 1
        maxSamplesPerSend: 5000
        batchSendDeadline: 5s
```

---

## 🔧 Full Prometheus

### 개념
- 전통적인 Prometheus 서버
- 로컬 TSDB에 메트릭 저장 + 쿼리 API 제공
- Alert Rules 및 Recording Rules 평가

### 주요 기능
- ✅ **로컬 쿼리**: PromQL 쿼리 API 제공
- ✅ **Alerting**: Prometheus → Alertmanager
- ✅ **Recording Rules**: 사전 계산된 메트릭 생성
- ✅ **장기 보존**: 로컬 TSDB (설정 가능)
- ✅ **Federation**: 다른 Prometheus 서버와 연동

### 사용 사례
- 중앙 모니터링 클러스터
- 로컬 대시보드가 필요한 환경
- Alert Rules 로컬 평가
- 독립적인 모니터링 (Remote Write 없이)

### 설정 예시
```yaml
# values.yaml (kube-prometheus-stack)
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 100Gi
    alerting:
      alertmanagers:
      - name: alertmanager-operated
        namespace: monitoring
        port: web
```

---

## 📊 성능 비교

### 리소스 사용량 (동일 워크로드)

#### 테스트 환경
- **Target 수**: 100개
- **Scrape Interval**: 15s
- **Metrics/Scrape**: 약 1000개
- **시계열 수**: ~100,000

#### Agent Mode
```
CPU: 0.2 cores (avg)
Memory: 180MB (avg), 250MB (peak)
Disk: 5GB (WAL)
Network Egress: 10MB/s (Remote Write)
```

#### Full Prometheus
```
CPU: 1.0 cores (avg)
Memory: 2GB (avg), 4GB (peak)
Disk: 50GB (15d retention)
Network Egress: 10MB/s (Remote Write, 선택적)
```

### 메모리 사용량 그래프

```
Memory Usage Over Time

4GB   │                    ┌─────Full Prometheus
      │                ┌───┘
3GB   │            ┌───┘
      │        ┌───┘
2GB   │    ┌───┘
      │┌───┘
1GB   │
      │
250MB │─────────────────────Agent Mode
      │
0     └────────────────────────────────────
      0h   6h   12h  18h  24h
```

---

## 🚀 사용 사례별 선택 가이드

### ✅ Agent Mode 선택
- **엣지 클러스터**: 리소스 제약이 있는 환경
- **IoT 디바이스**: Raspberry Pi, ARM 기반 디바이스
- **멀티클러스터**: 중앙집중식 모니터링 (Thanos Receiver)
- **비용 절감**: 클라우드 환경에서 리소스 비용 최소화

### ✅ Full Prometheus 선택
- **중앙 모니터링**: 단일 클러스터 모니터링
- **로컬 쿼리 필요**: Grafana가 로컬에 있는 경우
- **Alert Rules**: 로컬에서 알림 평가 필요
- **Recording Rules**: 사전 계산 메트릭 필요
- **독립 운영**: Remote Write 없이 독립적으로 운영

---

## 🔄 마이그레이션

### Full Prometheus → Agent Mode

#### 1. 기존 Prometheus 설정 백업
```bash
kubectl get prometheus -n monitoring -o yaml > prometheus-backup.yaml
```

#### 2. Agent Mode 배포
```yaml
# prometheus-agent-values.yaml
server:
  enableAgentMode: true
  retention: ""  # Agent는 retention 불필요

  remoteWrite:
    - url: https://thanos-receive.central.svc:19291/api/v1/receive
      remoteTimeout: 30s

  # Alert/Recording Rules 제거
  alerting: {}
  rules: {}
```

#### 3. ServiceMonitor/PodMonitor 마이그레이션
```bash
# 기존 ServiceMonitor 그대로 사용 가능
kubectl get servicemonitor -n monitoring
```

#### 4. Remote Write 검증
```bash
# Agent 로그 확인
kubectl logs -n monitoring prometheus-agent-0 | grep remote_write

# Receiver에서 메트릭 확인
kubectl exec -n monitoring thanos-query-0 -- \
  curl -s "http://localhost:9090/api/v1/query?query=up{cluster=\"cluster-02\"}"
```

#### 5. 기존 Prometheus 제거
```bash
kubectl delete prometheus -n monitoring kube-prometheus-stack-prometheus
```

---

## 💡 Agent Mode 최적화 팁

### 1. WAL 크기 제한
```yaml
server:
  extraArgs:
    storage.agent.path: /data
    storage.agent.wal-compression: true
    storage.agent.retention.max-time: 4h  # Remote Write 실패 대비
```

### 2. Remote Write 큐 튜닝
```yaml
server:
  remoteWrite:
    - url: https://thanos-receive:19291/api/v1/receive
      queueConfig:
        capacity: 20000           # 큐 용량 증가
        maxShards: 100            # 병렬 전송 증가
        minShards: 10
        maxSamplesPerSend: 10000  # 배치 크기 증가
        batchSendDeadline: 10s    # 배치 대기 시간
        minBackoff: 30ms
        maxBackoff: 5s
```

### 3. 메트릭 필터링 (불필요한 메트릭 제외)
```yaml
server:
  remoteWrite:
    - url: https://thanos-receive:19291/api/v1/receive
      writeRelabelConfigs:
      # 고빈도/저가치 메트릭 제외
      - sourceLabels: [__name__]
        regex: 'go_gc_duration_seconds_.*|go_memstats_.*'
        action: drop

      # 특정 네임스페이스만 포함
      - sourceLabels: [namespace]
        regex: 'kube-system|monitoring|default'
        action: keep
```

### 4. 리소스 제한 설정
```yaml
server:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  persistentVolume:
    size: 10Gi  # WAL 전용
```

---

## 🔗 관련 문서

- **전체 시스템 아키텍처** → [전체-시스템-아키텍처.md](./전체-시스템-아키텍처.md)
- **Thanos Receiver 패턴** → [Thanos-Receiver-패턴.md](./Thanos-Receiver-패턴.md)
- **성능 최적화** → [../09-성능-최적화/](../09-성능-최적화/)

---

## 📚 참고 자료

- [Prometheus Agent Mode 공식 문서](https://prometheus.io/docs/prometheus/latest/feature_flags/#prometheus-agent)
- [Prometheus Remote Write Specification](https://prometheus.io/docs/prometheus/latest/storage/#remote-storage-integrations)

---

**최종 업데이트**: 2025-10-20
