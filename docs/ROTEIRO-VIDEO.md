# Roteiro do vídeo de demonstração — CP4 ACR/ACI

Regras da rubrica que valem para este vídeo, não negociáveis:

- **Mínimo 720p**, áudio claro, **narrado por voz** (não é só tela + música).
- **Começa mostrando os recursos criados na Azure** (Portal ou `az` CLI — pode ser
  qualquer um dos dois, mas mostre de forma que dê para ler os nomes com prefixo RM562999).
- **Demonstração individual e detalhada de cada operação de CRUD**, com o `SELECT`
  correspondente no banco logo em seguida — não é aceitável mostrar só a chamada HTTP
  e dizer "funcionou", tem que aparecer a linha no banco.
- É a **prova entregue** — se não estiver no vídeo, não aconteceu para efeito de nota.

## Estrutura sugerida (~8–12 min)

### 1. Abertura (30s)
"Grupo 3, CP4 de DevOps Tools & Cloud Computing, projeto DimDim — vamos containerizar
a API de clínica veterinária do nosso projeto KURA em ACR/ACI."

### 2. Recursos na Azure (1-2 min) — OBRIGATÓRIO SER O PRIMEIRO BLOCO TÉCNICO
Mostrar, no Portal Azure ou via `az` CLI:
- Resource Group `rm562999-kura-cp4-rg`
- ACR `rm562999kuraacr` com as 2 imagens (`rm562999/kura-oracle-db`, `rm562999/kura-clinica-api`)
- Os 2 (ou 3, com o bônus) Container Instances, prefixo `rm562999-kura-*`
- Storage Account `rm562999kurastorage` + o File Share `kura-oracle-data`

Comando rápido para mostrar tudo de uma vez, se preferir CLI a Portal:
```bash
az resource list --resource-group rm562999-kura-cp4-rg -o table
```

### 3. Dockerfiles e comandos de build/push (1 min)
Abrir `db/Dockerfile` e `app-dotnet/Dockerfile` no editor, explicar rapidamente (banco =
imagem oficial pinada, app = multi-stage build .NET, non-root nos dois). Mostrar no
terminal os comandos reais que rodaram (podem ser colados do histórico, já executados
antes da gravação — não precisa rebuildar ao vivo, é lento):
```bash
docker build -f app-dotnet/Dockerfile -t rm562999kuraacr.azurecr.io/rm562999/kura-clinica-api:latest ../backend-clinica-dotnet
docker push rm562999kuraacr.azurecr.io/rm562999/kura-clinica-api:latest
```

### 4. Fluxo de autenticação (1 min)
- `POST /api/v1/auth/register-clinica` com `tests/json/01-register-clinica.json` — mostrar
  o corpo da resposta (clínica criada).
- `POST /api/v1/auth/login` com `tests/json/02-login.json` — mostrar o JWT recebido.
- Explicar em uma frase: "não usamos convite/token aqui porque é a clínica se
  autocadastrando — o fluxo com token de convite é do lado do app do tutor, fora do
  escopo deste container."

### 5. CRUD #1 — Veterinário (2-3 min, o coração do vídeo)
Para CADA operação, mostrar a chamada E o SELECT correspondente, sem pular nenhuma:
1. `POST /api/v1/veterinarios` → `SELECT * FROM VETERINARIO WHERE ID_VETERINARIO = <id>;`
2. `GET /api/v1/veterinarios/{id}` → aparece na tela o mesmo dado
3. `GET /api/v1/veterinarios` → lista com o novo registro
4. `PUT /api/v1/veterinarios/{id}` → `SELECT` de novo, mostrando o campo alterado
5. `DELETE /api/v1/veterinarios/{id}` → `SELECT` mostrando `ST_ATIVO = 'N'` (soft delete,
   nunca DELETE físico — é uma decisão de arquitetura do projeto, vale explicar em 1 frase)

### 6. CRUD #2 — Tutor + Pet (2-3 min)
Mesma lógica: `POST /tutores` (setup, 1 chamada) → depois o CRUD completo de Pet
(POST/GET/GET-lista/PUT/DELETE), cada um com `SELECT` na tela.

### 7. Fechamento (30s)
Reforçar: 2 ACIs exigidos pela rubrica (Oracle + .NET) provados de pé, persistência real
em Storage Account, e — se o bônus estiver ligado — mencionar em uma frase que o backend
Java também está no ar, aplicando o schema real via Flyway, como ponte para o Challenge.

## Comando pronto para o SELECT (preencher host/porta reais do ACI antes de gravar)

```bash
sqlplus RM562999/<ORACLE_APP_PASSWORD>@<FQDN-do-ACI-oracle>:1521/XEPDB1
SQL> SELECT id_veterinario, nm_veterinario, st_ativo FROM veterinario ORDER BY id_veterinario DESC FETCH FIRST 5 ROWS ONLY;
SQL> SELECT id_pet, nm_pet, st_ativo FROM pet ORDER BY id_pet DESC FETCH FIRST 5 ROWS ONLY;
```
(`tests/smoke-cp4.sh` imprime esse comando já com o `WHERE` filtrado pelo ID exato criado
na execução — mais fácil de narrar ao vivo do que digitar na hora.)

## Checklist antes de gravar

- [ ] `./azure/verify.sh` passou (núcleo saudável)
- [ ] `tests/smoke-cp4.sh` rodou sem erro contra o ambiente real
- [ ] Câmera/gravador de tela configurado em 720p+ com áudio testado
- [ ] Terminal com fonte grande o bastante para ler na gravação
- [ ] Portal Azure aberto na aba do Resource Group, pronto para o bloco 2
