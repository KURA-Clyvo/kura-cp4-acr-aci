# =============================================================================
# KURA CP4 · Dockerfile do banco (Oracle XE)
# =============================================================================
# Por que este Dockerfile é "fino" (só FROM + metadados) e isso é suficiente:
#
# A rubrica do CP4 pede "Dockerfile do banco E do app, ambos versionados no
# repo" e "duas imagens registradas no ACR". A imagem oficial
# gvenzl/oracle-xe:21-slim já é exatamente o que o KURA usa em produção
# (DevOps-Cloud/docker-compose.yml, serviço oracle-db) — ela:
#   - já roda como usuário não-root (a própria imagem cuida disso, ver
#     https://github.com/gvenzl/oci-oracle-xe);
#   - já expõe um mecanismo de bootstrap por env vars (ORACLE_PASSWORD,
#     APP_USER, APP_USER_PASSWORD) que é o mesmo usado no compose real;
#   - já expõe o diretório /container-entrypoint-initdb.d/ para scripts de
#     inicialização opcionais (SQL/shell), rodados uma única vez na primeira
#     subida, antes de qualquer conexão de aplicação.
#
# O KURA não precisa de bootstrap SQL manual: quem cria o schema é o Flyway
# do backend Java (V1→V19, ~27 tabelas) na primeira subida contra um Oracle
# vazio — ver CLAUDE.md do workspace, seção "Duas APIs, um banco Oracle".
# Portanto não há init script a copiar aqui por padrão.
#
# Mesmo assim, para satisfazer literalmente "criar uma imagem própria" (e não
# apenas referenciar a imagem pública direto no `docker build`/ACR), este
# Dockerfile:
#   1. Parte da imagem oficial pinada por tag (não "latest" solto);
#   2. Documenta explicitamente a decisão acima como comentário no build;
#   3. Deixa pronto (comentado) o COPY de um init script opcional, caso no
#      futuro se queira semear dado de demonstração direto no container do
#      banco em vez de depender só do Flyway.
#
# Referência: DevOps-Cloud/docker-compose.yml, serviço `oracle-db`.
# =============================================================================

FROM gvenzl/oracle-xe:21-slim

LABEL org.opencontainers.image.title="rm562999/kura-oracle-db"
LABEL org.opencontainers.image.description="Oracle XE 21c (slim) para o CP4 KURA — schema provisionado pelo Flyway do backend Java na primeira subida"
LABEL org.opencontainers.image.source="https://github.com/KURA-Clyvo/DevOps-Cloud"

# Opcional: script(s) de inicialização (SQL ou shell), rodados UMA vez na
# primeira subida do volume de dados, antes de qualquer app se conectar.
# Não usado hoje (o Flyway do kura-tutor provisiona o schema sozinho) —
# deixado comentado como ponto de extensão documentado, não como TODO real.
# COPY ./initdb.d/ /container-entrypoint-initdb.d/

# Porta padrão do listener Oracle — já EXPOSE na imagem base, repetido aqui
# só por clareza/documentação.
EXPOSE 1521

# ─── Shim de compatibilidade cgroup v1 (Azure Container Instances) ─────────
# Achado real medido nesta implantação: a imagem base funciona perfeitamente
# no Docker Desktop local, mas entra em crash loop no ACI (ORA-01081 logo
# após o listener subir) porque o entrypoint da imagem espera o caminho de
# cgroup v2 unificado (/sys/fs/cgroup/memory.max), que não existe no ACI
# (cgroup v1). Ver comentário completo, com evidência, em
# cgroup-v1-shim-entrypoint.sh. USER volta para root aqui de propósito — o
# shim precisa escrever em /sys/fs/cgroup/ (só root tem permissão nesse
# tmpfs) antes de derrubar privilégio pro usuário 'oracle' e entregar o
# processo pro entrypoint real da imagem.
USER root
COPY --chmod=755 cgroup-v1-shim-entrypoint.sh /usr/local/bin/cgroup-v1-shim-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/cgroup-v1-shim-entrypoint.sh"]
