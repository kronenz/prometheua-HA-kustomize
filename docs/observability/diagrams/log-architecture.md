``` mermaid
%% Log 수집 아키텍처
%% Application에서 Grafana까지 로그 수집 흐름

graph TB
    subgraph "애플리케이션 계층"
        App1[Application Pod<br/>JSON 로그 출력<br/>stdout/stderr]
        App2[Application Pod<br/>JSON 로그 출력<br/>stdout/stderr]
        App3[Application Pod<br/>JSON 로그 출력<br/>stdout/stderr]
    end

    subgraph "컨테이너 런타임 계층"
        CRI1[Container Runtime<br/>/var/log/containers/*.log<br/>레이블: app, service-team, namespace]
        CRI2[Container Runtime<br/>/var/log/containers/*.log<br/>레이블: app, service-team, namespace]
        CRI3[Container Runtime<br/>/var/log/containers/*.log<br/>레이블: app, service-team, namespace]
    end

    subgraph "로그 수집 계층"
        FB1[Fluent-Bit DaemonSet<br/><br/>1. tail 방식으로 로그 읽기<br/>2. Kubernetes 메타데이터 추가<br/>3. Multiline 파싱]
        FB2[Fluent-Bit DaemonSet<br/><br/>1. tail 방식으로 로그 읽기<br/>2. Kubernetes 메타데이터 추가<br/>3. Multiline 파싱]
        FB3[Fluent-Bit DaemonSet<br/><br/>1. tail 방식으로 로그 읽기<br/>2. Kubernetes 메타데이터 추가<br/>3. Multiline 파싱]
    end

    subgraph "로그 전처리 계층"
        Lua[Lua Filter<br/><br/>- JSON 파싱<br/>- 필드 추출/변환<br/>- 불필요한 필드 제거<br/>- 로그 레벨 정규화]
    end

    subgraph "로그 저장 계층"
        OS[OpenSearch Cluster<br/><br/>Index Pattern:<br/>logs-app-YYYY.MM.DD<br/><br/>필터링: app, service-team, level]
    end

    subgraph "로그 검색 계층"
        OSQuery[OpenSearch Query API<br/><br/>- 전체 텍스트 검색<br/>- 필드 필터링<br/>- 집계/분석]
    end

    subgraph "시각화 계층"
        Grafana[Grafana Dashboard<br/><br/>- 로그 검색/필터링<br/>- 실시간 로그 스트리밍<br/>- 알림 설정]
    end

    subgraph "백업 계층"
        S3[(MinIO S3<br/><br/>로그 아카이브<br/>장기 보관<br/>선택적)]
    end

    App1 -->|stdout/stderr| CRI1
    App2 -->|stdout/stderr| CRI2
    App3 -->|stdout/stderr| CRI3

    CRI1 -->|tail| FB1
    CRI2 -->|tail| FB2
    CRI3 -->|tail| FB3

    FB1 --> Lua
    FB2 --> Lua
    FB3 --> Lua

    Lua -->|HTTP/HTTPS| OS
    OS --> OSQuery
    OSQuery --> Grafana
    OS -.->|선택적 아카이브| S3

    %% 스타일 정의
    classDef appClass fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef criClass fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef fbClass fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef luaClass fill:#ede7f6,stroke:#311b92,stroke-width:2px
    classDef osClass fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px
    classDef vizClass fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    classDef s3Class fill:#fff9c4,stroke:#f57f17,stroke-width:2px

    class App1,App2,App3 appClass
    class CRI1,CRI2,CRI3 criClass
    class FB1,FB2,FB3 fbClass
    class Lua luaClass
    class OS,OSQuery osClass
    class Grafana vizClass
    class S3 s3Class

    %% 주석
    note1[로그 수집 흐름<br/>1. App이 JSON 형식으로 stdout 출력<br/>2. Container Runtime이 파일로 저장<br/>3. Fluent-Bit이 tail로 실시간 수집<br/>4. Lua Filter로 전처리<br/>5. OpenSearch에 인덱싱<br/>6. Grafana에서 검색/시각화]

    %% Multiline 처리 설명
    note2[Multiline 로그 처리<br/>Java Exception, Python Traceback 등<br/>여러 줄에 걸친 로그를<br/>하나의 이벤트로 병합]
```