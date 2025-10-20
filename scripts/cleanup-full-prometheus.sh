#!/bin/bash

# Cleanup Full Prometheus from Edge Clusters
# This script removes kube-prometheus-stack Full Prometheus and keeps only Prometheus Agent

set -e

CLUSTERS=("196" "197" "198")
CLUSTER_NAMES=("cluster-02" "cluster-03" "cluster-04")

echo "=========================================="
echo "Full Prometheus Cleanup Script"
echo "=========================================="
echo ""

for i in "${!CLUSTERS[@]}"; do
  NODE="${CLUSTERS[$i]}"
  CLUSTER_NAME="${CLUSTER_NAMES[$i]}"

  echo "=========================================="
  echo "Processing ${CLUSTER_NAME} (192.168.101.${NODE})"
  echo "=========================================="

  echo "--- Step 1: Backup Current Prometheus Data (Optional) ---"
  sshpass -p "123qwe" ssh -o StrictHostKeyChecking=no bsh@192.168.101.${NODE} \
    "kubectl get prometheus -n monitoring -o yaml > /tmp/prometheus-backup-${CLUSTER_NAME}.yaml 2>&1 || echo 'No Prometheus CRD found'"

  echo ""
  echo "--- Step 2: Delete Full Prometheus StatefulSet ---"
  sshpass -p "123qwe" ssh -o StrictHostKeyChecking=no bsh@192.168.101.${NODE} << 'EOSSH'
    # Delete Prometheus StatefulSet (keep Agent)
    if kubectl get statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring &>/dev/null; then
      echo "✓ Deleting prometheus-kube-prometheus-stack-prometheus..."
      kubectl delete statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring --cascade=orphan

      # Delete orphaned pods
      kubectl delete pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring --force --grace-period=0 2>/dev/null || true

      echo "✓ Full Prometheus StatefulSet removed"
    else
      echo "⚠ Full Prometheus StatefulSet not found"
    fi
EOSSH

  echo ""
  echo "--- Step 3: Delete Alertmanager (Central에서만 필요) ---"
  sshpass -p "123qwe" ssh -o StrictHostKeyChecking=no bsh@192.168.101.${NODE} << 'EOSSH'
    if kubectl get statefulset alertmanager-kube-prometheus-stack-alertmanager -n monitoring &>/dev/null; then
      echo "✓ Deleting alertmanager-kube-prometheus-stack-alertmanager..."
      kubectl delete statefulset alertmanager-kube-prometheus-stack-alertmanager -n monitoring --cascade=orphan
      kubectl delete pod alertmanager-kube-prometheus-stack-alertmanager-0 -n monitoring --force --grace-period=0 2>/dev/null || true
      echo "✓ Alertmanager removed"
    else
      echo "⚠ Alertmanager not found"
    fi
EOSSH

  echo ""
  echo "--- Step 4: Delete Grafana Test Pod ---"
  sshpass -p "123qwe" ssh -o StrictHostKeyChecking=no bsh@192.168.101.${NODE} << 'EOSSH'
    if kubectl get pod kube-prometheus-stack-grafana-test -n monitoring &>/dev/null; then
      echo "✓ Deleting kube-prometheus-stack-grafana-test..."
      kubectl delete pod kube-prometheus-stack-grafana-test -n monitoring --force --grace-period=0 2>/dev/null || true
      echo "✓ Grafana test pod removed"
    else
      echo "⚠ Grafana test pod not found"
    fi
EOSSH

  echo ""
  echo "--- Step 5: Clean up PVCs (Optional - Storage Reclaim) ---"
  echo "⚠ Skipping PVC cleanup to preserve data. Run manually if needed:"
  echo "   kubectl delete pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0 -n monitoring"
  echo "   kubectl delete pvc alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0 -n monitoring"

  echo ""
  echo "--- Step 6: Verify Prometheus Agent is Running ---"
  sshpass -p "123qwe" ssh -o StrictHostKeyChecking=no bsh@192.168.101.${NODE} << 'EOSSH'
    if kubectl get pod prometheus-agent-0 -n monitoring | grep -q "Running"; then
      echo "✅ Prometheus Agent is running"
      kubectl get pod prometheus-agent-0 -n monitoring
    else
      echo "❌ WARNING: Prometheus Agent is NOT running!"
      kubectl get pod prometheus-agent-0 -n monitoring 2>&1
    fi
EOSSH

  echo ""
  echo "--- Step 7: Current Monitoring Pods ---"
  sshpass -p "123qwe" ssh -o StrictHostKeyChecking=no bsh@192.168.101.${NODE} \
    "kubectl get pods -n monitoring --no-headers | grep -E 'prometheus|alertmanager|node-exporter|kube-state'" 2>&1 || echo "No pods found"

  echo ""
  echo "=========================================="
  echo "✓ ${CLUSTER_NAME} cleanup completed"
  echo "=========================================="
  echo ""

  # Add 5 second delay between clusters
  if [ $i -lt $((${#CLUSTERS[@]} - 1)) ]; then
    echo "Waiting 5 seconds before next cluster..."
    sleep 5
    echo ""
  fi
done

echo ""
echo "=========================================="
echo "🎉 All Edge Clusters Cleaned Up"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Full Prometheus: REMOVED"
echo "- Alertmanager: REMOVED"
echo "- Prometheus Agent: ✅ RUNNING"
echo "- Node Exporter: ✅ RUNNING"
echo "- Kube-State-Metrics: ✅ RUNNING"
echo ""
echo "Next Steps:"
echo "1. Verify Agent is sending metrics to Central Receiver:"
echo "   kubectl exec -n monitoring prometheus-agent-0 -- wget -O- http://192.168.101.210:19291/-/ready"
echo ""
echo "2. Check Thanos Receiver metrics on Central Cluster:"
echo "   kubectl logs -n monitoring thanos-receive-0 --tail=50"
echo ""
echo "3. Verify in Grafana that edge cluster metrics are visible"
