> ✅ **ENTREGA SUBMETIDA.** O ambiente foi implantado, validado ponta a ponta e derrubado.
> Este banner substitui o aviso de "EM ANDAMENTO" que ficou aqui durante a sessão 1.
>
> O que foi validado de verdade, com evidência em `STATUS-SESSAO-2.md`: os **3 ACIs** no ar
> (Oracle `Running` com `restartCount: 0` e `DATABASE IS READY TO USE!`, `.NET` e Java com
> health 200), `azure/verify.sh` passando 100% por FQDN público, as **13 chamadas** de
> `tests/smoke-cp4.sh` respondendo o HTTP esperado, o `SELECT` de prova com `ST_ATIVO = 'N'`
> confirmando o soft delete, e o snapshot real do `oradata` na Conta de Armazenamento
> (`system01.dbf` 917 MB, `control01/02.ctl` 18 MB cada).
>
> ⚠️ **Correção importante de diagnóstico:** o banner anterior citava "Oracle incompatível com
> cgroup v1 do ACI" como uma das causas. **Essa hipótese é falsa** — foi verificada contra o
> código da imagem na sessão 2 (`container-entrypoint.sh` linhas 306-315 já tratam cgroup v1 num
> `elif` explícito) e o shim correspondente foi removido no commit `c905cdf`. O crash real era
> outro: `restartPolicy: OnFailure` apagava o log do primeiro boot a cada reinício, escondendo a
> causa. Ver `STATUS-SESSAO-2.md` §1. Os outros achados da sessão 1 (User-Agent do apt, encoding
> do `az` CLI, Azure Files incompatível com `oradata`) continuam válidos.
>
> **Nomenclatura da entrega:** todos os recursos usam o prefixo `RM566315` (Gustavo Bosak), na
> região `eastus2` — é a nomenclatura oficial desta entrega, e é o que está descrito daqui para
> baixo. A região não foi escolha estética: `centralus` é bloqueado pela policy
> "Allowed resource deployment regions" da subscription, que só permite `southafricanorth`,
> `eastus`, `brazilsouth`, `chilecentral` e `eastus2`. O `deploy.sh` deriva **tudo** de `$RM` e
> `$AZURE_LOCATION`, então trocar prefixo ou região é só editar o `.env`.
>
> **Para recriar o ambiente** (regravar o vídeo, reconferir algo): `./azure/deploy.sh`, e
> `./azure/teardown.sh` ao terminar — ver `STATUS-SESSAO-2.md` §5.

# KURA CP4 · Imagem e Containers em Nuvem (ACR/ACI)

**1º Checkpoint do 2º Semestre — DevOps Tools & Cloud Computing (FIAP)**
Prof. João Menk · Projeto DimDim

**Grupo 3**

| Integrante | RM |
|---|---|
| Clayton Alves | RM562285 |
| Felipe Ferrete (representante) | RM562999 |
| Guilherme Sola | RM563674 |
| Gustavo Bosak | RM566315 |
| Nikolas Brisola | RM564371 |

- **Vídeo de demonstração**: `<link a preencher pelo representante após a gravação>`
- **Código-fonte da aplicação**: [`backend-clinica-dotnet`](https://github.com/KURA-Clyvo/backend-clinica-dotnet) (API .NET — App do CP4) e [`backend-tutor-java`](https://github.com/KURA-Clyvo/backend-tutor-java) (API Java — sobe como 3º container bônus, ver §5)
- **Este repositório**: infraestrutura, Dockerfiles, DDL e evidências de teste do CP4

---

## 1. O que este checkpoint exige (resumo da rubrica)

Duas imagens Docker (banco + app), construídas localmente com Dockerfile próprio,
testadas localmente, registradas no **ACR** com prefixo `RM566315`, implantadas como
**dois ACIs** (também com prefixo `RM566315`), com o banco persistindo dados numa
**Conta de Armazenamento** — e tudo isso criado **via Azure CLI**, nunca pelo Portal.

| # | Peça | Onde está neste repo |
|---|---|---|
| 1 | Banco em container na nuvem | `db/Dockerfile` (Oracle XE) + `azure/aci-oracle-db.yaml` |
| 2 | App em container na nuvem | `app-dotnet/Dockerfile` (cópia fiel de `backend-clinica-dotnet/Dockerfile`) + `azure/aci-dotnet-api.yaml` |
| 3 | Imagens com Dockerfile próprio | `db/Dockerfile`, `app-dotnet/Dockerfile` |
| 4/5 | Build e teste local | ver §4 |
| 6 | Registro no ACR com prefixo RM | `azure/deploy.sh` (`docker build`/`docker push` explícitos) |
| — | ACIs com prefixo RM, storage account | `azure/deploy.sh` |
| — | DDL das tabelas | `db/ddl/` (as 19 migrations Flyway reais, V1→V19) |
| — | JSONs de teste (GET/POST/PUT/DELETE) | `tests/json/` |
| — | Evidência de CRUD por `SELECT` | `tests/smoke-cp4.sh` (roda o CRUD e imprime o `sqlplus` pronto para o vídeo) |

## 2. Arquitetura

```
                          ┌─────────────────────────────┐
                          │   Azure Container Registry   │
                          │      rm566315kuraacr         │
                          │  rm566315/kura-oracle-db      │
                          │  rm566315/kura-clinica-api    │
                          └──────────────┬────────────────┘
                                         │ docker push
        ┌────────────────────────────────┼────────────────────────────────┐
        │                                │                                │
┌───────▼────────┐              ┌────────▼─────────┐            ┌─────────▼────────┐
│  ACI (núcleo)   │   Oracle Net │  ACI (núcleo)     │            │ ACI (bônus, fora  │
│ rm566315-kura-  │◄─────────────┤ rm566315-kura-    │            │ da rubrica CP4)   │
│ oracle-db       │   1521       │ clinica-api (.NET)│            │ rm566315-kura-    │
│ (gvenzl/        │              │ porta 8080         │            │ tutor-api (Java)  │
│ oracle-xe:21)   │              │                     │            │ porta 8081         │
└───────┬─────────┘              └────────────────────┘            └─────────┬─────────┘
        │ Azure Files (persistência real,                                    │
        │ RUBRICA — não é volume efêmero)                            Oracle Net (schema:
        │                                                             aplica Flyway V1→V19)
┌───────▼─────────┐
│  Storage Account │
│ rm566315kurastorage│
│ share: kura-oracle-data
└──────────────────┘
```

**Fluxo funcional de demonstração** (ver `tests/smoke-cp4.sh` para o script completo):

```
POST /api/v1/auth/register-clinica  →  cadastra a clínica (sem convite/token — self-service)
POST /api/v1/auth/login             →  devolve JWT
    │
    ▼ (com o JWT)
POST   /api/v1/veterinarios         →  cria veterinário         ─┐
GET    /api/v1/veterinarios/{id}    →  lê o criado               │  CRUD #1
GET    /api/v1/veterinarios         →  lista                     │  completo
PUT    /api/v1/veterinarios/{id}    →  atualiza                  │
DELETE /api/v1/veterinarios/{id}    →  soft-delete (ST_ATIVO='N')─┘
    │
POST   /api/v1/tutores              →  cria tutor (setup, 1 chamada)
POST   /api/v1/pets                 →  cria pet                 ─┐
GET    /api/v1/pets/{id}            →  lê o criado                │  CRUD #2
GET    /api/v1/pets                 →  lista                      │  completo
PUT    /api/v1/pets/{id}            →  atualiza                   │
DELETE /api/v1/pets/{id}            →  soft-delete                ┘
    │
    ▼
sqlplus RM566315/<senha>@<FQDN-do-ACI-oracle>:1521/XEPDB1
  SELECT * FROM VETERINARIO WHERE ...;   -- prova visual, uma linha por operação
  SELECT * FROM PET WHERE ...;
```

## 3. Por que o backend Java também sobe (3º ACI, fora da rubrica)

O `.NET` **não cria schema** — quem faz isso é o Flyway, exclusividade do backend
Java (ver `CLAUDE.md` do ecossistema, "Duas APIs, um banco Oracle"). Sem o Java rodar
pelo menos uma vez contra o Oracle vazio do ACI, o `.NET` sobe e responde `/health`,
mas **qualquer chamada de CRUD falha** (tabela inexistente).

Por isso: `.env` deste repo tem `DEPLOY_JAVA_BONUS=true` **ligado por decisão do
grupo** (não é o default do `.env.example`, que vem `false`) — o Java sobe como 3º
ACI, aplica V1→V19 sozinho na primeira subida, e só então o `.NET` funciona de
verdade. **Os dois ACIs que contam para a nota continuam sendo só Oracle + `.NET`** —
o Java é valor agregado, ponte para a Sprint 3 (App Service) do Challenge, e está
identificado como tal em todo comentário dos scripts.

## 4. Passo a passo (build local → nuvem → limpeza)

```bash
# 0. Pré-requisitos nesta máquina
az login
gh auth login          # se for versionar mudanças neste repo
docker --version        # Docker Desktop rodando

# 1. Configurar segredos (nunca versionados)
cp .env.example .env
# preencher ORACLE_SYS_PASSWORD, ORACLE_APP_PASSWORD, DOTNET_JWT_KEY, IOT_API_KEY,
# LUNA_API_KEY, LUNA_INBOUND_API_KEY, JAVA_JWT_SECRET — ver comentário "openssl rand"
# de cada variável no próprio .env.example
# Ligar o bônus Java (necessário para o .NET funcionar — ver §3):
#   DEPLOY_JAVA_BONUS=true

# 2. Build local + teste local (rubrica exige isto ANTES de subir na nuvem)
docker build -t kura-oracle-db:local ./db
docker build -f ./app-dotnet/Dockerfile -t kura-clinica-api:local ../backend-clinica-dotnet
docker build -f ./app-java/Dockerfile   -t kura-tutor-api:local   ../backend-tutor-java
# Testar localmente com o docker-compose já existente no DevOps-Cloud (mesmas 3 imagens,
# mesmas env vars) — mais rápido que montar um compose novo só para este teste:
#   cd ../DevOps-Cloud && cp .env.example .env && (preencher) && \
#   docker compose up oracle-db kura-tutor kura-api
# Confirmar localmente: registro de clínica → login → CRUD → SELECT no Oracle do compose.

# 3. Deploy real na nuvem (cria RG, ACR, storage account, faz o build+push das imagens
#    do ACR — não confundir com o build local do passo 2, que é só para testar antes —
#    e sobe os ACIs, na ordem Oracle → .NET → Java)
./azure/deploy.sh

# 4. Validação externa (por FQDN público, nunca localhost)
./azure/verify.sh

# 5. Rodar o smoke test funcional e capturar as evidências de CRUD
BASE_URL="http://$(az container show -g rm566315-kura-cp4-rg -n rm566315-kura-clinica-api --query ipAddress.fqdn -o tsv):8080" \
  ./tests/smoke-cp4.sh
# Cole o comando sqlplus impresso no final para tirar o SELECT de prova (grave a tela).

# 6. GRAVAR O VÍDEO (ver docs/ROTEIRO-VIDEO.md)

# 7. OBRIGATÓRIO — apagar tudo depois da correção/gravação
./azure/teardown.sh
```

## 5. Estrutura do repositório

```
kura-cp4-acr-aci/
  db/Dockerfile              Dockerfile do banco (Oracle XE)
  db/ddl/                    DDL real das tabelas — as 19 migrations Flyway (V1→V19)
  app-dotnet/Dockerfile      cópia fiel de backend-clinica-dotnet/Dockerfile
  app-java/Dockerfile        cópia fiel de backend-tutor-java/Dockerfile (bônus)
  azure/deploy.sh            provisiona tudo via Azure CLI (idempotente)
  azure/verify.sh            valida saúde dos ACIs por HTTP/TCP externo
  azure/teardown.sh          apaga o resource group inteiro (rodar sempre ao final)
  azure/aci-*.yaml           manifestos de container group (templates, sem segredo)
  tests/json/                payloads reais de GET/POST/PUT/DELETE
  tests/smoke-cp4.sh         executa o fluxo de CRUD completo e imprime o SELECT de prova
  .env.example               variáveis necessárias (sem valor real)
  NOTAS-PARA-O-MAESTRO.md    decisões técnicas e limitações conhecidas
```

## 6. Segurança e boas práticas já aplicadas

- Container do app roda **non-root** (`USER kura` no `.NET`, `USER spring` no Java) —
  herdado dos Dockerfiles de produção reais, não é específico deste CP4.
- Nenhuma credencial em texto no código-fonte ou nos scripts versionados — tudo em
  `.env` (gitignored) e `secureValue` nos manifestos ACI.
- `azure/teardown.sh` pede confirmação explícita (digitar o nome do resource group)
  antes de apagar, para evitar exclusão acidental.

## 7. Limitações conhecidas (declaradas, não escondidas)

Ver `NOTAS-PARA-O-MAESTRO.md` na íntegra. Resumo: sem VNET entre os ACIs (tráfego
Oracle↔apps atravessa FQDN público, sem TLS — aceitável para checkpoint acadêmico de
curta duração); sem HTTPS nos endpoints; persistência em Azure Files cobre só o
volume de dados do Oracle (é o que a rubrica pede), não os PDFs gerados pelo `.NET`.
