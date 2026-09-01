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

## 3. Mais dois achados reais, ambos só visíveis com o Oracle finalmente no ar

### 3.1 O passo de backup para a Storage Account nunca funcionou (commit `1bdea3b`)

A rubrica exige persistir em Conta de Armazenamento. O passo existia no `deploy.sh` desde a
sessão 1, mas **nunca tinha sido alcançado** (o Oracle nunca ficou saudável). Alcançado nesta
sessão, falhou — por duas armadilhas empilhadas, as duas confirmadas ao vivo:

1. **`az container exec --exec-command` quebra a string em espaços e monta o argv direto**, sem
   shell e sem respeitar aspas. A forma antiga chegava picada no meio das aspas:
   ```
   -p: -c: line 0: unexpected EOF while looking for matching `''
   error executing command [/bin/sh -c 'mkdir -p /mnt/kura-backup/oradata-snapshot ]
   ```
2. **No Git Bash, o MSYS reescreve argumento que parece caminho POSIX** — `/bin/mkdir` virava
   `C:/Program Files/Git/bin/mkdir`:
   ```
   exec: "C:/Program": stat C:/Program: no such file or directory
   ```

Fix: comandos separados em argv puro (sem shell, sem aspas, sem `&&`), cada um com
`MSYS_NO_PATHCONV=1` **por comando** — nunca exportado global, porque `substituir_placeholders()`
depende da conversão de path para o Python nativo do Windows (a própria função já documentava
essa tensão). A confirmação virou a presença do control file no destino, em vez de um
`echo BACKUP_OK` impossível em argv puro.

Resultado verificado no Azure Files: `control01.ctl`/`control02.ctl` (18 MB cada),
`system01.dbf` (917 MB), `sysaux01.dbf` (587 MB), `redo01/02.log`, `undotbs01.dbf`,
`users01.dbf`. Persistência real, não simulada.

### 3.2 O clone local do `backend-tutor-java` estava 35 commits atrás — só 6 das 19 migrations

O smoke test falhou no primeiro POST com `HTTP 500 DbUpdateException`. Log do `.NET`:

```
ORA-06550: line 14, column 138:
PL/SQL: ORA-00904: "NM_RAZAO_SOCIAL": invalid identifier
```

Log do Flyway no container Java:

```
Successfully validated 6 migrations
Successfully applied 6 migrations to schema "RM566315", now at version v6
```

`NM_RAZAO_SOCIAL` vem da `V8__clinica_razao_social.sql`. **Não é bug do CP4** — o clone de
`backend-tutor-java` desta máquina estava 35 commits atrás do `origin/main`, que tem as 19
(commit `de61cd2 fix(clinica): add V8/V9 migrations for .NET/Flyway schema drift`).

Antes de atualizar, foi verificado o risco de checksum: o repo reorganizou as migrations em
pastas por dialeto (`db/migration-oracle`, `db/migration-h2`), e `V2`/`V3`/`V5` saíram de
`db/migration/`. Se o conteúdo tivesse mudado, o Flyway falharia a validação contra o
`flyway_schema_history` já gravado. Conferido por md5: **os três são byte-idênticos**, só mudaram
de pasta, e `application-prod.yml` usa
`locations: classpath:db/migration,classpath:db/migration-oracle`. Logo dava para aplicar
V7→V19 incrementalmente, sem recriar o Oracle.

### 3.3 O smoke test não enviava `idClinica` (commit `2e2ae8d`)

Passo 3 respondia `HTTP 400`:
`{"errors":{"IdClinica":["'Id Clinica' must be greater than '0'."]}}`.
Conferido no código: `VeterinarioCreateDto` tem a propriedade e
`VeterinarioCreateValidator` exige `RuleFor(x => x.IdClinica).GreaterThan(0)`. O valor já estava
disponível (`ID_CLINICA`, capturado no passo 1). `TutorCreateDto`/`PetCreateDto` **não** têm o
campo (derivam a clínica do JWT), por isso só o payload de veterinário mudou.

## 4. Estado final do ambiente — TUDO NO AR E VALIDADO

Subscription **RM566315**, resource group `rm566315-kura-cp4-rg`, região **eastus2**.

| Recurso | Nome | Estado |
|---|---|---|
| ACR | `rm566315kuraacr` | 3 imagens publicadas |
| Storage Account | `rm566315kurastorage` | share `kura-oracle-data` com o snapshot real |
| ACI Oracle | `rm566315-kura-oracle-db` | `Running`, `restartCount: 0`, `DATABASE IS READY TO USE!` |
| ACI .NET | `rm566315-kura-clinica-api` | `Running`, `/health` → 200 |
| ACI Java (bônus) | `rm566315-kura-tutor-api` | `Running`, `/api/actuator/health` → 200, schema em **v19** |

Endpoints públicos (validados de fora, nunca localhost):

- Oracle: `rm566315-kura-oracle-db.eastus2.azurecontainer.io:1521` (XEPDB1)
- .NET: `http://rm566315-kura-clinica-api.eastus2.azurecontainer.io:8080` (`/health`, `/swagger`)
- Java: `http://rm566315-kura-tutor-api.eastus2.azurecontainer.io:8081/api` (`/actuator/health`, `/swagger-ui.html`)

**`azure/verify.sh`: passou 100%** (Oracle 1521 + .NET 200 + Java 200).

**`tests/smoke-cp4.sh`: as 13 chamadas passaram** — register-clinica, login, veterinário
(criar/buscar/listar/atualizar/inativar), tutor, pet (criar/buscar/listar/atualizar/inativar).

**SELECT de prova**, rodado com `sqlplus` dentro do próprio container Oracle (o `.sql` foi
enviado ao Azure Files e executado via `az container exec ... @/mnt/kura-backup/prova.sql` — 3
tokens de argv, contornando a limitação do §3.1):

```
ID_CLINICA  NM_CLINICA                     ID_VET  NM_VETERINARIO            ATIVO  ID_TUTOR  ID_PET  ATIVO
102         Clinica Veterinaria CP4 3049…  100     Dr. Carlos Lima Junior…   N      100       100     N
```

Os `ST_ATIVO = N` provam o soft delete dos passos 7 e 13 — DELETE provado, não assumido pelo 204.

## 5. O que falta (tarefas humanas)

1. Gravar o vídeo — roteiro em `docs/ROTEIRO-VIDEO.md`. **Ajustar os nomes**: o roteiro fala em
   `rm562999`/`centralus`, e o ambiente vivo é `rm566315`/`eastus2`.
2. Exportar `docs/CAPA-ENTREGA.html` para PDF (`Grupo3_container.pdf`).
3. ~~`./azure/teardown.sh` ao final~~ — **JÁ FOI FEITO no fim desta sessão**, a pedido do
   usuário. Confirmado com `az group exists --name rm566315-kura-cp4-rg` → `false`. **Custo
   zerado, nada ficou ligado.**

### Como recriar o ambiente para gravar o vídeo

O `deploy.sh` é idempotente e todos os fixes desta sessão estão commitados, então recriar é um
comando só — mas leva ~20 min (o push da imagem Oracle de 2,58 GB é o gargalo) e o Oracle sobe do
zero:

```bash
cd kura-cp4-acr-aci
./azure/deploy.sh          # recria RG, ACR, storage, e os 3 ACIs
./azure/verify.sh          # confirma os 3 endpoints
BASE_URL=http://<fqdn-do-aci-dotnet>:8080 ./tests/smoke-cp4.sh
./azure/teardown.sh        # NAO ESQUECER depois de gravar
```

Um cuidado: o `.env` **não é versionado**. Numa máquina nova, `cp .env.example .env`, preencher os
segredos com `openssl rand`, e ajustar `AZURE_LOCATION` para uma região que a policy da
subscription permita (ver §0 e o comentário no `.env.example`).

Outro cuidado, do §3.2: se o clone de `backend-tutor-java` estiver atrasado, o Flyway aplica só
parte das migrations e o `.NET` quebra com `ORA-00904`. Rodar `git pull` nos repos-fonte antes do
`deploy.sh`.

## 6. O que a sessão 3 NÃO deve refazer

- **Não reintroduzir o shim de cgroup.** A hipótese está refutada com o código da imagem citado
  no §1. Se o Oracle voltar a falhar, a causa é outra — procure no log do primeiro boot, que
  agora é capturável graças ao `restartPolicy: Never`.
- **Não interpretar `ORA-01081` como causa.** Pelo §1.1 ele é sempre sintoma de restart. O erro
  real do primeiro boot é o que importa.
- Continuam válidos todos os "não refaça" da §5 do `STATUS-SESSAO-1.md` (Azure Files para
  `oradata`, User-Agent do apt, acentuação nos YAML).
