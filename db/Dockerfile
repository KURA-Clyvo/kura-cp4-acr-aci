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

# ─── Por que NAO existe mais um "shim de cgroup v1" aqui ───────────────────
# A sessao 1 adicionou um ENTRYPOINT proprio (cgroup-v1-shim-entrypoint.sh)
# partindo da hipotese de que o entrypoint da imagem base so sabia ler o
# caminho de cgroup v2 (/sys/fs/cgroup/memory.max), inexistente no ACI.
#
# Na sessao 2 essa hipotese foi VERIFICADA CONTRA O CODIGO REAL da imagem e
# se mostrou FALSA. Em gvenzl/oracle-xe:21-slim
# (digest sha256:ecdf4302ac3d134e1bac5ef6e0c223c2d0f4d4d2b6d551aa79b2346f1ab8f792),
# /opt/oracle/container-entrypoint.sh linhas 306-315, a funcao
# check_minimum_memory ja trata os dois layouts e ainda tem fallback:
#
#   # cgroups v2
#   if [ -f /sys/fs/cgroup/memory.max ]; then
#     container_memory=$(< /sys/fs/cgroup/memory.max)
#   # cgroups v1
#   elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
#     container_memory=$(< /sys/fs/cgroup/memory/memory.limit_in_bytes)
#   else
#     echo "CONTAINER: INFO: Cannot determine memory, assuming default of 2 GB."
#
# Ou seja: em cgroup v1 (ACI) o script ja lia o valor certo sozinho, e o shim
# era, na melhor das hipoteses, um no-op caro -- e na pior, uma variavel a
# mais (trocava o mecanismo nativo de USER da imagem por um
# `chroot --userspec`, mudando a arvore de processos do PID 1).
#
# Aritmetica que fecha o caso: o entrypoint roda com `set -Eeuo pipefail`
# (linha 25) e o `startup;` roda sob `WHENEVER SQLERROR EXIT SQL.SQLCODE`,
# entao o ExitCode do container E o codigo do erro ORA truncado em 8 bits.
# O ExitCode observado no ACI foi 204 -> ORA-00204 (error in reading control
# file). ORA-01081 daria 1081 % 256 = 57, NAO 204 -- logo o ORA-01081 que a
# sessao 1 via no log era sintoma de um restart posterior, nao a causa da
# primeira falha. Ver STATUS-SESSAO-2.md, secao 1.
#
# Por isso a imagem volta a ser o entrypoint nativo da base, sem shim: menos
# uma variavel nao comprovada entre nos e a causa real.
