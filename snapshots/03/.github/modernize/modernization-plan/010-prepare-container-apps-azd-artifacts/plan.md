# Azure Containerization Plan for assets-manager (web + worker)

## **Goal**

Prepare Linux web/worker container (Dockerfile) and `azd` project (`azure.yaml`) artifacts so
both modules can be deployed to Azure Container Apps using the existing Bicep template from
task `007-prepare-bicep-and-db-init` (`infra/main.bicep`). Build images using the **local**
container engine only and run local smoke checks. Do **not** use remote build, ACR Tasks, or
`az acr build`; do **not** publish/push images, provision Azure resources, or run
`azd provision`/`azd deploy`. Assessment issues addressed: *No Dockerfile found*;
*Localhost Usage* (both modules already externalize all endpoints via environment variables —
see `web/src/main/resources/application.properties` and
`worker/src/main/resources/application.properties` — so no code change was required for that
finding; this task only adds the container artifacts).

## **List of services to be containerized**

- **web** (`java/web`) — Java 25 / Spring Boot 4.1.2 Maven module (`assets-manager-web`),
  entry point `com.microsoft.migration.assets.AssetsManagerApplication`. Serves the Thymeleaf
  UI and REST endpoints on port 8080 (Tomcat). Depends on Azure Service Bus (sender), Azure
  Blob Storage, and Azure Database for PostgreSQL Flexible Server — all via passwordless
  Azure Managed Identity. Part of a Maven **reactor** build (root `pom.xml` + `web` + `worker`).
- **worker** (`java/worker`) — Java 25 / Spring Boot 4.1.2 Maven module
  (`assets-manager-worker`), entry point `com.microsoft.migration.assets.worker.WorkerApplication`.
  Background Service Bus queue consumer (`image-processing`) that generates thumbnails; no HTTP
  listener/ingress. Same Azure dependencies and managed-identity authentication as `web`.
- **java/** (repo root) — root Maven reactor `pom.xml`, Maven wrapper (`mvnw`/`mvnw.cmd`/`.mvn`),
  and the new root `azure.yaml` azd project file. Required as the Docker **build context** for
  both Dockerfiles because this is a multi-module Maven reactor (the `web`/`worker` submodules
  cannot be built in isolation from their own directories).

## **Execution Steps**
> **Below are the steps for Copilot to follow; ask Copilot to update or execute this plan.**

Steps to containerize the project:
1. Check containerization pre-requisites:
    1. Confirmed Docker Desktop (`desktop-linux` context, Engine 29.9.3) is installed and running.
2. Scanned the repository using tool `appmod-analyze-repository`: monorepo with 2 Maven modules
   (`web`, `worker`), Java 25, Spring Boot, web exposes port 8080, worker exposes none.
3. Checked code is ready to run in a local container:
    1. Confirmed both modules already read all Azure endpoints/credentials from environment
       variables (`SERVICE_BUS_NAMESPACE`, `AZURE_STORAGE_BLOB_ENDPOINT`,
       `AZURE_STORAGE_CONTAINER_NAME`, `POSTGRESQL_SERVER`, `POSTGRESQL_DATABASE`,
       `POSTGRESQL_USERNAME`, `AZURE_MANAGED_IDENTITY_CLIENT_ID`) — no hardcoded `localhost` or
       other host literals in `application.properties` for either module (remediated in earlier
       migration tasks 003–006; this task does not change application source).
    2. Cloud dependencies the user must provision/approve separately before a real deployment:
       Azure Database for PostgreSQL Flexible Server, Azure Service Bus namespace/queue, Azure
       Blob Storage account/container, Azure Container Registry, and the Container Apps
       environment — all defined in `infra/main.bicep` (task 007) but **not provisioned** by
       this task.
4. Created a Dockerfile for each project using tool `appmod-plan-generate-dockerfile`
   (recommended base images: `mcr.microsoft.com/openjdk/jdk:25-azurelinux` for the Maven build
   stage, `mcr.microsoft.com/openjdk/jdk:25-distroless` for the runtime stage, non-root `app`
   user, multi-stage build):
    - `web/Dockerfile` — multi-stage: Maven reactor build (`./mvnw -pl web -am clean package
      -DskipTests`) then copies `assets-manager-web-*.jar` into the distroless runtime image.
      `EXPOSE 8080` (matches `infra/main.bicep` `webContainerApp` `targetPort = 8080`).
    - `worker/Dockerfile` — same pattern (`./mvnw -pl worker -am clean package -DskipTests`);
      no `EXPOSE` (matches `infra/main.bicep` `workerContainerApp` `enableIngress = false`).
    - Added root `.dockerignore` to exclude `target/`, VCS/IDE metadata, `.azure/`, `logs/`,
      `storage/`, `uploads/`, and other non-build-context files.
5. Built the Docker images for each project using tool `appmod-build-docker-image`, then
   `docker build` locally (build context = repo root `java/`, required by the reactor build):
    1. `docker build -f web/Dockerfile -t assets-manager-web:v1 -t assets-manager-web:latest
       --platform linux/amd64 .` → **succeeded**.
    2. `docker build -f worker/Dockerfile -t assets-manager-worker:v1 -t
       assets-manager-worker:latest --platform linux/amd64 .` → **succeeded**.
    3. Scanned both images using tool `appmod-scan-docker-image` (scanner `osv`, scanType
       `vulnerability`, severity `HIGH`) → **both passed, no significant vulnerabilities**.
    4. Tagged both images with `v1` (version) and `latest`, as above. No image was pushed to
       any registry (local Docker Desktop image store only).
6. Ran local smoke checks only (no remote/ACR build, no provisioning, no `azd` commands that
   touch Azure):
    1. `docker run --rm assets-manager-web:v1` with dummy, non-resolving Azure endpoint env vars
       → Spring Boot context started, Tomcat bound port 8080, Hibernate/HikariCP initialized,
       then failed (expected) trying to resolve the dummy PostgreSQL host — confirms the image,
       JAR packaging, and entrypoint are correct; only live Azure connectivity (intentionally not
       provisioned in this task) is missing.
    2. `docker run --rm assets-manager-worker:v1` with the same dummy env vars → Spring Boot
       context started identically (no HTTP listener, as expected for a Service Bus consumer).
    3. Created root `azure.yaml` (azd project: services `web`, `worker`, both `host:
       containerapp`, `docker.remoteBuild: false`, `infra.path: infra` / `infra.module: main`
       pointing at the existing task-007 Bicep). Validated it parses correctly with
       `azd show` — lists both services, reports *"You haven't created any environments"* and
       *"Application is not yet provisioned"* (confirms no environment/provisioning was created
       or touched by this task).
7. Summarized the containerization (see `summary.md`).

## Participant-only `azd` procedure (reference only — not executed by this task)

See the plan-level section **"별도 DB 초기화 및 참가자 azd 절차"** in
`.github/modernize/modernization-plan/plan.md` for the full, separately-approved participant
procedure (`azd auth login` → `azd env new` → review → `azd provision` → DB init → local image
build/review → `azd deploy`). The `azure.yaml` and Dockerfiles produced by this task are
consistent with and are the inputs to that procedure:
- `azd provision` will deploy `infra/main.bicep` (task 007), creating (among other resources)
  the Azure Container Registry and Container Apps environment/apps with placeholder images.
- `azd deploy` (separate approval) will then build these same Dockerfiles — by default via
  `azd`'s local Docker build (`remoteBuild: false`), **not** ACR Tasks/`az acr build` — push the
  resulting images to the provisioned ACR, and update the `web`/`worker` Container Apps to use
  them.
- No step in *this* task performed a provision, deploy, push, or remote build.
