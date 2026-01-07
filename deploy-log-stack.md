현재 로컬에 구성된 쿠버네티스와 사용가능한 자원량을 고려하여 최소 자워 사용으로 
opensearch와 fluent-bit operator  helm values.yaml 구성을 사용하여 kustomize로 배포관리 구성을 하고 opensearch , fluent-bit 에 application pod의 custom log를( log4j사용 ) hostpath로 /var/log/{namespace}/<app>-<servicename>-<logname>-YYYY-MM-dd.log 와 같은 형식으로 작성하게 하여 fluent-bit가 수집하여 opensearch에 수집할 수 있게 하는 파이프라인을 clusterinput , clusteroutput , clusterfilter , clusterparser와 같은 crd yaml을 별도로 정의하여 배포 관리하는 구성으로 배포 하고 
application 도 별도로 작성하여 배포하고 로그가 수집되어 opensearch로 조회할 수 있게 하는 
구성에 대해 설계하고 수행하여 결과를 확인할 수 있게 해줘