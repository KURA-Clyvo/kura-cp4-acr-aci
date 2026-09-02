# Payloads de exemplo — CP4 (ACR/ACI)

Corpo de requisição de cada chamada do fluxo de demonstração, extraído **literalmente** dos DTOs
e FluentValidation validators de `backend-clinica-dotnet` (não inventado). Fonte de cada campo,
arquivo a arquivo, abaixo da tabela.

Estes arquivos são a **referência canônica** de shape/campo — úteis para `curl -d @arquivo.json`
manual durante a gravação, se preciso repetir uma chamada isolada. O script `../smoke-cp4.sh`
**não lê estes arquivos diretamente**: ele gera os próprios payloads em memória (mesmo shape,
mesmos campos), porque dois passos do fluxo real dependem de dado que só existe em tempo de
execução — o e-mail/CNPJ precisam ser únicos a cada rodada (a clínica não pode colidir com uma já
cadastrada) e o `idTutor` do `06-pet-post.json` só existe depois que o POST de tutor (passo 5)
responde. Os valores abaixo (`12.345.678/0001-99`, `idTutor: 1` etc.) são ilustrativos — o script
substitui por dado gerado/capturado a cada execução.

| Arquivo | Endpoint / verbo | Auth | Observação |
|---|---|---|---|
| `01-register-clinica.json` | `POST /api/v1/auth/register-clinica` | nenhuma (`AllowAnonymous`) | Cadastro self-service da clínica + veterinário admin (`GESTOR`). Devolve `201` com `accessToken` já utilizável, mas o fluxo de demo faz login separado no passo 2 para provar o par email/senha de forma independente. |
| `02-login.json` | `POST /api/v1/auth/login` | nenhuma | Usa o mesmo par `dsEmailAcesso`/`dsSenha` do passo 1. Devolve `accessToken`, usado como `Authorization: Bearer` em todas as chamadas seguintes. |
| `03-veterinario-post.json` | `POST /api/v1/veterinarios` | Bearer | Cria um segundo veterinário na clínica autenticada. `idClinica` **É** campo obrigatório do DTO e precisa ser `> 0` — corrigido na sessão 2. Uma versão anterior deste README afirmava o contrário ("vem do JWT"), e o payload sem o campo fazia a API responder `400` com `{"errors":{"IdClinica":["'Id Clinica' must be greater than '0'."]}}` — confirmado rodando contra o ACI real. Fonte: `VeterinarioCreateDto.cs` (`public long IdClinica`) e `VeterinarioCreateValidator.cs` (`RuleFor(x => x.IdClinica).GreaterThan(0)`). No fluxo do `smoke-cp4.sh` o valor vem do `idClinica` devolvido pelo passo 1. **O `1` gravado no arquivo é ILUSTRATIVO** — usá-lo direto num `curl` manual dá `500` com `ORA-02291: integrity constraint (RM566315.FK_VET_CLINICA) violated - parent key not found`, porque nao existe clinica com esse id (a sequence do Oracle comeca bem acima de 1). Troque pelo id real da sua clinica antes de usar. |
| `04-veterinario-put.json` | `PUT /api/v1/veterinarios/{id}` | Bearer | Atualiza o veterinário criado no passo 3. Mesmo shape do POST (não há DTO de patch parcial). |
| `05-tutor-post.json` | `POST /api/v1/tutores` | Bearer | **Pré-requisito da entidade Pet**, não uma das "duas entidades" do CRUD em si — `Pet` exige `idTutor` de um tutor já existente (`PetsController.Create`: "vinculado a um tutor existente"). Cria o tutor e dispara (em modo real) um invite de onboarding; isso não afeta o teste. |
| `06-pet-post.json` | `POST /api/v1/pets` | Bearer | `idEspecie: 1` e `idRaca: 1` vêm do catálogo de referência semeado por `V14__seed_referencia.sql` (backend-tutor-java) — `1` = espécie "Cao", `1` = raça "Labrador" (`ID_ESPECIE=1`). `idTutor` deve ser o `id` devolvido pelo passo 5 (aqui está como `1` só de exemplo). |
| `07-pet-put.json` | `PUT /api/v1/pets/{id}` | Bearer | Atualiza o pet criado no passo 6. `PetUpdateDto` tem shape menor que o `PetCreateDto` — sem `idEspecie`/`idRaca`/`idTutor`/`dsVinculo` (não são editáveis por este endpoint). |

## GET e DELETE não precisam de body

Nenhum arquivo `.json` foi criado para as chamadas `GET /api/v1/veterinarios`,
`GET /api/v1/veterinarios/{id}`, `DELETE /api/v1/veterinarios/{id}`, `GET /api/v1/pets`,
`GET /api/v1/pets/{id}` e `DELETE /api/v1/pets/{id}` — são requisições sem corpo. Um JSON vazio
(`{}`) não corresponde a nada que a API espera e só acrescentaria ruído; o `smoke-cp4.sh` chama
esses verbos sem `-d`/`--data-binary`, como o HTTP exige.

## Origem de cada campo, arquivo a arquivo

- **`01-register-clinica.json`**: `Kura.Application/DTOs/Auth/RegisterClinicaDto.cs` +
  `Kura.Application/Validators/RegisterClinicaValidator.cs`.
  - `nrCnpj` precisa bater o regex `^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$` (formatado, com pontuação).
    O validator **não** confere dígito verificador — é só formato. O valor usado aqui
    (`12.345.678/0001-99`) é reaproveitado da própria suíte de testes do repo
    (`tests/Kura.Application.Tests/AuthServiceTests.cs`), então é sabidamente aceito pelo
    validator.
  - `dsSenha` exige mínimo 8 caracteres (`MinimumLength(8)`).
  - `nmRazaoSocial` e `nrTelefone` são os únicos campos opcionais do DTO (`string?`); os demais
    são `NotEmpty()`.
- **`02-login.json`**: `Kura.Application/DTOs/Auth/LoginDto.cs` (sem validator próprio — só
  `dsEmail`/`dsSenha`, sem regra de formato adicional além do que o `AuthService` compara contra
  o hash salvo).
- **`03-veterinario-post.json`** / **`04-veterinario-put.json`**:
  `Kura.Application/DTOs/Veterinario/VeterinarioCreateDto.cs` /
  `VeterinarioUpdateDto.cs` + `VeterinarioCreateValidator.cs` / `VeterinarioUpdateValidator.cs`.
  `nmVeterinario` (máx. 200), `nrCrmv` (máx. 20) e `dsEmail` (máx. 150) são `NotEmpty()`;
  `nrTelefone` está no DTO mas **sem** regra de validação (documentado assim no próprio
  validator — nenhuma `RuleFor` sobre o campo).
- **`03`/`04` e o campo `idClinica`**: só o DTO de veterinário tem esse campo. `TutorCreateDto` e `PetCreateDto` **não** têm — nesses a clínica vem do JWT. Conferido nos três DTOs, para ninguém generalizar a correção acima para os outros payloads.
- **`05-tutor-post.json`**: `Kura.Application/DTOs/Tutor/TutorCreateDto.cs` +
  `TutorCreateValidator.cs`. `nrCpf` precisa ter exatamente 11 dígitos numéricos
  (`Length(11)` + regex `^[0-9]{11}$`, sem checagem de dígito verificador). `dsCanalConvite`
  aceita só `WHATSAPP`, `EMAIL` ou `SMS`.
- **`06-pet-post.json`** / **`07-pet-put.json`**: `Kura.Application/DTOs/Pet/PetCreateDto.cs` /
  `PetUpdateDto.cs` + `PetCreateValidator.cs` / `PetUpdateValidator.cs`. `sgSexo` só aceita
  `M`/`F`; `sgPorte` só aceita `P`/`M`/`G`; `dtNascimento` não pode ser data futura
  (`LessThanOrEqualTo(DateTime.UtcNow)`); `idEspecie`/`idRaca` precisam ser `> 0` e existir na
  tabela de referência (senão `404`/erro de FK).

## Limitação documentada: por que Pet, e não Medicamento/ServicoPreco

O brief permitia trocar `PetsController` por uma entidade mais simples (`Medicamentos`,
`ServicosPreco`) caso `Pet` só pudesse ser criado via convite/onboarding do lado Java. **Isso não
foi necessário**: `POST /api/v1/tutores` (`TutoresController.cs`) já cria o `Tutor` no lado
`.NET`, autenticado pelo mesmo JWT de clínica — o convite de onboarding é disparado **como
efeito colateral**, não como pré-condição. Por isso a demo usa `Veterinarios` + `Pets`
(com `Tutores` como setup de uma linha), sem tocar `backend-tutor-java`.
