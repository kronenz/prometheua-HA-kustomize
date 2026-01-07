#!/bin/bash
# kubeadm 단일 노드 클러스터 설치 스크립트
# 컨트롤 플레인 + 워커 노드를 하나의 노드에 구성합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.29}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.96.0.0/12}"
CLUSTER_NAME="${CLUSTER_NAME:-single-node-cluster}"

echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  kubeadm 단일 노드 클러스터 설치 스크립트        ║${NC}"
echo -e "${BLUE}║  (Control Plane + Worker Node)                   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}설정:${NC}"
echo "  - Kubernetes Version: ${KUBERNETES_VERSION}"
echo "  - Pod CIDR: ${POD_CIDR}"
echo "  - Service CIDR: ${SERVICE_CIDR}"
echo "  - Cluster Name: ${CLUSTER_NAME}"
echo ""

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}이 스크립트는 root 권한으로 실행해야 합니다.${NC}"
    echo "사용법: sudo $0"
    exit 1
fi

# ============================================
# 1. 시스템 사전 준비
# ============================================
echo -e "${YELLOW}1. 시스템 사전 준비...${NC}"

# Swap 비활성화
echo -n "  Swap 비활성화... "
swapoff -a
sed -i '/swap/d' /etc/fstab
echo -e "${GREEN}✓${NC}"

# 필수 커널 모듈 로드
echo -n "  커널 모듈 로드... "
cat <<EOF | tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
echo -e "${GREEN}✓${NC}"

# 커널 파라미터 설정
echo -n "  커널 파라미터 설정... "
cat <<EOF | tee /etc/sysctl.d/k8s.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system > /dev/null 2>&1
echo -e "${GREEN}✓${NC}"

# ============================================
# 2. containerd 설치
# ============================================
echo ""
echo -e "${YELLOW}2. containerd 설치...${NC}"

if command -v containerd &> /dev/null; then
    echo -e "  ${GREEN}✓ containerd가 이미 설치되어 있습니다${NC}"
else
    echo "  필수 패키지 설치 중..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release apt-transport-https

    echo "  Docker 저장소 추가 중..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "  containerd 설치 중..."
    apt-get update -qq
    apt-get install -y -qq containerd.io

    echo -e "  ${GREEN}✓ containerd 설치 완료${NC}"
fi

# containerd 설정
echo -n "  containerd 설정... "
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

# SystemdCgroup 활성화
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
echo -e "${GREEN}✓${NC}"

# ============================================
# 3. kubeadm, kubelet, kubectl 설치
# ============================================
echo ""
echo -e "${YELLOW}3. Kubernetes 컴포넌트 설치...${NC}"

if command -v kubeadm &> /dev/null; then
    CURRENT_VERSION=$(kubeadm version -o short 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓ kubeadm이 이미 설치되어 있습니다 (${CURRENT_VERSION})${NC}"
else
    echo "  Kubernetes 저장소 추가 중..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg --yes

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

    echo "  kubeadm, kubelet, kubectl 설치 중..."
    apt-get update -qq
    apt-get install -y -qq kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    echo -e "  ${GREEN}✓ Kubernetes 컴포넌트 설치 완료${NC}"
fi

# kubelet 활성화
systemctl enable kubelet

# ============================================
# 4. kubeadm 클러스터 초기화
# ============================================
echo ""
echo -e "${YELLOW}4. Kubernetes 클러스터 초기화...${NC}"

# 기존 클러스터 확인
if [ -f /etc/kubernetes/admin.conf ]; then
    echo -e "${YELLOW}  기존 클러스터가 감지되었습니다.${NC}"
    read -p "  클러스터를 초기화하고 재설치하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "  기존 클러스터 제거 중..."
        kubeadm reset -f
        rm -rf /etc/cni/net.d
        rm -rf $HOME/.kube
        iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
    else
        echo -e "${GREEN}  기존 클러스터를 유지합니다.${NC}"
        exit 0
    fi
fi

echo "  클러스터 초기화 중 (약 2-3분 소요)..."
kubeadm init \
    --pod-network-cidr=${POD_CIDR} \
    --service-cidr=${SERVICE_CIDR} \
    --kubernetes-version=stable \
    --ignore-preflight-errors=NumCPU,Mem

echo -e "${GREEN}  ✓ 클러스터 초기화 완료${NC}"

# ============================================
# 5. kubectl 설정
# ============================================
echo ""
echo -e "${YELLOW}5. kubectl 설정...${NC}"

# root 사용자 설정
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 일반 사용자도 사용할 수 있도록 설정 (선택사항)
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
    mkdir -p $USER_HOME/.kube
    cp -f /etc/kubernetes/admin.conf $USER_HOME/.kube/config
    chown $SUDO_USER:$SUDO_USER $USER_HOME/.kube/config
fi

echo -e "${GREEN}  ✓ kubectl 설정 완료${NC}"

# ============================================
# 6. Control Plane Taint 제거 (워커 노드로도 사용)
# ============================================
echo ""
echo -e "${YELLOW}6. Control Plane Taint 제거...${NC}"

# 노드가 Ready 상태가 될 때까지 대기
echo -n "  노드 준비 대기 중... "
for i in {1..60}; do
    if kubectl get nodes 2>/dev/null | grep -q "NotReady"; then
        sleep 2
    else
        break
    fi
done

# Taint 제거 (워크로드 스케줄링 허용)
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true
echo -e "${GREEN}✓${NC}"

# ============================================
# 7. CNI (Flannel) 설치
# ============================================
echo ""
echo -e "${YELLOW}7. CNI (Flannel) 설치...${NC}"

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo -e "${GREEN}  ✓ Flannel CNI 설치 완료${NC}"

# ============================================
# 8. 노드 Ready 상태 대기
# ============================================
echo ""
echo -e "${YELLOW}8. 노드 Ready 상태 대기...${NC}"

echo -n "  노드 준비 중"
for i in {1..120}; do
    if kubectl get nodes 2>/dev/null | grep -q " Ready"; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# CoreDNS 준비 대기
echo -n "  CoreDNS 준비 중"
for i in {1..60}; do
    READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$READY" == *"True"* ]]; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# ============================================
# 9. 설치 확인
# ============================================
echo ""
echo -e "${YELLOW}9. 설치 확인...${NC}"

echo -n "  클러스터 상태 확인... "
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

echo -n "  노드 Ready 확인... "
if kubectl get nodes | grep -q " Ready"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

echo -n "  시스템 Pod 확인... "
PENDING=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -v NAME | wc -l)
if [ "$PENDING" -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}일부 Pod 대기 중${NC}"
fi

# ============================================
# 결과 출력
# ============================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       kubeadm 단일 노드 클러스터 설치 완료!      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}클러스터 정보:${NC}"
kubectl cluster-info
echo ""

echo -e "${GREEN}노드 정보:${NC}"
kubectl get nodes -o wide
echo ""

echo -e "${GREEN}시스템 Pod 상태:${NC}"
kubectl get pods -n kube-system
echo ""

echo -e "${GREEN}Kubernetes 버전:${NC}"
kubectl version --short 2>/dev/null || kubectl version
echo ""

echo -e "${YELLOW}다음 단계:${NC}"
echo "  1. metrics-server 설치 (선택사항):"
echo "     kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
echo ""
echo "  2. 스토리지 클래스 구성 (Longhorn):"
echo "     scripts/deploy-component.sh storage"
echo ""
echo "  3. Ingress Controller 설치:"
echo "     scripts/deploy-component.sh ingress"
echo ""
