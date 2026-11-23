# syntax=docker/dockerfile:1
# Build context MUST be the repository root (java/), not web/, because this is a
# multi-module Maven reactor build (root pom.xml + web + worker submodules).
# Example: docker build -f web/Dockerfile -t assets-manager-web:v1 .

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
RUN ./mvnw -q -pl web -am dependency:go-offline

# Now copy sources and build only the web module and its reactor dependencies.
COPY web/src web/src
COPY worker/src worker/src
RUN ./mvnw -q -pl web -am clean package -DskipTests

############################
# Stage 2: runtime (distroless, non-root)
############################
FROM mcr.microsoft.com/openjdk/jdk:25-distroless
WORKDIR /app

# Base image ships a non-root "app" user.
USER app

COPY --from=build --chown=app:app /workspace/web/target/assets-manager-web-*.jar /app/app.jar

# Matches Container Apps ingress targetPort (infra/main.bicep: webContainerApp targetPort = 8080).
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
