#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}ArgoCD-GitLab 연동 설정${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Get GitLab credentials
echo -e "${YELLOW}GitLab 접속 정보를 입력하세요:${NC}"
read -p "GitLab URL [http://gitlab.k8s-cluster-01.miribit.lab]: " GITLAB_URL
GITLAB_URL=${GITLAB_URL:-http://gitlab.k8s-cluster-01.miribit.lab}

read -p "GitLab Username [root]: " GITLAB_USERNAME
GITLAB_USERNAME=${GITLAB_USERNAME:-root}

read -sp "GitLab Password: " GITLAB_PASSWORD
echo ""

read -p "GitLab 저장소 URL [http://gitlab.k8s-cluster-01.miribit.lab/observability/thanos-multi-cluster.git]: " GITLAB_REPO
GITLAB_REPO=${GITLAB_REPO:-http://gitlab.k8s-cluster-01.miribit.lab/observability/thanos-multi-cluster.git}

echo ""
echo -e "${YELLOW}Step 1: ArgoCD에 GitLab 저장소 등록${NC}"

# Create GitLab repository credentials secret
kubectl create secret generic gitlab-repo-creds \
  -n argocd \
  --from-literal=username="$GITLAB_USERNAME" \
  --from-literal=password="$GITLAB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Update ArgoCD ConfigMap with repository configuration
kubectl patch configmap argocd-cm -n argocd --type merge -p "
data:
  repositories: |
    - url: $GITLAB_REPO
      passwordSecret:
        name: gitlab-repo-creds
        key: password
      usernameSecret:
        name: gitlab-repo-creds
        key: username
"

echo ""
echo -e "${YELLOW}Step 2: 에지 클러스터 kubeconfig 정보 추출${NC}"

# Function to extract and encode cluster credentials
extract_cluster_creds() {
  local cluster_name=$1
  local cluster_ip=$2
  local kubeconfig_path=$3

  echo "클러스터 $cluster_name 자격증명 추출 중..."

  # Extract from kubeconfig
  CA_DATA=$(kubectl config view --kubeconfig="$kubeconfig_path" --raw -o jsonpath="{.clusters[0].cluster.certificate-authority-data}")
  CERT_DATA=$(kubectl config view --kubeconfig="$kubeconfig_path" --raw -o jsonpath="{.users[0].user.client-certificate-data}")
  KEY_DATA=$(kubectl config view --kubeconfig="$kubeconfig_path" --raw -o jsonpath="{.users[0].user.client-key-data}")

  # Create cluster secret
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $cluster_name
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: $cluster_name
  server: https://$cluster_ip:6443
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "$CA_DATA",
        "certData": "$CERT_DATA",
        "keyData": "$KEY_DATA"
      }
    }
EOF
}

# Extract credentials for each edge cluster
if [ -f "$HOME/.kube/configs/cluster-02.conf" ]; then
  extract_cluster_creds "cluster-02-edge" "192.168.101.196" "$HOME/.kube/configs/cluster-02.conf"
fi

if [ -f "$HOME/.kube/configs/cluster-03.conf" ]; then
  extract_cluster_creds "cluster-03-edge" "192.168.101.197" "$HOME/.kube/configs/cluster-03.conf"
fi

if [ -f "$HOME/.kube/configs/cluster-04.conf" ]; then
  extract_cluster_creds "cluster-04-edge" "192.168.101.198" "$HOME/.kube/configs/cluster-04.conf"
fi

echo ""
echo -e "${YELLOW}Step 3: Observability 프로젝트 생성${NC}"
kubectl apply -f "$PROJECT_ROOT/argocd/projects/observability-project.yaml"

echo ""
echo -e "${YELLOW}Step 4: Root Application 배포${NC}"

# Update root application with GitLab repository
sed "s|<your-org>|observability|g" "$PROJECT_ROOT/argocd/root-application.yaml" | kubectl apply -f -

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}ArgoCD-GitLab 연동 설정 완료${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "1. 현재 코드를 GitLab 저장소에 푸시"
echo ""
echo "   cd $PROJECT_ROOT"
echo "   git init"
echo "   git remote add origin $GITLAB_REPO"
echo "   git add ."
echo "   git commit -m 'Initial commit: Multi-cluster observability with Thanos'"
echo "   git push -u origin main"
echo ""
echo "2. ArgoCD UI에서 Root Application 동기화"
echo "   - http://argocd.k8s-cluster-01.miribit.lab"
echo ""
echo -e "${GREEN}설정이 완료되었습니다!${NC}"
