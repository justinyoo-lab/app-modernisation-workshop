# Charter

## Metadata

| Field | Value |
|-------|-------|
| Rulebook Name | Java ACA 워크숍 현대화 기준 |

## Scope

### Covered Applications and Languages

Java applications are in scope. Java 8 applications are to be upgraded to JDK 25.

### Application Types

**Included:**

- web and worker workloads
- existing screens
- upload and file retrieval workflows
- asynchronous thumbnail workflows

**Excluded:**

- unnecessary frontend rewrites

### Constraints

- The approved plan scope must be followed.
- Installation and external service use require separate approval.
- S3 data migration and AWS access require separate approval.
- Azure resource creation, database changes, data migration, image publication, deployment, and deletion are excluded from plan execution and require participant approval before direct execution.

## Modernization Strategy (6R Guidelines)

| Application Type | Default Strategy | Override Conditions |
|------------------|-----------------|---------------------|
| Java application migrated to Linux Azure Container Apps | Refactor | A different stable Spring Boot version requires a rationale and change approval. |

## Principles

- JDK 25 EA versions must not be used.
- Spring Boot 4.1.2 is the baseline; JDK 25 and library compatibility and support conditions must be verified.
- Paid support or repositories must not be assumed.
- web and worker, existing screens, upload, file retrieval, and asynchronous thumbnail behavior must be maintained.
- DB behavior for S3 processing must preserve separation from dev-profile upload behavior.
- A separate migration target is required for DB recording and retrieval in S3 processing paths that do not use the dev profile.
