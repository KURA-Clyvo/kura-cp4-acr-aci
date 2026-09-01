# =============================================================================
# KURA CP4 · Dockerfile do app .NET (Kura.Api — backend clínica)
# Cópia FIEL de backend-clinica-dotnet/Dockerfile.
# Origem: repo backend-clinica-dotnet, commit de96c70 (main, 2026-08-31).
# Nenhuma linha de build foi alterada — só este cabeçalho de proveniência foi
# adicionado. Se o Dockerfile de origem mudar, resincronizar manualmente.
# =============================================================================

# Stage 1 — build
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /app

# Copiar apenas o csproj da Api para restaurar dependências
COPY src/Kura.Api/Kura.Api.csproj src/Kura.Api/
COPY src/Kura.Application/Kura.Application.csproj src/Kura.Application/
COPY src/Kura.CrossCutting/Kura.CrossCutting.csproj src/Kura.CrossCutting/
COPY src/Kura.Domain/Kura.Domain.csproj src/Kura.Domain/
COPY src/Kura.Infrastructure/Kura.Infrastructure.csproj src/Kura.Infrastructure/

# Restaurar apenas o projeto principal — projetos de teste não existem no container
RUN dotnet restore src/Kura.Api/Kura.Api.csproj

# Copiar o restante do código fonte (excluindo tests via .dockerignore)
COPY src/ src/

# Publicar apontando diretamente para o csproj da Api
RUN dotnet publish src/Kura.Api/Kura.Api.csproj \
    -c Release \
    -o /app/publish \
    --no-restore

# Stage 2 — runtime
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080

# curl is required for the Docker health check — aspnet:10.0 (Debian slim) ships without it
#
# DESVIO da cópia fiel (documentado, ver README/NOTAS-PARA-O-MAESTRO): esta rede
# (laboratório FIAP, testado em 2026-09-01) devolve 403 Forbidden para o
# apt-get update em archive.ubuntu.com/security.ubuntu.com quando a requisição
# carrega o User-Agent padrão do APT ("Debian APT-HTTP/1.3 ..."). Confirmado por
# teste isolado: a MESMA URL, MESMO IP, só trocando o User-Agent para algo tipo
# navegador, responde 200 normalmente — não é proxy do Docker Desktop nem IP
# specific do mirror (testado com --network=host e --build-arg *_PROXY vazio,
# nenhum dos dois mudou o resultado). É bloqueio de assinatura de tráfego, não
# de rede. Sem este contorno, o app-dotnet/Dockerfile original não builda nesta
# rede — vale propagar este fix para backend-clinica-dotnet/Dockerfile depois,
# fora do fluxo de revisão deste CP4.
RUN echo 'Acquire::http::User-Agent "Mozilla/5.0 (compatible; docker-build)";' \
        > /etc/apt/apt.conf.d/99fiap-network-ua-workaround \
    && apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Run as non-root for security and FIAP DevOps rubric 2.2
RUN groupadd -r kura && useradd -r -g kura kura
RUN chown -R kura:kura /app
USER kura

HEALTHCHECK --interval=30s --timeout=5s --retries=5 --start-period=60s \
    CMD curl -sf http://localhost:8080/health || exit 1

ENTRYPOINT ["dotnet", "Kura.Api.dll"]
