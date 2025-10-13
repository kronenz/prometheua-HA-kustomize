#!/bin/bash
# 로깅 스택 검증 스크립트
# OpenSearch, Fluent-bit가 정상적으로 동작하는지 확인합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       로깅 스택 검증 스크립트         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

FAILED=0

# 1. OpenSearch 확인
echo -e "${YELLOW}1. OpenSearch 확인 중...${NC}"
echo -n "  OpenSearch Pod 상태... "
if kubectl get pods -n logging -l app=opensearch -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  OpenSearch Service... "
if kubectl get svc -n logging opensearch-cluster-master > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  OpenSearch Health... "
OS_POD=$(kubectl get pod -n logging -l app=opensearch -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "${OS_POD}" ]; then
    HEALTH=$(kubectl exec -n logging ${OS_POD} -- curl -s http://localhost:9200/_cluster/health 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    if [ "${HEALTH}" = "green" ] || [ "${HEALTH}" = "yellow" ]; then
        echo -e "${GREEN}✓ (${HEALTH})${NC}"
    else
        echo -e "${RED}✗ (${HEALTH})${NC}"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗ (Pod 없음)${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 2. Fluent-bit 확인
echo -e "${YELLOW}2. Fluent-bit 확인 중...${NC}"
echo -n "  Fluent-bit DaemonSet... "
if kubectl get daemonset -n logging fluent-bit > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  Fluent-bit Pods... "
DESIRED=$(kubectl get daemonset -n logging fluent-bit -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
READY=$(kubectl get daemonset -n logging fluent-bit -o jsonpath='{.status.numberReady}' 2>/dev/null)
if [ "${DESIRED}" = "${READY}" ] && [ "${DESIRED}" -gt 0 ]; then
    echo -e "${GREEN}✓ (${READY}/${DESIRED})${NC}"
else
    echo -e "${RED}✗ (${READY}/${DESIRED})${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 3. 로그 수집 확인
echo -e "${YELLOW}3. 로그 수집 확인 중...${NC}"
echo -n "  OpenSearch 인덱스... "
if [ -n "${OS_POD}" ]; then
    INDICES=$(kubectl exec -n logging ${OS_POD} -- curl -s http://localhost:9200/_cat/indices 2>/dev/null | grep -c "logs-" || echo "0")
    if [ "${INDICES}" -gt 0 ]; then
        echo -e "${GREEN}✓ (${INDICES}개 인덱스)${NC}"
    else
        echo -e "${YELLOW}⚠ (인덱스 없음 - 로그 수집 대기 중)${NC}"
    fi
else
    echo -e "${RED}✗ (OpenSearch Pod 없음)${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  최근 로그 엔트리... "
if [ -n "${OS_POD}" ] && [ "${INDICES}" -gt 0 ]; then
    DOC_COUNT=$(kubectl exec -n logging ${OS_POD} -- curl -s http://localhost:9200/logs-*/_count 2>/dev/null | grep -o '"count":[0-9]*' | cut -d':' -f2)
    if [ "${DOC_COUNT}" -gt 0 ]; then
        echo -e "${GREEN}✓ (${DOC_COUNT}개 문서)${NC}"
    else
        echo -e "${YELLOW}⚠ (문서 없음 - 로그 수집 대기 중)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ (확인 불가)${NC}"
fi

echo ""

# 4. S3 설정 확인
echo -e "${YELLOW}4. S3 설정 확인 중...${NC}"
echo -n "  OpenSearch S3 Secret... "
if kubectl get secret opensearch-s3-config -n logging > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 5. ServiceMonitor 확인
echo -e "${YELLOW}5. ServiceMonitor 확인 중...${NC}"
echo -n "  OpenSearch ServiceMonitor... "
if kubectl get servicemonitor -n monitoring opensearch > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ (없음 - 메트릭 수집 안됨)${NC}"
fi

echo -n "  Fluent-bit ServiceMonitor... "
if kubectl get servicemonitor -n monitoring fluent-bit > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ (없음 - 메트릭 수집 안됨)${NC}"
fi

echo ""

# 결과 요약
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
if [ ${FAILED} -eq 0 ]; then
    echo -e "${BLUE}║        검증 성공! ✓                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}모든 로깅 컴포넌트가 정상적으로 동작합니다.${NC}"
    echo ""
    echo -e "${YELLOW}접근 URL:${NC}"
    echo "  OpenSearch: http://opensearch.mkube-<cluster>.miribit.lab:30080"
    echo ""
    echo -e "${YELLOW}샘플 쿼리:${NC}"
    echo "  kubectl exec -n logging ${OS_POD} -- curl -s http://localhost:9200/_cat/indices"
    echo "  kubectl exec -n logging ${OS_POD} -- curl -s http://localhost:9200/logs-*/_search?size=1"
    exit 0
else
    echo -e "${BLUE}║        검증 실패 ✗                     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}${FAILED}개 항목에서 문제가 발견되었습니다.${NC}"
    echo ""
    echo -e "${YELLOW}문제 해결 방법:${NC}"
    echo "  1. Pod 상태 확인: kubectl get pods -n logging"
    echo "  2. Pod 로그 확인: kubectl logs -n logging <pod-name>"
    echo "  3. 이벤트 확인: kubectl get events -n logging --sort-by='.lastTimestamp'"
    exit 1
fi
