# K8s 워크로드 대시보드 수정 요약

## 문제
- **Dashboard**: 쿠버네티스-05-인프라-워크로드 현황 (`/d/k8s-workload-status-v1`)
- **증상**: 모든 패널에 "No Data" 표시

## 원인
1. **kube-state-metrics 비활성화**: Deployment replica가 0으로 설정
2. **잘못된 PromQL 쿼리**: `count()` 대신 `sum(... == 1)` 사용 필요

## 해결
```bash
# 1. kube-state-metrics 활성화
kubectl scale deployment -n monitoring kube-prometheus-stack-kube-state-metrics --replicas=1

# 2. 쿼리 수정 (6개)
# 변경 전: count(kube_pod_status_phase{phase="Running"})
# 변경 후: sum(kube_pod_status_phase{phase="Running"} == 1)
```

## 결과
✅ 모든 패널 정상 작동:
- Running Pods: 59
- Pending Pods: 1
- Failed Pods: 5
- Deployments: 23
- StatefulSets: 12
- CrashLoopBackOff: 1

## 상세 문서
[11-K8s-워크로드-대시보드-수정-완료.md](./11-K8s-워크로드-대시보드-수정-완료.md)
