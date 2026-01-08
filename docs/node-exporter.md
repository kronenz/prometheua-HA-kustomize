아래는 베어메탈 Nginx LB 서버에 이미 containerd (ctr) 가 설치되어 있는 환경에서,
node-exporter를 “컨테이너 기반으로 배포·운영”하는 표준 가이드입니다.
(쿠버네티스 없이, systemd + containerd 조합으로 안정적으로 운영하는 방식)


---

containerd(ctr) 기반 node-exporter 배포·운영 가이드

1) 아키텍처 개요

[ Prometheus (K8s / kube-prometheus-stack) ]
              |
              |  scrape (9100)
              v
[ Baremetal Nginx LB ]
  └─ containerd
      └─ node-exporter (container)

컨테이너 실행 책임: containerd

프로세스 관리/자동 재시작: systemd

노출 포트: 9100/TCP

권한: host PID / mount namespace 접근 필요



---

2) 사전 확인

ctr version
containerd --version

권장:

containerd ≥ 1.6

node-exporter ≥ 1.6


네임스페이스 확인:

ctr namespaces list

> 기본적으로 default 네임스페이스 사용 권장
(쿠버네티스와 분리되어 있어 관리가 단순)




---

3) node-exporter 이미지 준비

3-1. 이미지 Pull

ctr -n default images pull docker.io/prom/node-exporter:v1.7.0

확인:

ctr -n default images list | grep node-exporter


---

4) 컨테이너 실행 옵션 설계 (중요)

node-exporter는 호스트 정보 접근이 필요하므로 다음이 필수입니다:

항목	이유

--net-host	호스트 네트워크(9100 직접 노출)
/proc, /sys, / 마운트	커널/파일시스템 메트릭
--pid=host	프로세스 메트릭
readonly rootfs	보안



---

5) ctr run으로 직접 실행 (테스트용)

⚠️ 운영은 systemd에서 실행 권장, 아래는 동작 확인용입니다.

ctr -n default run --rm \
  --net-host \
  --mount type=bind,src=/proc,dst=/host/proc,options=rbind:ro \
  --mount type=bind,src=/sys,dst=/host/sys,options=rbind:ro \
  --mount type=bind,src=/,dst=/rootfs,options=rbind:ro \
  docker.io/prom/node-exporter:v1.7.0 \
  node-exporter \
  /bin/node_exporter \
    --path.procfs=/host/proc \
    --path.sysfs=/host/sys \
    --path.rootfs=/rootfs \
    --web.listen-address=:9100

확인:

curl http://localhost:9100/metrics | head


---

6) systemd + containerd로 운영 구성 (권장 방식)

6-1. systemd 서비스 파일 생성

sudo tee /etc/systemd/system/node-exporter-container.service >/dev/null <<'EOF'
[Unit]
Description=Node Exporter (containerd)
After=network-online.target containerd.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ctr -n default run \
  --rm \
  --net-host \
  --mount type=bind,src=/proc,dst=/host/proc,options=rbind:ro \
  --mount type=bind,src=/sys,dst=/host/sys,options=rbind:ro \
  --mount type=bind,src=/,dst=/rootfs,options=rbind:ro \
  docker.io/prom/node-exporter:v1.7.0 \
  node-exporter \
  /bin/node_exporter \
    --path.procfs=/host/proc \
    --path.sysfs=/host/sys \
    --path.rootfs=/rootfs \
    --collector.systemd \
    --collector.processes \
    --web.listen-address=:9100

ExecStop=/usr/bin/ctr -n default task kill -s SIGTERM node-exporter

Restart=always
RestartSec=5
KillMode=process
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

6-2. 서비스 활성화

sudo systemctl daemon-reload
sudo systemctl enable --now node-exporter-container
sudo systemctl status node-exporter-container --no-pager


---

7) Prometheus 연동 (요약)

Prometheus 쪽은 기존 kube-prometheus-stack의 additionalScrapeConfigs 사용:

- job_name: "external-node-exporter"
  static_configs:
    - targets:
        - "NGINX_LB_IP:9100"
      labels:
        role: "lb"
        env: "prod"


---

8) 운영/보안 베스트 프랙티스

A. 방화벽 제한 (강력 권장)

9100/TCP는 Prometheus 노드/Pod CIDR만 허용

외부 인터넷 차단


B. 이미지 업그레이드 절차

ctr -n default images pull docker.io/prom/node-exporter:v1.7.1
sudo systemctl restart node-exporter-container

C. 상태 확인

ctr -n default tasks list
journalctl -u node-exporter-container -f

D. 라벨로 K8s 노드와 구분

Grafana에서 필터링용:

job=external-node-exporter

role=lb



---

9) 왜 이 방식이 좋은가?

항목	systemd + ctr

Docker 의존성	❌
kubelet 필요	❌
장애 시 자동 재시작	✅
보안 통제	높음
운영 단순성	높음



---

10) 대안 비교

방식	비고

ctr + systemd	⭐ 가장 추천
nerdctl	Docker와 유사 UX
docker	의존성 증가
grafana agent	remote_write 필요



---

원하시면 다음도 바로 만들어드릴 수 있습니다:

✅ nerdctl 기반 운영 가이드

✅ 여러 LB 서버를 위한 공통 systemd 템플릿

✅ node-exporter + nginx exporter 같이 띄우는 구성

✅ 보안(mTLS / reverse proxy) 적용 버전


원하는 방향 말해주시면 그 기준으로 정리해드릴게요.