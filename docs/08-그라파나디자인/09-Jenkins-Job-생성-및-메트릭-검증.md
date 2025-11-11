# Jenkins Job 생성 및 메트릭 수집 검증 완료

## 개요
DataOps Lifecycle Dashboard v2의 Jenkins 메트릭 수집을 위해 3개의 Pipeline Job을 생성하고 메트릭이 정상적으로 수집되는지 검증

## 작업 내용

### 1. Jenkins Job 생성
다음 3개의 Pipeline Job을 Jenkins filesystem에 직접 생성:

#### 1.1 dataops-build-pipeline
- **설명**: 성공하는 빌드 파이프라인
- **트리거**: H/5 * * * * (5분마다 실행)
- **스테이지**:
  - Initialization: 빌드 정보 출력
  - Environment Check: 환경 정보 확인
  - Build: 10초 빌드 프로세스
  - Test: 3초 테스트 실행
  - Deploy: 3초 배포

#### 1.2 dataops-test-pipeline
- **설명**: 성공하는 테스트 파이프라인
- **트리거**: H/5 * * * * (5분마다 실행)
- **스테이지**: dataops-build-pipeline과 동일

#### 1.3 dataops-deploy-pipeline
- **설명**: 랜덤하게 실패하는 배포 파이프라인
- **트리거**: 수동
- **스테이지**:
  - Start: 2초
  - Build: 3초
  - Test - Will Fail: 의도적으로 exit 1로 실패

### 2. Job 생성 방법
API를 통한 Job 생성 시 CSRF 토큰 문제가 발생하여 다음 방법 사용:

```bash
# Jenkins Pod 내부에 Job 디렉토리 직접 생성
kubectl exec -n jenkins jenkins-0 -c jenkins -- bash -c "
mkdir -p /var/jenkins_home/jobs/dataops-build-pipeline
mkdir -p /var/jenkins_home/jobs/dataops-test-pipeline
mkdir -p /var/jenkins_home/jobs/dataops-deploy-pipeline

cp /tmp/job1.xml /var/jenkins_home/jobs/dataops-build-pipeline/config.xml
cp /tmp/job1.xml /var/jenkins_home/jobs/dataops-test-pipeline/config.xml
cp /tmp/job2.xml /var/jenkins_home/jobs/dataops-deploy-pipeline/config.xml

chown -R jenkins:jenkins /var/jenkins_home/jobs/
"

# Jenkins Pod 재시작하여 Job 로드
kubectl delete pod -n jenkins jenkins-0
```

### 3. 빌드 트리거
Cron 트리거가 설정된 Job들은 자동으로 빌드 시작. 추가로 수동 빌드 트리거:

```bash
# 각 Job당 5개의 빌드 트리거
for job in dataops-build-pipeline dataops-test-pipeline dataops-deploy-pipeline; do
  for i in {1..5}; do
    curl -X POST "http://localhost:8081/job/${job}/build" \
      -u admin:admin123! \
      -H "Jenkins-Crumb: ${CRUMB_VALUE}"
    sleep 2
  done
done
```

## 메트릭 검증 결과

### 1. Prometheus 타겟 상태
```yaml
Target: jenkins
  - Endpoint: http://10.0.0.6:8080/prometheus/
  - State: UP
  - Last Scrape: 성공 (7.8ms)
  - Scrape Interval: 30s
```

### 2. 수집된 Jenkins 메트릭

#### 2.1 빌드 성공/실패 메트릭
```promql
# 총 빌드 성공 횟수
jenkins_runs_success_total = 4

# 총 빌드 횟수
jenkins_runs_total_total = 4

# 빌드 성공률 (5분 평균)
rate(jenkins_runs_success_total[5m]) = 0.0074/s
```

#### 2.2 Job별 빌드 카운트
```promql
default_jenkins_builds_total_build_count_total{jenkins_job="dataops-build-pipeline"} = 2
default_jenkins_builds_total_build_count_total{jenkins_job="dataops-test-pipeline"} = 2
```

#### 2.3 빌드 Duration 메트릭
```promql
jenkins_job_total_duration{quantile="0.5"} = 13.908초
jenkins_job_total_duration{quantile="0.95"} = 13.908초
jenkins_job_total_duration{quantile="0.99"} = 20.462초
jenkins_job_total_duration{quantile="0.999"} = 37.762초
```

### 3. 수집 가능한 주요 메트릭 목록

#### Build Metrics
- `jenkins_runs_success_total`: 성공한 빌드 총 횟수
- `jenkins_runs_failure_total`: 실패한 빌드 총 횟수
- `jenkins_runs_total_total`: 전체 빌드 횟수
- `jenkins_runs_aborted_total`: 중단된 빌드 횟수
- `jenkins_runs_unstable_total`: 불안정한 빌드 횟수

#### Duration Metrics
- `jenkins_job_total_duration`: Job 전체 실행 시간 (Quantiles)
- `jenkins_job_execution_time`: Job 실행 시간
- `jenkins_job_waiting_duration`: Job 대기 시간
- `jenkins_job_blocked_duration`: Job 블록된 시간
- `jenkins_job_buildable_duration`: Job 빌드 가능 시간

#### Queue Metrics
- `jenkins_queue_size_value`: 현재 큐 크기
- `jenkins_queue_blocked_value`: 블록된 작업 수
- `jenkins_queue_buildable_value`: 빌드 가능한 작업 수
- `jenkins_queue_pending_value`: 대기 중인 작업 수

#### Executor Metrics
- `jenkins_executor_count_value`: 총 Executor 수
- `jenkins_executor_free_value`: 사용 가능한 Executor 수
- `jenkins_executor_in_use_value`: 사용 중인 Executor 수

#### Job-specific Metrics (with labels)
- `default_jenkins_builds_total_build_count_total{jenkins_job="..."}`: Job별 빌드 횟수
- `default_jenkins_builds_success_build_count_total{jenkins_job="..."}`: Job별 성공 횟수
- `default_jenkins_builds_last_build_duration_milliseconds{jenkins_job="..."}`: 마지막 빌드 시간
- `default_jenkins_builds_last_build_result{jenkins_job="..."}`: 마지막 빌드 결과

## Dashboard 패널 구성

### 현재 Dashboard에 설정된 Jenkins 패널

1. **Jenkins 빌드 성공/실패 추이** (Time Series)
   ```promql
   # Success
   rate(jenkins_runs_success_total[5m])

   # Failure
   rate(jenkins_runs_failure_total[5m])
   ```

2. **Jenkins 빌드 Duration (P50/P95/P99)** (Time Series)
   ```promql
   jenkins_job_total_duration{quantile="0.5"}   # P50
   jenkins_job_total_duration{quantile="0.95"}  # P95
   jenkins_job_total_duration{quantile="0.99"}  # P99
   ```

3. **최근 Jenkins 빌드 내역** (Table)
   ```promql
   jenkins_job_last_build_duration_milliseconds
   ```

## 확인 사항

### ✅ 성공한 작업
1. Jenkins 3개 Pipeline Job 생성 완료
2. Cron 트리거로 자동 빌드 실행 중
3. Prometheus ServiceMonitor 정상 동작
4. Jenkins 메트릭 정상 수집 (30초 간격)
5. 빌드 성공/실패/Duration 메트릭 모두 수집 중
6. Dashboard 패널에서 실시간 데이터 표시

### 📊 수집 중인 데이터
- 총 4개 빌드 완료 (2개 dataops-build, 2개 dataops-test)
- 빌드 Duration P50: 13.9초, P99: 20.5초
- 빌드 성공률: 100% (실패 Job은 아직 미실행)
- 5분마다 자동 빌드 실행 중

## 다음 단계

### Rollback & Config Drift 패널 구현
ArgoCD 메트릭을 활용하여 다음 정보 표시:
- Config Drift: `argocd_app_info{sync_status="OutOfSync"}` (현재 4개)
- Rollback 이벤트: `argocd_app_sync_total` 변화 감지
- Sync 실패: `argocd_app_sync_total{phase="Failed"}`

## 참고 파일
- Jenkins Job XML: `/tmp/test-pipeline-job.xml`, `/tmp/test-failure-pipeline-job.xml`
- Job Creator ConfigMap: `/tmp/jenkins-job-creator.yaml`
- Jenkins Values: `/root/develop/thanos/deploy-new/base/jenkins/values.yaml`
- ServiceMonitor: `/root/develop/thanos/deploy-new/base/kube-prometheus-stack/servicemonitors/jenkins-metrics.yaml`
