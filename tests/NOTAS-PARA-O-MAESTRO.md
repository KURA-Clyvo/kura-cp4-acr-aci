# Notas para o maestro — CP4 (ACR/ACI)

Resumo das suposições e limitações encontradas ao montar `tests/` para o checkpoint CP4. Nada
aqui editou os repositórios-fonte — só leitura.

## 1. Pet NÃO exigiu trocar de entidade

O brief previa a possibilidade de `PetsController` só aceitar tutor via convite/onboarding do
lado Java, o que forçaria trocar a segunda entidade por `Medicamentos` ou `ServicosPreco`. Isso
**não aconteceu**: `POST /api/v1/tutores` (`TutoresController.cs:100-110`) já cria o `Tutor`
inteiramente do lado `.NET`, autenticado pelo mesmo JWT de clínica usado no resto do fluxo — o
invite de onboarding (`TutorComInviteResponseDto.Invite`) é gerado como efeito colateral da
criação, não como pré-condição dela. Por isso a demo usa **Veterinário + Pet**, com **Tutor como
setup de uma chamada** (não conta como uma das "duas entidades" com CRUD completo — só POST é
exercitado nele).

## 2. `idEspecie`/`idRaca` do Pet dependem do catálogo de referência já estar semeado

`PetCreateDto.IdEspecie`/`IdRaca` são FKs para `ESPECIE`/`RACA`. Esse catálogo **não nasce
automaticamente** com o schema — é semeado por `V14__seed_referencia.sql`
(`backend-tutor-java/src/main/resources/db/migration/V14__seed_referencia.sql`), que roda nos
dois profiles (`dev` e `prod`) desde a TASK-37 do ecossistema. Os IDs usados nos payloads
(`idEspecie: 1` = "Cao", `idRaca: 1` = "Labrador") vêm **diretamente do texto dessa migration**,
não de suposição. **Se o ACI subir com uma imagem do `backend-tutor-java` anterior à TASK-37, ou
se alguém rodar `flyway clean`/apontar para um schema que pulou essa migration, o `POST /pets`
vai falhar** (FK inexistente ou, na pior hipótese, `404`/erro de validação de referência) — não é
bug do script, é dado de catálogo ausente. Confirmar `SELECT COUNT(*) FROM RM562999.ESPECIE`
antes de rodar o passo 9, se a demonstração usar um ambiente que não seja o compose/imagem
padrão deste ecossistema.

## 3. CNPJ e CPF: validação é só de FORMATO, não de dígito verificador

- `RegisterClinicaValidator.NrCnpj`: regex `^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$`. **Não** calcula
  dígito verificador.
- `TutorCreateValidator.NrCpf`: `Length(11)` + regex `^[0-9]{11}$`. **Não** calcula dígito
  verificador.

Ainda assim, `smoke-cp4.sh` gera CNPJ/CPF com dígito verificador **real** (algoritmo módulo 11
padrão), pelo mesmo motivo que `DevOps-Cloud/scripts/smoke-contratos.sh` já faz isso: é mais
robusto (não depende de o validator nunca ganhar checagem de dígito no futuro) e mais realista
para uma gravação de demonstração. Os arquivos estáticos em `json/` usam valores fixos
(`12.345.678/0001-99`, reaproveitado da própria suíte de testes C# do repo;
`52998224725` para CPF) — servem só de referência de shape, não são o que o script de fato
envia.

## 4. `register-clinica` já devolve um `accessToken` — login é redundante, mas deliberado

`RegisterClinicaResponseDto` já inclui `accessToken`/`expiresAt` — tecnicamente dava para pular o
login e usar esse token direto. O fluxo pedido no brief (`register → login → CRUD`) foi mantido
literalmente: o script chama `POST /auth/login` com o mesmo par `dsEmailAcesso`/`dsSenha` do
registro e usa **o token do login**, não o do registro, para o restante das chamadas — prova
independente de que a credencial de acesso funciona via login, e não só no momento do cadastro
(mesmo padrão do teste `Registro_de_clinica_seguido_de_login_funciona_como_no_seed_demo` em
`tests/Kura.IntegrationTests/AutenticacaoHttpTests.cs` do próprio repo).

## 5. Ordem das chamadas de CRUD por entidade

Para poder testar `DELETE` (soft delete) sem invalidar as chamadas de leitura anteriores, a ordem
usada é **POST → GET por id → GET lista → PUT → DELETE**, não a ordem em que os arquivos `json/`
estão numerados na tabela do README (que segue a ordem "didática" GET/GET/POST/PUT/DELETE pedida
no brief). `smoke-cp4.sh` documenta essa ordem passo a passo nos comentários.

## 6. Porta/host do Oracle no ACI — não confirmado nesta sessão

As instruções de `sqlplus`/`sqlcl` impressas ao final de `smoke-cp4.sh` usam placeholders
(`<IP-OU-FQDN-DO-ACI>`, `<PORTA_ORACLE>`, `<SENHA_ORACLE_APP>`) porque **não há um ACI real
provisionado para conferir a porta publicada de fato**. No `docker-compose.yml` local do
`DevOps-Cloud`, o Oracle é publicado como `9092:1521` (host:container) — mas o YAML de deploy do
grupo de containers no ACI pode mapear diferente. Confirmar a porta real no `az container show`
(ou no YAML de deploy usado) antes da gravação, e substituir os placeholders.

## 7. Nenhuma credencial real foi usada

Senha da clínica (`Senha@CP4-<sufixo>`), CNPJ e CPF gerados são fictícios/sintéticos, gerados a
cada execução. A senha do Oracle (`ORACLE_APP_PASSWORD`) e o host/porta reais do ACI **não**
aparecem em nenhum arquivo deste pacote — ficam como placeholder para quem for gravar preencher
na hora, fora de qualquer arquivo versionável.
