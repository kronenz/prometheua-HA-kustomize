#!/bin/bash
# ============================================================================
# 멀티클러스터 메트릭 수집 진단 스크립트
# ============================================================================
# Thanos + Prometheus 멀티클러스터 환경에서 메트릭 수집 문제를 진단합니다.
#
# 사용법:
#   ./diagnose-multicluster-metrics.sh
#
# 요구사항:
#   - kubectl 설치
#   - 클러스터 contexts 설정 (cluster-01, cluster-02, cluster-03, cluster-04)
# ============================================================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 아이콘 정의
CHECK="✓"
CROSS="✗"
WARNING="⚠"
INFO="ℹ"

# 클러스터 목록
CLUSTERS=("cluster-01" "cluster-02" "cluster-03" "cluster-04")
CENTRAL_CLUSTER="cluster-01"
EDGE_CLUSTERS=("cluster-02" "cluster-03" "cluster-04")

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}  멀티클러스터 메트릭 수집 진단${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# ============================================================================
# 1. 클러스터 연결 확인
# ============================================================================
echo -e "${BLUE}[1] 클러스터 연결 확인${NC}"
echo "---"

for cluster in "${CLUSTERS[@]}"; do
    if kubectl --context "$cluster" cluster-info &>/dev/null; then
        echo -e "${GREEN}${CHECK}${NC} $cluster: 연결 성공"
    else
        echo -e "${RED}${CROSS}${NC} $cluster: 연결 실패"
        echo -e "${YELLOW}${WARNING}${NC} kubectl config에서 $cluster context를 확인하세요"
    fi
done
echo ""

# ============================================================================
# 2. Prometheus Pod 상태 확인
# ============================================================================
echo -e "${BLUE}[2] Prometheus Pod 상태 확인${NC}"
echo "---"

check_prometheus_pods() {
    local cluster=$1
    local namespace="monitoring"

    echo -e "${INFO} ${cluster}:"

    # Pod 목록
    local pods=$(kubectl --context "$cluster" get pods -n "$namespace" \
        -l "app.kubernetes.io/name=prometheus" --no-headers 2>/dev/null | awk '{print $1" "$3}')

    if [ -z "$pods" ]; then
        echo -e "  ${RED}${CROSS}${NC} Prometheus Pod를 찾을 수 없습니다"
        return
    fi

    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')

        if [ "$status" = "Running" ]; then
            echo -e "  ${GREEN}${CHECK}${NC} $pod_name: $status"
        else
            echo -e "  ${RED}${CROSS}${NC} $pod_name: $status"
        fi
    done <<< "$pods"
}

for cluster in "${CLUSTERS[@]}"; do
    check_prometheus_pods "$cluster"
done
echo ""

# ============================================================================
# 3. External Labels 확인
# ============================================================================
echo -e "${BLUE}[3] External Labels 확인${NC}"
echo "---"

check_external_labels() {
    local cluster=$1
    local namespace="monitoring"

    echo -e "${INFO} ${cluster}:"

    # Prometheus ConfigMap 확인
    local config=$(kubectl --context "$cluster" get cm -n "$namespace" \
        prometheus-kube-prometheus-stack-prometheus-rulefiles-0 -o yaml 2>/dev/null || \
        kubectl --context "$cluster" get cm -n "$namespace" \
        -l "app.kubernetes.io/name=prometheus" -o yaml 2>/dev/null | head -100)

    if [ -z "$config" ]; then
        # Prometheus CR에서 직접 확인
        local external_labels=$(kubectl --context "$cluster" get prometheus -n "$namespace" \
            -o jsonpath='{.items[0].spec.externalLabels}' 2>/dev/null)

        if [ -z "$external_labels" ] || [ "$external_labels" = "{}" ]; then
            echo -e "  ${RED}${CROSS}${NC} External Labels가 설정되지 않았습니다"
        else
            echo -e "  ${GREEN}${CHECK}${NC} External Labels: $external_labels"
        fi
    else
        # ConfigMap에서 external_labels 추출
        local labels=$(echo "$config" | grep -A 5 "external_labels:" | grep -v "external_labels:" | sed 's/^[[:space:]]*//')

        if [ -z "$labels" ]; then
            echo -e "  ${RED}${CROSS}${NC} External Labels가 설정되지 않았습니다"
        else
            echo -e "  ${GREEN}${CHECK}${NC} External Labels 설정됨:"
            echo "$labels" | while IFS= read -r label; do
                echo -e "    - $label"
            done
        fi
    fi
}

for cluster in "${CLUSTERS[@]}"; do
    check_external_labels "$cluster"
done
echo ""

# ============================================================================
# 4. Remote Write 설정 확인 (엣지 클러스터)
# ============================================================================
echo -e "${BLUE}[4] Remote Write 설정 확인 (엣지 클러스터)${NC}"
echo "---"

check_remote_write() {
    local cluster=$1
    local namespace="monitoring"

    echo -e "${INFO} ${cluster}:"

    # Prometheus CR에서 remoteWrite 확인
    local remote_write=$(kubectl --context "$cluster" get prometheus -n "$namespace" \
        -o jsonpath='{.items[0].spec.remoteWrite}' 2>/dev/null)

    if [ -z "$remote_write" ] || [ "$remote_write" = "[]" ]; then
        echo -e "  ${RED}${CROSS}${NC} Remote Write가 설정되지 않았습니다"
        return
    fi

    # Remote Write URL 추출
    local urls=$(kubectl --context "$cluster" get prometheus -n "$namespace" \
        -o jsonpath='{.items[0].spec.remoteWrite[*].url}' 2>/dev/null)

    if [ -n "$urls" ]; then
        echo -e "  ${GREEN}${CHECK}${NC} Remote Write 설정됨:"
        for url in $urls; do
            echo -e "    - $url"
        done
    fi

    # writeRelabelConfigs 확인 (메트릭 필터링)
    local relabel_configs=$(kubectl --context "$cluster" get prometheus -n "$namespace" \
        -o jsonpath='{.items[0].spec.remoteWrite[0].writeRelabelConfigs}' 2>/dev/null)

    if [ -n "$relabel_configs" ] && [ "$relabel_configs" != "[]" ]; then
        echo -e "  ${YELLOW}${WARNING}${NC} writeRelabelConfigs 설정됨 (메트릭 필터링 주의):"
        echo "$relabel_configs" | jq '.' 2>/dev/null || echo "$relabel_configs"
    fi
}

for cluster in "${EDGE_CLUSTERS[@]}"; do
    check_remote_write "$cluster"
done
echo ""

# ============================================================================
# 5. Thanos Receiver 상태 확인 (중앙 클러스터)
# ============================================================================
echo -e "${BLUE}[5] Thanos Receiver 상태 확인 (중앙)${NC}"
echo "---"

echo -e "${INFO} ${CENTRAL_CLUSTER}:"

# Thanos Receiver Pod 확인
receiver_pods=$(kubectl --context "$CENTRAL_CLUSTER" get pods -n monitoring \
    -l "app.kubernetes.io/name=thanos,app.kubernetes.io/component=receive" \
    --no-headers 2>/dev/null | awk '{print $1" "$3}')

if [ -z "$receiver_pods" ]; then
    # Bitnami chart 레이블 시도
    receiver_pods=$(kubectl --context "$CENTRAL_CLUSTER" get pods -n monitoring \
        -l "app.kubernetes.io/component=receive" \
        --no-headers 2>/dev/null | awk '{print $1" "$3}')
fi

if [ -z "$receiver_pods" ]; then
    echo -e "${RED}${CROSS}${NC} Thanos Receiver Pod를 찾을 수 없습니다"
else
    while IFS= read -r line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')

        if [ "$status" = "Running" ]; then
            echo -e "${GREEN}${CHECK}${NC} $pod_name: $status"
        else
            echo -e "${RED}${CROSS}${NC} $pod_name: $status"
        fi
    done <<< "$receiver_pods"

    # Receiver 로그에서 메트릭 수신 확인
    echo ""
    echo -e "${INFO} 최근 메트릭 수신 로그 (최근 10줄):"
    local receiver_pod=$(echo "$receiver_pods" | head -1 | awk '{print $1}')
    kubectl --context "$CENTRAL_CLUSTER" logs -n monitoring "$receiver_pod" --tail=10 2>/dev/null | \
        grep -i "receive\|write\|tenant\|series" || echo "  로그에서 메트릭 수신 기록을 찾을 수 없습니다"
fi
echo ""

# ============================================================================
# 6. Thanos Query Store API 연결 확인
# ============================================================================
echo -e "${BLUE}[6] Thanos Query Store API 연결 확인${NC}"
echo "---"

echo -e "${INFO} ${CENTRAL_CLUSTER}:"

# Thanos Query Pod 확인
query_pod=$(kubectl --context "$CENTRAL_CLUSTER" get pods -n monitoring \
    -l "app.kubernetes.io/component=query" --no-headers 2>/dev/null | head -1 | awk '{print $1}')

if [ -z "$query_pod" ]; then
    echo -e "${RED}${CROSS}${NC} Thanos Query Pod를 찾을 수 없습니다"
else
    echo -e "${GREEN}${CHECK}${NC} Thanos Query Pod: $query_pod"

    # Stores 연결 상태 확인
    echo ""
    echo -e "${INFO} Store API 연결 상태:"
    kubectl --context "$CENTRAL_CLUSTER" exec -n monitoring "$query_pod" -- \
        wget -q -O- http://localhost:9090/api/v1/stores 2>/dev/null | \
        jq -r '.data.store[] | "\(.name): \(.labelSets)"' 2>/dev/null || \
        echo "  Store API 조회 실패"
fi
echo ""

# ============================================================================
# 7. 클러스터별 메트릭 존재 여부 확인
# ============================================================================
echo -e "${BLUE}[7] 클러스터별 메트릭 존재 여부 확인 (Thanos Query)${NC}"
echo "---"

if [ -n "$query_pod" ]; then
    for cluster in "${CLUSTERS[@]}"; do
        echo -e "${INFO} ${cluster} 메트릭 확인:"

        # up 메트릭으로 클러스터 확인
        local result=$(kubectl --context "$CENTRAL_CLUSTER" exec -n monitoring "$query_pod" -- \
            wget -q -O- 'http://localhost:9090/api/v1/query?query=up{cluster="'$cluster'"}' 2>/dev/null)

        local metric_count=$(echo "$result" | jq -r '.data.result | length' 2>/dev/null)

        if [ -n "$metric_count" ] && [ "$metric_count" -gt 0 ]; then
            echo -e "  ${GREEN}${CHECK}${NC} $metric_count 개의 메트릭 발견"
        else
            echo -e "  ${RED}${CROSS}${NC} 메트릭을 찾을 수 없습니다"
            echo -e "  ${YELLOW}${WARNING}${NC} External Labels 또는 Remote Write 설정을 확인하세요"
        fi
    done
else
    echo -e "${YELLOW}${WARNING}${NC} Thanos Query Pod를 찾을 수 없어 메트릭 확인을 건너뜁니다"
fi
echo ""

# ============================================================================
# 8. Grafana Datasource 확인
# ============================================================================
echo -e "${BLUE}[8] Grafana Datasource 확인${NC}"
echo "---"

grafana_pod=$(kubectl --context "$CENTRAL_CLUSTER" get pods -n monitoring \
    -l "app.kubernetes.io/name=grafana" --no-headers 2>/dev/null | head -1 | awk '{print $1}')

if [ -z "$grafana_pod" ]; then
    echo -e "${YELLOW}${WARNING}${NC} Grafana Pod를 찾을 수 없습니다"
else
    echo -e "${GREEN}${CHECK}${NC} Grafana Pod: $grafana_pod"

    # Datasource 설정 확인
    local datasources=$(kubectl --context "$CENTRAL_CLUSTER" exec -n monitoring "$grafana_pod" -- \
        curl -s http://localhost:3000/api/datasources 2>/dev/null)

    if [ -n "$datasources" ]; then
        echo ""
        echo -e "${INFO} 설정된 Datasource:"
        echo "$datasources" | jq -r '.[] | "\(.name): \(.url) (default: \(.isDefault))"' 2>/dev/null || \
            echo "  Datasource 정보 파싱 실패"
    fi
fi
echo ""

# ============================================================================
# 9. 요약 및 권장사항
# ============================================================================
echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}  진단 요약 및 권장사항${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

echo -e "${INFO} 주요 확인 사항:"
echo ""
echo "1. ${GREEN}External Labels${NC}"
echo "   - 모든 Prometheus에 cluster, region, environment 레이블이 설정되어야 합니다"
echo "   - externalLabels가 없으면 Grafana에서 클러스터 필터링이 불가능합니다"
echo ""
echo "2. ${GREEN}Remote Write 설정${NC}"
echo "   - 엣지 클러스터는 Thanos Receiver로 메트릭을 전송해야 합니다"
echo "   - writeRelabelConfigs로 메트릭을 필터링하지 마세요 (모든 메트릭 전송)"
echo ""
echo "3. ${GREEN}Thanos Receiver${NC}"
echo "   - Receiver가 Running 상태여야 합니다"
echo "   - Receiver 로그에서 메트릭 수신 기록을 확인하세요"
echo ""
echo "4. ${GREEN}Thanos Query${NC}"
echo "   - Query가 Receiver와 Store Gateway에 연결되어야 합니다"
echo "   - /api/v1/stores 엔드포인트에서 연결 상태를 확인하세요"
echo ""
echo "5. ${GREEN}Grafana Datasource${NC}"
echo "   - Thanos Query를 기본 데이터소스로 설정하세요"
echo "   - URL: http://thanos-query.monitoring.svc.cluster.local:9090"
echo ""

echo -e "${YELLOW}${WARNING}${NC} 문제가 지속되면 아래 명령으로 상세 로그를 확인하세요:"
echo ""
echo "  # Prometheus 로그"
echo "  kubectl --context cluster-02 logs -n monitoring prometheus-xxx -f"
echo ""
echo "  # Thanos Receiver 로그"
echo "  kubectl --context cluster-01 logs -n monitoring thanos-receive-0 -f"
echo ""
echo "  # Thanos Query 로그"
echo "  kubectl --context cluster-01 logs -n monitoring thanos-query-xxx -f"
echo ""

echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}진단 완료${NC}"
echo -e "${BLUE}============================================================================${NC}"
