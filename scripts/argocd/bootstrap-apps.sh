#!/bin/bash

# Root Application 배포 및 전체 시스템 부트스트랩

set -e

echo "=== ArgoCD Application 부트스트랩 시작 ==="

# 1. Root Application 배포
echo "[1/2] Root Application 배포..."
kubectl apply -f argocd/root-app.yaml

# 2. Root Application Sync 대기
echo "[2/2] Root Application Sync 대기..."
argocd app wait root-app --health --timeout 600

echo ""
echo "=== 부트스트랩 완료 ==="
echo ""
echo "ArgoCD UI에서 배포 상태 확인:"
echo "  https://argocd.k8s-cluster-01.miribit.lab"
echo ""
echo "CLI로 Application 상태 확인:"
echo "  argocd app list"
echo ""
