# Architecture Diagram

This Java application is a multi-module assets manager that provides a Spring MVC web interface and an asynchronous worker for generating image thumbnails. It supports AWS S3 or local filesystem storage through profile-specific implementations.

## Application Architecture

```mermaid
flowchart TD
    subgraph Client["Client Layer"]
        Browser["Web Browser"]
        Thymeleaf["Thymeleaf Templates"]
    end

    subgraph Web["Web Module - Spring Boot 2.7.18"]
        MVC["Spring MVC Controllers"]
        Storage["StorageService Abstraction"]
        S3Service["AWS S3 Storage Service"]
        LocalService["Local File Storage Service"]
        JPA["Spring Data JPA"]
        Backup["Backup Message Monitor"]
    end

    subgraph Worker["Worker Module - Spring Boot 2.7.18"]
        Listener["RabbitMQ Image Listener"]
        Processor["Thumbnail Processing Service"]
        S3Processor["S3 Processing Implementation"]
        LocalProcessor["Local Processing Implementation"]
    end

    subgraph Messaging["Messaging"]
        Rabbit[("RabbitMQ image-processing queue")]
    end

    subgraph Data["Data and Storage"]
        PostgreSQL[("PostgreSQL 14 or compatible")]
        S3[("AWS S3 Bucket")]
        Files[("Local Storage Directory")]
    end

    Browser -->|"HTTP requests"| MVC
    MVC -->|"renders views"| Thymeleaf
    MVC -->|"storage operations"| Storage
    Storage -->|"production profile"| S3Service
    Storage -->|"development profile"| LocalService
    S3Service -->|"object CRUD"| S3
    S3Service -->|"publish processing message"| Rabbit
    S3Service -->|"metadata CRUD"| JPA
    LocalService -->|"file CRUD"| Files
    LocalService -->|"publish processing message"| Rabbit
    JPA -->|"SQL queries"| PostgreSQL
    Rabbit -->|"deliver image message"| Listener
    Listener --> Processor
    Processor -->|"S3 storage type"| S3Processor
    Processor -->|"local storage type"| LocalProcessor
    S3Processor -->|"download and upload images"| S3
    S3Processor -->|"update metadata"| JPA
    LocalProcessor -->|"read and write files"| Files
    Rabbit -.->|"backup profile monitoring"| Backup
```

### Technology Stack Summary

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| Parent build | Maven | 4.0.0 model | Builds the web and worker modules |
| Runtime | Java | 8 | Application language and runtime |
| Application framework | Spring Boot | 2.7.18 | Web, messaging, worker, and configuration support |
| Presentation | Spring MVC and Thymeleaf | Managed by Spring Boot | Server-side pages and asset views |
| Data access | Spring Data JPA and Hibernate | Managed by Spring Boot | Image metadata persistence |
| Database | PostgreSQL JDBC | PostgreSQL driver | Stores image metadata |
| Messaging | Spring AMQP and RabbitMQ | Spring Boot managed | Distributes thumbnail jobs |
| Object storage | AWS SDK for Java | 2.25.13 | S3 object operations |
| Image processing | Java Image I/O | JDK 8 | Thumbnail scaling and sharpening |

### Data Storage & External Services

PostgreSQL stores image metadata such as filename, content type, size, S3 key, and thumbnail key. AWS S3 is the production object store, while the dev profile uses a local filesystem directory. RabbitMQ provides the image-processing queue that decouples uploads from thumbnail generation.

### Key Architectural Decisions

- Uses the StorageService interface with S3 and local filesystem implementations selected by Spring profiles.
- Uses RabbitMQ and manual acknowledgments to decouple web uploads from asynchronous thumbnail processing.
- Uses Spring Data JPA repositories for metadata while object data remains in S3 or the local filesystem.

## Component Relationships

```mermaid
flowchart LR
    subgraph Presentation["Presentation"]
        Home["HomeController"]
        S3Ctrl["S3Controller"]
        Templates["Thymeleaf Templates"]
    end

    subgraph WebBusiness["Web Business Logic"]
        StorageAPI["StorageService"]
        AwsStore["AwsS3Service"]
        LocalStore["LocalFileStorageService"]
        Backup["BackupMessageProcessor"]
    end

    subgraph WorkerBusiness["Worker Business Logic"]
        FileProcessor["AbstractFileProcessingService"]
        S3Worker["S3FileProcessingService"]
        LocalWorker["LocalFileProcessingService"]
    end

    subgraph DataAccess["Data Access"]
        WebRepo["Web ImageMetadataRepository"]
        WorkerRepo["Worker ImageMetadataRepository"]
    end

    subgraph Infrastructure["Infrastructure"]
        Rabbit["RabbitConfig"]
        S3Config["AwsS3Config"]
        Queue[("image-processing queue")]
    end

    Home -->|"redirect"| S3Ctrl
    S3Ctrl -->|"delegates storage operations"| StorageAPI
    S3Ctrl -->|"model and redirect attributes"| Templates
    StorageAPI -->|"production implementation"| AwsStore
    StorageAPI -->|"development implementation"| LocalStore
    AwsStore -->|"publishes"| Queue
    LocalStore -->|"publishes"| Queue
    AwsStore -->|"metadata operations"| WebRepo
    S3Ctrl -.->|"cross-module HTTP view"| Templates
    Queue -->|"manual acknowledgment listener"| FileProcessor
    FileProcessor -->|"S3 storage type"| S3Worker
    FileProcessor -->|"local storage type"| LocalWorker
    S3Worker -->|"thumbnail metadata"| WorkerRepo
    Rabbit -->|"configures listener and converter"| FileProcessor
    S3Config -->|"provides S3 client"| AwsStore
    S3Config -->|"provides S3 client"| S3Worker
    Queue -.->|"backup profile listener"| Backup
```

### Component Inventory

| Component | Layer | Type | Responsibility |
|---|---|---|---|
| HomeController | Presentation | MVC Controller | Redirects the application root to the storage page |
| S3Controller | Presentation | MVC Controller | Lists, uploads, views, and deletes stored objects |
| Thymeleaf Templates | Presentation | View | Renders list, upload, and view pages |
| StorageService | Web Business Logic | Service interface | Defines provider-neutral storage operations |
| AwsS3Service | Web Business Logic | Storage service | Implements S3 upload, download, listing, deletion, and metadata updates |
| LocalFileStorageService | Web Business Logic | Storage service | Implements storage operations against the local filesystem |
| BackupMessageProcessor | Web Business Logic | Rabbit listener | Optionally monitors and acknowledges processing messages |
| AbstractFileProcessingService | Worker Business Logic | Listener and processor base | Receives jobs, creates thumbnails, and handles acknowledgments |
| S3FileProcessingService | Worker Business Logic | Storage processor | Downloads originals and uploads thumbnails in S3 |
| LocalFileProcessingService | Worker Business Logic | Storage processor | Reads originals and writes thumbnails locally |
| Web ImageMetadataRepository | Data Access | JPA Repository | Persists and retrieves web-module image metadata |
| Worker ImageMetadataRepository | Data Access | JPA Repository | Updates thumbnail metadata in the worker module |
| RabbitConfig | Infrastructure | Spring configuration | Declares the durable queue and JSON manual-ack listener |
| AwsS3Config | Infrastructure | Spring configuration | Builds the AWS S3 client from application settings |
| image-processing queue | Infrastructure | RabbitMQ Queue | Carries image processing messages from web module to worker |
