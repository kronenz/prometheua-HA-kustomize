│  > prometheus agent remotewrite를 thanos receiver replica3 으로 구성시에 ingress와  service 구성은 어떻게 해야하는가 clusterip 로 설정하면 해쉬링 통신이 안되고 headless로 remotewrite를   │
│    붙이면 receive를 찾지 못                                                                                                                                                                │
╰────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

✦ 안녕하세요. Prometheus remote_write를 3개의 복제본을 가진 Thanos Receive와 연동할 때 겪는 문제는 쿠버네티스에서 상태를 가진(stateful) 애플리케이션의 네트워킹을 구성할 때 흔히 발생하는
  상황입니다.

  문제의 핵심은 두 가지 통신 경로를 분리해서 생각해야 한다는 것입니다.

   1. Ingestion (수집) 경로: Prometheus Agent가 메트릭을 Thanos Receive로 보내는 경로 (remote_write).
   2. Gossip/Hashring 경로: Thanos Receive 복제본들이 서로를 발견하고 해시링을 구성하기 위해 통신하는 경로.

  사용자께서 겪으신 문제는 다음과 같습니다.
   * ClusterIP 서비스 사용 시: Prometheus는 remote_write를 잘 보내지만, 서비스 IP가 트래픽을 라운드로빈으로 분산시키므로 해시링 멤버 간의 직접적인 통신이 어렵습니다.
   * Headless 서비스 사용 시: Prometheus remote_write 설정에 Headless 서비스의 DNS (my-headless-svc.namespace.svc.cluster.local)를 직접 사용하면, 해당 DNS는 여러 Pod IP로 확인되므로
     Prometheus가 특정 엔드포인트를 선택하는 데 어려움을 겪거나 실패합니다.

  해결책: 두 종류의 서비스를 모두 사용

  올바른 구성은 각 통신 경로의 목적에 맞는 별도의 쿠버네티스 서비스를 생성하는 것입니다.

   1. `ClusterIP` 서비스 (Ingestion용): Prometheus가 remote_write 데이터를 보낼 단일하고 안정적인 엔드포인트를 제공합니다. 이 서비스는 들어오는 쓰기 요청을 여러 Thanos Receive Pod에
      분산합니다.
   2. `Headless` 서비스 (Hashring용): Thanos Receive Pod들이 서로를 DNS로 조회하고 직접 통신하여 해시링을 구성할 수 있도록 합니다. 이 서비스는 clusterIP: None으로 설정하여 각 Pod의 고유한
      DNS A 레코드를 생성합니다.

  구성 예제

  아래는 StatefulSet으로 Thanos Receive를 배포하고, 두 종류의 서비스를 설정하는 전체 예제입니다.

  가정:
   * 네임스페이스: monitoring
   * Thanos Receive 포트:
       * 10908 (http - remote_write 수신용)
       * 10907 (grpc - 해시링 및 내부 통신용)

  ---

  1. Thanos Receive StatefulSet

  StatefulSet은 각 Pod에 안정적인 네트워크 식별자(예: thanos-receive-0, thanos-receive-1)를 제공하므로 해시링 구성에 필수적입니다.

  thanos-receive-sts.yaml:

    1 apiVersion: apps/v1
    2 kind: StatefulSet
    3 metadata:
    4   name: thanos-receive
    5   namespace: monitoring
    6   labels:
    7     app.kubernetes.io/name: thanos-receive
    8 spec:
    9   replicas: 3
   10   selector:
   11     matchLabels:
   12       app.kubernetes.io/name: thanos-receive
   13   serviceName: "thanos-receive-headless" # Headless 서비스와 연결
   14   template:
   15     metadata:
   16       labels:
   17         app.kubernetes.io/name: thanos-receive
   18     spec:
   19       containers:
   20         - name: thanos-receive
   21           image: quay.io/thanos/thanos:v0.32.5 # 최신 버전 사용 권장
   22           args:
   23             - "receive"
   24             - "--tsdb.path=/var/thanos/receive"
   25             - "--grpc-address=0.0.0.0:10907"
   26             - "--http-address=0.0.0.0:10908"
   27             - "--log.level=info"
   28             - "--label=receive_replica=\"$(POD_NAME)\""
   29             # Headless 서비스를 사용하여 다른 피어를 찾음
   30             - "--cluster.peers=dnssrv+_grpc._tcp.thanos-receive-headless.monitoring.svc.cluster.local"
   31           ports:
   32             - name: http
   33               containerPort: 10908
   34             - name: grpc
   35               containerPort: 10907
   36           env:
   37             - name: POD_NAME
   38               valueFrom:
   39                 fieldRef:
   40                   fieldPath: metadata.name
   41           volumeMounts:
   42             - name: data
   43               mountPath: /var/thanos/receive
   44   volumeClaimTemplates:
   45     - metadata:
   46         name: data
   47       spec:
   48         accessModes: ["ReadWriteOnce"]
   49         resources:
   50           requests:
   51             storage: 10Gi
  핵심 설정:
   * serviceName: "thanos-receive-headless": 이 StatefulSet이 thanos-receive-headless 서비스에 의해 관리됨을 명시합니다.
   * --cluster.peers: dnssrv+... 형태의 DNS SRV 레코드를 조회하여 해시링 멤버를 동적으로 찾습니다. 이것이 Headless 서비스가 필요한 이유입니다.

  ---

  2. Headless 서비스 (Hashring 통신용)

  thanos-receive-headless-svc.yaml:

    1 apiVersion: v1
    2 kind: Service
    3 metadata:
    4   name: thanos-receive-headless
    5   namespace: monitoring
    6 spec:
    7   clusterIP: None # Headless 서비스로 정의
    8   selector:
    9     app.kubernetes.io/name: thanos-receive
   10   ports:
   11     - name: grpc
   12       port: 10907
   13       targetPort: 10907
   14     - name: http
   15       port: 10908
   16       targetPort: 10908
  이 서비스는 thanos-receive-0.thanos-receive-headless.monitoring.svc.cluster.local, thanos-receive-1... 과 같은 각 Pod의 DNS 레코드를 생성합니다.

  ---

  3. ClusterIP 서비스 (Ingestion용)

  thanos-receive-svc.yaml:

    1 apiVersion: v1
    2 kind: Service
    3 metadata:
    4   name: thanos-receive
    5   namespace: monitoring
    6 spec:
    7   type: ClusterIP
    8   selector:
    9     app.kubernetes.io/name: thanos-receive
   10   ports:
   11     - name: http
   12       port: 10908
   13       targetPort: 10908
  이 서비스는 thanos-receive.monitoring.svc.cluster.local이라는 단일 DNS 이름을 제공하며, Prometheus Agent가 remote_write 대상으로 사용합니다.

  ---

  4. Ingress (선택 사항)

  클러스터 외부에서 remote_write를 허용해야 하는 경우, Ingress를 ClusterIP 서비스(thanos-receive)에 연결합니다.

  thanos-receive-ingress.yaml:

    1 apiVersion: networking.k8s.io/v1
    2 kind: Ingress
    3 metadata:
    4   name: thanos-receive
    5   namespace: monitoring
    6   annotations:
    7     # 사용하는 Ingress Controller에 맞는 어노테이션을 사용하세요.
    8     # 예: nginx.ingress.kubernetes.io/rewrite-target: /
    9 spec:
   10   rules:
   11     - host: thanos-receive.your-domain.com
   12       http:
   13         paths:
   14           - path: /
   15             pathType: Prefix
   16             backend:
   17               service:
   18                 name: thanos-receive # ClusterIP 서비스에 연결
   19                 port:
   20                   name: http

  ---

  최종 Prometheus Agent 설정

  이제 Prometheus Agent의 remote_write 설정은 ClusterIP 서비스를 가리키도록 합니다.

   1 # prometheus.yaml 또는 agent.yaml
   2 remote_write:
   3   - url: "http://thanos-receive.monitoring.svc.cluster.local:10908/api/v1/write"
   * api/v1/write는 Thanos v0.32.0 이상에서 권장되는 remote_write 경로입니다. 이전 버전을 사용 중이라면 api/v1/receive를 사용하세요.

  요약

   1. `StatefulSet`으로 Thanos Receive를 배포하여 안정적인 Pod ID를 보장합니다.
   2. `Headless` 서비스를 생성하고, StatefulSet의 --cluster.peers 인자가 이 서비스를 가리키도록 하여 해시링 통신을 활성화합니다.
   3. `ClusterIP` 서비스를 생성하여 Prometheus Agent가 remote_write할 수 있는 안정적인 단일 엔드포인트를 제공합니다.
   4. Prometheus Agent의 remote_write.url은 `ClusterIP` 서비스의 주소를 사용합니다.
   5. 외부 노출이 필요하면 `Ingress`를 ClusterIP 서비스에 연결합니다.

  이 구성을 통해 Prometheus는 안정적으로 데이터를 보낼 수 있고, Thanos Receive 복제본들은 서로를 원활하게 찾아 해시링을 구성할 수 있습니다.