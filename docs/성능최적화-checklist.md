아래는 복사/붙여넣기 용으로 완전히 정돈된 Markdown 표 형식입니다.
불필요한 공백/줄바꿈 없이 바로 GitHub·Notion·Wiki 등에 붙여 넣을 수 있습니다.


---

## Thanos Helm 17.3.1 – 대규모/장기 쿼리 최적화 체크리스트 (Markdown)


---

0. Global – Objstore & Cache

항목	체크	설명

S3 설정(objstore)	☐	objstoreConfig 또는 Secret 기반 S3 설정 필수
indexCacheConfig	☐	비어있으면 장기 쿼리 심각한 성능저하 발생
bucketCacheConfig	☐	S3 chunk/metadata 캐시 필수
Cache eviction 모니터링	☐	hit/miss/eviction 기반으로 용량 조정 필요



---

1. Prometheus Agent / remote_write

항목	체크	설명

external_labels	☐	cluster, env, replica 설정 (HA dedup용)
remote_write 튜닝	☐	max_shards, max_samples_per_send 조정
high-cardinality 제거	☐	pod_uid, request_id 등 불필요 라벨 drop
active_series 모니터링	☐	장기 쿼리 성능의 핵심 지표



---

2. Thanos Receive

항목	체크	설명

receive.enabled	☐	remote_write 종착점 활성화
replicaCount (3~5 추천)	☐	노드/클러스터 수와 무관, 트래픽 기준
hashring 설정	☐	모든 receive를 링에 포함, 균등 샤딩
persistence(PVC)	☐	TSDB/WAL IOPS 충분해야 함
TSDB compaction 성능	☐	블록 업로드 지연 시 쿼리 구간 누락 발생 가능



---

3. Compactor

항목	체크	설명

compact.enabled	☐	단일 instance 권장
persistence(PVC)	☐	충분한 디스크 용량 (수백 GB 가능)
downsampling 보존 설정	☐	raw 짧게 · 5m/1h 길게 보존
compaction backlog	☐	쌓이면 장기 쿼리 극적으로 느려짐
retention 설정	☐	resolution 별 보존 기간 명확히 설정



---

4. Store Gateway

항목	체크	설명

storegateway.enabled	☐	S3 기반 히스토리 쿼리 핵심 컴포넌트
replicaCount	☐	최소 2, 보통 3~N
Sharded Store enabled	☐	메타데이터 분산, 메모리/성능 최적화 핵심
shard count	☐	replica 수 이상으로 분산
indexCacheConfig 적용	☐	캐시 없으면 S3 반복 조회로 느려짐
bucketCacheConfig 적용	☐	metadata/chunk 캐싱 필수
캐시 backend(memcached)	☐	large-scale 환경에서는 반드시 사용
리소스(CPU/MEM)	☐	메모리 부족 시 eviction/OOM →



---

5. Thanos Query

항목	체크	설명

query.enabled	☐	전역 쿼리 엔진
replicaCount	☐	2~3개 (고가용성)
replicaLabel 설정	☐	--query.replica-label=replica (HA dedup)
store/receive discovery	☐	Query가 모든 Store/Receive를 인식해야 함
auto downsampling	☐	장기 쿼리 성능 향상 핵심
partial-response	☐	일부 Store 장애 시에도 응답 가능
query timeout	☐	Grafana timeout과 일치하도록 조정



---

6. Thanos Query Frontend

항목	체크	설명

queryFrontend.enabled	☐	대규모/장기 쿼리 성능의 핵심
Response cache(mced/redis)	☐	캐싱 효과 극대화
Query split	☐	대규모 range 쿼리를 시간별로 분할
Step alignment	☐	캐시 재사용률 증가
Rate limiting	☐	heavy query 동시 실행제어
Grafana → Frontend 연결	☐	Grafana가 Query Frontend를 바라봐야 함



---

7. Cache Backend (Memcached/Redis)

항목	체크	설명

memcached 설치	☐	Store index/bucket + Frontend 캐시에서 사용
max_memory / item_size	☐	eviction 증가 시 즉시 조정
low-latency 배치	☐	Thanos Pod와 동일 AZ/노드 풀 권장



---

8. Grafana / Dashboard 설계

항목	체크	설명

기본 시간 범위 제한	☐	기본 1h~12h 설정
장기 쿼리 전용 대시보드	☐	7d/30d/90d 별도로 운영
$__interval / min_interval	☐	장기쿼리 step 증가 필수
변수(Variables) 사용	☐	cluster/namespace 먼저 선택하도록
heavy promql 최소화	☐	label_join, count_by(high-cardinality) 최소화



---

핵심 요약 (6대 구성요소)

1. Compactor (downsampling + block merge)


2. Store Gateway (sharded + index/bucket 캐시)


3. Query Frontend (쿼리 분할 + 캐시)


4. Query (HA dedup + auto downsampling)


5. Cache Infra (memcached)


6. Prometheus Agent 카디널리티 관리




---

필요하면 이 체크리스트 기반으로
values.yaml 실제 설정을 진단해 드릴 수도 있어요.
