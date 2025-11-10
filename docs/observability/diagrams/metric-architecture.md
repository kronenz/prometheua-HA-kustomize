``` mermaid
%% Metric 수집 아키텍처
%% Application에서 Grafana까지 메트릭 수집 흐름

graph TB
    subgraph "애플리케이션 계층"
        App[Application Pod<br/>포트: 9090/metrics]
        App2[Application Pod<br/>포트: 9090/metrics]
        App3[Application Pod<br/>포트: 9090/metrics]
    end

    subgraph "Service 계층"
        Svc[Service: myapp-metrics<br/>포트: 9090<br/>레이블: app=myapp, service-team=myteam]
    end

    subgraph "모니터링 설정 계층"
        SM[ServiceMonitor<br/>또는<br/>PodMonitor<br/><br/>selector: app=myapp<br/>endpoint: metrics:9090<br/>interval: 30s]
    end

    subgraph "Prometheus Operator 계층"
        PO[Prometheus Operator<br/><br/>1. ServiceMonitor 감지<br/>2. Prometheus Config 생성<br/>3. Scrape Target 등록]
    end

    subgraph "메트릭 수집 계층"
        Prom[Prometheus<br/><br/>- 30초마다 scrape<br/>- 로컬 TSDB 저장<br/>- 15일 retention]
    end

    subgraph "장기 보관 계층"
        Thanos[Thanos Sidecar<br/><br/>- Prometheus 메트릭 읽기<br/>- S3로 업로드<br/>- 무제한 보관]
        S3[(MinIO S3<br/><br/>장기 메트릭 저장소<br/>압축 + 다운샘플링)]
    end

    subgraph "쿼리 계층"
        TQ[Thanos Query<br/><br/>- Prometheus 쿼리 통합<br/>- S3 데이터 쿼리<br/>- 글로벌 뷰 제공]
    end

    subgraph "시각화 계층"
        Grafana[Grafana Dashboard<br/><br/>- PromQL 쿼리<br/>- 팀별 필터링<br/>- 알림 설정]
    end

    App --> Svc
    App2 --> Svc
    App3 --> Svc
    Svc -.-> SM
    SM --> PO
    PO --> Prom
    Prom -->|scrape /metrics| Svc
    Prom --> Thanos
    Thanos -->|upload| S3
    Prom --> TQ
    S3 --> TQ
    TQ --> Grafana

    %% 스타일 정의
    classDef appClass fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef svcClass fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef monClass fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef promClass fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef thanosClass fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    classDef vizClass fill:#fce4ec,stroke:#880e4f,stroke-width:2px

    class App,App2,App3 appClass
    class Svc svcClass
    class SM,PO monClass
    class Prom promClass
    class Thanos,TQ,S3 thanosClass
    class Grafana vizClass

    %% 주석
    note1[메트릭 수집 흐름<br/>1. App이 /metrics 엔드포인트 노출<br/>2. ServiceMonitor가 수집 대상 정의<br/>3. Prometheus Operator가 자동 설정<br/>4. Prometheus가 30초마다 수집<br/>5. Thanos가 S3에 장기 보관<br/>6. Grafana에서 시각화]
```