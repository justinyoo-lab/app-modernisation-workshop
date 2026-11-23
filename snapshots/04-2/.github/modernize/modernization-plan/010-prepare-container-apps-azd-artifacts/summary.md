# Summary: 010-prepare-container-apps-azd-artifacts

## Status: ✅ Success (local-only)

## Files created/modified
- `web/Dockerfile` — multi-stage build (Maven reactor build on
  `mcr.microsoft.com/openjdk/jdk:25-azurelinux`, runtime on
  `mcr.microsoft.com/openjdk/jdk:25-distroless`, non-root `app` user), `EXPOSE 8080`.
- `worker/Dockerfile` — same pattern, no `EXPOSE` (background Service Bus consumer, no ingress).
- `.dockerignore` (repo root) — excludes `target/`, VCS/IDE metadata, `.azure/`, `logs/`,
  `storage/`, `uploads/`.
- `azure.yaml` (repo root) — azd project definition: `web` and `worker` services, both
  `host: containerapp`, `docker.remoteBuild: false`, `infra.path: infra` / `infra.module: main`
  (reuses the existing Bicep from task `007-prepare-bicep-and-db-init`).

## Why the build context is the repo root
`web` and `worker` are modules of a single Maven **reactor** (root `pom.xml`). Building either
module requires the root `pom.xml`, the Maven wrapper (`mvnw`, `mvnw.cmd`, `.mvn/`), and both
modules' `pom.xml`/`src` to resolve inter-module dependencies, so both Dockerfiles are written
to be built with `java/` (the repo root) as the Docker build context, e.g.:
```
docker build -f web/Dockerfile    -t assets-manager-web:v1    .
docker build -f worker/Dockerfile -t assets-manager-worker:v1 .
```

## Local build results
| Image | Result | Final size (runtime layer) |
|---|---|---|
| `assets-manager-web:v1` / `:latest` | ✅ Built successfully | ~282 MB |
| `assets-manager-worker:v1` / `:latest` | ✅ Built successfully | ~275 MB |

No image was pushed/published to any registry; no remote build, ACR Tasks, or `az acr build`
was used — both builds ran against the local Docker Desktop engine (`desktop-linux` context).

## Vulnerability scans (`appmod-scan-docker-image`, scanner `osv`, severity `HIGH`)
| Image | Result |
|---|---|
| `assets-manager-web:v1` | ✅ Passed — no significant vulnerabilities |
| `assets-manager-worker:v1` | ✅ Passed — no significant vulnerabilities |

## Local smoke checks
- `docker run --rm assets-manager-web:v1` (dummy, non-resolving Azure env vars): Spring Boot
  context started, Tomcat bound port 8080, Hibernate/HikariCP initialized, then failed as
  expected trying to resolve the dummy PostgreSQL hostname — confirms the JAR, entrypoint, and
  runtime image are correctly packaged.
- `docker run --rm assets-manager-worker:v1` (same dummy env vars): Spring Boot context started
  identically (no HTTP listener, as expected).
- `azd show` (no environment created): correctly lists both `web` and `worker` services from
  the new `azure.yaml`, and reports no environment exists and the application is not yet
  provisioned — confirms the azd project file parses correctly without provisioning anything.

## Explicitly NOT done in this task (by design)
- No `az acr build` / ACR Tasks / remote build of any kind.
- No `docker push` / image publish to any registry.
- No `azd env new`, `azd provision`, or `azd deploy`.
- No Azure resources created, modified, or deleted.
- No application source code changes (the "Localhost Usage" finding was already remediated in
  earlier migration tasks; both modules read all endpoints from environment variables).

## Participant-only `azd` procedure
Already documented in `.github/modernize/modernization-plan/plan.md` under
**"별도 DB 초기화 및 참가자 azd 절차"** (not duplicated here). The `azure.yaml` and Dockerfiles
produced by this task are the artifacts that procedure's `azd provision` / `azd deploy` steps
will consume.
