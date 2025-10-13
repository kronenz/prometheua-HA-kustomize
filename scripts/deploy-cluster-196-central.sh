#!/bin/bash
# 중앙 클러스터 (196) 배포 스크립트
# Longhorn, Ingress-nginx, Prometheus+Thanos, OpenSearch, Fluent-bit 배포

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 프로젝트 루트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   중앙 클러스터 (196) 배포 스크립트   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# kubectl 연결 확인
echo -e "${YELLOW}사전 확인 중...${NC}"
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}❌ Kubernetes 클러스터에 연결할 수 없습니다.${NC}"
    echo "Minikube가 실행 중인지 확인하세요: minikube status"
    exit 1
fi
echo -e "${GREEN}✓ Kubernetes 클러스터 연결 확인${NC}"

# kustomize 확인
if ! command -v kustomize &> /dev/null; then
    echo -e "${YELLOW}kustomize가 설치되어 있지 않습니다. kubectl kustomize를 사용합니다.${NC}"
    KUSTOMIZE_CMD="kubectl kustomize"
else
    KUSTOMIZE_CMD="kustomize build"
fi

echo ""

# 1. Longhorn 배포
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}1/5 Longhorn 배포 중...${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

echo "Longhorn 매니페스트 생성 중..."
${KUSTOMIZE_CMD} ${PROJECT_ROOT}/deploy/overlays/cluster-196-central/longhorn --enable-helm > /tmp/longhorn.yaml

echo "Longhorn 배포 중..."
kubectl apply -f /tmp/longhorn.yaml

echo "Longhorn 준비 대기 중 (최대 5분)..."
kubectl wait --for=condition=available --timeout=300s deployment/longhorn-driver-deployer -n longhorn-system || true

echo -e "${GREEN}✓ Longhorn 배포 완료${NC}"
echo ""

# 2. Ingress-nginx 배포
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}2/5 NGINX Ingress 배포 중...${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

echo "Ingress-nginx 매니페스트 생성 중..."
${KUSTOMIZE_CMD} ${PROJECT_ROOT}/deploy/overlays/cluster-196-central/ingress-nginx --enable-helm > /tmp/ingress-nginx.yaml

echo "Ingress-nginx 배포 중..."
kubectl apply -f /tmp/ingress-nginx.yaml

echo "Ingress Controller 준비 대기 중 (최대 3분)..."
kubectl wait --for=condition=available --timeout=180s deployment/ingress-nginx-controller -n ingress-nginx || true

echo -e "${GREEN}✓ NGINX Ingress 배포 완료${NC}"
echo ""

# 3. Prometheus + Thanos 배포
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}3/5 Prometheus + Thanos 배포 중...${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "Prometheus + Thanos 매니페스트 생성 중..."
${KUSTOMIZE_CMD} ${PROJECT_ROOT}/deploy/overlays/cluster-196-central/prometheus --enable-helm > /tmp/prometheus.yaml

echo "Prometheus + Thanos 배포 중..."
kubectl apply -f /tmp/prometheus.yaml

echo "Prometheus Operator 준비 대기 중 (최대 5분)..."
kubectl wait --for=condition=available --timeout=300s deployment/kube-prometheus-stack-operator -n monitoring || true

echo -e "${GREEN}✓ Prometheus + Thanos 배포 완료${NC}"
echo ""

# 4. OpenSearch 배포
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}4/5 OpenSearch 배포 중...${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -

echo "OpenSearch 매니페스트 생성 중..."
${KUSTOMIZE_CMD} ${PROJECT_ROOT}/deploy/overlays/cluster-196-central/opensearch --enable-helm > /tmp/opensearch.yaml

echo "OpenSearch 배포 중..."
kubectl apply -f /tmp/opensearch.yaml

echo "OpenSearch 준비 대기 중 (최대 5분)..."
kubectl wait --for=condition=ready --timeout=300s pod -l app=opensearch -n logging || true

echo -e "${GREEN}✓ OpenSearch 배포 완료${NC}"
echo ""

# 5. Fluent-bit 배포
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}5/5 Fluent-bit 배포 중...${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

echo "Fluent-bit 매니페스트 생성 중..."
${KUSTOMIZE_CMD} ${PROJECT_ROOT}/deploy/overlays/cluster-196-central/fluent-bit --enable-helm > /tmp/fluent-bit.yaml

echo "Fluent-bit 배포 중..."
kubectl apply -f /tmp/fluent-bit.yaml

echo "Fluent-bit 준비 대기 중 (최대 2분)..."
kubectl wait --for=condition=ready --timeout=120s pod -l app.kubernetes.io/name=fluent-bit -n logging || true

echo -e "${GREEN}✓ Fluent-bit 배포 완료${NC}"
echo ""

# 배포 결과 확인
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          배포 완료!                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}배포된 리소스 확인:${NC}"
echo ""
echo "Longhorn (longhorn-system):"
kubectl get pods -n longhorn-system | head -5
echo ""
echo "Ingress-nginx (ingress-nginx):"
kubectl get pods -n ingress-nginx
echo ""
echo "Prometheus + Thanos (monitoring):"
kubectl get pods -n monitoring | head -10
echo ""
echo "OpenSearch (logging):"
kubectl get pods -n logging
echo ""

echo -e "${YELLOW}접근 URL (NodePort 30080):${NC}"
echo "  - Grafana: http://grafana.mkube-196.miribit.lab:30080"
echo "  - Thanos Query: http://thanos.mkube-196.miribit.lab:30080"
echo "  - Alertmanager: http://alertmanager.mkube-196.miribit.lab:30080"
echo "  - OpenSearch: http://opensearch.mkube-196.miribit.lab:30080"
echo "  - Longhorn UI: http://longhorn.mkube-196.miribit.lab:30080"
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "  1. 엣지 클러스터 배포: scripts/deploy-cluster-197-edge.sh"
echo "  2. 엣지 클러스터 배포: scripts/deploy-cluster-198-edge.sh"
echo "  3. 모니터링 검증: scripts/validation/verify-monitoring.sh"
echo ""
