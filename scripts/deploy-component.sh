#!/bin/bash
# 개별 컴포넌트 배포 스크립트
# 특정 컴포넌트를 현재 클러스터에 배포합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 스크립트 경로
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 사용법
usage() {
    echo "사용법: $0 <component> [cluster-name]"
    echo ""
    echo "Components:"
    echo "  longhorn       - Longhorn Storage 배포"
    echo "  ingress-nginx  - NGINX Ingress 배포"
    echo "  prometheus     - Prometheus Stack 배포"
    echo "  opensearch     - OpenSearch 배포"
    echo "  fluent-bit     - Fluent-bit 배포"
    echo ""
    echo "Cluster Names:"
    echo "  cluster-196-central"
    echo "  cluster-197-edge"
    echo "  cluster-198-edge"
    echo ""
    echo "예제:"
    echo "  $0 longhorn cluster-196-central"
    echo "  $0 prometheus  # 자동 감지"
    exit 1
}

# 인자 확인
if [ $# -lt 1 ]; then
    usage
fi

COMPONENT="$1"
CLUSTER_NAME="${2:-}"

# 클러스터 이름 자동 감지
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${YELLOW}클러스터 이름 자동 감지 중...${NC}"

    if ! kubectl cluster-info > /dev/null 2>&1; then
        echo -e "${RED}kubectl이 클러스터에 연결되어 있지 않습니다${NC}"
        exit 1
    fi

    # 노드 IP로 클러스터 감지
    NODE_IP=$(kubectl get nodes -o wide 2>/dev/null | awk 'NR==2 {print $6}')

    if [[ "$NODE_IP" =~ 192\.168\.101\.196 ]]; then
        CLUSTER_NAME="cluster-196-central"
    elif [[ "$NODE_IP" =~ 192\.168\.101\.197 ]]; then
        CLUSTER_NAME="cluster-197-edge"
    elif [[ "$NODE_IP" =~ 192\.168\.101\.198 ]]; then
        CLUSTER_NAME="cluster-198-edge"
    else
        echo -e "${RED}클러스터를 자동 감지할 수 없습니다. 명시적으로 지정하세요.${NC}"
        usage
    fi

    echo -e "${GREEN}감지된 클러스터: ${CLUSTER_NAME}${NC}"
fi

# 네임스페이스 결정
case "$COMPONENT" in
    longhorn)
        NAMESPACE="longhorn-system"
        DISPLAY_NAME="Longhorn Storage"
        ;;
    ingress-nginx)
        NAMESPACE="ingress-nginx"
        DISPLAY_NAME="NGINX Ingress Controller"
        ;;
    prometheus)
        NAMESPACE="monitoring"
        DISPLAY_NAME="Prometheus Stack"
        ;;
    opensearch)
        NAMESPACE="logging"
        DISPLAY_NAME="OpenSearch"
        ;;
    fluent-bit)
        NAMESPACE="logging"
        DISPLAY_NAME="Fluent-bit"
        ;;
    *)
        echo -e "${RED}알 수 없는 컴포넌트: ${COMPONENT}${NC}"
        usage
        ;;
esac

OVERLAY_PATH="${PROJECT_ROOT}/deploy/overlays/${CLUSTER_NAME}/${COMPONENT}"

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ${DISPLAY_NAME} 배포${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "클러스터: ${CLUSTER_NAME}"
echo "컴포넌트: ${COMPONENT}"
echo "네임스페이스: ${NAMESPACE}"
echo "Overlay 경로: ${OVERLAY_PATH}"
echo ""

# Overlay 디렉토리 확인
if [ ! -d "$OVERLAY_PATH" ]; then
    echo -e "${RED}✗ Overlay 디렉토리가 존재하지 않습니다: ${OVERLAY_PATH}${NC}"
    exit 1
fi

# Kustomize 확인
if ! command -v kustomize &> /dev/null; then
    echo -e "${RED}✗ kustomize가 설치되어 있지 않습니다${NC}"
    exit 1
fi

# kubectl 클러스터 연결 확인
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${RED}✗ kubectl이 클러스터에 연결되어 있지 않습니다${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 사전 확인 완료${NC}"
echo ""

# 네임스페이스 생성
echo -e "${YELLOW}네임스페이스 생성 중...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ 네임스페이스 준비 완료${NC}"
echo ""

# Kustomize 빌드 미리보기 (선택사항)
if [ "${DRY_RUN:-false}" = "true" ]; then
    echo -e "${YELLOW}Dry-run 모드: 빌드 결과 미리보기${NC}"
    echo "─────────────────────────────────────────────────"
    kustomize build "${OVERLAY_PATH}" --enable-helm
    echo "─────────────────────────────────────────────────"
    exit 0
fi

# 배포 실행
echo -e "${YELLOW}배포 시작...${NC}"
echo ""

if kustomize build "${OVERLAY_PATH}" --enable-helm | kubectl apply -f - -n "$NAMESPACE"; then
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ${DISPLAY_NAME} 배포 완료!${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
    echo ""

    # 배포 확인
    echo -e "${YELLOW}배포 상태 확인 중 (30초 대기)...${NC}"
    sleep 5

    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "  (아직 생성 중...)"

    echo ""
    echo "Services:"
    kubectl get svc -n "$NAMESPACE" 2>/dev/null || echo "  (아직 생성 중...)"

    echo ""
    echo -e "${BLUE}다음 명령으로 상태를 모니터링하세요:${NC}"
    echo "  kubectl get pods -n ${NAMESPACE} -w"
    echo ""
    echo -e "${BLUE}로그 확인:${NC}"
    echo "  kubectl logs -n ${NAMESPACE} -l app=${COMPONENT} --tail=100"
    echo ""

    exit 0
else
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ${DISPLAY_NAME} 배포 실패${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}문제 해결:${NC}"
    echo "  1. Overlay 경로 확인: ${OVERLAY_PATH}"
    echo "  2. Kustomize 빌드 테스트: kustomize build ${OVERLAY_PATH} --enable-helm"
    echo "  3. 클러스터 상태 확인: kubectl cluster-info"
    echo "  4. 리소스 확인: kubectl get all -n ${NAMESPACE}"
    exit 1
fi
