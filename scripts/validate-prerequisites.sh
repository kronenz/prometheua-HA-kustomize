#!/bin/bash
# 사전 요구사항 검증 스크립트
# Phase 2: Foundational 단계 - T009, T010 검증

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 설정
S3_API_ENDPOINT="${S3_ENDPOINT:-http://s3.minio.miribit.lab}"
S3_CONSOLE="${S3_CONSOLE:-http://console.minio.miribit.lab}"
NODES=("192.168.101.196" "192.168.101.197" "192.168.101.198")
NODE_NAMES=("196" "197" "198")
SSH_USER="${SSH_USER:-bsh}"
SSH_PASS="${SSH_PASS:-123qwe}"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Thanos Multi-Cluster Prerequisites${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# 검증 결과 추적
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# 함수: 체크 결과 출력
check_result() {
    local name="$1"
    local result="$2"
    local message="${3:-}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ${name}"
        [ -n "$message" ] && echo -e "  ${message}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        echo -e "${RED}✗${NC} ${name}"
        [ -n "$message" ] && echo -e "  ${RED}${message}${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

echo -e "${YELLOW}[1/4] MinIO S3 연결성 검증${NC}"
echo "----------------------------------------"

# MinIO Console 접근성 확인 (현재 호스트에서)
echo -n "MinIO Console (${S3_CONSOLE}) 접근성... "
if curl -s -f -m 5 "${S3_CONSOLE}" > /dev/null 2>&1; then
    check_result "MinIO Console 접근 가능" 0 "URL: ${S3_CONSOLE}"
else
    check_result "MinIO Console 접근" 1 "Console에 접근할 수 없습니다: ${S3_CONSOLE}"
fi

echo ""
echo -e "${YELLOW}[2/4] 클러스터 노드 S3 연결성 검증 (T009)${NC}"
echo "----------------------------------------"
echo -e "${BLUE}참고: SSH 접근이 필요합니다 (${SSH_USER}@노드)${NC}"
echo ""

# 각 노드에서 S3 연결 테스트
for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"

    echo "노드 ${node_name} (${node}):"

    # SSH 접근 가능 여부 확인
    if command -v sshpass &> /dev/null; then
        # sshpass 사용 가능한 경우
        if sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${SSH_USER}@${node}" "curl -s -f -m 5 ${S3_API_ENDPOINT}/minio/health/live" > /dev/null 2>&1; then
            check_result "  S3 API 연결 (${node})" 0
        else
            check_result "  S3 API 연결 (${node})" 1 "  ${S3_API_ENDPOINT} 접근 불가"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} SSH 자동 테스트 불가 (sshpass 미설치)"
        echo -e "  ${YELLOW}수동 확인 필요:${NC}"
        echo -e "  ${BLUE}ssh ${SSH_USER}@${node} 'curl -k ${S3_API_ENDPOINT}/minio/health/live'${NC}"
    fi
    echo ""
done

echo -e "${YELLOW}[3/4] DNS 와일드카드 레코드 검증 (T010)${NC}"
echo "----------------------------------------"

# DNS 검증
for i in "${!NODE_NAMES[@]}"; do
    node_name="${NODE_NAMES[$i]}"
    node_ip="${NODES[$i]}"
    hostname="grafana.mkube-${node_name}.miribit.lab"

    echo -n "DNS: ${hostname} → ${node_ip}... "

    # nslookup로 DNS 확인
    resolved_ip=$(nslookup "${hostname}" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -v '#53' | head -1)

    if [ -n "$resolved_ip" ] && [ "$resolved_ip" = "$node_ip" ]; then
        check_result "DNS 해석 (${hostname})" 0 "  ${hostname} → ${resolved_ip}"
    else
        check_result "DNS 해석 (${hostname})" 1 "  예상: ${node_ip}, 실제: ${resolved_ip:-해석 실패}"
        echo -e "  ${YELLOW}DNS 레코드 설정 필요:${NC}"
        echo -e "  ${BLUE}*.mkube-${node_name}.miribit.lab → ${node_ip}${NC}"
    fi
    echo ""
done

echo -e "${YELLOW}[4/4] 노드 리소스 확인${NC}"
echo "----------------------------------------"

for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    node_name="${NODE_NAMES[$i]}"

    echo "노드 ${node_name} (${node}):"

    if command -v sshpass &> /dev/null; then
        # CPU 확인
        cpu_count=$(sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${SSH_USER}@${node}" "nproc" 2>/dev/null || echo "0")
        if [ "$cpu_count" -ge 4 ]; then
            check_result "  CPU (${cpu_count} cores)" 0
        else
            check_result "  CPU (${cpu_count} cores)" 1 "  최소 4 cores 필요"
        fi

        # 메모리 확인
        mem_gb=$(sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${SSH_USER}@${node}" "free -g | awk '/^Mem:/ {print \$2}'" 2>/dev/null || echo "0")
        if [ "$mem_gb" -ge 16 ]; then
            check_result "  메모리 (${mem_gb}GB)" 0
        else
            check_result "  메모리 (${mem_gb}GB)" 1 "  최소 16GB 필요"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} SSH 자동 테스트 불가 (sshpass 미설치)"
        echo -e "  ${YELLOW}수동 확인 필요:${NC}"
        echo -e "  ${BLUE}ssh ${SSH_USER}@${node} 'nproc; free -h'${NC}"
    fi
    echo ""
done

# 최종 결과
echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}검증 결과 요약${NC}"
echo -e "${BLUE}=====================================${NC}"
echo -e "총 체크: ${TOTAL_CHECKS}"
echo -e "${GREEN}통과: ${PASSED_CHECKS}${NC}"
echo -e "${RED}실패: ${FAILED_CHECKS}${NC}"
echo ""

if [ "$FAILED_CHECKS" -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 사전 요구사항이 충족되었습니다!${NC}"
    echo -e "${GREEN}Phase 3 (Minikube 설치)를 진행할 수 있습니다.${NC}"
    exit 0
else
    echo -e "${RED}✗ 일부 요구사항이 충족되지 않았습니다.${NC}"
    echo -e "${YELLOW}실패한 항목을 수정한 후 다시 실행하세요.${NC}"
    echo ""
    echo -e "${BLUE}수동 검증 명령어:${NC}"
    echo ""
    echo "S3 연결 테스트:"
    for node in "${NODES[@]}"; do
        echo "  ssh ${SSH_USER}@${node} 'curl ${S3_API_ENDPOINT}/minio/health/live'"
    done
    echo ""
    echo "DNS 확인:"
    for node_name in "${NODE_NAMES[@]}"; do
        echo "  nslookup grafana.mkube-${node_name}.miribit.lab"
    done
    exit 1
fi
