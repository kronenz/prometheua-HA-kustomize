#!/bin/bash
# 전체 클러스터 배포 마스터 스크립트
# 모든 노드에 전체 모니터링 스택을 순차적으로 배포합니다.

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY_DIR="${PROJECT_ROOT}/deploy"

# 클러스터 정의
declare -A CLUSTERS
CLUSTERS[196]="192.168.101.196:cluster-196-central"
CLUSTERS[197]="192.168.101.197:cluster-197-edge"
CLUSTERS[198]="192.168.101.198:cluster-198-edge"

SSH_USER="${SSH_USER:-bsh}"
SSH_PASS="${SSH_PASS:-123qwe}"

# 배포 단계
PHASES=(
    "longhorn:Longhorn Storage"
    "ingress-nginx:NGINX Ingress"
    "prometheus:Prometheus Stack"
    "opensearch:OpenSearch"
    "fluent-bit:Fluent-bit"
)

echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Thanos Multi-Cluster 전체 배포 스크립트      ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# 사전 확인
echo -e "${YELLOW}[0/5] 사전 확인${NC}"
echo "───────────────────────────────────────────────"

# Kustomize 확인
if ! command -v kustomize &> /dev/null; then
    echo -e "${RED}✗ kustomize가 설치되어 있지 않습니다${NC}"
    echo "설치: curl -s \"https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh\" | bash"
    exit 1
fi
echo -e "${GREEN}✓ kustomize 설치 확인${NC}"

# kubectl 확인
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl이 설치되어 있지 않습니다${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl 설치 확인${NC}"

# sshpass 확인 (선택사항)
if ! command -v sshpass &> /dev/null; then
    echo -e "${YELLOW}⚠ sshpass 미설치 - 원격 배포는 수동으로 진행해야 합니다${NC}"
    REMOTE_DEPLOY=false
else
    echo -e "${GREEN}✓ sshpass 설치 확인${NC}"
    REMOTE_DEPLOY=true
fi

echo ""

# 배포 모드 선택
echo -e "${BLUE}배포 모드를 선택하세요:${NC}"
echo "  1. 로컬만 배포 (현재 노드의 Minikube 클러스터)"
echo "  2. 특정 노드 배포 (SSH 사용)"
echo "  3. 전체 노드 배포 (196, 197, 198 모두)"
echo ""
read -p "선택 (1-3): " DEPLOY_MODE
echo ""

case "$DEPLOY_MODE" in
    1)
        echo -e "${GREEN}로컬 배포 모드${NC}"
        DEPLOY_CLUSTERS=("local")
        ;;
    2)
        echo -e "${GREEN}특정 노드 배포 모드${NC}"
        echo "배포할 노드 번호를 입력하세요 (196, 197, 198):"
        read -p "노드: " NODE_NUM
        if [[ ! "${!CLUSTERS[@]}" =~ "${NODE_NUM}" ]]; then
            echo -e "${RED}잘못된 노드 번호입니다${NC}"
            exit 1
        fi
        DEPLOY_CLUSTERS=("${NODE_NUM}")
        ;;
    3)
        echo -e "${GREEN}전체 노드 배포 모드${NC}"
        DEPLOY_CLUSTERS=("196" "197" "198")
        ;;
    *)
        echo -e "${RED}잘못된 선택입니다${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}배포를 시작합니다...${NC}"
echo ""

# 함수: 로컬 배포
deploy_local() {
    local component="$1"
    local name="$2"
    local overlay_path="$3"

    echo -e "${CYAN}>>> ${name} 배포 중...${NC}"

    # 네임스페이스 결정
    local namespace=""
    case "$component" in
        longhorn)
            namespace="longhorn-system"
            ;;
        ingress-nginx)
            namespace="ingress-nginx"
            ;;
        prometheus)
            namespace="monitoring"
            ;;
        opensearch|fluent-bit)
            namespace="logging"
            ;;
    esac

    # 네임스페이스 생성
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

    # Kustomize 빌드 및 배포
    if kustomize build "${overlay_path}" --enable-helm | kubectl apply -f - -n "$namespace"; then
        echo -e "${GREEN}✓ ${name} 배포 완료${NC}"
        return 0
    else
        echo -e "${RED}✗ ${name} 배포 실패${NC}"
        return 1
    fi
}

# 함수: 원격 배포
deploy_remote() {
    local node_ip="$1"
    local node_num="$2"
    local cluster_name="$3"
    local component="$4"
    local name="$5"

    echo -e "${CYAN}>>> [노드 ${node_num}] ${name} 배포 중...${NC}"

    local overlay_path="deploy/overlays/${cluster_name}/${component}"

    # 원격 실행 스크립트
    local remote_script="
        set -e
        cd ${PROJECT_ROOT}

        # 네임스페이스 결정
        case '${component}' in
            longhorn) namespace='longhorn-system' ;;
            ingress-nginx) namespace='ingress-nginx' ;;
            prometheus) namespace='monitoring' ;;
            opensearch|fluent-bit) namespace='logging' ;;
        esac

        # 네임스페이스 생성
        kubectl create namespace \$namespace --dry-run=client -o yaml | kubectl apply -f -

        # 배포
        kustomize build ${overlay_path} --enable-helm | kubectl apply -f - -n \$namespace
    "

    if sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no "${SSH_USER}@${node_ip}" "${remote_script}"; then
        echo -e "${GREEN}✓ [노드 ${node_num}] ${name} 배포 완료${NC}"
        return 0
    else
        echo -e "${RED}✗ [노드 ${node_num}] ${name} 배포 실패${NC}"
        return 1
    fi
}

# 배포 실행
TOTAL_DEPLOYMENTS=0
SUCCESS_DEPLOYMENTS=0
FAILED_DEPLOYMENTS=0

for cluster_id in "${DEPLOY_CLUSTERS[@]}"; do
    if [ "$cluster_id" = "local" ]; then
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}   로컬 클러스터 배포${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo ""

        # 로컬 컨텍스트 확인
        if ! kubectl cluster-info > /dev/null 2>&1; then
            echo -e "${RED}kubectl이 클러스터에 연결되어 있지 않습니다${NC}"
            echo "Minikube를 시작하세요: minikube start"
            exit 1
        fi

        # 현재 노드 번호 추정 (IP 기반)
        NODE_IP=$(kubectl get nodes -o wide | awk 'NR==2 {print $6}')
        if [[ "$NODE_IP" =~ 192\.168\.101\.([0-9]+) ]]; then
            NODE_NUM="${BASH_REMATCH[1]}"
            CLUSTER_NAME="cluster-${NODE_NUM}-$([ "$NODE_NUM" = "196" ] && echo "central" || echo "edge")"
        else
            echo -e "${YELLOW}노드 번호를 자동 감지할 수 없습니다. 196으로 가정합니다.${NC}"
            CLUSTER_NAME="cluster-196-central"
        fi

        echo -e "클러스터: ${GREEN}${CLUSTER_NAME}${NC}"
        echo ""

        # 각 컴포넌트 배포
        for phase in "${PHASES[@]}"; do
            IFS=':' read -r component name <<< "$phase"

            TOTAL_DEPLOYMENTS=$((TOTAL_DEPLOYMENTS + 1))

            overlay_path="${DEPLOY_DIR}/overlays/${CLUSTER_NAME}/${component}"

            if [ ! -d "$overlay_path" ]; then
                echo -e "${YELLOW}⊘ ${name} 스킵 (overlay 없음: ${overlay_path})${NC}"
                continue
            fi

            if deploy_local "$component" "$name" "$overlay_path"; then
                SUCCESS_DEPLOYMENTS=$((SUCCESS_DEPLOYMENTS + 1))
            else
                FAILED_DEPLOYMENTS=$((FAILED_DEPLOYMENTS + 1))
            fi

            echo ""
            sleep 2
        done

    else
        # 원격 배포
        node_ip=$(echo "${CLUSTERS[$cluster_id]}" | cut -d':' -f1)
        cluster_name=$(echo "${CLUSTERS[$cluster_id]}" | cut -d':' -f2)

        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}   노드 ${cluster_id} (${node_ip}) 배포${NC}"
        echo -e "${BLUE}   클러스터: ${cluster_name}${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo ""

        if [ "$REMOTE_DEPLOY" = false ]; then
            echo -e "${YELLOW}원격 배포를 위해 다음 명령을 각 노드에서 실행하세요:${NC}"
            echo ""
            for phase in "${PHASES[@]}"; do
                IFS=':' read -r component name <<< "$phase"
                echo "ssh ${SSH_USER}@${node_ip}"
                echo "cd ${PROJECT_ROOT}"
                echo "./scripts/deploy-component.sh ${component} ${cluster_name}"
                echo ""
            done
            continue
        fi

        # SSH 연결 확인
        if ! sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${SSH_USER}@${node_ip}" "echo test" > /dev/null 2>&1; then
            echo -e "${RED}✗ 노드 ${cluster_id} (${node_ip})에 SSH 연결 실패${NC}"
            echo ""
            continue
        fi

        # 각 컴포넌트 배포
        for phase in "${PHASES[@]}"; do
            IFS=':' read -r component name <<< "$phase"

            TOTAL_DEPLOYMENTS=$((TOTAL_DEPLOYMENTS + 1))

            if deploy_remote "$node_ip" "$cluster_id" "$cluster_name" "$component" "$name"; then
                SUCCESS_DEPLOYMENTS=$((SUCCESS_DEPLOYMENTS + 1))
            else
                FAILED_DEPLOYMENTS=$((FAILED_DEPLOYMENTS + 1))
            fi

            echo ""
            sleep 2
        done
    fi

    echo ""
done

# 최종 결과
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           배포 완료 요약                       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "총 배포: ${TOTAL_DEPLOYMENTS}"
echo -e "${GREEN}성공: ${SUCCESS_DEPLOYMENTS}${NC}"
echo -e "${RED}실패: ${FAILED_DEPLOYMENTS}${NC}"
echo ""

if [ "$FAILED_DEPLOYMENTS" -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 배포가 성공적으로 완료되었습니다!${NC}"
    echo ""
    echo -e "${YELLOW}다음 단계:${NC}"
    echo "  1. 배포 상태 확인: ./scripts/validate-deployment.sh"
    echo "  2. Grafana 접속: http://grafana.mkube-196.miribit.lab"
    echo "  3. 모니터링 시작!"
    exit 0
else
    echo -e "${RED}✗ 일부 배포가 실패했습니다.${NC}"
    echo "로그를 확인하고 문제를 해결하세요."
    exit 1
fi
