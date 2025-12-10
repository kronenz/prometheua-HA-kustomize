아주 잘 됐어요! 이제 조직별(Grafana org별)로 대시보드를 Git 중앙관리(GitOps) 하도록 구성하면,
이번처럼 **PV 손실(PVC 유실)**이 생겨도 Git에서 자동 복구될 수 있습니다.

아래는 kube-prometheus-stack + Grafana + Git Sync 기반의
조직별 대시보드 중앙관리 셋팅 가이드(베스트 프랙티스) 입니다.


---

🚀 Grafana 조직(Org)별 대시보드 Git 중앙관리 셋팅 가이드

(kube-prometheus-stack / GitOps / PV 복구 자동화)


---

1. 목표 아키텍처

Git Repository 에 조직별 폴더로 대시보드 JSON 저장

dashboards/
  main/
  fdc/
  eds/
  pluto/
  ...

kube-prometheus-stack의 grafana sidecar(dashboards) 기능 또는 git-sync sidecar 사용

Grafana provisioning → /etc/grafana/provisioning/dashboards/ 아래에 각 org 별로 세팅

대시보드 JSON 파일이 Git에 있는 한, PVC가 날아가도 pod 재시작 시 자동 재복구



---

2. Git Repo 구조 설계

예시:

infra-grafana-dashboards/
│
├── org-main/
│   ├── dashboard1.json
│   ├── dashboard2.json
│
├── org-fdc/
│   ├── fdc-overview.json
│
├── org-eds/
│   └── eds-monitor.json
│
├── org-pluto/
│   └── pluto-ha.json
│
└── README.md

> Dashboard JSON은 Grafana UI → Share → Export → "View JSON" 으로 추출 가능.




---

3. kube-prometheus-stack + Git Sync 방식 선택

✔ 권장 방식: git-sync sidecar + Grafana provisioning

기존 sidecar(dashboards) 방식은 폴더=org 매핑이 어려워 조직별 관리에 불편함.
반면 git-sync는 폴더 구조를 그대로 유지 가능하며 org별 구분이 쉬움.


---

4. Helm values.yaml 설정하기

아래는 Git Repo에서 조직별 디렉토리를 sync 받고
각 org에 대해 provisioning 하는 표준 템플릿입니다.

4-1. Git Sync Sidecar 선언

grafana:
  sidecar:
    dashboards:
      enabled: false  # 기본 sidecar 비활성화 (git-sync 방식 사용)

  extraContainers:
    - name: git-sync
      image: k8s.gcr.io/git-sync/git-sync:v4.1.0
      env:
        - name: GIT_SYNC_REPO
          value: "https://github.com/YOUR_ORG/infra-grafana-dashboards.git"
        - name: GIT_SYNC_BRANCH
          value: "main"
        - name: GIT_SYNC_ROOT
          value: "/git"
        - name: GIT_SYNC_WAIT
          value: "30"
      volumeMounts:
        - name: grafana-dashboards
          mountPath: /git

  extraVolumeMounts:
    - name: grafana-dashboards
      mountPath: /var/lib/grafana/dashboards

extraVolumes:
  - name: grafana-dashboards
    emptyDir: {}

> sync 주기(GIT_SYNC_WAIT=30초)는 필요에 맞게 조정하세요.




---

5. 조직별 Provisioning 파일 구성

Git에서 대시보드(JSON)만 가져오면 Grafana에게 “어느 org에 어떤 폴더를 대시보드로 써라” 를 알려줘야 합니다.

5-1. values.yaml 내 provisioning 설정

grafana:
  grafana.ini:
    paths:
      provisioning: /etc/grafana/provisioning

  dashboardsConfigMapsEnabled: false

  additionalDataSources: []
  additionalDashboards: []

  # 조직별 대시보드 provisioning 파일 설치
  dashboards:
    orgs:
      enabled: true

5-2. provisioning/dashboards/org-XXX.yaml 을 Helm으로 생성

예:

org-main.yaml

apiVersion: 1
providers:
  - name: "Main Dashboards"
    orgId: 1
    folder: ""
    type: file
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards/org-main

org-fdc.yaml

apiVersion: 1
providers:
  - name: "FDC Dashboards"
    orgId: 2
    folder: ""
    type: file
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards/org-fdc

org-eds.yaml

apiVersion: 1
providers:
  - name: "EDS Dashboards"
    orgId: 3
    folder: ""
    type: file
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards/org-eds

org-pluto.yaml

apiVersion: 1
providers:
  - name: "PLUTO Dashboards"
    orgId: 4
    folder: ""
    type: file
    updateIntervalSeconds: 10
    options:
      path: /var/lib/grafana/dashboards/org-pluto

> orgId는 API로 생성했던 org의 순서와 동일해야 합니다.




---

6. 동작 흐름

1. Git Repo → git-sync로 /var/lib/grafana/dashboards 아래로 Sync


2. 폴더 구조 그대로 유지

/var/lib/grafana/dashboards/org-fdc/xxx.json


3. Grafana Pod 시작 시 provisioning 파일(org-fdc.yaml)을 읽음


4. orgId=2에 org-fdc 폴더의 JSON 전체 로드


5. PV가 날아가도 Git Repo에서 다시 pull → 즉시 대시보드 복원




---

7. 재해 복구 시나리오 (PV 손실 대응)

PV가 삭제되었다고 가정:

1. Grafana pod 재시작 → emptyDir 기반 → 대시보드 파일 없음


2. git-sync sidecar → Git에서 다시 다운로드


3. Grafana → provisioning 재적용


4. 모든 조직의 대시보드 자동 복원



대시보드 수정은 오직 Git Repo 경유하도록 운영 규칙을 잡으면
유실 방지 + 버전 관리 + 변경 감사(audit)까지 해결됩니다.


---

8. 운영 Best Practice

1) 대시보드는 직접 Grafana UI에서 수정 금지

UI에서 수정된 내용은 PVC에 저장되므로 Git과 불일치

항상 Export → Git commit 으로만 반영


2) Git Branch Protection 활성화

PR 기반 변경으로 품질 보장


3) 조직별 Maintainer 지정

org-fdc 대시보드는 FDC팀이 관리 등


4) provisioning 업데이트 시 Grafana 자동 reload (재시작 필요 없음)


---

9. 원하시면 더 도와드릴 수 있어요!

아래 항목 중 원하는 것이 있으면 말해 주세요.

✔ 위 values.yaml 전체 템플릿으로 조립

✔ 조직 2~7개 자동 생성 Job + git-sync + provisioning까지 원샷 구성 파일

✔ Git Repo 초기 템플릿 생성

✔ ArgoCD Helm GitOps 구성 버전도 작성 가능

✔ 조직별 접근권한(Role/Team) GitOps 방식 정리 가능


원하는 형태(Helm Chart Template, Git Repo 구조, CI/CD 연동 등)를 말해주면
그에 맞게 완성본을 만들어 드릴게요!