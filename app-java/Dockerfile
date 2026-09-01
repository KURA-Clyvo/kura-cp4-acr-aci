# =============================================================================
# KURA CP4 · Dockerfile do app Java (kura-backend-tutor) — 3º ACI OPCIONAL
# Cópia FIEL de backend-tutor-java/Dockerfile.
# Origem: repo backend-tutor-java, commit 2d3ffc5 (main, 2026-09-01).
# Nenhuma linha de build foi alterada — só este cabeçalho de proveniência foi
# adicionado. Se o Dockerfile de origem mudar, resincronizar manualmente.
#
# Este Dockerfile só é usado se o 3º ACI opcional (bônus, fora da rubrica do
# CP4) for construído — ver azure/aci-java-api.yaml e o aviso em deploy.sh.
# =============================================================================

# ─── Stage 1: Builder ─────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build

# Cache Maven dependencies as a separate layer.
# This layer is only invalidated when pom.xml changes, not when source changes.
COPY pom.xml .
RUN mvn dependency:go-offline -q

COPY src ./src

# Normalize CRLF and strip UTF-8 BOM — both added by Windows editors, both fatal to javac on Linux.
RUN apt-get update && apt-get install -y --no-install-recommends dos2unix \
    && find ./src -name "*.java" -type f -exec dos2unix {} + \
    && find ./src -name "*.java" -type f -exec sed -i 's/\xEF\xBB\xBF//g' {} + \
    && find ./src -name "*.java" -type f -exec sed -i 's/\xef\xbb\xbf//g' {} + \
    && rm -rf /var/lib/apt/lists/*

RUN mvn package -DskipTests -q

# ─── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy AS runtime

# curl is required by HEALTHCHECK
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user: spring uid=1000 gid=1000
RUN groupadd --gid 1000 spring \
    && useradd --uid 1000 --gid spring --shell /bin/bash --create-home spring

WORKDIR /app

# --chown avoids a separate RUN chown layer
COPY --chown=spring:spring --from=builder \
    /build/target/kura-backend-tutor-*.jar app.jar

USER spring

EXPOSE 8081

# start-period gives Spring Boot time to establish the Oracle FIAP connection
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:8081/api/actuator/health || exit 1

ENTRYPOINT ["java", \
    "-XX:MaxRAMPercentage=75.0", \
    "-XX:+UseG1GC", \
    "-jar", "app.jar"]
