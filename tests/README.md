# Testes CP4 — Imagem e Containers em Nuvem (ACR/ACI)

Artefatos de teste para o checkpoint CP4 da FIAP, validando a API `.NET` da clínica veterinária
(`backend-clinica-dotnet`, porta 8080, contexto B2B) rodando como imagem publicada no **Azure
Container Registry (ACR)** e executada em **Azure Container Instance (ACI)**.

Este diretório é **só de testes** — nenhum arquivo aqui edita os repositórios-fonte
(`C:\Users\labsfiap\backend-clinica-dotnet`, `backend-tutor-java`, `DevOps-Cloud`), que foram
apenas **lidos** para extrair os contratos reais (DTOs + FluentValidation validators) usados
nos payloads.

## O que este pacote prova

1. **Cadastro self-service de clínica** — `POST /api/v1/auth/register-clinica`, sem precisar de
   dado pré-existente no banco (endpoint público, `[AllowAnonymous]`).
2. **Login** — `POST /api/v1/auth/login`, devolve um JWT.
3. **CRUD completo (GET lista, GET por id, POST, PUT, DELETE) em DUAS entidades**, autenticado
   pelo JWT do passo 2:
   - `Veterinario` (`VeterinariosController`)
   - `Pet` (`PetsController`), com criação de `Tutor` (`TutoresController`) como
     pré-requisito de uma linha — ver `json/README.md`, seção "Limitação documentada", para o
     porquê disso não exigir trocar de entidade.

## Estrutura

```
tests/
  json/                    payloads de exemplo, um por chamada — ver json/README.md
  smoke-cp4.sh             script que executa o fluxo completo contra um BASE_URL informado
  README.md                este arquivo
  NOTAS-PARA-O-MAESTRO.md  suposições e limitações encontradas durante o levantamento
```

## Como rodar

```bash
BASE_URL=http://<ip-ou-fqdn-do-aci>:8080 ./smoke-cp4.sh
```

- `BASE_URL` é **obrigatório** — o script recusa rodar sem ele (nunca assume `localhost`; o
  objetivo é provar a API rodando de fato no ACI, não num ambiente local).
- Requer `bash`, `curl` e `python` ou `python3` no PATH. **Não usa `jq`** — o ecossistema KURA já
  estabeleceu esse padrão (ver `DevOps-Cloud/scripts/smoke-contratos.sh`) porque `jq` pode não
  estar instalado por padrão no ambiente de gravação.
- Cada chamada verifica o HTTP status code **explicitamente** (`curl -w '%{http_code}'`) e o
  script **para imediatamente** (`exit 1`) na primeira divergência — sinal de pass/fail
  inequívoco para a gravação do vídeo, em vez de confiar em exit code de pipe.
- O script gera CNPJ, CPF, e-mails e senha **únicos a cada execução** (sufixo por timestamp +
  `$RANDOM`), então pode ser rodado várias vezes seguidas sem colidir com uma clínica já
  cadastrada.
- Ao final, o script **imprime** (não executa) o comando `sqlplus`/`sqlcl` pronto para copiar e
  colar contra o Oracle do ACI, com os IDs reais criados nesta execução — é o `SELECT` de prova
  pedido pela rubrica. Ver a seção correspondente no output do script.

## Por que Veterinário + Pet, e não Medicamento/ServicoPreco

O brief original previa trocar `Pet` por uma entidade mais simples caso `Pet` só pudesse ser
criado via fluxo de convite/onboarding do lado Java (`backend-tutor-java`). Isso **não foi
necessário**: `POST /api/v1/tutores` no próprio `.NET` já cria o `Tutor`, autenticado pelo mesmo
JWT de clínica — o convite é disparado como efeito colateral, não como pré-condição. Detalhe
completo em `json/README.md` e em `NOTAS-PARA-O-MAESTRO.md`.

## Fonte dos contratos

Todo campo, tipo, tamanho máximo e formato usado nos payloads foi extraído lendo, no repositório
`backend-clinica-dotnet`:

- Controllers: `src/Kura.Api/Controllers/AuthController.cs`, `VeterinariosController.cs`,
  `PetsController.cs`, `TutoresController.cs`.
- DTOs: `src/Kura.Application/DTOs/Auth/*`, `DTOs/Veterinario/*`, `DTOs/Pet/*`, `DTOs/Tutor/*`.
- Validators (FluentValidation): `src/Kura.Application/Validators/RegisterClinicaValidator.cs`,
  `VeterinarioCreateValidator.cs`, `VeterinarioUpdateValidator.cs`, `PetCreateValidator.cs`,
  `PetUpdateValidator.cs`, `TutorCreateValidator.cs`.
- Catálogo de referência (`idEspecie`/`idRaca` do Pet): `V14__seed_referencia.sql`, em
  `backend-tutor-java` (Flyway é a única autoridade de DDL neste ecossistema, mesmo para tabelas
  `.NET`-owned).
- Mapeamento tabela/coluna (para o `SELECT` de prova): `src/Kura.Infrastructure/Persistence/
  Configurations/{Clinica,Veterinario,Pet,Tutor}Configuration.cs`.

Nenhum campo foi inventado; nenhuma credencial real foi usada (senhas de exemplo óbvias, geradas
com sufixo por execução).
