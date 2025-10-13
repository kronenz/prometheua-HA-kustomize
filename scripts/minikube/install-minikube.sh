#!/bin/bash
# Minikube 설치 및 초기화 스크립트
# 각 노드에서 실행하여 Minikube 클러스터를 설치합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정
MINIKUBE_VERSION="${MINIKUBE_VERSION:-latest}"
KUBECTL_VERSION="${KUBECTL_VERSION:-latest}"
DRIVER="${DRIVER:-containerd}"
CPUS="${CPUS:-4}"
MEMORY="${MEMORY:-16384}"
DISK_SIZE="${DISK_SIZE:-50g}"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Minikube 설치 및 초기화 스크립트   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}설정:${NC}"
echo "  - Driver: ${DRIVER}"
echo "  - CPUs: ${CPUS}"
echo "  - Memory: ${MEMORY}MB"
echo "  - Disk: ${DISK_SIZE}"
echo ""

# 사전 요구사항 확인
echo -e "${YELLOW}1. 사전 요구사항 확인 중...${NC}"

# Docker/containerd 확인
if [ "${DRIVER}" = "containerd" ]; then
    echo -n "  containerd 확인 중... "
    if command -v containerd &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}containerd가 설치되어 있지 않습니다.${NC}"
        echo "다음 명령으로 설치하세요:"
        echo "  sudo apt-get update && sudo apt-get install -y containerd"
        exit 1
    fi
elif [ "${DRIVER}" = "docker" ]; then
    echo -n "  Docker 확인 중... "
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}Docker가 설치되어 있지 않습니다.${NC}"
        exit 1
    fi
fi

# curl 확인
echo -n "  curl 확인 중... "
if command -v curl &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}curl이 설치되어 있지 않습니다.${NC}"
    sudo apt-get update && sudo apt-get install -y curl
fi

# Minikube 설치
echo ""
echo -e "${YELLOW}2. Minikube 설치 중...${NC}"

if command -v minikube &> /dev/null; then
    CURRENT_VERSION=$(minikube version --short 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓ Minikube가 이미 설치되어 있습니다 (${CURRENT_VERSION})${NC}"
else
    echo "  Minikube 다운로드 중..."
    curl -sLO https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64

    echo "  Minikube 설치 중..."
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64

    echo -e "  ${GREEN}✓ Minikube 설치 완료${NC}"
fi

# kubectl 설치
echo ""
echo -e "${YELLOW}3. kubectl 설치 중...${NC}"

if command -v kubectl &> /dev/null; then
    KUBECTL_CURRENT=$(kubectl version --client -o json 2>/dev/null | grep gitVersion || echo "unknown")
    echo -e "  ${GREEN}✓ kubectl이 이미 설치되어 있습니다${NC}"
else
    echo "  kubectl 다운로드 중..."
    if [ "${KUBECTL_VERSION}" = "latest" ]; then
        KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
    fi

    curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

    echo "  kubectl 설치 중..."
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl

    echo -e "  ${GREEN}✓ kubectl 설치 완료${NC}"
fi

# Minikube 시작
echo ""
echo -e "${YELLOW}4. Minikube 클러스터 시작 중...${NC}"

# 기존 클러스터 확인
if minikube status > /dev/null 2>&1; then
    echo -e "${YELLOW}  기존 Minikube 클러스터가 실행 중입니다.${NC}"
    read -p "  클러스터를 삭제하고 재설치하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "  기존 클러스터 삭제 중..."
        minikube delete
    else
        echo -e "${GREEN}  기존 클러스터를 유지합니다.${NC}"
        echo ""
        echo -e "${GREEN}=== 설치 완료 ===${NC}"
        minikube status
        exit 0
    fi
fi

# 새 클러스터 시작
echo "  새 클러스터 생성 중 (약 5분 소요)..."
minikube start \
    --driver=${DRIVER} \
    --cpus=${CPUS} \
    --memory=${MEMORY} \
    --disk-size=${DISK_SIZE} \
    --kubernetes-version=stable \
    --addons=metrics-server

echo -e "${GREEN}✓ Minikube 클러스터 시작 완료${NC}"

# 설치 확인
echo ""
echo -e "${YELLOW}5. 설치 확인 중...${NC}"

echo -n "  클러스터 상태 확인... "
if minikube status > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

echo -n "  kubectl 연결 확인... "
if kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

echo -n "  노드 준비 확인... "
if kubectl get nodes | grep -q "Ready"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# 결과 출력
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Minikube 설치 완료!             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}클러스터 정보:${NC}"
minikube status
echo ""
echo -e "${GREEN}노드 정보:${NC}"
kubectl get nodes -o wide
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "  1. 다른 노드에도 이 스크립트를 실행하세요"
echo "  2. S3 버킷을 생성하세요: scripts/s3/create-buckets.sh"
echo "  3. 배포를 시작하세요: scripts/deploy-*.sh"
echo ""
