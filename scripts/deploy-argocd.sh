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
echo -e "${GREEN}ArgoCD 배포 스크립트${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Check if kubectl is configured for cluster-01
echo -e "${YELLOW}Step 1: kubectl 컨텍스트 확인${NC}"
CURRENT_CONTEXT=$(kubectl config current-context)
echo "현재 컨텍스트: $CURRENT_CONTEXT"

if [[ "$CURRENT_CONTEXT" != *"cluster-01"* ]]; then
  echo -e "${RED}경고: 현재 컨텍스트가 cluster-01이 아닙니다.${NC}"
  echo "cluster-01 컨텍스트로 전환하시겠습니까? (y/n)"
  read -r response
  if [[ "$response" == "y" ]]; then
    kubectl config use-context cluster-01
  else
    echo "배포를 취소합니다."
    exit 1
  fi
fi

echo ""
echo -e "${YELLOW}Step 2: ArgoCD 네임스페이스 및 리소스 배포${NC}"
cd "$PROJECT_ROOT/deploy/overlays/cluster-01-central/argocd"

# Deploy ArgoCD
kustomize build . | kubectl apply -f -

echo ""
echo -e "${YELLOW}Step 3: ArgoCD 파드 준비 대기 (최대 5분)${NC}"
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd \
  --timeout=300s

echo ""
echo -e "${YELLOW}Step 4: ArgoCD 초기 admin 비밀번호 조회${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}ArgoCD 접속 정보${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "URL: ${YELLOW}http://argocd.k8s-cluster-01.miribit.lab${NC}"
echo -e "Username: ${YELLOW}admin${NC}"
echo -e "Password: ${YELLOW}$ARGOCD_PASSWORD${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Save credentials to file
cat > "$PROJECT_ROOT/argocd-credentials.txt" <<EOF
ArgoCD 접속 정보
==================
URL: http://argocd.k8s-cluster-01.miribit.lab
Username: admin
Password: $ARGOCD_PASSWORD

초기 설정 완료 후 비밀번호를 변경하세요:
argocd account update-password
EOF

echo -e "${GREEN}접속 정보가 argocd-credentials.txt 파일에 저장되었습니다.${NC}"
echo ""
echo -e "${YELLOW}Step 5: ArgoCD CLI를 사용한 로그인 (선택 사항)${NC}"
echo "다음 명령어로 ArgoCD CLI에 로그인할 수 있습니다:"
echo ""
echo "  argocd login argocd.k8s-cluster-01.miribit.lab --username admin --password '$ARGOCD_PASSWORD' --insecure"
echo ""
echo -e "${GREEN}ArgoCD 배포가 완료되었습니다!${NC}"
