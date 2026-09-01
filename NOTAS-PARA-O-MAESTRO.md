# Notas para o maestro — KURA CP4 (ACR/ACI)

Escrito depois de montar todos os artefatos deste repo. Resumo de decisões
técnicas, suposições que precisei fazer, e o que falta para rodar de ponta a
ponta. `az`/`docker` **não foram executados de verdade** — sem login
configurado, como instruído. O que **foi** validado localmente:

- Sintaxe dos 3 scripts (`bash -n`) — sem erro.
- Os 3 Dockerfiles copiados (`app-dotnet/Dockerfile`, `app-java/Dockerfile`)
  são **idênticos** aos originais (conferido por `diff`, ignorando só
  comentário/linha em branco do cabeçalho de proveniência que acrescentei).
- A função de substituição de placeholders (`substituir_placeholders` em
  `deploy.sh`) foi extraída e rodada de verdade contra os 3 templates YAML
  reais, com valores fake — os 3 geraram YAML válido (parseado com
  `yaml.safe_load`), sem placeholder `__ALGO__` sobrando.
- Esse teste **pegou e corrigiu 3 bugs reais** antes de eu considerar o
  script pronto (detalhe no §3) — vale ler antes de rodar contra Azure de
  verdade, porque mostra exatamente que classe de armadilha esperar.

## 1. Decisões técnicas

- **Nomenclatura de recurso**: `$RM="RM562999"` é a única fonte do prefixo em
  `deploy.sh`/`verify.sh`/`teardown.sh` (nunca hardcoded em segundo lugar).
  Uma versão em minúsculo (`$RM_LOWER`) é derivada no topo porque ACR,
  Storage Account e nome de imagem Docker **exigem lowercase** — só o
  Resource Group e os nomes de ACI toleram hífen, mas ainda assim uso tudo
  minúsculo por consistência (`rm562999-kura-oracle-db`, não
  `RM562999-kura-oracle-db`).
- **`az acr login` em vez de credencial fixa no `.env`**: a rubrica pediu
  "login no ACR a partir do ACI (`--registry-login-server`/
  `--registry-username`/`--registry-password` lendo do `.env`)". Decidi
  **não** pedir usuário/senha do ACR no `.env` — em vez disso, `deploy.sh`
  habilita o admin user do ACR (`az acr update --admin-enabled true`) e
  busca username/senha em tempo real via `az acr credential show`, injetando
  nos placeholders do YAML (`imageRegistryCredentials`). Motivo: a senha
  admin do ACR é **gerada pelo Azure**, não escolhida pelo usuário — pedir
  para copiar isso à mão para o `.env` seria um passo manual frágil (fica
  desatualizado se alguém rodar `az acr credential renew`). O espírito da
  exigência (nenhuma credencial hardcoded, autenticação explícita via
  `--registry-*`) está preservado; só a *origem* do valor mudou de "usuário
  digita no `.env`" para "script busca do próprio Azure".
- **Sem VNET entre os ACIs**: cada container group tem seu próprio IP/FQDN
  público. O `.NET` (e o Java bônus) conectam no Oracle pelo **FQDN público**
  do ACI do banco (`rm562999-kura-oracle-db.<região>.azurecontainer.io:1521`),
  não por rede privada — ACI puro (sem VNET integration, que é
  significativamente mais complexo de scriptar em CLI) não compartilha uma
  rede interna entre container groups do jeito que o `docker-compose.yml`
  original faz via `kura-net`. **Consequência de segurança real**: o tráfego
  Oracle↔.NET/Java atravessa a internet pública entre dois FQDNs do Azure
  (autenticado por usuário/senha do Oracle, mas não teria TLS entre os
  serviços — Oracle Net não fala TLS por padrão nesta configuração). Aceitável
  para um checkpoint acadêmico de curta duração (por isso o `teardown.sh` é
  enfaticamente obrigatório), mas **não é o desenho que eu recomendaria para
  produção** — lá entraria VNET + Private Endpoint.
- **`STORAGE_BASE_PATH` do .NET não usa Azure Files**: só o volume do Oracle
  (`/opt/oracle/oradata`) está no Azure Files, como a rubrica exige
  explicitamente. O `.NET` grava PDF de receituário na camada gravável do
  próprio container (`Storage__BasePath=/data/kura/receituarios`), que
  **some a cada recreate do ACI** — mesma limitação que o `docker-compose.yml`
  original tinha resolvido com um segundo volume nomeado
  (`kura-storage-documentos`) que eu **não** replico aqui, porque a rubrica só
  pede persistência do banco. Se quiser persistir isso também, dá para
  acrescentar um segundo Azure Files share e montá-lo no ACI do `.NET` do
  mesmo jeito que fiz para o Oracle — deixei o padrão pronto para copiar.
- **`imageRegistryCredentials`/segredos em texto no YAML gerado**: o schema
  de manifesto do ACI (`az container create --file`) não separa "arquivo de
  secrets" de manifesto — o campo `secureValue` é a única forma suportada de
  não expor o valor em `az container show`/logs depois de criado, mas ele
  ainda precisa estar em texto plano no arquivo YAML **no momento da
  criação**. Por isso os arquivos preenchidos vivem em `azure/.generated/`
  (gitignored) e nunca em `azure/*.yaml` (esses são só os templates com
  placeholder, seguros para commit).
- **Restart policy `OnFailure`** nos 3 container groups: ACI não tem
  healthcheck nativo equivalente ao `HEALTHCHECK` do Dockerfile (que os 3
  Dockerfiles já declaram, mas ACI simplesmente ignora essa instrução) — o
  que existe é o `restartPolicy`, que só reage a **crash do processo**
  (`exit != 0`), não a "processo vivo mas não saudável". Um Oracle que sobe
  mas trava a meio-caminho da criação do PDB não seria reiniciado
  automaticamente. `verify.sh` é o substituto funcional: ele prova saúde de
  fora, com retry generoso, e é o gate real antes de gravar o vídeo.
- **`docker build`/`docker push` explícitos, sem `az acr build`**: seguido à
  risca conforme pedido — o build roda nesta máquina (usa os repos-fonte
  como contexto, ver §2) e só o artefato final (a imagem) sobe pro ACR.

## 2. Suposições que precisei fazer

- **Caminho dos repos-fonte**: assumi que `backend-clinica-dotnet` e
  `backend-tutor-java` são **diretórios irmãos** deste repo
  (`C:\Users\labsfiap\backend-clinica-dotnet`,
  `C:\Users\labsfiap\backend-tutor-java`), porque foi onde os encontrei
  durante a extração das env vars. `.env.example` tem
  `SRC_DOTNET_REPO_PATH`/`SRC_JAVA_REPO_PATH` justamente para não travar o
  script se isso mudar de máquina (o CLAUDE.md do workspace `dev VsClaude`
  já registra esse tipo de variação entre máquinas como fato recorrente do
  ecossistema KURA).
- **`ORACLE_PDB_SERVICE=XEPDB1`**: não encontrei essa variável nomeada
  explicitamente em nenhum lugar — é o nome de PDB *default* da imagem
  `gvenzl/oracle-xe:21-slim` quando nenhuma variável `ORACLE_DATABASE` é
  passada (confirmado contra o uso literal `oracle-db:1521/XEPDB1` no
  `ConnectionStrings__DefaultConnection`/`DB_URL` do
  `DevOps-Cloud/docker-compose.yml`). Tratei como constante conhecida, não
  como segredo.
- **`LUNA_BASE_URL`/`LUNA_API_KEY`/`LUNA_INBOUND_API_KEY`/`DAILY_API_KEY`**: a
  Luna (Python/FastAPI) **não faz parte deste CP4** — nem do núcleo, nem do
  bônus (o enunciado só pediu Oracle + .NET obrigatório, e Java como extra).
  Mas o `Kura.Api` lê essas 4 variáveis **incondicionalmente no startup**
  (`Luna__BaseUrl`, `Luna__InboundApiKey`, `IoT__ApiKey`, `Luna__ApiKey`,
  `Daily__ApiKey` — bindings confirmados em `DevOps-Cloud/docker-compose.yml`)
  e algumas delas (`Luna__InboundApiKey`) não têm fallback opcional como o
  `Daily__ApiKey` tem. Preenchi com placeholders dummy documentados no
  `.env.example` (`LUNA_BASE_URL` aponta para um hostname que nunca vai
  resolver) — o `.NET` sobe normalmente porque essas integrações só falham
  **na hora de usar a feature** (transcrição de áudio, triagem IA), não no
  boot. Nenhuma chamada real a essas 3 features vai funcionar neste
  ambiente — isso é esperado e não é bug do CP4.
- **Localização (`centralus`)**: reaproveitei a região do `script-azure.sh`
  do checkpoint anterior (histórico de capacidade OK para essa subscription
  acadêmica). Se a subscription usada agora for diferente, `AZURE_LOCATION`
  no `.env` pode não ter cota de ACI/vCPU disponível — nesse caso, trocar
  para outra região é o primeiro coisa a tentar (`brazilsouth`, `eastus`
  costumam ser as próximas alternativas óbvias).
- **SKU do ACR = `Basic`**: suficiente para 2-3 imagens pequenas de uso
  acadêmico de curta duração; não precisa de `Standard`/`Premium` (geo-replicação,
  throughput maior) para este escopo.
- **CPU/memória dos ACI**: 2 vCPU/4GB para o Oracle (mínimo realista para o
  boot do XE não estourar timeout), 1 vCPU/2GB para .NET e Java. Não medi
  contra carga real — são valores conservadores de literatura/experiência
  com `gvenzl/oracle-xe`, não benchmark feito neste repo.

## 3. Bugs achados e corrigidos durante a montagem (vale ler antes de rodar)

Rodei a função `substituir_placeholders` de verdade (extraída do `deploy.sh`)
contra os 3 templates YAML reais, com valores fake, antes de considerar o
script pronto. Isso pegou 3 problemas que só apareceriam depois, em pleno
deploy contra Azure real:

1. **Falso positivo no detector de placeholder esquecido**: a checagem
   original de "sobrou algum `__..__`?" batia em nomes de env var .NET
   legítimos como `ConnectionStrings__DefaultConnection`/`Jwt__Key` (que usam
   `__` como separador por convenção do ASP.NET, não como placeholder). Troquei
   por um regex que só reconhece `__TUDO_MAIUSCULO__` como placeholder de
   verdade.
2. **Vazamento de valor substituído para dentro de um comentário**: os
   cabeçalhos de `aci-dotnet-api.yaml`/`aci-java-api.yaml` citavam o nome do
   placeholder (`__ORACLE_CONNECTION_STRING__`, `__DB_URL__`) dentro de uma
   frase explicativa — como a substituição é troca de texto simples, isso
   also fazia o segredo real aparecer **duas vezes** no YAML gerado (uma vez
   no comentário, goulash de prosa ilegível, e uma vez no campo de verdade).
   Reescrevi os dois comentários para citar o **nome da env var** em vez do
   **token de placeholder**.
3. **`STORAGE_BASE_PATH` (e qualquer valor parecido com caminho absoluto
   Linux) chegava corrompido**: o Git Bash reescreve silenciosamente
   argumentos de linha de comando que parecem caminho absoluto —
   `/data/kura/receituarios` virava
   `C:/Program Files/Git/data/kura/receituarios` antes mesmo de chegar no
   Python. É a mesma classe de armadilha que o `CLAUDE.md` do workspace já
   documenta para `MSYS_NO_PATHCONV` — só que aqui `export
   MSYS_NO_PATHCONV=1` bruto não dava para usar, porque os caminhos do
   *template*/*saída* do próprio YAML (esses sim precisam ser convertidos
   para o Python nativo do Windows achar o arquivo) estariam na mesma
   chamada. Resolvido codificando cada valor em base64 antes de passar como
   argumento — nenhum caminho ambíguo passa em texto puro pro Python.

Não tenho como garantir que não existe uma **quarta** armadilha desta classe
esperando em algum outro valor que eu não testei (ex.: um segredo real gerado
por `openssl rand -base64` que comece por acaso com algo que pareça caminho)
— mas o padrão de correção (base64 em vez de texto puro) deveria blindar
contra qualquer variação disso, não só o caso específico achado.

## 4. O que falta para rodar de ponta a ponta

1. `az login` numa subscription com cota de ACI disponível.
2. `cp .env.example .env` e preencher os segredos (`openssl rand -base64 …`
   como o próprio arquivo indica).
3. Confirmar que `SRC_DOTNET_REPO_PATH`/`SRC_JAVA_REPO_PATH` no `.env` apontam
   para checkouts reais e atualizados dos 2 repos nesta máquina.
4. Rodar `./azure/deploy.sh` de verdade — **nunca testado contra Azure real
   nesta tarefa**, só a lógica local de geração de YAML/idempotência de
   nome foi exercitada. Esperar que apareça alguma fricção real de API do
   Azure (nome de recurso já em uso globalmente por outra conta FIAP é o
   caso mais provável — `ACR_NAME`/`STORAGE_ACCOUNT_NAME` no `.env` têm
   comentário orientando a trocar o sufixo se isso acontecer).
5. `./azure/verify.sh` — também nunca exercitado contra ambiente real.
6. Gravar o vídeo de demonstração.
7. `./azure/teardown.sh` — **obrigatório**, mesmo que a correção não tenha
   sido perfeita, para não deixar Oracle XE + 1-3 ACIs cobrando indefinidamente.

## 5. O que este repo explicitamente NÃO faz (fora de escopo, por decisão)

- Não roda o Flyway manualmente separado — o container Java aplica V1→V19
  sozinho contra o Oracle vazio na primeira subida (mesmo comportamento do
  `docker-compose.yml` original). Se `DEPLOY_JAVA_BONUS=false` (default),
  **o schema nunca é criado** neste ambiente, porque só o backend Java tem
  as migrations — o `.NET` sozinho sobe e responde `/health`, mas qualquer
  endpoint que dependa de tabela vai falhar contra um Oracle vazio. Isso é
  esperado dado o escopo da rubrica (só Oracle + .NET são exigidos) — vale
  deixar claro na gravação do vídeo que "schema vazio" é o estado esperado
  se o bônus Java não for ligado, não um bug.
- Não usa Key Vault para os segredos — ficam em `.env` local (gitignored) e
  como `secureValue`/`--secure-environment-variables` no ACI. Key Vault
  seria o próximo passo natural para produção, fora do escopo deste CP4.
- Não configura HTTPS/TLS nos endpoints ACI — eles respondem em HTTP puro
  por FQDN público (`http://…azurecontainer.io:8080`). Aceitável para
  checkpoint de curta duração, não para produção.
