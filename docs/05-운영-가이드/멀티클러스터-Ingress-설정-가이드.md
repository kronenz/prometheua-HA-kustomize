# 멀티클러스터 Ingress 설정 가이드

## 목차
1. [개요](#개요)
2. [Ingress 필요성 분석](#ingress-필요성-분석)
3. [필수 Ingress 설정](#필수-ingress-설정)
4. [선택적 Ingress 설정](#선택적-ingress-설정)
5. [보안 설정](#보안-설정)
6. [엣지 클러스터 연동](#엣지-클러스터-연동)
7. [트러블슈팅](#트러블슈팅)

---

## 개요

Prometheus Agent + Receiver 패턴으로 멀티클러스터를 구성할 때, 중앙 클러스터의 특정 Thanos 컴포넌트는 클러스터 외부와 통신하기 위해 **Ingress** 설정이 필요합니다.

### 아키텍처 개요

```
┌──────────────────────────────────────────────────────────────┐
│                     중앙 클러스터 (Central)                      │
│                                                                │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐  │
│  │   Grafana    │────▶│ Thanos Query │◀────│ Store Gateway│  │
│  │  (Ingress)   │     │  (Ingress)   │     │ (Internal)   │  │
│  └──────────────┘     └──────────────┘     └──────────────┘  │
│                              │                                 │
│                              ▼                                 │
│                    ┌──────────────────┐                        │
│                    │ Thanos Receiver  │                        │
│                    │    (Ingress)     │                        │
│                    └──────────────────┘                        │
│                              ▲                                 │
└──────────────────────────────┼─────────────────────────────────┘
                               │
                               │ Remote Write (HTTPS)
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
┌───────▼────────┐    ┌────────▼───────┐    ┌────────▼───────┐
│ Edge Cluster 1 │    │ Edge Cluster 2 │    │ Edge Cluster 3 │
│                │    │                │    │                │
│  Prometheus    │    │  Prometheus    │    │  Prometheus    │
│     Agent      │    │     Agent      │    │     Agent      │
└────────────────┘    └────────────────┘    └────────────────┘
```

---

## Ingress 필요성 분석

### 컴포넌트별 Ingress 필요성

| 컴포넌트 | Ingress 필요 | 우선순위 | 포트 | 접근 주체 | 이유 |
|---------|-------------|---------|------|----------|------|
| **Thanos Receiver** | ✅ 필수 | 최우선 | 19291 | 엣지 클러스터 Prometheus Agent | Remote Write 엔드포인트 |
| **Thanos Query** | ✅ 필수 | 필수 | 10902 | Grafana, 외부 사용자 | 통합 쿼리 인터페이스 |
| **Grafana** | ✅ 필수 | 필수 | 3000 | 운영자, 개발자 | 대시보드 UI |
| **Query Frontend** | ⚠️ 선택 | 권장 | 9090 | Grafana (Query 대신) | 쿼리 캐싱, 성능 최적화 |
| **Bucket Web** | ⚠️ 선택 | 선택 | 8080 | 운영자 | S3 블록 상태 디버깅 |
| **Compactor** | ❌ 불필요 | - | 10902 | S3만 | 내부에서 S3와만 통신 |
| **Store Gateway** | ❌ 불필요 | - | 10901/10902 | Query (내부) | Query가 gRPC로 내부 통신 |
| **Ruler** | ❌ 불필요 | - | 10902 | Query (내부) | Query에 gRPC로 쿼리 |

---

## 필수 Ingress 설정

### 1. Thanos Receiver (최우선 필수)

**목적**: 엣지 클러스터의 Prometheus Agent가 Remote Write로 메트릭을 전송

```yaml
receive:
  enabled: true
  mode: standalone  # 또는 dual-mode

  ingress:
    enabled: true
    hostname: thanos-receiver.k8s-central.example.com
    ingressClassName: nginx

    annotations:
      # HTTPS 리디렉션
      nginx.ingress.kubernetes.io/ssl-redirect: "true"

      # 백엔드 프로토콜
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"

      # cert-manager 연동
      cert-manager.io/cluster-issuer: letsencrypt-prod

      # Rate Limiting (DDoS 방지)
      nginx.ingress.kubernetes.io/limit-rps: "100"
      nginx.ingress.kubernetes.io/limit-connections: "10"

      # Body Size (대용량 메트릭 전송)
      nginx.ingress.kubernetes.io/proxy-body-size: "100m"

      # Timeout (장시간 전송 허용)
      nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "600"

    tls: true
    selfSigned: false

    # 추가 Path (옵션)
    path: /
    pathType: Prefix
```

**엣지 클러스터 연동**:
```yaml
# prometheus-agent-config.yaml
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive
    queue_config:
      capacity: 10000
      max_shards: 50
```

---

### 2. Thanos Query (필수)

**목적**: Grafana 데이터소스, 통합 쿼리 인터페이스

```yaml
query:
  enabled: true

  ingress:
    enabled: true
    hostname: thanos-query.k8s-central.example.com
    ingressClassName: nginx

    annotations:
      # HTTPS 리디렉션
      nginx.ingress.kubernetes.io/ssl-redirect: "true"

      # cert-manager 연동
      cert-manager.io/cluster-issuer: letsencrypt-prod

      # CORS 설정 (Grafana 연동)
      nginx.ingress.kubernetes.io/enable-cors: "true"
      nginx.ingress.kubernetes.io/cors-allow-origin: "https://grafana.k8s-central.example.com"

      # 쿼리 타임아웃
      nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "300"

    tls: true

    # 추가 호스트 (옵션)
    extraHosts:
      - name: thanos-query-internal.k8s-central.example.com
        path: /
```

**Grafana 데이터소스 설정**:
```yaml
grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Thanos
          type: prometheus
          url: https://thanos-query.k8s-central.example.com
          access: proxy
          isDefault: true
```

---

### 3. Grafana (필수)

**목적**: 사용자 접근 대시보드 UI

```yaml
grafana:
  enabled: true

  ingress:
    enabled: true
    hostname: grafana.k8s-central.example.com
    ingressClassName: nginx

    annotations:
      # HTTPS 리디렉션
      nginx.ingress.kubernetes.io/ssl-redirect: "true"

      # cert-manager 연동
      cert-manager.io/cluster-issuer: letsencrypt-prod

      # WebSocket 지원 (실시간 대시보드)
      nginx.ingress.kubernetes.io/websocket-services: "grafana"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"

      # 세션 어피니티
      nginx.ingress.kubernetes.io/affinity: "cookie"
      nginx.ingress.kubernetes.io/session-cookie-name: "grafana-session"

    tls: true

    # 여러 도메인 지원
    extraHosts:
      - name: monitoring.k8s-central.example.com
        path: /
```

**Grafana 설정**:
```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.k8s-central.example.com
      serve_from_sub_path: false
```

---

## 선택적 Ingress 설정

### 4. Thanos Query Frontend (권장)

**목적**: 쿼리 캐싱 및 분할로 성능 향상

```yaml
queryFrontend:
  enabled: true

  ingress:
    enabled: true
    hostname: thanos-query-frontend.k8s-central.example.com
    ingressClassName: nginx

    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/ssl-redirect: "true"

      # 캐싱 설정
      nginx.ingress.kubernetes.io/proxy-buffering: "on"
      nginx.ingress.kubernetes.io/proxy-cache-valid: "200 10m"

    tls: true
```

**Grafana 데이터소스 변경** (Query 대신 Query Frontend 사용):
```yaml
grafana:
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Thanos
          type: prometheus
          url: https://thanos-query-frontend.k8s-central.example.com
```

---

### 5. Thanos Bucket Web (선택)

**목적**: S3 블록 상태 시각화 및 디버깅

```yaml
bucketweb:
  enabled: true

  ingress:
    enabled: true
    hostname: thanos-bucketweb.k8s-central.example.com
    ingressClassName: nginx

    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/ssl-redirect: "true"

      # Basic Auth (보안)
      nginx.ingress.kubernetes.io/auth-type: basic
      nginx.ingress.kubernetes.io/auth-secret: basic-auth
      nginx.ingress.kubernetes.io/auth-realm: "Thanos Bucket Web - Authentication Required"

    tls: true
```

**Basic Auth Secret 생성**:
```bash
# htpasswd 생성
htpasswd -c auth admin

# Secret 생성
kubectl create secret generic basic-auth \
  --from-file=auth \
  -n monitoring
```

---

## 보안 설정

### TLS/HTTPS 필수 설정

#### 1. cert-manager 연동 (Let's Encrypt)

```yaml
# ClusterIssuer 생성
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

#### 2. Ingress에서 TLS 활성화

```yaml
ingress:
  enabled: true
  tls: true
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
```

---

### Basic Authentication

#### Receiver 보안 (선택)

```yaml
receive:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/auth-type: basic
      nginx.ingress.kubernetes.io/auth-secret: thanos-receiver-auth
```

**Secret 생성**:
```bash
# 사용자 추가
htpasswd -c receiver-auth edge-cluster-01
htpasswd receiver-auth edge-cluster-02
htpasswd receiver-auth edge-cluster-03

# Secret 생성
kubectl create secret generic thanos-receiver-auth \
  --from-file=auth=receiver-auth \
  -n monitoring
```

**엣지 클러스터 설정**:
```yaml
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive
    basic_auth:
      username: edge-cluster-01
      password: secret-password
```

---

### IP Whitelist (선택)

```yaml
ingress:
  annotations:
    # 특정 IP만 허용
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
```

---

### Rate Limiting

```yaml
receive:
  ingress:
    annotations:
      # Rate Limiting
      nginx.ingress.kubernetes.io/limit-rps: "100"
      nginx.ingress.kubernetes.io/limit-connections: "10"
      nginx.ingress.kubernetes.io/limit-burst-multiplier: "5"
```

---

## 엣지 클러스터 연동

### Prometheus Agent 설정

#### 기본 설정

```yaml
# prometheus-agent-config.yaml
global:
  external_labels:
    cluster: edge-cluster-01
    region: us-west
    environment: production

remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive

    # Queue 설정
    queue_config:
      capacity: 10000
      max_shards: 50
      min_shards: 1
      max_samples_per_send: 5000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s

    # 재시도 설정
    write_relabel_configs: []
```

#### TLS 설정

```yaml
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive

    tls_config:
      # TLS 검증 (프로덕션)
      insecure_skip_verify: false

      # CA 인증서 (자체 서명 인증서 사용 시)
      # ca_file: /etc/prometheus/tls/ca.crt
```

#### Basic Auth 설정

```yaml
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive

    basic_auth:
      username: edge-cluster-01
      password: secret-password

    # 또는 파일에서 읽기
    # basic_auth:
    #   username: edge-cluster-01
    #   password_file: /etc/prometheus/secrets/password
```

#### OAuth2 설정 (선택)

```yaml
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive

    oauth2:
      client_id: prometheus-agent
      client_secret: oauth-secret
      token_url: https://auth.example.com/oauth/token
```

---

### 연동 검증

#### 1. DNS 확인

```bash
# 엣지 클러스터에서 실행
nslookup thanos-receiver.k8s-central.example.com
dig thanos-receiver.k8s-central.example.com
```

#### 2. 네트워크 연결 확인

```bash
# HTTPS 연결 테스트
curl -v https://thanos-receiver.k8s-central.example.com/api/v1/receive

# 포트 확인
nc -zv thanos-receiver.k8s-central.example.com 443
```

#### 3. Remote Write 테스트

```bash
# Prometheus Agent 로그 확인
kubectl logs -f prometheus-agent-0 -n monitoring | grep remote_write

# 성공 예시:
# level=info ts=2024-10-28T01:00:00.000Z caller=dedupe.go:112 component=remote msg="Remote storage write successful" duration=50ms
```

#### 4. Receiver 메트릭 확인

```bash
# Receiver에서 수신한 샘플 수 확인
kubectl exec -it thanos-receiver-0 -n monitoring -- \
  wget -qO- http://localhost:19291/metrics | grep thanos_receive_replications_total

# 중앙 클러스터에서 쿼리
curl -s "https://thanos-query.k8s-central.example.com/api/v1/query?query=up{cluster='edge-cluster-01'}"
```

---

## 트러블슈팅

### 문제 1: Receiver Ingress 503 Service Unavailable

**증상**:
```bash
curl https://thanos-receiver.k8s-central.example.com/api/v1/receive
# 503 Service Unavailable
```

**원인**: Receiver Pod가 Ready 상태가 아님

**해결**:
```bash
# Pod 상태 확인
kubectl get pods -n monitoring -l app.kubernetes.io/name=thanos-receiver

# Pod 로그 확인
kubectl logs -f thanos-receiver-0 -n monitoring

# Readiness Probe 확인
kubectl describe pod thanos-receiver-0 -n monitoring | grep -A 10 Readiness
```

---

### 문제 2: Remote Write 실패

**증상**:
```
level=warn ts=2024-10-28T01:00:00.000Z caller=dedupe.go:112 component=remote msg="Remote write failed" err="Post https://thanos-receiver.k8s-central.example.com/api/v1/receive: context deadline exceeded"
```

**원인**: 네트워크 타임아웃 또는 Receiver 과부하

**해결**:
```yaml
# 1. Ingress 타임아웃 증가
receive:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "600"

# 2. Prometheus Agent Queue 설정 조정
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive
    queue_config:
      capacity: 20000  # 증가
      max_shards: 100  # 증가
      batch_send_deadline: 10s  # 증가

# 3. Receiver 리소스 증가
receive:
  resources:
    requests:
      cpu: 2
      memory: 4Gi
    limits:
      cpu: 4
      memory: 8Gi
```

---

### 문제 3: TLS 인증서 오류

**증상**:
```
x509: certificate signed by unknown authority
```

**원인**: 자체 서명 인증서 사용 또는 CA 인증서 누락

**해결**:
```yaml
# 옵션 1: 프로덕션 환경 (Let's Encrypt 사용)
ingress:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls: true

# 옵션 2: 개발 환경 (TLS 검증 건너뛰기)
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive
    tls_config:
      insecure_skip_verify: true  # 프로덕션에서는 사용 금지

# 옵션 3: 자체 CA 인증서 사용
remote_write:
  - url: https://thanos-receiver.k8s-central.example.com/api/v1/receive
    tls_config:
      ca_file: /etc/prometheus/tls/ca.crt
```

---

### 문제 4: Basic Auth 실패

**증상**:
```
401 Unauthorized
```

**원인**: 잘못된 인증 정보

**해결**:
```bash
# 1. Secret 확인
kubectl get secret basic-auth -n monitoring -o jsonpath='{.data.auth}' | base64 -d

# 2. 인증 정보 테스트
curl -u username:password https://thanos-receiver.k8s-central.example.com/api/v1/receive

# 3. Prometheus Agent 설정 확인
kubectl get secret prometheus-agent-config -n monitoring -o yaml
```

---

### 문제 5: CORS 오류 (Grafana)

**증상**:
```
Access to XMLHttpRequest at 'https://thanos-query.k8s-central.example.com' from origin 'https://grafana.k8s-central.example.com' has been blocked by CORS policy
```

**원인**: CORS 헤더 누락

**해결**:
```yaml
query:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/enable-cors: "true"
      nginx.ingress.kubernetes.io/cors-allow-origin: "https://grafana.k8s-central.example.com"
      nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, OPTIONS"
      nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
```

---

## 완전한 설정 예시

### 중앙 클러스터 values.yaml

```yaml
# values.yaml (cluster-01-central)

# ============================================================
# Thanos Receiver (필수)
# ============================================================
receive:
  enabled: true
  mode: standalone

  replicaCount: 3

  ingress:
    enabled: true
    hostname: thanos-receiver.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
      nginx.ingress.kubernetes.io/limit-rps: "100"
      nginx.ingress.kubernetes.io/proxy-body-size: "100m"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    tls: true

  resources:
    requests:
      cpu: 2
      memory: 4Gi
    limits:
      cpu: 4
      memory: 8Gi

# ============================================================
# Thanos Query (필수)
# ============================================================
query:
  enabled: true
  replicaCount: 2

  ingress:
    enabled: true
    hostname: thanos-query.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/enable-cors: "true"
      nginx.ingress.kubernetes.io/cors-allow-origin: "https://grafana.k8s-central.example.com"
    tls: true

# ============================================================
# Grafana (필수)
# ============================================================
grafana:
  enabled: true

  ingress:
    enabled: true
    hostname: grafana.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/websocket-services: "grafana"
    tls: true

  grafana.ini:
    server:
      root_url: https://grafana.k8s-central.example.com

  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Thanos
          type: prometheus
          url: https://thanos-query.k8s-central.example.com
          access: proxy
          isDefault: true

# ============================================================
# Thanos Query Frontend (선택)
# ============================================================
queryFrontend:
  enabled: true

  ingress:
    enabled: true
    hostname: thanos-query-frontend.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
    tls: true

# ============================================================
# Thanos Bucket Web (선택)
# ============================================================
bucketweb:
  enabled: true

  ingress:
    enabled: true
    hostname: thanos-bucketweb.k8s-central.example.com
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/auth-type: basic
      nginx.ingress.kubernetes.io/auth-secret: basic-auth
    tls: true

# ============================================================
# 내부 통신만 사용 (Ingress 불필요)
# ============================================================
compactor:
  enabled: true
  ingress:
    enabled: false

storegateway:
  enabled: true
  ingress:
    enabled: false

ruler:
  enabled: true
  ingress:
    enabled: false
```

---

## 요약

### Ingress 필수 여부

| 컴포넌트 | Ingress | 이유 |
|---------|---------|------|
| Receiver | ✅ 필수 | 엣지 클러스터 Remote Write |
| Query | ✅ 필수 | Grafana 데이터소스 |
| Grafana | ✅ 필수 | 사용자 UI |
| Query Frontend | ⚠️ 권장 | 성능 최적화 |
| Bucket Web | ⚠️ 선택 | 디버깅 |
| Compactor | ❌ 불필요 | S3 통신만 |
| Store Gateway | ❌ 불필요 | 내부 gRPC |
| Ruler | ❌ 불필요 | 내부 통신 |

### 보안 체크리스트

- [ ] TLS/HTTPS 활성화 (Let's Encrypt)
- [ ] Basic Auth 설정 (Receiver, Bucket Web)
- [ ] Rate Limiting 설정 (Receiver)
- [ ] IP Whitelist 설정 (필요시)
- [ ] CORS 설정 (Query)
- [ ] Timeout 설정 (대용량 전송)
- [ ] Body Size 제한 해제 (Receiver)

### 연동 체크리스트

- [ ] DNS 레코드 설정
- [ ] cert-manager ClusterIssuer 생성
- [ ] Ingress Controller 설치 (nginx)
- [ ] Prometheus Agent Remote Write URL 설정
- [ ] TLS 인증서 발급 확인
- [ ] 연결 테스트 (curl, nc)
- [ ] 메트릭 수신 확인

**핵심**: Receiver, Query, Grafana 3개는 반드시 Ingress 설정이 필요하며, TLS/HTTPS는 필수입니다!
