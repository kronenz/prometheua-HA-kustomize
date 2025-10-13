#!/bin/bash
# S3 버킷 생성 스크립트
# MinIO S3에 Thanos, OpenSearch, Longhorn 백업용 버킷을 생성합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 설정
S3_ENDPOINT="${S3_ENDPOINT:-https://172.20.40.21:30001}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-minio}"
S3_SECRET_KEY="${S3_SECRET_KEY:-minio123}"

BUCKETS=("thanos" "opensearch-logs" "longhorn-backups")

echo -e "${GREEN}=== MinIO S3 버킷 생성 ===${NC}"
echo "Endpoint: ${S3_ENDPOINT}"
echo ""

# mc (MinIO Client) 설치 확인
if ! command -v mc &> /dev/null; then
    echo -e "${YELLOW}MinIO Client (mc)가 설치되어 있지 않습니다. 설치를 시작합니다...${NC}"
    curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc
    chmod +x /tmp/mc
    sudo mv /tmp/mc /usr/local/bin/mc
    echo -e "${GREEN}MinIO Client 설치 완료${NC}"
fi

# mc alias 설정
echo -e "${YELLOW}MinIO 연결 설정 중...${NC}"
mc alias set thanos-minio ${S3_ENDPOINT} ${S3_ACCESS_KEY} ${S3_SECRET_KEY} --insecure

# 연결 테스트
if ! mc admin info thanos-minio --insecure > /dev/null 2>&1; then
    echo -e "${RED}❌ MinIO 연결 실패. 엔드포인트와 인증 정보를 확인하세요.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ MinIO 연결 성공${NC}"
echo ""

# 버킷 생성
for bucket in "${BUCKETS[@]}"; do
    echo -e "${YELLOW}버킷 생성 중: ${bucket}${NC}"

    # 버킷이 이미 존재하는지 확인
    if mc ls thanos-minio/${bucket} --insecure > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 버킷이 이미 존재합니다: ${bucket}${NC}"
    else
        # 버킷 생성
        if mc mb thanos-minio/${bucket} --insecure; then
            echo -e "${GREEN}✓ 버킷 생성 완료: ${bucket}${NC}"
        else
            echo -e "${RED}❌ 버킷 생성 실패: ${bucket}${NC}"
            exit 1
        fi
    fi
    echo ""
done

# 버킷 목록 확인
echo -e "${GREEN}=== 생성된 버킷 목록 ===${NC}"
mc ls thanos-minio --insecure

echo ""
echo -e "${GREEN}=== S3 버킷 생성 완료 ===${NC}"
echo ""
echo "다음 버킷들이 준비되었습니다:"
for bucket in "${BUCKETS[@]}"; do
    echo "  - ${bucket}"
done

# 버킷 상세 정보
echo ""
echo -e "${YELLOW}버킷 상세 정보:${NC}"
for bucket in "${BUCKETS[@]}"; do
    echo ""
    echo "버킷: ${bucket}"
    mc stat thanos-minio/${bucket} --insecure 2>/dev/null || echo "  (정보 없음)"
done
