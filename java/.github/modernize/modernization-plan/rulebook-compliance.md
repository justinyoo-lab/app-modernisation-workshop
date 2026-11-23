## Rulebook Compliance

| Rulebook | Rule | Status | Task |
|----------|------|--------|------|
| charter.md | Java 8 source upgraded to JDK 25 | ✅ COVERED | 001, 002 |
| charter.md | Include web/worker, current screens and workflows; avoid unnecessary frontend rewrites | ✅ COVERED | 001, 003–006, 010 |
| charter.md | Follow approved scope; installation, external services, S3/AWS, resource/DB/data changes, publication, deployment and deletion need separate approval or are excluded | ✅ COVERED | 006–010 |
| charter.md | Refactor Java workloads for Linux Azure Container Apps | ✅ COVERED | 007, 010 |
| charter.md | Use stable JDK 25; prohibit EA builds | ✅ COVERED | 002 |
| charter.md | Use Spring Boot 4.1.2 baseline; verify JDK 25 and library compatibility; approve any alternative | ✅ COVERED | 002 |
| charter.md | Do not assume paid support or private repositories | ✅ COVERED | 002 |
| charter.md | Preserve screens, uploads, retrieval, asynchronous thumbnails and distinct dev/non-dev metadata behavior | ✅ COVERED | 001, 005, 006, 008 |
| charter.md | Provide a separate Azure DB target for non-dev/S3-path metadata recording and retrieval | ✅ COVERED | 003, 006 |
| policies.md | Use managed identity and least privilege | ✅ COVERED | 003–007 |
| policies.md | Separate database principal/grants from ARM roles | ✅ COVERED | 003, 007 |
| policies.md | Identify the migration operator separately from workload identity | ✅ COVERED | 003, 007 |
| policies.md | Do not store secrets in code, configuration or Git | ✅ COVERED | 003–007, 010 |
| policies.md | Use TLS | ✅ COVERED | 003, 004, 007 |
| policies.md | Keep Blob storage private | ✅ COVERED | 005–007 |
| policies.md | Do not use indefinite SAS URLs | ✅ COVERED | 005, 006 |
| policies.md | Do not target prohibited AKS or App Service services | ✅ COVERED | 007, 010 |
| policies.md | Do not use remote build, ACR Tasks or `az acr build` | ✅ COVERED | 010 |
| policies.md | Prohibit public Blob storage | ✅ COVERED | 005–007 |
| policies.md | Prohibit indefinite SAS bypass | ✅ COVERED | 005, 006 |
| policies.md | Prohibit secrets in source/configuration/Git | ✅ COVERED | 003–007, 010 |
| policies.md | Do not delete/skip tests or report skipped work as success | ✅ COVERED | 001, 002, 008, 009 |
| policies.md | Select JDK 8/25 with the supplied PowerShell/Bash scripts | ✅ COVERED | 001, 002 |
| policies.md | Use Maven Wrapper in the selected-JDK shell | ✅ COVERED | 001, 002 |
| policies.md | Order baseline, upgrade, Azure code and azd work in one gated plan | ✅ COVERED | 001–010 |
| policies.md | State file scope, version rationale, validation commands, stop and recovery criteria | ✅ COVERED | plan.md; 001, 002, 007–010 |
| policies.md | Preserve duplicate delivery, retry, dead-letter and shutdown behavior | ✅ COVERED | 004, 008 |
| policies.md | Keep resource creation, DB changes/data migration, image publication, deployment and deletion out of plan execution pending approval | ✅ COVERED | 006–010 |
| policies.md | Require separate approval for S3 migration and AWS access | ✅ COVERED | 006 |
| policies.md | Require separate approval for installation and external service use | ✅ COVERED | plan.md; 003–010 |
| policies.md | Record Java version, exit code and actual Maven test count | ✅ COVERED | 001, 002, 008–010 |
| policies.md | Distinguish executed results from integration checks not run | ✅ COVERED | 008 |
| policies.md | Keep skipped/deleted tests visible and never count them as passing | ✅ COVERED | 001, 002, 009 |
| policies.md | Validate both JDK selections with the supplied scripts | ✅ COVERED | plan.md; 001, 002 |
| targets.md | Target stable JDK 25 | ✅ COVERED | 002 |
| targets.md | Use Spring Boot 4.1.2 baseline and verify compatibility/support | ✅ COVERED | 002 |
| targets.md | Target Linux Azure Container Apps | ✅ COVERED | 007, 010 |
| targets.md | Migrate PostgreSQL to Azure Database for PostgreSQL Flexible Server | ✅ COVERED | 003, 007 |
| targets.md | Migrate local files and S3 to private Blob storage | ✅ COVERED | 005–007 |
| targets.md | Migrate RabbitMQ to Azure Service Bus | ✅ COVERED | 004, 007 |
| targets.md | Use JDK 25 for Java runtime | ✅ COVERED | 002, 010 |
| targets.md | Prepare azd artifacts and Bicep | ✅ COVERED | 007, 010 |
| targets.md | Build container images with a local engine | ✅ COVERED | 010 |

**COVERED: 43/43  ·  VIOLATED: 0/43  ·  NOT COVERED: 0/43**
