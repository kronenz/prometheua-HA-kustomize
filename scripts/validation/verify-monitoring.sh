#!/bin/bash
# 모니터링 스택 검증 스크립트
# Prometheus, Thanos, Grafana가 정상적으로 동작하는지 확인합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      모니터링 스택 검증 스크립트      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

FAILED=0

# 1. Prometheus 확인
echo -e "${YELLOW}1. Prometheus 확인 중...${NC}"
echo -n "  Prometheus Pod 상태... "
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  Prometheus Service... "
if kubectl get svc -n monitoring kube-prometheus-stack-prometheus > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  Prometheus 메트릭 수집... "
if kubectl exec -n monitoring -c prometheus $(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') -- wget -q -O- http://localhost:9090/api/v1/targets 2>/dev/null | grep -q "up"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 2. Thanos 확인
echo -e "${YELLOW}2. Thanos 확인 중...${NC}"

echo -n "  Thanos Sidecar... "
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | grep -q "thanos-sidecar"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ (Sidecar 없음)${NC}"
    FAILED=$((FAILED + 1))
fi

# 중앙 클러스터인 경우 추가 컴포넌트 확인
if kubectl get deployment thanos-query -n monitoring > /dev/null 2>&1; then
    echo -n "  Thanos Query... "
    if kubectl get pods -n monitoring -l app=thanos-query -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        FAILED=$((FAILED + 1))
    fi

    echo -n "  Thanos Store... "
    if kubectl get pods -n monitoring -l app=thanos-store -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        FAILED=$((FAILED + 1))
    fi

    echo -n "  Thanos Compactor... "
    if kubectl get pods -n monitoring -l app=thanos-compactor -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        FAILED=$((FAILED + 1))
    fi

    echo -n "  Thanos Ruler... "
    if kubectl get pods -n monitoring -l app=thanos-ruler -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "  ${YELLOW}엣지 클러스터 (Query/Store/Compactor 없음)${NC}"
fi

echo ""

# 3. Grafana 확인
echo -e "${YELLOW}3. Grafana 확인 중...${NC}"
echo -n "  Grafana Pod 상태... "
if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  Grafana Service... "
if kubectl get svc -n monitoring kube-prometheus-stack-grafana > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 4. Alertmanager 확인
echo -e "${YELLOW}4. Alertmanager 확인 중...${NC}"
echo -n "  Alertmanager Pod 상태... "
if kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 5. ServiceMonitor 확인
echo -e "${YELLOW}5. ServiceMonitor 확인 중...${NC}"
SM_COUNT=$(kubectl get servicemonitor -n monitoring 2>/dev/null | wc -l)
if [ ${SM_COUNT} -gt 1 ]; then
    echo -e "  ${GREEN}✓ ${SM_COUNT} ServiceMonitors 발견${NC}"
else
    echo -e "  ${RED}✗ ServiceMonitors 없음${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 6. S3 Secret 확인
echo -e "${YELLOW}6. S3 설정 확인 중...${NC}"
echo -n "  Thanos S3 Secret... "
if kubectl get secret thanos-s3-config -n monitoring > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    FAILED=$((FAILED + 1))
fi

echo ""

# 결과 요약
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
if [ ${FAILED} -eq 0 ]; then
    echo -e "${BLUE}║        검증 성공! ✓                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}모든 모니터링 컴포넌트가 정상적으로 동작합니다.${NC}"
    echo ""
    echo -e "${YELLOW}접근 URL:${NC}"
    echo "  Grafana: http://grafana.mkube-<cluster>.miribit.lab:30080"
    echo "  Prometheus: http://prometheus.mkube-<cluster>.miribit.lab:30080"
    if kubectl get deployment thanos-query -n monitoring > /dev/null 2>&1; then
        echo "  Thanos Query: http://thanos.mkube-<cluster>.miribit.lab:30080"
    fi
    exit 0
else
    echo -e "${BLUE}║        검증 실패 ✗                     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}${FAILED}개 항목에서 문제가 발견되었습니다.${NC}"
    echo ""
    echo -e "${YELLOW}문제 해결 방법:${NC}"
    echo "  1. Pod 상태 확인: kubectl get pods -n monitoring"
    echo "  2. Pod 로그 확인: kubectl logs -n monitoring <pod-name>"
    echo "  3. 이벤트 확인: kubectl get events -n monitoring --sort-by='.lastTimestamp'"
    exit 1
fi
