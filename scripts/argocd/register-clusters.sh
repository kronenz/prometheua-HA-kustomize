#!/bin/bash

# 원격 클러스터를 ArgoCD에 등록하는 스크립트

set -e

echo "=== ArgoCD 클러스터 등록 시작 ==="

# ArgoCD CLI 설치 확인
if ! command -v argocd &> /dev/null; then
    echo "Error: argocd CLI가 설치되지 않았습니다."
    echo "설치 방법: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
    exit 1
fi

# 1. cluster-02 등록 (196)
echo "[1/3] cluster-02 등록 (192.168.101.196)..."
argocd cluster add cluster-02-context \
    --name cluster-02 \
    --server-side-apply

# 2. cluster-03 등록 (197)
echo "[2/3] cluster-03 등록 (192.168.101.197)..."
argocd cluster add cluster-03-context \
    --name cluster-03 \
    --server-side-apply

# 3. cluster-04 등록 (198)
echo "[3/3] cluster-04 등록 (192.168.101.198)..."
argocd cluster add cluster-04-context \
    --name cluster-04 \
    --server-side-apply

echo ""
echo "=== 클러스터 등록 완료 ==="
echo ""
echo "등록된 클러스터 확인:"
argocd cluster list
echo ""
