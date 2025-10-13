#!/bin/bash
# S3 버킷 검증 스크립트
# MinIO S3의 버킷이 정상적으로 생성되고 접근 가능한지 확인합니다.

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

echo -e "${GREEN}=== MinIO S3 버킷 검증 ===${NC}"
echo "Endpoint: ${S3_ENDPOINT}"
echo ""

# mc 설치 확인
if ! command -v mc &> /dev/null; then
    echo -e "${RED}❌ MinIO Client (mc)가 설치되어 있지 않습니다.${NC}"
    echo "다음 명령으로 설치하세요: scripts/s3/create-buckets.sh"
    exit 1
fi

# mc alias 설정
mc alias set thanos-minio ${S3_ENDPOINT} ${S3_ACCESS_KEY} ${S3_SECRET_KEY} --insecure > /dev/null 2>&1

# 연결 테스트
echo -e "${YELLOW}MinIO 연결 확인 중...${NC}"
if ! mc admin info thanos-minio --insecure > /dev/null 2>&1; then
    echo -e "${RED}❌ MinIO 연결 실패${NC}"
    exit 1
fi
echo -e "${GREEN}✓ MinIO 연결 성공${NC}"
echo ""

# 버킷 검증
echo -e "${GREEN}=== 버킷 검증 ===${NC}"
FAILED=0

for bucket in "${BUCKETS[@]}"; do
    echo -n "버킷: ${bucket} ... "

    # 버킷 존재 확인
    if mc ls thanos-minio/${bucket} --insecure > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 존재${NC}"

        # 쓰기 테스트
        TEST_FILE="/tmp/test-${bucket}.txt"
        echo "test" > ${TEST_FILE}

        if mc cp ${TEST_FILE} thanos-minio/${bucket}/test.txt --insecure > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓ 쓰기 가능${NC}"

            # 읽기 테스트
            if mc cat thanos-minio/${bucket}/test.txt --insecure > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓ 읽기 가능${NC}"
            else
                echo -e "  ${RED}❌ 읽기 실패${NC}"
                FAILED=$((FAILED + 1))
            fi

            # 삭제 테스트
            if mc rm thanos-minio/${bucket}/test.txt --insecure > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓ 삭제 가능${NC}"
            else
                echo -e "  ${YELLOW}⚠ 삭제 실패 (권한 문제 가능성)${NC}"
            fi

            rm -f ${TEST_FILE}
        else
            echo -e "  ${RED}❌ 쓰기 실패${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}❌ 존재하지 않음${NC}"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

# 결과 요약
echo -e "${GREEN}=== 검증 결과 ===${NC}"
if [ ${FAILED} -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 버킷이 정상적으로 동작합니다.${NC}"
    exit 0
else
    echo -e "${RED}❌ ${FAILED}개 버킷에서 문제가 발견되었습니다.${NC}"
    echo "scripts/s3/create-buckets.sh를 실행하여 버킷을 생성하세요."
    exit 1
fi
