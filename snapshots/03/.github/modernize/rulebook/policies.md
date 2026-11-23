# Policies

## Security Requirements

### Authentication & Authorization

- Modernized workloads must use managed identity and least-privilege access.
- The database principal and its permissions must be distinguished from ARM roles.
- The account that performs migration work must be specified separately.

### Secrets Management

- Secrets must not be stored in code, configuration, or Git.

### Network Security

- TLS must be used.
- Blob storage must not be made public.
- Indefinite SAS URLs must not be used to bypass private Blob storage.

## Guardrails (Hard Boundaries)

### Prohibited Technologies

| Technology | Reason | Approved Alternative |
|-----------|--------|---------------------|
| JDK 25 EA releases | EA releases are not approved. | Stable JDK 25 |
| AKS | Not approved for the final environment. | Linux Azure Container Apps |
| App Service | Not approved for the final environment. | Linux Azure Container Apps |
| Remote build | Remote builds are prohibited. | Local container engine build |
| ACR Tasks | Remote build tooling is prohibited. | Local container engine build |
| `az acr build` | Remote build tooling is prohibited. | Local container engine build |

### Prohibited Patterns

| Pattern | Reason | Approved Alternative |
|---------|--------|---------------------|
| Public Blob storage | Private Blob storage is required. | Private Blob storage |
| Indefinite SAS URL bypass | Private Blob storage must not be bypassed. | Private Blob storage |
| Storing secrets in code, configuration, or Git | Secrets must not be stored in these locations. | Managed identity and approved secret handling |
| Deleting or skipping tests and reporting success | Test failures and skipped work must remain visible. | Execute and report tests, including tests not run |

### Required Elements

Every modernized application must include:

- JDK selection by `use-java.ps1 -Jdk 8` or `-Jdk 25` on Windows PowerShell 7, or `use-java.sh --jdk 8` or `--jdk 25` on macOS/Linux before migration work.
- Maven Wrapper use in the same shell after JDK selection.
- Baseline test, upgrade, Azure code, and azd artifact work in sequence within one plan.
- Files to change, rationale for version choices, validation commands, and stop and recovery criteria in the plan.
- Preserved duplicate message reception, retry, dead-letter, and shutdown behavior.
- Execution of Azure resource creation, database changes, data migration, image publication, deployment, and deletion only after separate participant approval.
- Separate approval for S3 data migration and AWS access.
- Separate approval for installation and external service use.

## Validation & Quality Gates

- Record the Java version, exit code, and actual test count for Maven Wrapper execution.
- Record actual execution results separately from integration tests that were not executed.
- Do not treat deleted or skipped tests as successful tests.
- Test both `JDK 8` selection and `JDK 25` selection using the supplied shell scripts when applicable.
