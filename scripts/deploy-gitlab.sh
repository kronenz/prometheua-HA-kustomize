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
echo -e "${GREEN}GitLab 배포 스크립트${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Check S3 credentials
if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
  echo -e "${RED}오류: S3 자격증명이 설정되지 않았습니다.${NC}"
  echo "다음 환경변수를 설정하세요:"
  echo "  export S3_ACCESS_KEY=your_access_key"
  echo "  export S3_SECRET_KEY=your_secret_key"
  exit 1
fi

echo -e "${YELLOW}Step 1: kubectl 컨텍스트 확인${NC}"
CURRENT_CONTEXT=$(kubectl config current-context)
echo "현재 컨텍스트: $CURRENT_CONTEXT"

if [[ "$CURRENT_CONTEXT" != *"cluster-01"* ]]; then
  echo -e "${RED}경고: 현재 컨텍스트가 cluster-01이 아닙니다.${NC}"
  kubectl config use-context cluster-01
fi

echo ""
echo -e "${YELLOW}Step 2: S3 버킷 생성 (MinIO)${NC}"
echo "GitLab에 필요한 S3 버킷을 생성합니다..."

# Create GitLab S3 buckets
cat > /tmp/create-gitlab-buckets.sh <<'EOF'
#!/bin/bash
mc alias set minio http://s3.minio.miribit.lab:9000 $S3_ACCESS_KEY $S3_SECRET_KEY

buckets=("gitlab-lfs" "gitlab-artifacts" "gitlab-uploads" "gitlab-packages" "gitlab-backups" "gitlab-tmp")

for bucket in "${buckets[@]}"; do
  if mc ls minio/$bucket >/dev/null 2>&1; then
    echo "버킷 $bucket 이미 존재함"
  else
    mc mb minio/$bucket
    echo "버킷 $bucket 생성됨"
  fi
done
EOF

chmod +x /tmp/create-gitlab-buckets.sh
S3_ACCESS_KEY=$S3_ACCESS_KEY S3_SECRET_KEY=$S3_SECRET_KEY /tmp/create-gitlab-buckets.sh

echo ""
echo -e "${YELLOW}Step 3: GitLab object storage secret 생성${NC}"
cd "$PROJECT_ROOT/deploy/overlays/cluster-01-central/gitlab"

# Replace S3 credentials in secret
envsubst < gitlab-object-storage-secret.yaml | kubectl apply -f -

echo ""
echo -e "${YELLOW}Step 4: PostgreSQL 및 Redis 배포${NC}"
kubectl apply -f postgresql.yaml
kubectl apply -f redis.yaml

echo "PostgreSQL이 준비될 때까지 대기 중..."
kubectl wait --for=condition=ready pod \
  -l app=postgresql \
  -n gitlab \
  --timeout=300s

echo "Redis가 준비될 때까지 대기 중..."
kubectl wait --for=condition=ready pod \
  -l app=redis \
  -n gitlab \
  --timeout=300s

echo ""
echo -e "${YELLOW}Step 5: GitLab Helm Chart 배포${NC}"
kustomize build . --enable-helm | kubectl apply -f -

echo ""
echo -e "${YELLOW}Step 6: GitLab 파드 준비 대기 (최대 10분)${NC}"
echo "GitLab 초기화에는 시간이 걸립니다. 잠시 기다려 주세요..."

kubectl wait --for=condition=ready pod \
  -l app=webservice \
  -n gitlab \
  --timeout=600s || echo "경고: 일부 파드가 아직 준비되지 않았습니다."

echo ""
echo -e "${YELLOW}Step 7: GitLab root 비밀번호 조회${NC}"
GITLAB_ROOT_PASSWORD=$(kubectl get secret -n gitlab gitlab-gitlab-initial-root-password -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "초기 비밀번호를 찾을 수 없습니다. GitLab 파드 로그를 확인하세요.")

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}GitLab 접속 정보${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "URL: ${YELLOW}http://gitlab.k8s-cluster-01.miribit.lab${NC}"
echo -e "Username: ${YELLOW}root${NC}"
echo -e "Password: ${YELLOW}$GITLAB_ROOT_PASSWORD${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Save credentials to file
cat > "$PROJECT_ROOT/gitlab-credentials.txt" <<EOF
GitLab 접속 정보
==================
URL: http://gitlab.k8s-cluster-01.miribit.lab
Username: root
Password: $GITLAB_ROOT_PASSWORD

초기 설정 완료 후 비밀번호를 변경하세요.
EOF

echo -e "${GREEN}접속 정보가 gitlab-credentials.txt 파일에 저장되었습니다.${NC}"
echo ""
echo -e "${GREEN}GitLab 배포가 완료되었습니다!${NC}"
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "1. GitLab에 로그인하여 초기 설정을 완료하세요"
echo "2. 새로운 프로젝트 'observability/thanos-multi-cluster' 생성"
echo "3. 현재 코드를 GitLab 저장소에 푸시"
echo "4. ArgoCD와 GitLab 연동 설정"
