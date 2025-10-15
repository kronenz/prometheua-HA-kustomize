#!/bin/bash
# 배포 검증 스크립트
# 모든 클러스터의 배포 상태를 확인합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 설정
NAMESPACES=("longhorn-system" "ingress-nginx" "monitoring" "logging")

echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Thanos 배포 상태 검증 스크립트          ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# 검증 결과 추적
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# 함수: 체크 결과 출력
check_result() {
    local name="$1"
    local result="$2"
    local message="${3:-}"
    local level="${4:-error}"  # error or warning

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} ${name}"
        [ -n "$message" ] && echo -e "  ${message}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        if [ "$level" = "warning" ]; then
            echo -e "${YELLOW}⚠${NC} ${name}"
            [ -n "$message" ] && echo -e "  ${YELLOW}${message}${NC}"
            WARNINGS=$((WARNINGS + 1))
        else
            echo -e "${RED}✗${NC} ${name}"
            [ -n "$message" ] && echo -e "  ${RED}${message}${NC}"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
        return 1
    fi
}

# kubectl 클러스터 연결 확인
echo -e "${YELLOW}[1/6] 클러스터 연결 확인${NC}"
echo "───────────────────────────────────────────────"

if kubectl cluster-info > /dev/null 2>&1; then
    CLUSTER_NAME=$(kubectl config current-context)
    check_result "Kubernetes 클러스터 연결" 0 "Context: ${CLUSTER_NAME}"
else
    check_result "Kubernetes 클러스터 연결" 1 "kubectl이 클러스터에 연결되어 있지 않습니다"
    exit 1
fi

# 노드 상태 확인
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")

if [ "$NODE_COUNT" -gt 0 ] && [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    check_result "노드 상태" 0 "${READY_NODES}/${NODE_COUNT} 노드 Ready"
else
    check_result "노드 상태" 1 "${READY_NODES}/${NODE_COUNT} 노드 Ready (일부 노드 Not Ready)"
fi

echo ""

# 네임스페이스 존재 확인
echo -e "${YELLOW}[2/6] 네임스페이스 확인${NC}"
echo "───────────────────────────────────────────────"

for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" > /dev/null 2>&1; then
        check_result "네임스페이스: $ns" 0
    else
        check_result "네임스페이스: $ns" 1 "네임스페이스가 존재하지 않습니다" "warning"
    fi
done

echo ""

# Pods 상태 확인
echo -e "${YELLOW}[3/6] Pods 상태 확인${NC}"
echo "───────────────────────────────────────────────"

for ns in "${NAMESPACES[@]}"; do
    if ! kubectl get namespace "$ns" > /dev/null 2>&1; then
        echo -e "${YELLOW}⊘${NC} ${ns}: 네임스페이스 없음 (스킵)"
        continue
    fi

    echo ""
    echo -e "${BLUE}${ns}:${NC}"

    TOTAL_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)

    if [ "$TOTAL_PODS" -eq 0 ]; then
        check_result "  Pods 존재" 1 "  Pods가 배포되지 않았습니다" "warning"
        continue
    fi

    RUNNING_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    PENDING_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
    FAILED_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -cE "Error|CrashLoopBackOff|ImagePullBackOff" || echo "0")

    if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ]; then
        check_result "  Pods 상태" 0 "  ${RUNNING_PODS}/${TOTAL_PODS} Running"
    elif [ "$PENDING_PODS" -gt 0 ]; then
        check_result "  Pods 상태" 1 "  Running: ${RUNNING_PODS}, Pending: ${PENDING_PODS}, Failed: ${FAILED_PODS}" "warning"
    else
        check_result "  Pods 상태" 1 "  Running: ${RUNNING_PODS}, Pending: ${PENDING_PODS}, Failed: ${FAILED_PODS}"
    fi

    # 각 Pod의 Ready 상태 확인
    NOT_READY=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{print $2}' | grep -v "^[0-9]*/\1$" | wc -l || echo "0")

    if [ "$NOT_READY" -eq 0 ]; then
        check_result "  Pods Ready" 0 "  모든 컨테이너 Ready"
    else
        check_result "  Pods Ready" 1 "  ${NOT_READY} Pods가 Ready 상태가 아닙니다"
    fi
done

echo ""

# Services 확인
echo -e "${YELLOW}[4/6] Services 확인${NC}"
echo "───────────────────────────────────────────────"

# 중요 서비스 목록
declare -A IMPORTANT_SERVICES
IMPORTANT_SERVICES["monitoring"]="prometheus-kube-prometheus-prometheus grafana thanos-query"
IMPORTANT_SERVICES["logging"]="opensearch fluent-bit"
IMPORTANT_SERVICES["longhorn-system"]="longhorn-frontend"
IMPORTANT_SERVICES["ingress-nginx"]="ingress-nginx-controller"

for ns in "${!IMPORTANT_SERVICES[@]}"; do
    if ! kubectl get namespace "$ns" > /dev/null 2>&1; then
        continue
    fi

    echo ""
    echo -e "${BLUE}${ns}:${NC}"

    for svc in ${IMPORTANT_SERVICES[$ns]}; do
        if kubectl get svc "$svc" -n "$ns" > /dev/null 2>&1; then
            check_result "  Service: $svc" 0
        else
            # Service 이름이 정확하지 않을 수 있으므로 부분 일치 검사
            FOUND=$(kubectl get svc -n "$ns" --no-headers 2>/dev/null | grep -c "$svc" || echo "0")
            if [ "$FOUND" -gt 0 ]; then
                check_result "  Service: $svc*" 0 "  (부분 일치)"
            else
                check_result "  Service: $svc" 1 "  Service가 존재하지 않습니다" "warning"
            fi
        fi
    done
done

echo ""

# Ingress 확인
echo -e "${YELLOW}[5/6] Ingress 확인${NC}"
echo "───────────────────────────────────────────────"

INGRESS_COUNT=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l)

if [ "$INGRESS_COUNT" -gt 0 ]; then
    check_result "Ingress 리소스" 0 "${INGRESS_COUNT}개 Ingress 발견"

    echo ""
    echo -e "${BLUE}Ingress 목록:${NC}"
    kubectl get ingress --all-namespaces -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
HOSTS:.spec.rules[*].host 2>/dev/null || true
else
    check_result "Ingress 리소스" 1 "Ingress가 배포되지 않았습니다" "warning"
fi

echo ""

# PVC 확인
echo -e "${YELLOW}[6/6] PersistentVolumeClaim 확인${NC}"
echo "───────────────────────────────────────────────"

TOTAL_PVCS=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)

if [ "$TOTAL_PVCS" -gt 0 ]; then
    BOUND_PVCS=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep -c "Bound" || echo "0")

    if [ "$BOUND_PVCS" -eq "$TOTAL_PVCS" ]; then
        check_result "PVC 상태" 0 "${BOUND_PVCS}/${TOTAL_PVCS} Bound"
    else
        check_result "PVC 상태" 1 "${BOUND_PVCS}/${TOTAL_PVCS} Bound (일부 Pending)"
    fi

    echo ""
    echo -e "${BLUE}PVC 목록:${NC}"
    kubectl get pvc --all-namespaces -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
STATUS:.status.phase,\
CAPACITY:.status.capacity.storage 2>/dev/null || true
else
    check_result "PVC 상태" 1 "PVC가 생성되지 않았습니다" "warning"
fi

echo ""
echo ""

# 최종 결과
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║             검증 결과 요약                     ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "총 체크: ${TOTAL_CHECKS}"
echo -e "${GREEN}통과: ${PASSED_CHECKS}${NC}"
echo -e "${YELLOW}경고: ${WARNINGS}${NC}"
echo -e "${RED}실패: ${FAILED_CHECKS}${NC}"
echo ""

# 성공률 계산
if [ "$TOTAL_CHECKS" -gt 0 ]; then
    SUCCESS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo -e "성공률: ${SUCCESS_RATE}%"
    echo ""
fi

# 상세 정보 명령어
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}상세 확인 명령어:${NC}"
echo ""
echo "전체 Pods 상태:"
echo "  kubectl get pods --all-namespaces"
echo ""
echo "특정 네임스페이스 상세:"
echo "  kubectl get all -n monitoring"
echo "  kubectl get all -n logging"
echo ""
echo "Pod 로그 확인:"
echo "  kubectl logs -n monitoring <pod-name>"
echo ""
echo "이벤트 확인:"
echo "  kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
echo ""

# 종료 코드 결정
if [ "$FAILED_CHECKS" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
        echo -e "${GREEN}✓ 모든 검증이 성공적으로 완료되었습니다!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ 일부 경고가 있지만 핵심 기능은 정상입니다.${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ 일부 검증이 실패했습니다. 위 로그를 확인하세요.${NC}"
    exit 1
fi
