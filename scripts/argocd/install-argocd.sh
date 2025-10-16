#!/bin/bash

# ArgoCD 설치 스크립트 (HA mode)
# 중앙 클러스터(cluster-01-central)에 설치

set -e

echo "=== ArgoCD 설치 시작 ==="

# 1. Namespace 생성
echo "[1/5] Namespace 생성..."
kubectl apply -f argocd/install/namespace.yaml

# 2. ArgoCD HA 설치
echo "[2/5] ArgoCD HA 설치..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml

# 3. ArgoCD 준비 대기
echo "[3/5] ArgoCD Pods 준비 대기..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 4. Ingress 생성
echo "[4/5] Ingress 생성..."
kubectl apply -f argocd/install/ingress.yaml

# 5. 초기 admin 비밀번호 확인
echo "[5/5] 초기 admin 비밀번호 확인..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "=== ArgoCD 설치 완료 ==="
echo ""
echo "접속 정보:"
echo "  URL: https://argocd.k8s-cluster-01.miribit.lab"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "다음 명령어로 ArgoCD CLI 로그인:"
echo "  argocd login argocd.k8s-cluster-01.miribit.lab --username admin --password ${ARGOCD_PASSWORD}"
echo ""
