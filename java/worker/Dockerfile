# syntax=docker/dockerfile:1
# Build context MUST be the repository root (java/), not worker/, because this is a
# multi-module Maven reactor build (root pom.xml + web + worker submodules).
# Example: docker build -f worker/Dockerfile -t assets-manager-worker:v1 .

############################
# Stage 1: build (Maven reactor)
############################
FROM mcr.microsoft.com/openjdk/jdk:25-azurelinux AS build
WORKDIR /workspace

# Install tar, required by the Maven wrapper download/unpack on this base image.
RUN tdnf install -y tar gzip && tdnf clean all

# Copy the Maven wrapper and reactor POMs first to maximize Docker layer caching
# for dependency resolution across rebuilds.
COPY mvnw mvnw.cmd ./
COPY .mvn .mvn
COPY pom.xml ./
COPY web/pom.xml web/pom.xml
COPY worker/pom.xml worker/pom.xml
RUN chmod +x mvnw

# Pre-fetch dependencies for both modules (best-effort; offline flag not required).
RUN ./mvnw -q -pl worker -am dependency:go-offline

# Now copy sources and build only the worker module and its reactor dependencies.
COPY web/src web/src
COPY worker/src worker/src
RUN ./mvnw -q -pl worker -am clean package -DskipTests

############################
# Stage 2: runtime (distroless, non-root)
############################
FROM mcr.microsoft.com/openjdk/jdk:25-distroless
WORKDIR /app

# Base image ships a non-root "app" user.
USER app

COPY --from=build --chown=app:app /workspace/worker/target/assets-manager-worker-*.jar /app/app.jar

# The worker has no HTTP listener; it only consumes Service Bus messages (infra/main.bicep:
# workerContainerApp enableIngress = false), so no EXPOSE/targetPort is declared.

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
