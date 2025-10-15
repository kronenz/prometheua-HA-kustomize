#!/bin/bash

# Ubuntu 22.04에 최적화된 단일 노드 Kubernetes 클러스터 구축 스크립트
# Container Runtime: containerd (Binary)
# CNI: Cilium (Helm) with kube-proxy replacement & L2 Announcement

# 스크립트 실행 중 오류가 발생하면 즉시 중단
set -e

# --- 변수 정의 ---
CONTAINERD_VERSION="2.1.4"
KUBERNETES_VERSION="1.34.1"
NODE_IP="192.168.56.10"
POD_CIDR="10.244.0.0/16"

# --- 1. 시스템 사전 설정 ---
echo "--- [단계 1/7] 시스템 사전 설정 시작 ---"
sudo swapoff -a
sudo sed -i '/[[:space:]]swap[[:space:]]/ s/^\(.*\)$/#\1/' /etc/fstab
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
echo "--- [단계 1/7] 시스템 사전 설정 완료 ---"
echo ""


# --- 2. Containerd (바이너리) 및 runc (apt) 설치 ---
echo "--- [단계 2/7] Containerd v${CONTAINERD_VERSION} 및 runc 설치 시작 ---"
sudo apt-get update && sudo apt upgrade -y && sudo apt install net-tools -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release runc

# containerd 최신 바이너리 다운로드 및 설치
wget "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
sudo tar Czxvf "/usr/local" "containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
rm "containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"

# containerd systemd 서비스 파일 설정
sudo wget -O /etc/systemd/system/containerd.service https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

# containerd 설정
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable containerd
echo "--- [단계 2/7] Containerd 및 runc 설치 완료 ---"
echo ""


# --- 3. Kubernetes 도구 설치 ---
echo "--- [단계 3/7] Kubernetes 도구 설치 시작 ---"
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
echo "--- [단계 3/7] Kubernetes 도구 설치 완료 ---"
echo ""


# --- 4. kubeadm으로 클러스터 초기화 ---
echo "--- [단계 4/7] kubeadm 설정 파일 생성 및 클러스터 초기화 시작 ---"
cat <<EOF | sudo tee /root/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  name: kubernetes
skipPhases:
  - addon/kube-proxy
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: ${KUBERNETES_VERSION}
controlPlaneEndpoint: "${NODE_IP}:6443"
networking:
  podSubnet: ${POD_CIDR}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

sudo kubeadm init --config /root/kubeadm-config.yaml --upload-certs
echo "--- [단계 4/7] Kubernetes 클러스터 초기화 완료 ---"
echo ""

# --- 5. kubectl 환경 설정 및 단일 노드 설정 ---
echo "--- [단계 5/7] kubectl 환경 설정 및 단일 노드 설정 시작 ---"
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl scale deployment coredns -n kube-system --replicas=1
echo "--- [단계 5/7] kubectl 환경 설정 및 단일 노드 설정 완료 ---"
echo ""

# --- 6. Helm CLI 설치 및 Cilium CLI 설치 ---
echo "--- [단계 6/7] Helm CLI 설치 시작 ---"
sudo apt-get install -y curl gpg apt-transport-https

curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update
sudo apt-get install -y helm

CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}


echo "--- [단계 6/7] Helm CLI 및 Cilium CLI 설치 완료 ---"
echo ""


# --- 7. Helm을 사용하여 Cilium CNI 설치 ---
echo "--- [단계 7/7] Cilium 설치 시작 ---"
helm repo add cilium https://helm.cilium.io/
helm repo update

echo "Cilium을 설치합니다... (kube-proxy replacement, L2 announcement, operator replicas=1 최적화)"
helm install cilium cilium/cilium --version 1.18.2 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=${NODE_IP} \
  --set k8sServicePort=6443 \
  --set l2announcements.enabled=true \
  --set operator.replicas=1

echo "--- [단계 7/7] Cilium 설치 완료 ---"
echo ""
echo "🎉 전체 클러스터 구성이 완료되었습니다! 🎉"
echo ""
echo "잠시 후 아래 명령어로 Cilium Pod들이 정상적으로 실행되는지 확인하세요:"
echo "kubectl get pods -n kube-system -w"


apiVersion: "cilium.io/v2"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "ip-pool"
spec:
  blocks:
  - start: "192.168.101.194"
    stop: "192.168.101.194"

