# Status — Sessão 2 (2026-09-01)

Continuação de `STATUS-SESSAO-1.md`. Mesma disciplina: **nada aqui é suposição** — cada
afirmação abaixo tem o comando que a produziu ou o trecho de código que a sustenta.

## 0. A sessão 2 começou em outra máquina e outra subscription

O `PROMPT_CONTINUIDADE_SESSAO_2.md` assumia a máquina da sessão 1. Não é o caso. Levantado no
Passo 0:

| Item | Sessão 1 | Sessão 2 (esta) |
|---|---|---|
| Usuário / path do repo | `C:\Users\labsfiap\kura-cp4-acr-aci` | `C:\Users\gbs53\Downloads\kura-cp4-acr-aci` |
| Subscription Azure | Felipe Ferrete — RM562999 | **Gustavo Bosak — RM566315** |
| `rm562999-kura-cp4-rg` | vivo, com ACR + ACI do Oracle | **`ResourceGroupNotFound`** |
| `.env` | preenchido | não existia — recriado nesta sessão |
| `gh` CLI | autenticado | **não instalado** |
| Repo `.NET` | `~\backend-clinica-dotnet` | `~\RiderProjects\backend-clinica-dotnet` |
| Repo Java | `~\backend-tutor-java` | `~\Downloads\backend-tutor-java` |
| Docker | ok | ok (29.7.2) |

**Consequência direta:** o Passo 1 do prompt de continuidade — "capture o log do restart atual do
ACI `rm562999-kura-oracle-db` antes que ele seja limpo" — **é impossível daqui**. Aquele ACI vive
na subscription do Felipe. O crash teve que ser reatacado pelo código, não pelo log daquele
container.

**Decisão tomada com o usuário:** implantar do zero na subscription RM566315, com prefixo
`rm566315` em todos os recursos (`deploy.sh` já deriva tudo de `$RM`, então foi só o `.env`).
Evita colisão de nome global de ACR/Storage com os recursos que o Felipe já criou.

## 1. ACHADO PRINCIPAL — a causa raiz da sessão 1 (cgroup v1) estava ERRADA

A sessão 1 concluiu (achado #4) que o crash loop do Oracle no ACI vinha do
`container-entrypoint.sh` da imagem `gvenzl/oracle-xe:21-slim` ler **só** o caminho de cgroup v2
(`/sys/fs/cgroup/memory.max`), inexistente no ACI. O commit `a273da3` adicionou um shim inteiro
por causa disso.

**Essa hipótese foi verificada contra o código real da imagem nesta sessão, e é falsa.**

Comando:

```bash
docker run --rm --user root --entrypoint sh gvenzl/oracle-xe:21-slim \
  -c 'grep -n "cgroup" /opt/oracle/container-entrypoint.sh'
```

Saída (imagem oficial, digest `sha256:ecdf4302ac3d134e1bac5ef6e0c223c2d0f4d4d2b6d551aa79b2346f1ab8f792`):

```
306:  # cgroups v2
307:  if [ -f /sys/fs/cgroup/memory.max ]; then
308:    container_memory=$(< /sys/fs/cgroup/memory.max)
309:  # cgroups v1
310:  elif [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
311:    container_memory=$(< /sys/fs/cgroup/memory/memory.limit_in_bytes)
```

E logo abaixo ainda há `else ... container_memory=2147483648` ("assuming default of 2 GB").
Ou seja: a função `check_minimum_memory` **já trata cgroup v1 num `elif` explícito**, com
fallback. Em ACI ela sempre leu o valor certo sozinha. O shim era, na melhor das hipóteses, um
no-op; na pior, uma variável a mais (trocava o `USER` nativo da imagem por um
`chroot --userspec`, mudando a árvore de processos do PID 1).

Isso também explica por que o shim "pareceu ajudar": ele não mudou nada de relevante. O progresso
maior no boot observado na sessão 1 era variação normal entre tentativas, não efeito do fix.

### 1.1 A aritmética que fecha o caso: `ExitCode 204` não é `ORA-01081`

Dois fatos do mesmo arquivo:

- linha 25: `set -Eeuo pipefail` — qualquer comando que falhe aborta o script inteiro;
- o bloco de start roda `sqlplus` com `WHENEVER SQLERROR EXIT SQL.SQLCODE`:

```bash
lsnrctl start && \
sqlplus -s / as sysdba << EOF
   WHENEVER SQLERROR EXIT SQL.SQLCODE
   startup;
   exit;
EOF
```

Logo, **o ExitCode do container é o código do erro ORA truncado em 8 bits**. Então:

| Erro | Código | ExitCode esperado (`% 256`) |
|---|---|---|
| `ORA-00204` (error in reading control file) | 204 | **204** ✅ |
| `ORA-00205` (error identifying control file) | 205 | 205 |
| `ORA-01081` (cannot start already-running ORACLE) | 1081 | **57** ❌ |

A sessão 1 registrou `ExitCode 204` **sempre**. `ORA-01081` daria 57, não 204. Portanto o
`ORA-01081` que aparecia no log **não era o erro fatal** — era sintoma de um restart posterior,
capturado porque o log do primeiro boot já tinha sido perdido.

### 1.2 Por que o crash loop nunca se curava sozinho

`setup_env_vars` (mesmo arquivo) decide o caminho de boot por **uma única condição**:

```bash
if [ -d "${ORACLE_BASE}/oradata/dbconfig/${ORACLE_SID}" ]; then
    DATABASE_ALREADY_EXISTS="true";
```

Se o primeiro boot morre no meio da criação do banco, esse diretório **já existe** mas o
`oradata` está incompleto. Todo restart seguinte então pula `create_dbconfig`, cai direto no
`startup;` e falha lendo o control file — `ORA-00204`, ExitCode 204, para sempre. É um crash loop
que, por construção, **não pode** se curar reiniciando.

## 2. Correções aplicadas (commit `c905cdf`)

1. **Shim de cgroup removido** (`db/cgroup-v1-shim-entrypoint.sh` deletado, `db/Dockerfile` volta
   ao entrypoint nativo). Confirmado após o build:
   `ENTRYPOINT=[container-entrypoint.sh] USER=oracle WORKDIR=/opt/oracle`.
   O motivo da remoção ficou documentado como comentário no próprio `db/Dockerfile`, com o trecho
   de código citado — para ninguém "reintroduzir o fix" mais tarde sem ler o porquê.
2. **`restartPolicy` do ACI do Oracle: `OnFailure` → `Never`**, por dois motivos independentes:
   - *diagnóstico*: com `OnFailure` o buffer do `az container logs` é limpo a cada restart — é
     exatamente por isso que a sessão 1 nunca capturou o log do primeiro crash (vinha sempre
     vazio/`None`). Com `Never`, o container para no primeiro erro e o log completo do boot
     inicial fica disponível;
   - *corretude*: pelo §1.2, reiniciar este container nunca conserta nada.
   - `azure/aci-oracle-db.yaml` reconferido em ASCII puro depois da edição (0 bytes > 127),
     preservando o fix do achado #2 da sessão 1.

## 3. Estado do deploy nesta sessão

<!-- PREENCHER AO FIM DA SESSÃO -->

## 4. O que a sessão 3 NÃO deve refazer

- **Não reintroduzir o shim de cgroup.** A hipótese está refutada com o código da imagem citado
  no §1. Se o Oracle voltar a falhar, a causa é outra — procure no log do primeiro boot, que
  agora é capturável graças ao `restartPolicy: Never`.
- **Não interpretar `ORA-01081` como causa.** Pelo §1.1 ele é sempre sintoma de restart. O erro
  real do primeiro boot é o que importa.
- Continuam válidos todos os "não refaça" da §5 do `STATUS-SESSAO-1.md` (Azure Files para
  `oradata`, User-Agent do apt, acentuação nos YAML).
