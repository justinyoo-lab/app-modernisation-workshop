# Targets

## Target Frameworks

| Language | Target Version | Notes |
|----------|---------------|-------|
| Java | JDK 25 | JDK 8 is the source version. Stable releases only; EA versions are prohibited. |
| Java | Spring Boot 4.1.2 | Baseline; verify compatibility and support conditions with JDK 25 and libraries. A different stable version requires rationale and change approval. |

## Target Compute Services

| Platform | Use When |
|----------|----------|
| Linux Azure Container Apps | Final environment |

## Target Data Services

| Service | Use When |
|---------|----------|
| Azure Database for PostgreSQL Flexible Server | Migrating PostgreSQL |
| Private Blob storage | Migrating local files and S3 data |

## Target Integration Services

| Service | Use When |
|---------|----------|
| Azure Service Bus | Migrating RabbitMQ |

## Target Libraries

| Category | Source | Target | Notes |
|----------|--------|--------|-------|
| Java runtime | JDK 8 | JDK 25 | Use stable JDK 25 only. |

## Target Artifacts

| Artifact | Location | Notes |
|----------|----------|-------|
| azd artifacts | Plan and Azure deployment project | Use azd and Bicep. |
| Container application artifacts | Local container engine | Use the local container engine for builds; remote builds are prohibited. |
