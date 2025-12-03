kube-prometheus-stack + Grafana에서 org별로 대시보드/데이터소스를 Git에서 관리 + 자동 sync 하고 싶으면, 보통 아래 패턴으로 구현합니다:

> Git → (Flux/Argo CD 등이 K8s 리소스로 sync) →
Grafana sidecar 컨테이너가 ConfigMap/Secret를 감시 →
orgId / folder 기반으로 org별 대시보드·datasource 분리



아래는 kube-prometheus-stack 기준으로, 바로 따라할 수 있게 단계별로 정리해볼게요.


---

1. kube-prometheus-stack 에서 Grafana sidecar 켜기

values.yaml (혹은 values-grafana.yaml) 에 Grafana 설정을 넣습니다.

grafana:
  enabled: true

  # org 여러 개 쓸 거면 로그인/계정 정책은 상황에 맞게 조정
  grafana.ini:
    users:
      allow_sign_up: false
    auth:
      disable_login_form: false

  # GitOps로 넣는 provisioning 파일을 mount할 디렉토리
  extraVolumeMounts:
    - name: dashboard-providers
      mountPath: /etc/grafana/provisioning/dashboards/custom
      readOnly: true

  extraVolumes:
    - name: dashboard-providers
      configMap:
        name: grafana-dashboard-providers

  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard        # 이 label 가진 ConfigMap/Secret를 대시보드로 인식
      folderAnnotation: grafana_folder # 이 annotation으로 폴더/경로 분리
      searchNamespace: ALL            # 필요 시 조정
    datasources:
      enabled: true
      label: grafana_datasource       # 이 label 가진 ConfigMap/Secret를 데이터소스로 인식
      searchNamespace: ALL

핵심은:

label 로 어떤 ConfigMap이 Grafana 대시보드/데이터소스인지 구분

folderAnnotation 으로 org별 폴더를 나누고, 이 폴더 경로를 org별 provider에 매핑



---

2. Git 저장소 구조 예시 (org별로 폴더 분리)

예를 들어 Git repo를 이렇게 구성할 수 있어요:

git-repo/
  kube-prometheus/
    values-grafana.yaml          # 위의 Helm values
    dashboards/
      org1/
        some-dashboard.json
        another-dashboard.json
      org2/
        team-dashboard.json
    datasources/
      org1-datasource.yaml
      org2-datasource.yaml
    providers/
      dashboard-providers.yaml   # orgId / folder 매핑
  k8s-manifests/
    grafana-datasource-org1-cm.yaml
    grafana-datasource-org2-cm.yaml
    grafana-dashboards-org1-cm.yaml
    grafana-dashboards-org2-cm.yaml
    grafana-dashboard-providers-cm.yaml

kube-prometheus/… 디렉토리: 순수 Grafana JSON/YAML

k8s-manifests/… 디렉토리: 위 파일들을 ConfigMap으로 감싸는 K8s manifest (Flux/ArgoCD가 apply)



---

3. org별 datasource provisioning (ConfigMap + orgId)

3-1. Git에 datasource 정의 (순수 Grafana provisioning yaml)

kube-prometheus/datasources/org1-datasource.yaml:

apiVersion: 1
orgId: 1
datasources:
  - name: Prometheus-org1
    type: prometheus
    access: proxy
    url: http://kube-prometheus-stack-prometheus:9090
    isDefault: true
    editable: true

kube-prometheus/datasources/org2-datasource.yaml:

apiVersion: 1
orgId: 2
datasources:
  - name: Prometheus-org2
    type: prometheus
    access: proxy
    url: http://kube-prometheus-stack-prometheus:9090
    isDefault: true
    editable: true

여기서 중요한 포인트:

orgId 필드를 반드시 넣어야 org별로 datasource가 분리됩니다.

sidecar는 이 yaml을 그대로 /etc/grafana/provisioning/datasources/.. 로 복사하고, Grafana가 해석합니다.


3-2. 이 파일들을 ConfigMap으로 감싸기

k8s-manifests/grafana-datasource-org1-cm.yaml:

apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-org1
  labels:
    grafana_datasource: "1"   # sidecar.datasources.label 값과 동일해야 함
data:
  org1-datasource.yaml: |-
    apiVersion: 1
    orgId: 1
    datasources:
      - name: Prometheus-org1
        type: prometheus
        access: proxy
        url: http://kube-prometheus-stack-prometheus:9090
        isDefault: true
        editable: true

org2 도 동일하게 하나 더 만들고, orgId: 2, 파일 이름 등만 바꾸면 됩니다.

이 ConfigMap들이 Git에 있고, Flux/Argo CD가 클러스터에 apply 해 주면, sidecar가 감지해서 자동으로 datasource provision이 일어납니다.


---

4. org별 대시보드 provisioning

4-1. Git에 org별 대시보드 JSON 파일

예시: kube-prometheus/dashboards/org1/org1-overview.json (내용은 일반 Grafana dashboard JSON)

{
  "uid": "org1-overview",
  "title": "Org1 Overview",
  "tags": ["org1"],
  "schemaVersion": 36,
  "version": 1,
  "time": { "from": "now-6h", "to": "now" },
  "panels": [
    // ...
  ]
}

org2도 비슷하게 dashboards/org2/... 로 구성.

4-2. ConfigMap으로 감싸면서 org별 folder 지정

k8s-manifests/grafana-dashboards-org1-cm.yaml:

apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards-org1
  labels:
    grafana_dashboard: "1"             # sidecar.dashboards.label
  annotations:
    grafana_folder: "Org1"             # sidecar.dashboards.folderAnnotation
data:
  org1-overview.json: |-
    { ... 위 JSON ... }
  # 필요하면 여러 dashboard json 추가

grafana_folder: "Org1" annotation 덕분에 sidecar가 /var/lib/grafana/dashboards/Org1/... 구조로 파일을 떨굽니다.

org2:

metadata:
  name: grafana-dashboards-org2
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: "Org2"


---

5. orgId와 folder를 매핑하는 dashboard provider 설정

이제 Org1 폴더 → orgId=1, Org2 폴더 → orgId=2 로 연결해야 합니다.
Grafana의 dashboard provisioning 기능을 쓰면 됩니다.

5-1. Git에 provider 정의 파일

kube-prometheus/providers/dashboard-providers.yaml:

apiVersion: 1
providers:
  - name: 'org1-dashboards'
    orgId: 1
    folder: 'Org1'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards/Org1

  - name: 'org2-dashboards'
    orgId: 2
    folder: 'Org2'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards/Org2

5-2. ConfigMap으로 감싸서 Grafana에 mount

k8s-manifests/grafana-dashboard-providers-cm.yaml:

apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-providers
data:
  dashboard-providers.yaml: |-
    apiVersion: 1
    providers:
      - name: 'org1-dashboards'
        orgId: 1
        folder: 'Org1'
        type: file
        options:
          path: /var/lib/grafana/dashboards/Org1
      - name: 'org2-dashboards'
        orgId: 2
        folder: 'Org2'
        type: file
        options:
          path: /var/lib/grafana/dashboards/Org2

이 ConfigMap은 앞에서 extraVolumes / extraVolumeMounts 로 /etc/grafana/provisioning/dashboards/custom 아래에 마운트하도록 했죠. Grafana는 부팅 때 이 provider를 읽고:

orgId=1 사용자 → Org1 폴더의 대시보드

orgId=2 사용자 → Org2 폴더의 대시보드


를 자동으로 로드합니다.


---

6. Git Sync (Flux / Argo CD) 흐름

1. 개발자가 Git에 변경

dashboards/org1/*.json / dashboards/org2/*.json 수정

datasource yaml 수정 등



2. GitOps 툴 (Flux/ArgoCD)

k8s-manifests/*.yaml 을 클러스터에 kubectl apply 형태로 지속적으로 반영



3. Grafana sidecar

grafana_dashboard, grafana_datasource label 가진 ConfigMap 변경을 감지

내용을 Grafana의 provisioning 경로로 복사

Grafana는 hot reload (대시보드는 거의 바로, datasource는 프로세스 재시작 없이도 로딩)




결과적으로, Git 커밋만 하면 org별 대시보드/데이터소스 구성이 자동으로 반영됩니다.


---

7. 추가 팁 / 한계

org 자체 생성/삭제

Grafana org는 UI, API, Terraform, grafana-operator 등으로 관리하는 게 일반적입니다.

kube-prometheus-stack만으로 org 생성까지 GitOps 하고 싶으면, 보통 grafana-operator를 별도로 쓰거나, 별도 Job/Script로 Grafana HTTP API를 호출하는 패턴을 씁니다.


권한(Role) / User 관리

org별 Viewer/Editor/Admin 권한도 GitOps 하고 싶다면, Terraform + Grafana provider 또는 grafana-operator가 훨씬 편합니다.


테스트 환경

prod에 바로 적용하기 전에, 같은 구조를 가진 dev/stage namespace에 먼저 붙여보는 걸 추천합니다.

orgId 값(1, 2, …)이 실제 Grafana의 org와 일치하는지 꼭 확인하세요.




---

원하시면:

실제 쓰시는 org 이름/갯수

kube-prometheus-stack chart 버전

GitOps 도구(Flux인지 ArgoCD인지)


를 기준으로, 딱 맞는 values.yaml + ConfigMap 예제 세트를 한 번에 복붙용으로 정리해서도 만들어 줄게요.