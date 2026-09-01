# Status — Sessão 1 (2026-09-01)

Escrito ao final da sessão porque o representante precisou sair. **Leia este arquivo e
`PROMPT_CONTINUIDADE_SESSAO_2.md` antes de qualquer coisa na sessão 2** — não repita os testes já
feitos aqui, o achado da sessão 1 é justamente ter isolado a causa raiz depois de várias
hipóteses erradas.

## 1. Onde a entrega está agora

- **Repo `KURA-Clyvo/kura-cp4-acr-aci`**: criado, público, com todo o scaffolding (Dockerfiles,
  scripts Azure CLI, DDL real — as 19 migrations Flyway —, JSONs de teste, README, roteiro de
  vídeo, material de apresentação). Commits até `a273da3`.
- **Time e RM confirmados**: Grupo 3 — Clayton Alves (RM562285), Felipe Ferrete (RM562999,
  representante), Guilherme Sola (RM563674), Gustavo Bosak (RM566315), Nikolas Brisola
  (RM564371). Já estão no `README.md` e em `docs/CAPA-ENTREGA.html`.
- **Artifacts publicados** (links no `README.md` original desta sessão, ou peça pro Felipe): um
  "Manifesto CP4" (arquitetura + runbook visual) e uma "Apresentação CP4" (roteiro de fala pra
  Parte 2). Ainda válidos, não precisam ser refeitos.
- **Recursos reais no Azure, resource group `rm562999-kura-cp4-rg`, região `centralus`**:
  - `rm562999kuraacr` (ACR) — com as 3 imagens já publicadas (`kura-oracle-db`,
    `kura-clinica-api`, `kura-tutor-api`, todas `:latest`).
  - `rm562999kurastorage` (Storage Account) — com o file share `kura-oracle-data` (vazio hoje;
    a ideia do "snapshot pós-boot" ainda não foi exercitada porque o Oracle nunca ficou saudável
    por tempo suficiente).
  - `rm562999-kura-oracle-db` (ACI) — **em pé, mas não confirmado saudável**. Ver §3.
  - **NÃO existe ainda**: o ACI do `.NET` (`rm562999-kura-clinica-api`) nem o do Java bônus
    (`rm562999-kura-tutor-api`) — o deploy nunca passou do Oracle.
- **`.env` local** (`kura-cp4-acr-aci/.env`, gitignored, existe na máquina onde a sessão 1
  rodou): já preenchido com segredos gerados, `DEPLOY_JAVA_BONUS=true`. Se a sessão 2 rodar em
  outra máquina, não existe — recriar com `cp .env.example .env` e os `openssl rand` indicados.

⚠️ **Custo real acontecendo agora**: o resource group está vivo, cobrando. Não é urgente (poucos
recursos pequenos), mas se a sessão 2 demorar a começar, considere `az group show --name
rm562999-kura-cp4-rg` pra confirmar que ainda existe, e decidir se vale manter ligado esperando
ou rodar `./azure/teardown.sh` e recomeçar do zero mais tarde (o script inteiro é idempotente,
recriar não é caro em tempo, só em ter que esperar o Oracle subir de novo).

## 2. Os 5 problemas reais encontrados e corrigidos nesta sessão — nenhum deles óbvio, todos com
   evidência, nenhum é "achismo"

Ordem cronológica, cada um bloqueava o seguinte:

1. **`apt-get` bloqueado por User-Agent nesta rede** (build local do `.NET`/Java falhava com
   `403 Forbidden` em `archive.ubuntu.com`). Isolado trocando só o User-Agent do `curl` — mesma
   URL, mesmo IP, 403 vira 200. Fix: `db/Dockerfile`... não, `app-dotnet/Dockerfile` e
   `app-java/Dockerfile` ganharam um `apt.conf.d` com UA de navegador antes do `apt-get update`.
   Commit `2a0111a`.
2. **`az container create --file` quebrava com `'charmap' codec can't decode byte 0x81`** — o
   Python do `az` CLI lê o YAML gerado usando `locale.getpreferredencoding()`, que nesta máquina
   Windows é `cp1252`, não UTF-8. `PYTHONUTF8=1`/`PYTHONIOENCODING=utf-8` **não resolveram**
   (o `az` parece forçar a leitura com encoding do sistema, ignorando isso). Commits `c1c9f73`
   (a tentativa que não bastou) e `d77c2f8` (o fix real: transliterar os 3 templates YAML pra
   ASCII puro — 0 bytes não-ASCII confirmados).
3. **Oracle não roda com `/opt/oracle/oradata` em Azure Files (SMB)** — o DBCA chegava a criar os
   datafiles com sucesso (control01.ctl/control02.ctl de 18MB cada, vistos de verdade no file
   share), mas a instância entrava em crash loop logo depois
   (`ORA-00205`/`ORA-00210: cannot open control file`). Confirmado contra a fonte:
   `gvenzl/oci-oracle-xe#191`, fechada como "invalid" pelo mantenedor — volume de rede pra
   `oradata` não é suportado, ponto (SMB não dá o locking/`O_DIRECT` que o Oracle exige).
   Fix: `oradata` volta a ser filesystem local do container (mesmo padrão do `docker-compose.yml`
   original, que já usava volume Docker local, nunca de rede); a persistência em Storage Account
   exigida pela rubrica passou a ser um **snapshot pós-boot** copiado via `az container exec`
   pra um SEGUNDO volume Azure Files (`/mnt/kura-backup`) — cópia sequencial, não E/S ao vivo,
   por isso funciona sobre SMB. Commit `3d43358`. **Esse passo de backup nunca chegou a rodar de
   verdade ainda**, porque o Oracle nunca ficou saudável depois dessa mudança (achado #4 abaixo
   apareceu em seguida).
4. **Oracle em crash loop no ACI mesmo com `oradata` local** —
   `ORA-01081: cannot start already-running ORACLE - shut it down first`, sempre depois do
   listener subir, `ExitCode 204` sempre. A MESMA imagem funciona perfeitamente no Docker Desktop
   local (`DATABASE IS READY TO USE!`, sem erro). Isolado por teste direto, não suposição: o ACI
   expõe **cgroup v1** (`/sys/fs/cgroup/memory/memory.limit_in_bytes` existe,
   `/sys/fs/cgroup/memory.max` NÃO existe); o Docker Desktop local usa **cgroup v2** unificado
   (`/sys/fs/cgroup/memory.max` = `"max"`). O `container-entrypoint.sh` da imagem `gvenzl/oracle-xe`
   lê o caminho v2 — bate com a issue pública `gvenzl/oci-oracle-xe#142` ("linha 293:
   `/sys/fs/cgroup/memory.max: No such file or directory`"). Bump de recursos (até 4 vCPU/8GB) e
   troca de imagem pra `gvenzl/oracle-free` **não foram necessários nem testados até o fim** —
   o diagnóstico do cgroup veio antes.
5. **Fix do #4, em 3 iterações porque a primeira e a segunda tentativa também quebraram, e cada
   quebra tinha uma causa real e nova**:
   - `db/cgroup-v1-shim-entrypoint.sh` (novo arquivo): roda como root, cria
     `/sys/fs/cgroup/memory.max`/`cpu.max` a partir dos valores reais de cgroup v1 SE o caminho v2
     não existir (no-op completo em host com cgroup v2 — confirmado local antes E depois do fix).
   - Precisa trocar de usuário pra `oracle` (uid 54321) antes de entregar o processo pro
     entrypoint real. **`su` e `gosu` não existem nesta imagem "slim"** — descoberto rodando local
     (`exec: su: not found`, exit 127). Fix: `chroot --userspec=UID:GID / ...` (GNU coreutils,
     confirmado presente).
   - `--userspec=oracle:oracle` falhou com `"invalid group"` — o grupo primário do usuário
     `oracle` (uid 54321) se chama **`oinstall`** (gid 54321), não `oracle`. Fix: userspec
     numérico (`54321:54321`), com `--groups=` listando os grupos suplementares reais (dba,
     oper, backupdba, dgdba, kmdba, racdba — todos vistos com `id oracle` dentro da imagem).
   - `chroot` reseta o `cwd` pra `/` do novo root mesmo quando o novo root é o mesmo `/` de
     sempre — `container-entrypoint.sh` usa caminho relativo (`./createAppUser`) e precisa do
     `cwd` = `/opt/oracle` (o `WORKDIR` da imagem base, confirmado com `docker inspect`). Fix:
     `chroot ... sh -c 'cd /opt/oracle && exec container-entrypoint.sh'`.
   - **Confirmado local, com os 3 sub-fixes juntos**: `DATABASE IS READY TO USE!`, container fica
     `running`, sem erro. Commit `a273da3`.

## 3. O que NÃO está confirmado — é exatamente aqui que a sessão 2 começa

O fix do item 5 foi buildado, publicado no ACR (`docker push ... :latest`, digest
`sha256:10cbc7a2a4...`), e o ACI do Oracle foi recriado com ele **ao vivo, no Azure real**. O
resultado até o momento em que a sessão precisou parar:

- `restartCount` chegou a **0** bem mais longe no boot do que qualquer tentativa anterior — as
  tentativas 1–4 (achados #3 e #4 acima) sempre crashavam quase imediatamente após o listener
  subir; desta vez o container passou por "uncompressing database data files... done" sem crash
  e ficou `state: Running` por um tempo visivelmente maior. **É evidência forte de que o fix
  ajudou.**
- Mas `restartCount` **incrementou pra 1** antes da sessão terminar. **O log desse crash
  específico não foi capturado** (a checagem seguinte já mostrou `az container logs` vazio —
  buffer limpo pro próximo restart, mesmo padrão de antes).
- Ou seja: **não dá pra afirmar que o problema #4 está 100% resolvido.** Pode ser: (a) o mesmo
  `ORA-01081` ainda acontecendo, só que mais tarde no boot (progresso parcial, não solução
  completa); (b) um problema novo e diferente, só visível depois que o #4 parou de bloquear cedo;
  (c) um crash isolado sem relação com os anteriores (menos provável, mas não descartado).

**Primeiro passo da sessão 2, antes de qualquer outra coisa**: capturar o log do restart
ATUAL/PRÓXIMO com `az container logs --name rm562999-kura-oracle-db --resource-group
rm562999-kura-cp4-rg` — se necessário, rodar em loop curto (a cada 10-15s) pra pegar o log antes
dele ser limpo pelo próximo restart. Ver o prompt de continuidade pro comando exato.

## 4. O que ainda falta, além de confirmar o Oracle saudável

1. Confirmar Oracle 100% saudável (porta 1521 respondendo de fora, `verify.sh` ou equivalente).
2. Rodar o passo de backup real (`az container exec ... cp -a /opt/oracle/oradata/.
   /mnt/kura-backup/oradata-snapshot/`) — já está no `deploy.sh` (achado #3), nunca testado
   porque o Oracle nunca chegou saudável.
3. Subir o ACI do `.NET` (núcleo exigido pela rubrica — nunca chegou a ser criado nesta sessão).
4. Subir o ACI do Java bônus (`DEPLOY_JAVA_BONUS=true` já está no `.env`) — é ele quem aplica o
   Flyway e cria o schema real que o `.NET` precisa pra funcionar.
5. Rodar `azure/verify.sh` fim a fim.
6. Rodar `tests/smoke-cp4.sh` contra o ambiente real, capturar o `SELECT` de prova.
7. Gravar o vídeo (`docs/ROTEIRO-VIDEO.md` já pronto).
8. `azure/teardown.sh` no final.

## 5. Coisas que a sessão 2 NÃO precisa refazer

- Não questionar de novo a escolha `.NET` + Oracle + Java bônus — decisão já validada com o
  Felipe, documentada no `README.md` e nos artifacts publicados.
- Não tentar de novo Azure Files pra `oradata` — já provado que não funciona (achado #3), fonte
  citada.
- Não gastar tempo comparando `oracle-xe` vs `oracle-free` — o diagnóstico correto (cgroup v1)
  veio antes de precisar trocar de imagem; `oracle-xe:21-slim` com o shim deve bastar. Só
  considerar `oracle-free` se o shim se provar insuficiente por um motivo NOVO e diferente do
  cgroup (documentar esse motivo antes de trocar).
- Não repetir os testes de `docker build` local do banco/`.NET`/Java sem o fix de User-Agent —
  já resolvido (achado #1), está commitado.
