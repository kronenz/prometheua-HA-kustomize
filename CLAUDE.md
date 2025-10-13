192.168.101.196, 192.168.101.197, 192.168.101.198 노드에 접속하기 위한 정보는 bsh / 123qwe 이다. 해당 노드 각각에 1. 미니쿠베를 설치하고 2. 스토리지 클래스로 롱혼을 구성 . 3. nginx ingress구성 
4. 그리고 kube-prometheus-stack 타노스 멀티클러스터 구성 5. opensearch + fluent-bit구성 을 통해 minio s3 저장소를 사용하여 데이터를 저장하고 관리하게 할것이다. 타노스 멀티클러스터 구성시 196번 노드가 중앙 클러스터가 될것이고 나머지 노드에 분산클러스터 구성을 하면된다. 위 구성에 대해
kutomizaion.yaml + helm chart 구성을 통해 각각 멀티클러스터에 배포하고자 한다. helm install 금지
kustomize build . --enable-helm | kubectl -f - -n monitor 와 같은 명령어로만 배포 
궁극적인 목적은 프로메세우스의 단일 구성의 한계를 극복하기 위한 타노스 추가 구성을 하기 위함이고 최대한 artifacthub의 kube-prometheus-stack , opensearch , fluent-bit , fluent-d 구성을 values.yaml 로 수정하여 통합 관리 할 수 있게 하고 불가피한경구 리소스를 kustomization.yaml file에 구성한다.
1. 아키텍처가 명확해야하고 , 2. 부하분산이 적절해야하여 , 로컬 스토리지를 사용하지 않아야 한다. (모두 s3 에서 관리 ) , 가이드 문서가 명확하게 작성되어야 한다. (한글 상세, mermaid), s3 저장소는 별도 구축 예정이므로 변수처리