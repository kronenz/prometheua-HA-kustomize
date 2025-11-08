#!/bin/bash

# ============================================================================
# Grafana 대시보드 구성 검증 스크립트
# ============================================================================
# 목적: Grafana 대시보드 ConfigMap 및 Sidecar 설정을 검증
# 사용법: ./scripts/validate-grafana-dashboards.sh [namespace]
# ============================================================================

set -e

# 기본값 설정
NAMESPACE="${1:-monitoring}"
DASHBOARD_LABEL="grafana_dashboard=1"
GRAFANA_DEPLOYMENT="kube-prometheus-stack-grafana"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 헤더 출력
echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}  Grafana 대시보드 구성 검증${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo -e "Namespace: ${YELLOW}${NAMESPACE}${NC}\n"

# 검증 결과 카운터
PASS_COUNT=0
FAIL_COUNT=0

# 검증 함수
function check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

function check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

function check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

function section_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================================
# 1. ConfigMap 검증
# ============================================================================
section_header "1. 대시보드 ConfigMap 검증"

echo "레이블 검색: ${DASHBOARD_LABEL}"
CONFIGMAPS=$(kubectl get cm -n "${NAMESPACE}" -l "${DASHBOARD_LABEL}" --no-headers 2>/dev/null | awk '{print $1}')
CM_COUNT=$(echo "${CONFIGMAPS}" | grep -c . || echo 0)

if [ "${CM_COUNT}" -gt 0 ]; then
    check_pass "ConfigMap 발견: ${CM_COUNT}개"
    echo ""
    echo "발견된 ConfigMaps:"
    for cm in ${CONFIGMAPS}; do
        # ConfigMap 데이터 키 확인
        DATA_KEYS=$(kubectl get cm -n "${NAMESPACE}" "${cm}" -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null)
        echo -e "  • ${YELLOW}${cm}${NC}"
        for key in ${DATA_KEYS}; do
            echo -e "    - ${key}"
        done
    done
else
    check_fail "ConfigMap을 찾을 수 없습니다"
    echo "  확인 사항:"
    echo "  1. ConfigMap이 생성되었는지 확인"
    echo "  2. 레이블 'grafana_dashboard: \"1\"'이 있는지 확인"
    echo "  3. Namespace가 올바른지 확인"
fi

# ============================================================================
# 2. Grafana Deployment 검증
# ============================================================================
section_header "2. Grafana Deployment 검증"

# Grafana Deployment 존재 확인
if kubectl get deployment -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}" &>/dev/null; then
    check_pass "Grafana Deployment 발견: ${GRAFANA_DEPLOYMENT}"

    # Replicas 확인
    DESIRED=$(kubectl get deployment -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}" -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}" -o jsonpath='{.status.readyReplicas}')

    if [ "${DESIRED}" -eq "${READY}" ]; then
        check_pass "Replicas: ${READY}/${DESIRED} (Ready)"
    else
        check_warn "Replicas: ${READY}/${DESIRED} (일부 Pod가 준비되지 않음)"
    fi
else
    check_fail "Grafana Deployment를 찾을 수 없습니다: ${GRAFANA_DEPLOYMENT}"
fi

# ============================================================================
# 3. Grafana Sidecar 컨테이너 검증
# ============================================================================
section_header "3. Grafana Dashboard Sidecar 검증"

# Sidecar 컨테이너 존재 확인
SIDECAR_EXISTS=$(kubectl get deployment -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}" -o json 2>/dev/null | \
    jq -r '.spec.template.spec.containers[] | select(.name == "grafana-sc-dashboard") | .name' 2>/dev/null)

if [ -n "${SIDECAR_EXISTS}" ]; then
    check_pass "Dashboard Sidecar 컨테이너 발견: grafana-sc-dashboard"

    # Sidecar 환경 변수 확인
    echo ""
    echo "Sidecar 환경 변수:"

    # LABEL 환경 변수
    LABEL_VALUE=$(kubectl get deployment -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}" -o json | \
        jq -r '.spec.template.spec.containers[] | select(.name == "grafana-sc-dashboard") | .env[] | select(.name == "LABEL") | .value' 2>/dev/null)
    if [ -n "${LABEL_VALUE}" ]; then
        check_pass "  LABEL: ${LABEL_VALUE}"
    else
        check_warn "  LABEL 환경 변수가 설정되지 않음"
    fi

    # FOLDER 환경 변수
    FOLDER_VALUE=$(kubectl get deployment -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}" -o json | \
        jq -r '.spec.template.spec.containers[] | select(.name == "grafana-sc-dashboard") | .env[] | select(.name == "FOLDER") | .value' 2>/dev/null)
    if [ -n "${FOLDER_VALUE}" ]; then
        check_pass "  FOLDER: ${FOLDER_VALUE}"
    else
        check_warn "  FOLDER 환경 변수가 설정되지 않음"
    fi

    # NAMESPACE 환경 변수 (searchNamespace)
    NS_VALUE=$(kubectl get deployment -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}" -o json | \
        jq -r '.spec.template.spec.containers[] | select(.name == "grafana-sc-dashboard") | .env[] | select(.name == "NAMESPACE") | .value' 2>/dev/null)
    if [ -n "${NS_VALUE}" ]; then
        check_pass "  NAMESPACE: ${NS_VALUE}"
    else
        check_warn "  NAMESPACE 환경 변수가 설정되지 않음 (현재 namespace만 검색)"
    fi

else
    check_fail "Dashboard Sidecar 컨테이너를 찾을 수 없습니다"
    echo "  sidecar.dashboards.enabled: true로 설정되었는지 확인하세요"
fi

# ============================================================================
# 4. Grafana Pod 및 Sidecar 로그 검증
# ============================================================================
section_header "4. Grafana Pod 및 Sidecar 로그 검증"

# Grafana Pod 확인
GRAFANA_PODS=$(kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=grafana" --no-headers 2>/dev/null | awk '{print $1}')
POD_COUNT=$(echo "${GRAFANA_PODS}" | grep -c . || echo 0)

if [ "${POD_COUNT}" -gt 0 ]; then
    check_pass "Grafana Pod 발견: ${POD_COUNT}개"

    # 첫 번째 Pod의 Sidecar 로그 확인
    FIRST_POD=$(echo "${GRAFANA_PODS}" | head -1)
    echo ""
    echo "Sidecar 로그 (최근 10줄, Pod: ${FIRST_POD}):"
    echo "─────────────────────────────────────────────────────────────────"
    kubectl logs -n "${NAMESPACE}" "${FIRST_POD}" -c grafana-sc-dashboard --tail=10 2>/dev/null || \
        check_warn "Sidecar 로그를 가져올 수 없습니다"
    echo "─────────────────────────────────────────────────────────────────"

    # 대시보드 로딩 메시지 확인
    DASHBOARD_LOADED=$(kubectl logs -n "${NAMESPACE}" "${FIRST_POD}" -c grafana-sc-dashboard 2>/dev/null | \
        grep -i "dashboard\|configmap\|copied" | tail -5)

    if [ -n "${DASHBOARD_LOADED}" ]; then
        echo ""
        echo "대시보드 로딩 로그:"
        echo "${DASHBOARD_LOADED}"
    fi

else
    check_fail "Grafana Pod를 찾을 수 없습니다"
fi

# ============================================================================
# 5. Grafana Datasource 검증
# ============================================================================
section_header "5. Grafana Datasource 검증"

# Datasource ConfigMap 확인
DS_CM=$(kubectl get cm -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}-datasource" 2>/dev/null)
if [ $? -eq 0 ]; then
    check_pass "Datasource ConfigMap 발견"

    # Thanos Query datasource 확인
    THANOS_DS=$(kubectl get cm -n "${NAMESPACE}" "${GRAFANA_DEPLOYMENT}-datasource" -o yaml | grep -i "thanos")
    if [ -n "${THANOS_DS}" ]; then
        check_pass "Thanos Query datasource 설정됨"
    else
        check_warn "Thanos Query datasource가 설정되지 않음"
    fi
else
    check_warn "Datasource ConfigMap을 찾을 수 없습니다"
fi

# ============================================================================
# 6. Grafana Ingress 검증
# ============================================================================
section_header "6. Grafana Ingress 검증"

INGRESS_NAME=$(kubectl get ingress -n "${NAMESPACE}" -l "app.kubernetes.io/name=grafana" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "${INGRESS_NAME}" ]; then
    check_pass "Ingress 발견: ${INGRESS_NAME}"

    # Ingress 호스트 확인
    INGRESS_HOST=$(kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o jsonpath='{.spec.rules[0].host}')
    if [ -n "${INGRESS_HOST}" ]; then
        check_pass "Ingress 호스트: ${INGRESS_HOST}"
        echo "  Grafana URL: http://${INGRESS_HOST}"
    fi

    # Ingress 주소 확인
    INGRESS_ADDRESS=$(kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -n "${INGRESS_ADDRESS}" ]; then
        check_pass "LoadBalancer IP: ${INGRESS_ADDRESS}"
    else
        check_warn "LoadBalancer IP가 아직 할당되지 않음"
    fi
else
    check_warn "Ingress를 찾을 수 없습니다"
fi

# ============================================================================
# 7. 대시보드 파일 구조 검증 (로컬)
# ============================================================================
section_header "7. 로컬 대시보드 파일 구조 검증"

DASHBOARD_DIR="deploy-new/overlays/cluster-01-central/kube-prometheus-stack/dashboards"

if [ -d "${DASHBOARD_DIR}" ]; then
    check_pass "대시보드 디렉토리 발견: ${DASHBOARD_DIR}"

    # 대시보드 파일 개수 확인
    DASHBOARD_FILES=$(ls -1 "${DASHBOARD_DIR}"/grafana-dashboard-*.yaml 2>/dev/null | wc -l)
    if [ "${DASHBOARD_FILES}" -gt 0 ]; then
        check_pass "대시보드 YAML 파일: ${DASHBOARD_FILES}개"
        echo ""
        echo "파일 목록:"
        ls -1 "${DASHBOARD_DIR}"/grafana-dashboard-*.yaml | while read -r file; do
            filename=$(basename "${file}")
            echo -e "  • ${filename}"
        done
    else
        check_fail "대시보드 YAML 파일을 찾을 수 없습니다"
    fi
else
    check_warn "로컬 대시보드 디렉토리를 찾을 수 없습니다: ${DASHBOARD_DIR}"
fi

# ============================================================================
# 결과 요약
# ============================================================================
section_header "검증 결과 요약"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo ""
echo -e "${GREEN}✓ 통과:${NC} ${PASS_COUNT}/${TOTAL}"
echo -e "${RED}✗ 실패:${NC} ${FAIL_COUNT}/${TOTAL}"
echo ""

if [ "${FAIL_COUNT}" -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  모든 검증을 통과했습니다! 🎉${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "다음 단계:"
    echo "  1. Grafana UI 접속: http://grafana.k8s-cluster-01.miribit.lab"
    echo "  2. 로그인: admin / admin123"
    echo "  3. Dashboards → Browse → General 폴더 확인"
    echo "  4. 대시보드 열기 및 수정 테스트"
    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  일부 검증에 실패했습니다. 위 내용을 확인하세요.${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "문제 해결 방법:"
    echo "  1. README-DASHBOARDS.md 문서 참고"
    echo "  2. kubectl logs 명령으로 자세한 로그 확인"
    echo "  3. ConfigMap 레이블 확인: kubectl get cm -n ${NAMESPACE} -l ${DASHBOARD_LABEL}"
    exit 1
fi
