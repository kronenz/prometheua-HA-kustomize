# DataOps 플랫폼 모니터링 전문가 회의록

**일시**: 2025-11-05
**참석자**: SRE 전문가, 플랫폼 엔지니어, 데이터 엔지니어
**주제**: 빅데이터 DataOps 플랫폼 End-to-End 모니터링 시스템 설계

---

## 📋 회의 안건

1. 현재 플랫폼 아키텍처 및 복잡도 분석
2. 모니터링 요구사항 정의
3. 대시보드 계층 구조 설계
4. 메트릭 수집 전략
5. SLO 및 알림 정책
6. 구현 로드맵

---

## 🎯 회의 결과

### 1. 플랫폼 복잡도 분석 (SRE 전문가)

**현재 상황**:
```
사용자 Portal
    ↓
[GitOps Layer]
 • Bitbucket (소스 관리)
 • Jenkins (CI 파이프라인)
 • ArgoCD (CD 배포)
    ↓
[Application Layer]
 • Apache Spark (분산 처리)
 • Apache Airflow (워크플로우 오케스트레이션)
 • Trino (분산 SQL 엔진)
    ↓
[Data Lake Layer]
 • Apache Iceberg (테이블 포맷)
 • Hive Metastore (메타데이터 카탈로그)
    ↓
[Storage Layer]
 • S3/MinIO (오브젝트 스토리지)
 • Oracle DB (트랜잭션 DB)
 • Isilon (NAS 스토리지)
 • Ceph (분산 스토리지)
```

**주요 복잡성 요인**:

1. **다층 아키텍처**: 6개 계층이 순차적으로 연결
2. **이기종 스토리지**: S3, Oracle, Isilon, Ceph 혼재
3. **복잡한 데이터 흐름**: Iceberg를 통한 다중 스토리지 접근
4. **분산 처리**: Spark Executor 분산, Trino Worker 분산
5. **상태 관리**: Hive Metastore + Oracle DB 의존성

**SRE 전문가 의견**:
> "이 정도 복잡도라면 단일 대시보드로는 불가능합니다.
> 계층적 드릴다운 구조가 필수이며, 각 계층별로 독립적인
> 모니터링이 필요하면서도 E2E 추적이 가능해야 합니다."

---

### 2. 모니터링 요구사항 정의 (플랫폼 엔지니어)

#### 2.1 사용자 관점 요구사항

| 사용자 유형 | 주요 관심사 | 필요 메트릭 |
|------------|-----------|-----------|
| **데이터 엔지니어** | - 내 Job이 실패했는가?<br/>- 왜 느린가?<br/>- 리소스가 부족한가? | Job 상태, 실행 시간, 에러 로그 |
| **플랫폼 운영자** | - 전체 시스템이 정상인가?<br/>- 리소스가 부족한가?<br/>- 어디서 병목이 발생하는가? | 가용성, 리소스 사용률, 병목 구간 |
| **SRE** | - SLO를 준수하는가?<br/>- Error Budget은?<br/>- 장애 예측은? | SLI/SLO, Error Budget, 예측 모델 |
| **경영진** | - 플랫폼 활용도는?<br/>- 비용은 적절한가?<br/>- ROI는? | 처리량, 비용, 활용도 |

#### 2.2 계층별 모니터링 요구사항

**Layer 1: GitOps 배포 파이프라인**
```
목표: 배포가 정상적으로 완료되었는가?

Critical Metrics:
1. Jenkins 빌드 성공률 (목표: > 95%)
2. ArgoCD Sync 상태 (목표: Healthy)
3. Pod Readiness (목표: 100%)
4. 배포 소요 시간 (목표: < 10분)

Alert 조건:
- 빌드 실패 3회 연속
- ArgoCD Out of Sync > 5분
- Pod CrashLoopBackOff
```

**Layer 2: 리소스 가용량**
```
목표: 워크로드 실행에 충분한 리소스가 있는가?

Critical Metrics:
1. CPU 가용량 (목표: > 20% 여유)
2. 메모리 가용량 (목표: > 15% 여유)
3. 스토리지 용량 (목표: < 80% 사용)
4. 네트워크 대역폭 (목표: < 70% 사용)

Alert 조건:
- CPU 사용률 > 85%
- 메모리 사용률 > 90%
- 스토리지 > 85%
- OOM Kill 발생
```

**Layer 3: 워크로드 실행**
```
목표: Job이 정상적으로 실행되고 완료되는가?

Spark Metrics:
1. Active Jobs
2. Failed Jobs (목표: < 2% in 24h)
3. Stage Duration (P95 < SLA)
4. Executor Memory Usage
5. GC Time Ratio (목표: < 10%)

Airflow Metrics:
1. DAG Run Success Rate (목표: > 95%)
2. Task Duration (P95 < SLA)
3. Scheduler Lag (목표: < 30s)
4. Worker Availability

Trino Metrics:
1. Query Success Rate (목표: > 99%)
2. Query Wall Time (P95 < 10m)
3. Worker Node Count
4. Memory Pool Usage

Alert 조건:
- Job 실패율 > 5%
- 실행 시간 > SLA + 50%
- GC Time > 20%
```

**Layer 4: 데이터 파이프라인**
```
목표: 데이터가 올바르게 저장/읽기되는가?

Iceberg Metrics:
1. Table Metadata Size
2. Snapshot Count (목표: < 100)
3. Small Files Ratio (목표: < 30%)
4. Compaction Pending

S3/MinIO Metrics:
1. GET/PUT Latency (목표: < 100ms)
2. Error Rate (목표: < 0.1%)
3. Throughput

Hive Metastore Metrics:
1. Response Time (목표: < 1s)
2. Connection Pool (목표: < 80%)
3. Lock Wait Time

Oracle DB Metrics:
1. Connection Pool (목표: < 90%)
2. Query Duration (목표: < 5s)
3. Tablespace Usage (목표: < 85%)

Alert 조건:
- S3 Error Rate > 1%
- Metastore Response > 3s
- Oracle Tablespace > 90%
```

**Layer 5: 최적화 & 트러블슈팅**
```
목표: 성능 문제를 사전에 식별하고 해결하는가?

Performance Metrics:
1. Slow Queries (> P95)
2. Long Running Jobs (> SLA)
3. Failed Tasks by Error Type
4. Resource Idle Rate

Cost Metrics:
1. Compute Cost Trend
2. Storage Cost Trend
3. Over-provisioned Resources
4. Idle Resource Ratio

Alert 조건:
- Slow Query Count > 10 in 1h
- Cost Increase > 20% WoW
- Idle Rate > 30%
```

**Layer 6: End-to-End**
```
목표: 전체 파이프라인이 SLO를 준수하는가?

E2E Metrics:
1. Pipeline Completion Time (Portal → Data)
2. Data Processing Latency (P50/P95/P99)
3. Overall Success Rate
4. Data Volume Processed

SLI/SLO:
- Availability: 99.9% (43분 downtime/month)
- Latency: P95 < 1 hour
- Success Rate: > 98%
- Error Budget: 0.1%

Alert 조건:
- Availability < 99.9%
- Error Budget 소진 > 50%
```

---

### 3. 대시보드 계층 구조 설계 (종합)

#### 3.1 Information Architecture

```
Level 0: Main Navigation Hub
├── Quick Status (4개 핵심 메트릭)
└── 6개 도메인 카드 (클릭 가능)

Level 1: Domain Dashboards (6개)
├── 1. GitOps Deployment Pipeline
├── 2. Resource Capacity Planning
├── 3. Workload Execution Monitoring
├── 4. Data Pipeline Health
├── 5. Optimization & Troubleshooting
└── 6. End-to-End Analytics

Level 2: Detailed Drill-down
├── Specific Job/Query Details
├── Resource Timeline
├── Error Analysis
└── Log Correlation
```

#### 3.2 UX/UI 설계 원칙

**플랫폼 엔지니어 제안**:

1. **3-Click Rule**:
   - 모든 정보는 메인에서 최대 3번 클릭으로 도달

2. **Color Coding**:
   ```
   Green: 정상 (>= SLO)
   Yellow: 주의 (80-99% SLO)
   Orange: 경고 (70-79% SLO)
   Red: 위험 (< 70% SLO)
   ```

3. **Progressive Disclosure**:
   - Level 0: 전체 상태 (Green/Red)
   - Level 1: 도메인별 상세
   - Level 2: 개별 메트릭 + 로그

4. **Contextual Navigation**:
   - 각 패널에서 관련 대시보드로 직접 이동
   - Breadcrumb Navigation

5. **Time Range Consistency**:
   - 모든 대시보드에서 동일한 시간 범위 유지
   - URL 파라미터로 전달

---

### 4. 메트릭 수집 전략 (SRE 전문가)

#### 4.1 Exporter 배포 계획

| 컴포넌트 | Exporter 타입 | 배포 방법 | 수집 주기 |
|----------|--------------|----------|----------|
| **Kubernetes** | kube-state-metrics | DaemonSet | 30s |
| **Jenkins** | prometheus-plugin | Plugin | 1m |
| **ArgoCD** | built-in metrics | ServiceMonitor | 30s |
| **Spark** | JMX Exporter | Sidecar | 15s |
| **Airflow** | StatsD → Prometheus | StatsD Exporter | 30s |
| **Trino** | built-in /metrics | ServiceMonitor | 30s |
| **Iceberg** | Custom Exporter | CronJob | 5m |
| **Hive Metastore** | JMX Exporter | Sidecar | 1m |
| **S3/MinIO** | built-in metrics | ServiceMonitor | 1m |
| **Oracle** | oracledb_exporter | Deployment | 1m |
| **Ceph** | ceph-exporter | DaemonSet | 1m |
| **Isilon** | Custom REST API Exporter | Deployment | 5m |

#### 4.2 메트릭 레이블 표준화

```yaml
# 모든 메트릭에 공통 레이블 추가
external_labels:
  cluster: "dataops-prod"
  environment: "production"
  platform: "dataops"

# Application 레이블
relabel_configs:
  - source_labels: [__meta_kubernetes_pod_label_app]
    target_label: application
  - source_labels: [__meta_kubernetes_pod_label_spark_app_id]
    target_label: spark_app_id
  - source_labels: [__meta_kubernetes_pod_label_airflow_dag_id]
    target_label: dag_id
  - source_labels: [__meta_kubernetes_pod_label_trino_query_id]
    target_label: query_id
```

#### 4.3 Recording Rules

```yaml
# 자주 사용되는 복잡한 쿼리를 사전 계산
groups:
  - name: dataops_recording_rules
    interval: 30s
    rules:
      # 전체 플랫폼 가용성
      - record: dataops:platform:availability
        expr: |
          avg(up{job=~"spark.*|airflow.*|trino.*"})

      # Spark Job 성공률 (24시간)
      - record: dataops:spark:success_rate_24h
        expr: |
          sum(increase(spark_job_succeeded_total[24h])) /
          sum(increase(spark_job_total[24h]))

      # 리소스 사용률 (클러스터별)
      - record: dataops:cluster:cpu_usage
        expr: |
          1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))

      - record: dataops:cluster:memory_usage
        expr: |
          1 - (
            sum(node_memory_MemAvailable_bytes) /
            sum(node_memory_MemTotal_bytes)
          )

      # 스토리지 용량 예측 (7일 후)
      - record: dataops:storage:forecast_7d
        expr: |
          predict_linear(
            dataops:storage:usage_bytes[7d], 7*24*3600
          )
```

#### 4.4 메트릭 Retention 정책

| 메트릭 유형 | Raw 데이터 | Downsampled (5m) | Downsampled (1h) |
|------------|-----------|------------------|------------------|
| **인프라** | 15일 | 90일 | 1년 |
| **애플리케이션** | 7일 | 30일 | 90일 |
| **비즈니스** | 30일 | 1년 | 무제한 |

**Thanos 설정**:
```yaml
- retention.resolution-raw: 15d
- retention.resolution-5m: 90d
- retention.resolution-1h: 1y
```

---

### 5. SLO 및 알림 정책 (SRE 전문가)

#### 5.1 SLO 정의

```yaml
# Error Budget 계산
# SLO = 99.9% → Error Budget = 0.1%
# Monthly Error Budget = 43.2분

slos:
  - name: platform_availability
    objective: 99.9
    sli:
      error_rate_ratio:
        total:
          metric: dataops:requests:total
        errors:
          metric: dataops:requests:errors
    window: 30d

  - name: deployment_success_rate
    objective: 95
    sli:
      success_rate:
        good_metric: argocd_app_sync_succeeded
        total_metric: argocd_app_sync_total
    window: 7d

  - name: spark_job_latency
    objective:
      p95: 3600  # 1 hour
    sli:
      latency:
        metric: spark_job_duration_seconds
    window: 24h

  - name: data_pipeline_freshness
    objective:
      max_age: 7200  # 2 hours
    sli:
      freshness:
        metric: iceberg_table_last_update_timestamp
    window: 24h
```

#### 5.2 Multi-Window Alert 전략

```yaml
# Burn Rate 기반 알림
# Fast Burn (1h window) + Slow Burn (6h window)

alerting_rules:
  - alert: ErrorBudgetBurn_Critical
    expr: |
      (
        (1 - dataops:platform:availability) > (14.4 * 0.001)
        and
        (1 - dataops:platform:availability) > (14.4 * 0.001)
      )
    for: 2m
    severity: critical
    annotations:
      summary: "Error Budget 소진 속도가 매우 빠름 (1시간 내 5% 소진)"

  - alert: ErrorBudgetBurn_Warning
    expr: |
      (
        (1 - dataops:platform:availability) > (6 * 0.001)
        and
        (1 - dataops:platform:availability) > (6 * 0.001)
      )
    for: 15m
    severity: warning
    annotations:
      summary: "Error Budget 소진 속도 주의 (6시간 내 5% 소진)"
```

#### 5.3 알림 라우팅

```yaml
route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h

  routes:
    # Critical: 즉시 PagerDuty + Slack
    - match:
        severity: critical
      receiver: pagerduty-critical
      continue: true

    - match:
        severity: critical
      receiver: slack-critical

    # High: Slack + Email
    - match:
        severity: high
      receiver: slack-ops
      continue: true

    - match:
        severity: high
      receiver: email-ops

    # Medium: Slack만
    - match:
        severity: medium
      receiver: slack-ops

receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '<PagerDuty Integration Key>'

  - name: 'slack-critical'
    slack_configs:
      - channel: '#dataops-critical'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'

  - name: 'slack-ops'
    slack_configs:
      - channel: '#dataops-ops'

  - name: 'email-ops'
    email_configs:
      - to: 'dataops-ops@company.com'
```

---

### 6. 구현 로드맵 (플랫폼 엔지니어)

#### Phase 1: Foundation (Week 1-2)

**목표**: 기본 메트릭 수집 및 인프라 구축

**Task List**:
```
Week 1:
□ Prometheus/Thanos 설정 검증
□ ServiceMonitor 생성 (K8s, Spark, Airflow, Trino)
□ JMX Exporter 배포 (Spark, Hive)
□ Recording Rules 정의

Week 2:
□ Custom Exporter 개발 (Iceberg, Isilon)
□ Oracle Exporter 배포
□ 메트릭 검증 및 테스트
□ Grafana Datasource 설정
```

**Deliverables**:
- [ ] 모든 컴포넌트에서 메트릭 수집 확인
- [ ] Prometheus Targets 100% UP
- [ ] Recording Rules 동작 확인

#### Phase 2: Core Dashboards (Week 3-4)

**목표**: Level 0, Level 1 대시보드 개발

**Task List**:
```
Week 3:
□ Main Navigation Dashboard 개발
□ GitOps Pipeline Dashboard 개발
□ Resource Capacity Dashboard 개발

Week 4:
□ Workload Execution Dashboard 개발
□ Data Pipeline Health Dashboard 개발
□ 사용자 피드백 수집 및 개선
```

**Deliverables**:
- [ ] 5개 핵심 대시보드 완성
- [ ] 드릴다운 링크 설정
- [ ] 사용자 테스트 완료

#### Phase 3: Advanced Features (Week 5-6)

**목표**: Level 2 드릴다운, 알림, SLO 대시보드

**Task List**:
```
Week 5:
□ Optimization Dashboard 개발
□ E2E Analytics Dashboard 개발
□ Detailed Drill-down 페이지 개발
□ Alert Rules 설정

Week 6:
□ SLO Dashboard 개발
□ Error Budget Tracking
□ Alert 통합 (PagerDuty, Slack)
□ 문서화 완료
```

**Deliverables**:
- [ ] 전체 대시보드 완성 (Level 0-2)
- [ ] 알림 시스템 가동
- [ ] SLO 모니터링 시작
- [ ] 운영 가이드 문서

#### Phase 4: Optimization & Automation (Week 7-8)

**목표**: 성능 최적화 및 자동화

**Task List**:
```
Week 7:
□ 대시보드 로딩 성능 최적화
□ 쿼리 최적화 (Recording Rules 추가)
□ 자동 리포트 생성 (일간/주간)
□ 용량 예측 모델 구현

Week 8:
□ Auto-remediation Playbook 작성
□ 비용 최적화 권장사항 자동화
□ 대시보드 버전 관리 (Git)
□ 백업 및 DR 계획
```

**Deliverables**:
- [ ] 대시보드 로딩 < 3초
- [ ] 자동 리포트 발송
- [ ] Auto-remediation 3개 이상
- [ ] 전체 시스템 Go-Live

---

### 7. 성공 지표 (Success Metrics)

#### 7.1 기술 지표

| 지표 | 목표 | 측정 방법 |
|------|------|----------|
| **MTTD** (Mean Time to Detect) | < 5분 | 장애 발생 시각 - 알림 수신 시각 |
| **MTTR** (Mean Time to Resolve) | < 30분 | 알림 수신 - 해결 완료 |
| **Alert Accuracy** | > 95% | 유효한 알림 / 전체 알림 |
| **Dashboard Load Time** | < 3초 | Grafana 로드 시간 측정 |

#### 7.2 비즈니스 지표

| 지표 | 목표 | 측정 방법 |
|------|------|----------|
| **사용자 만족도** | > 4.0/5.0 | 분기별 설문조사 |
| **운영 효율성** | +30% | On-call 시간 감소 |
| **비용 절감** | 15% | 리소스 최적화 |
| **장애 감소** | -50% | 분기별 Incident 수 |

---

## 🎬 Action Items

### Immediate (이번 주)
- [ ] Prometheus/Thanos 설정 검증
- [ ] ServiceMonitor 템플릿 작성
- [ ] 메트릭 수집 테스트

### Short-term (2주 내)
- [ ] JMX Exporter 배포
- [ ] Custom Exporter 개발
- [ ] Main Navigation Dashboard 완성

### Mid-term (1개월 내)
- [ ] 전체 대시보드 완성
- [ ] 알림 시스템 구축
- [ ] SLO 모니터링 시작

### Long-term (2개월 내)
- [ ] 자동화 구현
- [ ] 성능 최적화
- [ ] 전체 시스템 Go-Live

---

## 📚 참고 자료

1. **SRE Workbook**: https://sre.google/workbook/
2. **Prometheus Best Practices**: https://prometheus.io/docs/practices/
3. **Grafana Dashboard Best Practices**: https://grafana.com/docs/grafana/latest/best-practices/
4. **Thanos Architecture**: https://thanos.io/tip/thanos/design.md/

---

**다음 회의**: 2주 후 진행 상황 리뷰
**문서 작성**: SRE Team
**최종 승인**: CTO
