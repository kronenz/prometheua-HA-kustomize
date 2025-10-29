# S3 TLS 인증서 설정 가이드 (Thanos)

## 목차
1. [개요](#개요)
2. [인증서 준비](#인증서-준비)
3. [Kubernetes Secret 생성](#kubernetes-secret-생성)
4. [Thanos 컴포넌트별 설정](#thanos-컴포넌트별-설정)
5. [Kustomize 구성](#kustomize-구성)
6. [Helm Values 설정](#helm-values-설정)
7. [검증 및 테스트](#검증-및-테스트)
8. [트러블슈팅](#트러블슈팅)

---

## 개요

Thanos가 S3 오브젝트 스토리지에 HTTPS로 안전하게 접속하기 위해서는 TLS 인증서 설정이 필요합니다. 특히 자체 서명(Self-Signed) 인증서나 사설 CA를 사용하는 MinIO 같은 경우 필수입니다.

### 적용 대상 컴포넌트

| 컴포넌트 | S3 접근 | TLS 필요 | 이유 |
|---------|---------|---------|------|
| **Thanos Receiver** | ✅ 예 | ✅ 필수 | 메트릭 블록 업로드 |
| **Thanos Compactor** | ✅ 예 | ✅ 필수 | 블록 압축 및 다운샘플링 |
| **Thanos Store Gateway** | ✅ 예 | ✅ 필수 | 과거 데이터 쿼리 |
| **Thanos Ruler** | ✅ 예 | ✅ 필수 | Recording Rules 저장 |
| **Thanos Query** | ❌ 아니오 | ❌ 불필요 | S3 직접 접근 안 함 |
| **Thanos Query Frontend** | ❌ 아니오 | ❌ 불필요 | S3 직접 접근 안 함 |

### 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│            Kubernetes Cluster (Central)                 │
│                                                           │
│  ┌──────────────┐      ┌──────────────┐                 │
│  │   Receiver   │      │  Compactor   │                 │
│  └──────┬───────┘      └──────┬───────┘                 │
│         │ HTTPS (TLS)         │ HTTPS (TLS)             │
│         │ + CA Certificate    │ + CA Certificate        │
│         │                     │                         │
│  ┌──────▼──────────────────────▼───────┐                │
│  │      Store Gateway + Ruler          │                │
│  │    HTTPS (TLS) + CA Certificate     │                │
│  └──────────────┬──────────────────────┘                │
└─────────────────┼──────────────────────────────────────┘
                  │
                  │ HTTPS Port 9000
                  │ TLS Certificate Validation
                  │
         ┌────────▼────────┐
         │   MinIO S3      │
         │  (Self-Signed   │
         │   Certificate)  │
         └─────────────────┘
```

---

## 인증서 준비

### 1. MinIO 인증서 추출

MinIO가 사용하는 TLS 인증서를 추출합니다.

#### MinIO에서 인증서 다운로드

```bash
# MinIO 서버에서 public.crt 파일 위치 확인
# 일반적으로 /root/.minio/certs/public.crt

# MinIO 컨테이너에서 인증서 추출
kubectl exec -it minio-0 -n minio -- cat /root/.minio/certs/public.crt > minio-ca.crt

# 또는 SSH로 직접 접근
scp user@minio-server:/root/.minio/certs/public.crt ./minio-ca.crt
```

#### 인증서 확인

```bash
# 인증서 정보 확인
openssl x509 -in minio-ca.crt -text -noout

# 출력 예시:
# Certificate:
#     Data:
#         Version: 3 (0x2)
#         Serial Number: ...
#         Signature Algorithm: sha256WithRSAEncryption
#         Issuer: CN=minio.example.com
#         Validity
#             Not Before: Jan  1 00:00:00 2024 GMT
#             Not After : Dec 31 23:59:59 2034 GMT
#         Subject: CN=minio.example.com
```

---

### 2. Let's Encrypt 또는 공인 CA 인증서

Let's Encrypt나 공인 CA 발급 인증서를 사용하는 경우:

```bash
# Let's Encrypt Root CA 다운로드
wget https://letsencrypt.org/certs/isrgrootx1.pem -O letsencrypt-ca.crt

# 또는 시스템 CA 인증서 사용
cp /etc/ssl/certs/ca-certificates.crt system-ca.crt
```

---

### 3. 자체 서명(Self-Signed) 인증서 생성 (테스트용)

테스트 환경에서 자체 서명 인증서를 생성하는 경우:

```bash
# CA 개인키 생성
openssl genrsa -out ca.key 4096

# CA 인증서 생성
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/CN=MinIO-CA/O=My Organization/C=US"

# MinIO 서버 개인키 생성
openssl genrsa -out minio.key 2048

# CSR 생성
openssl req -new -key minio.key -out minio.csr \
  -subj "/CN=s3.minio.example.com/O=My Organization/C=US"

# 서버 인증서 생성
openssl x509 -req -in minio.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out minio.crt -days 3650 \
  -extfile <(printf "subjectAltName=DNS:s3.minio.example.com,DNS:*.minio.example.com")

# 생성된 파일:
# - ca.crt: CA 인증서 (Thanos에서 사용)
# - minio.crt: MinIO 서버 인증서
# - minio.key: MinIO 서버 개인키
```

---

## Kubernetes Secret 생성

### 방법 1: kubectl로 직접 생성

```bash
# Secret 생성
kubectl create secret generic thanos-s3-ca-cert \
  --from-file=ca.crt=minio-ca.crt \
  -n monitoring

# Secret 확인
kubectl get secret thanos-s3-ca-cert -n monitoring -o yaml
```

### 방법 2: YAML 파일로 생성

```yaml
# s3-ca-cert-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: thanos-s3-ca-cert
  namespace: monitoring
type: Opaque
data:
  ca.crt: |
    LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURm...
    # Base64 인코딩된 인증서 내용
```

Base64 인코딩:
```bash
# 인증서를 Base64로 인코딩
cat minio-ca.crt | base64 -w 0

# 또는 직접 YAML에 삽입
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: thanos-s3-ca-cert
  namespace: monitoring
type: Opaque
data:
  ca.crt: $(cat minio-ca.crt | base64 -w 0)
EOF
```

---

### 방법 3: Kustomize SecretGenerator 사용 (권장)

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

secretGenerator:
  - name: thanos-s3-ca-cert
    files:
      - ca.crt=./certs/minio-ca.crt
    options:
      disableNameSuffixHash: true
```

---

## Thanos 컴포넌트별 설정

### 1. S3 Config 설정 (objstore.yml)

```yaml
# objstore.yml
type: S3
config:
  bucket: "thanos"
  endpoint: "s3.minio.example.com:9000"
  access_key: "minio"
  secret_key: "minio123"
  insecure: false

  # TLS 설정
  http_config:
    tls_config:
      # CA 인증서 파일 경로
      ca_file: /etc/thanos/certs/ca.crt

      # 인증서 검증 (프로덕션: true, 개발: false)
      insecure_skip_verify: false

      # 서버 이름 검증
      server_name: s3.minio.example.com
```

### ConfigMap 생성

```bash
# ConfigMap 생성
kubectl create configmap thanos-objstore-config \
  --from-file=objstore.yml \
  -n monitoring

# 또는 YAML로 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: thanos-objstore-config
  namespace: monitoring
data:
  objstore.yml: |
    type: S3
    config:
      bucket: "thanos"
      endpoint: "s3.minio.example.com:9000"
      access_key: "minio"
      secret_key: "minio123"
      insecure: false
      http_config:
        tls_config:
          ca_file: /etc/thanos/certs/ca.crt
          insecure_skip_verify: false
          server_name: s3.minio.example.com
EOF
```

---

## Kustomize 구성

### 디렉토리 구조

```
overlays/cluster-01-central/
├── kustomization.yaml
├── thanos-receiver/
│   ├── kustomization.yaml
│   ├── values.yaml
│   └── certs/
│       └── minio-ca.crt
├── thanos-compactor/
│   ├── kustomization.yaml
│   ├── values.yaml
│   └── certs/
│       └── minio-ca.crt
├── thanos-store/
│   ├── kustomization.yaml
│   ├── values.yaml
│   └── certs/
│       └── minio-ca.crt
└── thanos-ruler/
    ├── kustomization.yaml
    ├── values.yaml
    └── certs/
        └── minio-ca.crt
```

### 공통 kustomization.yaml

```yaml
# overlays/cluster-01-central/thanos-receiver/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
  - ../../../base/thanos-receiver

# S3 CA 인증서 Secret 생성
secretGenerator:
  - name: thanos-s3-ca-cert
    files:
      - ca.crt=./certs/minio-ca.crt
    options:
      disableNameSuffixHash: true

# S3 Config ConfigMap 생성
configMapGenerator:
  - name: thanos-objstore-config
    files:
      - objstore.yml
    options:
      disableNameSuffixHash: true

# Helm Values 패치
helmCharts:
  - name: thanos
    repo: https://charts.bitnami.com/bitnami
    version: 17.3.1
    releaseName: thanos
    namespace: monitoring
    valuesFile: values.yaml
```

---

## Helm Values 설정

### 1. Thanos Receiver 설정

```yaml
# overlays/cluster-01-central/thanos-receiver/values.yaml
receive:
  enabled: true

  # S3 설정
  objstoreConfig:
    # 외부 ConfigMap 사용
    existingConfigmap: thanos-objstore-config
    existingConfigmapKey: objstore.yml

  # CA 인증서 볼륨 마운트
  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert
        defaultMode: 0644

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

  # 환경 변수 (선택)
  extraEnvVars:
    - name: SSL_CERT_FILE
      value: /etc/thanos/certs/ca.crt
```

---

### 2. Thanos Compactor 설정

```yaml
# overlays/cluster-01-central/thanos-compactor/values.yaml
compactor:
  enabled: true

  # S3 설정
  objstoreConfig:
    existingConfigmap: thanos-objstore-config
    existingConfigmapKey: objstore.yml

  # CA 인증서 볼륨 마운트
  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert
        defaultMode: 0644

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

  # Compactor 전용 설정
  retentionResolutionRaw: 30d
  retentionResolution5m: 180d
  retentionResolution1h: 10y
```

---

### 3. Thanos Store Gateway 설정

```yaml
# overlays/cluster-01-central/thanos-store/values.yaml
storegateway:
  enabled: true

  # S3 설정
  objstoreConfig:
    existingConfigmap: thanos-objstore-config
    existingConfigmapKey: objstore.yml

  # CA 인증서 볼륨 마운트
  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert
        defaultMode: 0644

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

  # 인덱스 캐시 설정
  indexCacheConfig: |-
    type: IN-MEMORY
    config:
      max_size: 2GB
```

---

### 4. Thanos Ruler 설정

```yaml
# overlays/cluster-01-central/thanos-ruler/values.yaml
ruler:
  enabled: true

  # S3 설정
  objstoreConfig:
    existingConfigmap: thanos-objstore-config
    existingConfigmapKey: objstore.yml

  # CA 인증서 볼륨 마운트
  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert
        defaultMode: 0644

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

  # Ruler 설정
  alertmanagers:
    - http://alertmanager.monitoring.svc.cluster.local:9093

  queries:
    - dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local
```

---

### 5. 통합 values.yaml (모든 컴포넌트)

```yaml
# overlays/cluster-01-central/values.yaml
# 공통 S3 설정을 모든 컴포넌트에 적용

# ============================================================
# 공통 S3 오브젝트 스토리지 설정
# ============================================================
objstoreConfig: |-
  type: S3
  config:
    bucket: "thanos"
    endpoint: "s3.minio.example.com:9000"
    access_key: "minio"
    secret_key: "minio123"
    insecure: false
    http_config:
      tls_config:
        ca_file: /etc/thanos/certs/ca.crt
        insecure_skip_verify: false
        server_name: s3.minio.example.com

# ============================================================
# Thanos Receiver
# ============================================================
receive:
  enabled: true
  mode: standalone
  replicaCount: 3

  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

# ============================================================
# Thanos Compactor
# ============================================================
compactor:
  enabled: true

  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

  retentionResolutionRaw: 30d
  retentionResolution5m: 180d
  retentionResolution1h: 10y

# ============================================================
# Thanos Store Gateway
# ============================================================
storegateway:
  enabled: true
  replicaCount: 2

  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

# ============================================================
# Thanos Ruler
# ============================================================
ruler:
  enabled: true

  extraVolumes:
    - name: s3-ca-cert
      secret:
        secretName: thanos-s3-ca-cert

  extraVolumeMounts:
    - name: s3-ca-cert
      mountPath: /etc/thanos/certs
      readOnly: true

  alertmanagers:
    - http://alertmanager.monitoring.svc.cluster.local:9093

  queries:
    - dnssrv+_http._tcp.thanos-query.monitoring.svc.cluster.local

# ============================================================
# Thanos Query (S3 접근 안 함)
# ============================================================
query:
  enabled: true
  replicaCount: 2

# ============================================================
# Grafana
# ============================================================
grafana:
  enabled: true
```

---

## 배포 방법

### 1. Secret 및 ConfigMap 생성

```bash
# 1. CA 인증서 Secret 생성
kubectl create secret generic thanos-s3-ca-cert \
  --from-file=ca.crt=./certs/minio-ca.crt \
  -n monitoring

# 2. S3 Config ConfigMap 생성
kubectl create configmap thanos-objstore-config \
  --from-file=objstore.yml \
  -n monitoring
```

---

### 2. Kustomize + Helm으로 배포

```bash
# Kustomize 빌드 후 kubectl 적용
cd overlays/cluster-01-central/thanos-receiver
kustomize build . --enable-helm | kubectl apply -f -

# 또는 모든 컴포넌트 배포
cd overlays/cluster-01-central
kustomize build . --enable-helm | kubectl apply -f -
```

---

### 3. Helm만 사용하는 경우

```bash
# values.yaml 준비 후 Helm 설치
helm upgrade --install thanos bitnami/thanos \
  --namespace monitoring \
  --create-namespace \
  --values values.yaml \
  --wait
```

---

## 검증 및 테스트

### 1. Secret 확인

```bash
# Secret 존재 확인
kubectl get secret thanos-s3-ca-cert -n monitoring

# Secret 내용 확인
kubectl get secret thanos-s3-ca-cert -n monitoring -o jsonpath='{.data.ca\.crt}' | base64 -d

# Secret이 올바른 인증서인지 확인
kubectl get secret thanos-s3-ca-cert -n monitoring -o jsonpath='{.data.ca\.crt}' | \
  base64 -d | openssl x509 -text -noout
```

---

### 2. Pod 볼륨 마운트 확인

```bash
# Receiver Pod 확인
kubectl exec -it thanos-receiver-0 -n monitoring -- ls -la /etc/thanos/certs/

# 출력 예시:
# total 8
# drwxrwxrwt 3 root root  120 Oct 28 01:00 .
# drwxr-xr-x 3 root root 4096 Oct 28 01:00 ..
# drwxr-xr-x 2 root root   80 Oct 28 01:00 ..2024_10_28_01_00_00.123456789
# lrwxrwxrwx 1 root root   31 Oct 28 01:00 ..data -> ..2024_10_28_01_00_00.123456789
# lrwxrwxrwx 1 root root   13 Oct 28 01:00 ca.crt -> ..data/ca.crt

# 인증서 내용 확인
kubectl exec -it thanos-receiver-0 -n monitoring -- cat /etc/thanos/certs/ca.crt
```

---

### 3. S3 연결 테스트

```bash
# Receiver에서 S3 연결 테스트
kubectl exec -it thanos-receiver-0 -n monitoring -- \
  curl -v --cacert /etc/thanos/certs/ca.crt \
  https://s3.minio.example.com:9000/minio/health/live

# 성공 출력:
# * Server certificate:
# *  subject: CN=s3.minio.example.com
# *  issuer: CN=MinIO-CA
# *  SSL certificate verify ok.
# < HTTP/1.1 200 OK
```

---

### 4. Thanos 로그 확인

```bash
# Receiver 로그에서 S3 연결 확인
kubectl logs -f thanos-receiver-0 -n monitoring | grep -i "s3\|bucket\|objstore"

# 성공 로그 예시:
# level=info ts=2024-10-28T01:00:00.000Z caller=objstore.go:123 msg="bucket client created" bucket=thanos
# level=info ts=2024-10-28T01:00:00.000Z caller=shipper.go:234 msg="upload successful" block=01HX...

# 오류 로그 예시 (TLS 실패):
# level=error ts=2024-10-28T01:00:00.000Z caller=objstore.go:123 msg="failed to create bucket client" err="x509: certificate signed by unknown authority"
```

---

### 5. S3 블록 업로드 확인

```bash
# MinIO에서 블록 확인
kubectl exec -it minio-0 -n minio -- mc ls local/thanos/

# 또는 mc 클라이언트 사용
mc alias set minio https://s3.minio.example.com:9000 minio minio123 \
  --insecure  # 자체 서명 인증서인 경우

mc ls minio/thanos/

# 출력 예시:
# [2024-10-28 01:00:00 UTC]     0B 01HX.../
# [2024-10-28 02:00:00 UTC]     0B 01HY.../
```

---

### 6. Thanos Store Gateway 쿼리 테스트

```bash
# Store Gateway에서 블록 목록 조회
kubectl exec -it thanos-store-0 -n monitoring -- \
  wget -qO- http://localhost:10902/api/v1/stores

# Query에서 Store Gateway 연동 확인
kubectl exec -it thanos-query-0 -n monitoring -- \
  wget -qO- http://localhost:10902/api/v1/stores | jq .
```

---

## 트러블슈팅

### 문제 1: x509: certificate signed by unknown authority

**증상**:
```
level=error msg="failed to create bucket client" err="x509: certificate signed by unknown authority"
```

**원인**: CA 인증서가 마운트되지 않았거나 경로가 잘못됨

**해결**:
```bash
# 1. Secret 확인
kubectl get secret thanos-s3-ca-cert -n monitoring

# 2. Pod 볼륨 마운트 확인
kubectl describe pod thanos-receiver-0 -n monitoring | grep -A 10 "Mounts:"

# 3. 인증서 파일 확인
kubectl exec -it thanos-receiver-0 -n monitoring -- ls -la /etc/thanos/certs/ca.crt

# 4. values.yaml 수정
extraVolumes:
  - name: s3-ca-cert
    secret:
      secretName: thanos-s3-ca-cert  # Secret 이름 확인

extraVolumeMounts:
  - name: s3-ca-cert
    mountPath: /etc/thanos/certs  # 경로 확인
    readOnly: true

# 5. objstore.yml 경로 확인
http_config:
  tls_config:
    ca_file: /etc/thanos/certs/ca.crt  # 경로 일치 확인
```

---

### 문제 2: x509: certificate is valid for X, not Y

**증상**:
```
x509: certificate is valid for s3.minio.local, not s3.minio.example.com
```

**원인**: 인증서의 CN/SAN과 endpoint 호스트명 불일치

**해결**:
```yaml
# 옵션 1: server_name 설정
http_config:
  tls_config:
    ca_file: /etc/thanos/certs/ca.crt
    server_name: s3.minio.local  # 인증서의 CN과 일치

# 옵션 2: endpoint 수정
config:
  endpoint: "s3.minio.local:9000"  # 인증서의 CN 사용

# 옵션 3: 검증 건너뛰기 (개발 환경만)
http_config:
  tls_config:
    ca_file: /etc/thanos/certs/ca.crt
    insecure_skip_verify: true  # 프로덕션에서는 금지
```

---

### 문제 3: Secret이 Pod에 마운트되지 않음

**증상**:
```bash
kubectl exec -it thanos-receiver-0 -n monitoring -- ls /etc/thanos/certs/
# ls: cannot access '/etc/thanos/certs/': No such file or directory
```

**원인**: Helm values에 볼륨 설정이 반영되지 않음

**해결**:
```bash
# 1. Helm Release 확인
helm get values thanos -n monitoring

# 2. values.yaml 재확인
cat overlays/cluster-01-central/thanos-receiver/values.yaml

# 3. Pod 재생성
kubectl delete pod thanos-receiver-0 -n monitoring

# 4. StatefulSet 확인
kubectl get statefulset thanos-receiver -n monitoring -o yaml | grep -A 20 volumes:
```

---

### 문제 4: ConfigMap 변경이 반영되지 않음

**증상**: objstore.yml 수정 후에도 이전 설정 사용

**원인**: ConfigMap은 Pod 재시작 필요

**해결**:
```bash
# 1. ConfigMap 업데이트
kubectl apply -f objstore-config.yaml

# 2. Pod 재시작
kubectl rollout restart statefulset/thanos-receiver -n monitoring
kubectl rollout restart statefulset/thanos-compactor -n monitoring
kubectl rollout restart statefulset/thanos-store -n monitoring

# 3. 변경 확인
kubectl exec -it thanos-receiver-0 -n monitoring -- \
  cat /etc/thanos/objstore.yml
```

---

### 문제 5: MinIO 연결 타임아웃

**증상**:
```
level=error msg="failed to upload block" err="context deadline exceeded"
```

**원인**: 네트워크 문제 또는 MinIO 다운

**해결**:
```bash
# 1. MinIO 상태 확인
kubectl get pods -n minio

# 2. MinIO 서비스 확인
kubectl get svc -n minio

# 3. 네트워크 연결 테스트
kubectl exec -it thanos-receiver-0 -n monitoring -- \
  nc -zv s3.minio.example.com 9000

# 4. DNS 확인
kubectl exec -it thanos-receiver-0 -n monitoring -- \
  nslookup s3.minio.example.com

# 5. Endpoint 수정 (IP 사용)
config:
  endpoint: "192.168.101.195:9000"  # IP 직접 사용
```

---

## 보안 고려사항

### 1. Secret 보안

```yaml
# Secret을 Git에 커밋하지 않기
# .gitignore에 추가
*.crt
*.key
*.pem
certs/

# Sealed Secrets 사용 (권장)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: thanos-s3-ca-cert
  namespace: monitoring
spec:
  encryptedData:
    ca.crt: AgB...encrypted...
```

---

### 2. 최소 권한 원칙

```yaml
# Secret을 필요한 컴포넌트에만 마운트
# Query, Query Frontend는 S3 접근 안 함
query:
  enabled: true
  extraVolumes: []  # S3 CA 인증서 불필요
  extraVolumeMounts: []
```

---

### 3. 인증서 만료 모니터링

```yaml
# Prometheus Rule 추가
groups:
  - name: certificate_expiry
    rules:
      - alert: S3CertificateExpiring
        expr: |
          (
            time() -
            (ssl_certificate_not_after{job="minio"} - 2592000)
          ) > 0
        for: 24h
        labels:
          severity: warning
        annotations:
          summary: "S3 인증서가 30일 내 만료됩니다"
```

---

## 요약

### 필수 단계

1. ✅ MinIO CA 인증서 추출 (minio-ca.crt)
2. ✅ Kubernetes Secret 생성 (thanos-s3-ca-cert)
3. ✅ S3 Config ConfigMap 생성 (objstore.yml)
4. ✅ Helm Values에 볼륨 마운트 설정
5. ✅ objstore.yml에 ca_file 경로 설정
6. ✅ Pod 재시작 및 연결 확인

### 체크리스트

| 단계 | 확인 항목 |
|------|----------|
| **인증서** | ✅ CA 인증서 파일 준비 (.crt) |
| **Secret** | ✅ kubectl create secret으로 생성 |
| **ConfigMap** | ✅ objstore.yml 생성 및 ca_file 경로 설정 |
| **Helm Values** | ✅ extraVolumes, extraVolumeMounts 설정 |
| **배포** | ✅ kustomize build 또는 helm upgrade |
| **검증** | ✅ Pod 볼륨 마운트 확인 |
| **테스트** | ✅ S3 연결 테스트 (curl) |
| **로그** | ✅ Thanos 로그에서 오류 없는지 확인 |
| **블록** | ✅ MinIO에 블록 업로드 확인 |

### 적용 대상

| 컴포넌트 | CA 인증서 필요 |
|---------|--------------|
| Receiver | ✅ 필수 |
| Compactor | ✅ 필수 |
| Store Gateway | ✅ 필수 |
| Ruler | ✅ 필수 |
| Query | ❌ 불필요 |
| Query Frontend | ❌ 불필요 |
| Grafana | ❌ 불필요 |

**핵심**: S3에 직접 접근하는 컴포넌트(Receiver, Compactor, Store, Ruler)만 CA 인증서 설정이 필요합니다!
