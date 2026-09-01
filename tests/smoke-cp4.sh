#!/usr/bin/env bash
# =============================================================================
# smoke-cp4.sh — CP4 (Imagem e Containers em Nuvem, ACR/ACI): fluxo de prova
# ponta a ponta contra a API .NET da clinica veterinaria (backend-clinica-dotnet,
# porta 8080), rodando dentro de um Azure Container Instance.
#
# Fluxo: cadastro self-service de clinica -> login -> CRUD completo (GET lista,
# GET por id, POST, PUT, DELETE) em DUAS entidades (Veterinario e Pet), com
# criacao de Tutor como pre-requisito de Pet (ver tests/json/README.md, secao
# "Limitacao documentada").
#
# Uso:
#   BASE_URL=http://<ip-ou-fqdn-do-aci>:8080 ./smoke-cp4.sh
#
# NUNCA roda contra localhost por padrao — BASE_URL e OBRIGATORIO (ver bloco
# abaixo). E deliberado: este script existe para provar a API rodando no ACI,
# nao um ambiente local.
#
# Pre-requisitos:
#   - bash, curl no PATH
#   - python (ou python3) no PATH — usado so para extrair campos de JSON e
#     gerar CPF/CNPJ validos (formato). SEM dependencia de jq — pode nao estar
#     instalado no ambiente de gravacao. Ver "campo()" e "gerar_cnpj()"/
#     "gerar_cpf()" abaixo.
#
# Padrao de sentinela de sucesso (mesmo espirito de scripts/smoke-contratos.sh
# do DevOps-Cloud): cada chamada verifica o HTTP status code EXPLICITAMENTE
# via `curl -w '%{http_code}'`, nunca confia no exit code do curl nem de
# qualquer pipe — e falha alto (`exit 1`) na primeira divergencia, para dar um
# sinal de pass/fail inequivoco durante a gravacao do video.
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# ─── BASE_URL obrigatorio, sem default localhost ────────────────────────────
if [ -z "${BASE_URL:-}" ]; then
  echo "erro: defina BASE_URL com o endereco do ACI, ex.:" >&2
  echo "  BASE_URL=http://<ip-ou-fqdn-do-aci>:8080 ./smoke-cp4.sh" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"  # remove barra final, se houver

PY=python
command -v python >/dev/null 2>&1 || PY=python3
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "erro: nem 'python' nem 'python3' foram encontrados no PATH (necessario para parse de JSON — sem jq)." >&2
  exit 2
fi

BODY_FILE=$(mktemp)
PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE" "$PAYLOAD_FILE"' EXIT

# ─── helpers ─────────────────────────────────────────────────────────────────

# chamar <nome> <esperado> <metodo> <url> [payload] [token]
# Imprime a requisicao e a resposta de forma legivel; corpo por ARQUIVO
# (--data-binary @arquivo), nunca por argumento de linha de comando — evita a
# corrupcao de UTF-8 que o MSYS/Git Bash do Windows causa ao converter
# argumento para curl.exe nativo (achado real do FIX_7 deste ecossistema).
chamar() {
  local nome=$1 esperado=$2 metodo=$3 url=$4 payload=${5:-} token=${6:-}
  echo
  echo ">>> $nome"
  echo "    $metodo $url"
  local args=(-s -o "$BODY_FILE" -w '%{http_code}' -X "$metodo" "$url")
  if [ -n "$payload" ]; then
    printf '%s' "$payload" > "$PAYLOAD_FILE"
    echo "    payload: $payload"
    args+=(-H 'Content-Type: application/json' --data-binary "@$PAYLOAD_FILE")
  fi
  if [ -n "$token" ]; then
    args+=(-H "Authorization: Bearer $token")
  fi
  local code
  code=$(curl "${args[@]}")
  echo "    resposta HTTP $code:"
  sed 's/^/    /' "$BODY_FILE" 2>/dev/null || true
  echo
  # sentinela de sucesso: status HTTP explicito, exit alto na primeira falha
  if [ "$code" != "$esperado" ]; then
    echo "FALHA: $nome — esperado HTTP $esperado, obtido HTTP $code" >&2
    exit 1
  fi
  echo "ok: $nome ($code)"
}

# campo <caminho.pontilhado> — le do ultimo BODY_FILE gravado por chamar().
# Segmentos so-digitos indexam listas (ex.: "0.id").
campo() {
  "$PY" -c '
import json, sys
with open(sys.argv[2], "r", encoding="utf-8") as f:
    data = json.load(f)
cur = data
for p in sys.argv[1].split("."):
    cur = cur[int(p)] if p.isdigit() else cur[p]
sys.stdout.write(str(cur))
' "$1" "$BODY_FILE"
}

# CPF valido (11 digitos, sem formatacao), digito verificador real (modulo 11).
# TutorCreateValidator so exige o formato (11 digitos numericos) — o calculo
# do digito real e so para nao depender de um valor fixo que colida entre
# execucoes/tutores.
gerar_cpf() {
  "$PY" -c '
import random
rnd = random.SystemRandom()
def dv(nums):
    s = sum(n * w for n, w in zip(nums, range(len(nums) + 1, 1, -1)))
    r = s % 11
    return 0 if r < 2 else 11 - r
base = [rnd.randint(0, 9) for _ in range(9)]
d1 = dv(base)
d2 = dv(base + [d1])
print("".join(map(str, base + [d1, d2])))
'
}

# CNPJ valido e FORMATADO (00.000.000/0000-00) — RegisterClinicaValidator
# exige esse formato exato via regex. Filial fixa "0001", raiz aleatoria de 8
# digitos, 2 digitos verificadores reais (modulo 11) para nao depender de um
# CNPJ fixo que colidiria (clinica ja cadastrada) numa segunda execucao.
gerar_cnpj() {
  "$PY" -c '
import random
rnd = random.SystemRandom()
def dv(nums, weights):
    s = sum(n * w for n, w in zip(nums, weights))
    r = s % 11
    return 0 if r < 2 else 11 - r
base = [rnd.randint(0, 9) for _ in range(8)] + [0, 0, 0, 1]
w1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
w2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
d1 = dv(base, w1)
d2 = dv(base + [d1], w2)
s = "".join(map(str, base + [d1, d2]))
print(f"{s[0:2]}.{s[2:5]}.{s[5:8]}/{s[8:12]}-{s[12:14]}")
'
}

# ─── dados unicos desta execucao (nunca hardcoded, para o script ser repetivel) ──
SUFIXO="$(( $(date +%s) % 1000000 ))${RANDOM}"
CNPJ_CLINICA=$(gerar_cnpj)
CPF_TUTOR=$(gerar_cpf)
EMAIL_ACESSO="gestor.cp4-$SUFIXO@clinicacp4.test"
SENHA="Senha@CP4-$SUFIXO"

echo "=============================================================="
echo " smoke-cp4.sh — CP4 ACR/ACI — sufixo desta execucao: $SUFIXO"
echo " BASE_URL: $BASE_URL"
echo "=============================================================="

# ─── 1. Cadastro self-service da clinica (POST /api/v1/auth/register-clinica) ──
# Campos e formatos: ver tests/json/01-register-clinica.json e
# tests/json/README.md ("Origem de cada campo").
PAYLOAD_REGISTER=$(cat <<JSON
{
  "nmClinica": "Clinica Veterinaria CP4 $SUFIXO",
  "nrCnpj": "$CNPJ_CLINICA",
  "nmRazaoSocial": "Clinica Veterinaria CP4 $SUFIXO Ltda",
  "dsEndereco": "Rua das Palmeiras, 456",
  "nmCidade": "Sao Paulo",
  "sgUf": "SP",
  "nrCep": "01310-100",
  "nrTelefone": "11987654321",
  "dsEmail": "contato-$SUFIXO@clinicacp4.test",
  "dsEmailAcesso": "$EMAIL_ACESSO",
  "dsSenha": "$SENHA",
  "nmVeterinarioAdmin": "Dra. Ana Souza",
  "nrCRMV": "SP-$SUFIXO"
}
JSON
)
chamar "1. register-clinica" 201 POST "$BASE_URL/api/v1/auth/register-clinica" "$PAYLOAD_REGISTER"
ID_CLINICA=$(campo idClinica)
echo "    -> clinica criada, idClinica=$ID_CLINICA"

# ─── 2. Login (POST /api/v1/auth/login) ──────────────────────────────────────
PAYLOAD_LOGIN=$(cat <<JSON
{
  "dsEmail": "$EMAIL_ACESSO",
  "dsSenha": "$SENHA"
}
JSON
)
chamar "2. login" 200 POST "$BASE_URL/api/v1/auth/login" "$PAYLOAD_LOGIN"
TOKEN=$(campo accessToken)
echo "    -> JWT capturado (${#TOKEN} caracteres)"

# ═══════════════════════ ENTIDADE 1: VETERINARIO ════════════════════════════

# ─── 3. POST /api/v1/veterinarios ────────────────────────────────────────────
PAYLOAD_VET_POST=$(cat <<JSON
{
  "nmVeterinario": "Dr. Carlos Lima $SUFIXO",
  "nrCrmv": "SP-VET-$SUFIXO",
  "dsEmail": "carlos.lima-$SUFIXO@clinicacp4.test",
  "nrTelefone": "11912345678"
}
JSON
)
chamar "3. veterinario/criar" 201 POST "$BASE_URL/api/v1/veterinarios" "$PAYLOAD_VET_POST" "$TOKEN"
ID_VETERINARIO=$(campo id)
echo "    -> veterinario criado, id=$ID_VETERINARIO"

# ─── 4. GET /api/v1/veterinarios/{id} ────────────────────────────────────────
chamar "4. veterinario/buscar-por-id" 200 GET "$BASE_URL/api/v1/veterinarios/$ID_VETERINARIO" '' "$TOKEN"

# ─── 5. GET /api/v1/veterinarios (lista) ─────────────────────────────────────
chamar "5. veterinario/listar" 200 GET "$BASE_URL/api/v1/veterinarios" '' "$TOKEN"

# ─── 6. PUT /api/v1/veterinarios/{id} ────────────────────────────────────────
PAYLOAD_VET_PUT=$(cat <<JSON
{
  "nmVeterinario": "Dr. Carlos Lima Junior $SUFIXO",
  "nrCrmv": "SP-VET-$SUFIXO",
  "dsEmail": "carlos.lima.junior-$SUFIXO@clinicacp4.test",
  "nrTelefone": "11912345679"
}
JSON
)
chamar "6. veterinario/atualizar" 200 PUT "$BASE_URL/api/v1/veterinarios/$ID_VETERINARIO" "$PAYLOAD_VET_PUT" "$TOKEN"

# ─── 7. DELETE /api/v1/veterinarios/{id} (soft delete) ───────────────────────
chamar "7. veterinario/inativar" 204 DELETE "$BASE_URL/api/v1/veterinarios/$ID_VETERINARIO" '' "$TOKEN"

# ═══════════════════════ ENTIDADE 2: PET (com Tutor como setup) ═════════════

# ─── 8. POST /api/v1/tutores (pre-requisito: Pet exige tutor existente) ──────
# PetsController.Create: "Cadastra um novo pet vinculado a um TUTOR EXISTENTE".
# Ver tests/json/README.md, secao "Limitacao documentada" — POST /tutores e
# acessivel com o mesmo JWT de clinica, sem depender do fluxo de convite/
# onboarding do backend-tutor-java.
PAYLOAD_TUTOR=$(cat <<JSON
{
  "nmTutor": "Mariana Torres $SUFIXO",
  "nrCpf": "$CPF_TUTOR",
  "dsEmail": "mariana.torres-$SUFIXO@example.test",
  "nrTelefone": "11998877665",
  "dsCanalConvite": "EMAIL"
}
JSON
)
chamar "8. tutor/criar (setup)" 201 POST "$BASE_URL/api/v1/tutores" "$PAYLOAD_TUTOR" "$TOKEN"
ID_TUTOR=$(campo id)
echo "    -> tutor criado, id=$ID_TUTOR"

# ─── 9. POST /api/v1/pets ─────────────────────────────────────────────────────
# idEspecie=1 (Cao) e idRaca=1 (Labrador) vem do catalogo de referencia
# semeado por V14__seed_referencia.sql (backend-tutor-java) — ver
# tests/json/README.md.
PAYLOAD_PET_POST=$(cat <<JSON
{
  "idEspecie": 1,
  "idRaca": 1,
  "idVeterinarioResp": null,
  "nmPet": "Rex $SUFIXO",
  "dtNascimento": "2022-03-15T00:00:00Z",
  "sgSexo": "M",
  "sgPorte": "M",
  "idTutor": $ID_TUTOR,
  "stPrincipal": true,
  "dsVinculo": "PROPRIETARIO"
}
JSON
)
chamar "9. pet/criar" 201 POST "$BASE_URL/api/v1/pets" "$PAYLOAD_PET_POST" "$TOKEN"
ID_PET=$(campo id)
echo "    -> pet criado, id=$ID_PET"

# ─── 10. GET /api/v1/pets/{id} ────────────────────────────────────────────────
chamar "10. pet/buscar-por-id" 200 GET "$BASE_URL/api/v1/pets/$ID_PET" '' "$TOKEN"

# ─── 11. GET /api/v1/pets (lista) ─────────────────────────────────────────────
chamar "11. pet/listar" 200 GET "$BASE_URL/api/v1/pets" '' "$TOKEN"

# ─── 12. PUT /api/v1/pets/{id} ────────────────────────────────────────────────
PAYLOAD_PET_PUT=$(cat <<JSON
{
  "idVeterinarioResp": null,
  "nmPet": "Rex Atualizado $SUFIXO",
  "sgSexo": "M",
  "sgPorte": "G"
}
JSON
)
chamar "12. pet/atualizar" 200 PUT "$BASE_URL/api/v1/pets/$ID_PET" "$PAYLOAD_PET_PUT" "$TOKEN"

# ─── 13. DELETE /api/v1/pets/{id} (soft delete) ───────────────────────────────
chamar "13. pet/inativar" 204 DELETE "$BASE_URL/api/v1/pets/$ID_PET" '' "$TOKEN"

echo
echo "=============================================================="
echo " TODAS as chamadas passaram (HTTP esperado == HTTP obtido em todas)."
echo "=============================================================="
echo
echo " IDs criados nesta execucao, para a prova por SELECT abaixo:"
echo "   ID_CLINICA     = $ID_CLINICA"
echo "   ID_VETERINARIO = $ID_VETERINARIO"
echo "   ID_TUTOR       = $ID_TUTOR"
echo "   ID_PET         = $ID_PET"
echo

# =============================================================================
# INSTRUCOES PARA O SELECT DE PROVA (rubrica CP4) — NAO EXECUTADO POR ESTE
# SCRIPT. Rodar manualmente contra o Oracle do ACI durante a gravacao, com
# sqlplus ou sqlcl. Copiar/colar o bloco abaixo, substituindo <...>.
# =============================================================================
cat <<SQLPLUS_INSTRUCTIONS

==============================================================
 PROVA POR SELECT CONTRA O ORACLE DO ACI (schema RM562999)
==============================================================

O schema da aplicacao e RM562999 (ORACLE_APP_USER padrao deste ecossistema —
ver DevOps-Cloud/docker-compose.yml). O Oracle roda em outro container do
mesmo grupo ACI (imagem gvenzl/oracle-xe:21-slim), service name XEPDB1,
porta interna 1521 (no compose local ela e publicada como 9092:1521 — no
ACI, confirmar a porta publicada de fato no YAML de deploy do grupo de
containers antes de conectar).

1) Conectar com sqlplus (Oracle Instant Client) ou sqlcl:

   sqlplus RM562999/<SENHA_ORACLE_APP>@<IP-OU-FQDN-DO-ACI>:<PORTA_ORACLE>/XEPDB1

   -- ou, com sqlcl:
   sql RM562999/<SENHA_ORACLE_APP>@<IP-OU-FQDN-DO-ACI>:<PORTA_ORACLE>/XEPDB1

   <SENHA_ORACLE_APP> = valor de ORACLE_APP_PASSWORD do .env usado no deploy
   (NUNCA commitar esse valor em lugar nenhum deste repositorio de testes).

2) SELECT de prova — junta as 4 linhas criadas por este script nesta
   execucao (clinica, veterinario, tutor, pet), provando que a API gravou de
   fato no Oracle do ACI e nao so respondeu 2xx:

   SELECT
       c.ID_CLINICA, c.NM_CLINICA, c.NR_CNPJ, c.DS_EMAIL_ACESSO,
       v.ID_VETERINARIO, v.NM_VETERINARIO, v.NR_CRMV, v.ST_ATIVO AS ST_ATIVO_VET,
       t.ID_TUTOR, t.NM_TUTOR, t.NR_CPF,
       p.ID_PET, p.NM_PET, p.SG_PORTE, p.ST_ATIVO AS ST_ATIVO_PET
   FROM RM562999.CLINICA c
   JOIN RM562999.VETERINARIO v ON v.ID_CLINICA = c.ID_CLINICA
   JOIN RM562999.TUTOR       t ON t.ID_CLINICA = c.ID_CLINICA
   JOIN RM562999.PET         p ON p.ID_CLINICA = c.ID_CLINICA
   WHERE c.ID_CLINICA = $ID_CLINICA
     AND v.ID_VETERINARIO = $ID_VETERINARIO
     AND t.ID_TUTOR = $ID_TUTOR
     AND p.ID_PET = $ID_PET;

3) Prova extra do soft delete (rubrica costuma pedir DELETE provado, nao so
   assumido pelo 204 HTTP) — ST_ATIVO deve ser 'N' para o veterinario e o pet
   que este script inativou (DELETE fisico nunca acontece neste projeto):

   SELECT ID_VETERINARIO, NM_VETERINARIO, ST_ATIVO
   FROM RM562999.VETERINARIO
   WHERE ID_VETERINARIO = $ID_VETERINARIO;
   -- esperado: ST_ATIVO = 'N'

   SELECT ID_PET, NM_PET, ST_ATIVO
   FROM RM562999.PET
   WHERE ID_PET = $ID_PET;
   -- esperado: ST_ATIVO = 'N'

4) Sair:

   EXIT;

==============================================================
SQLPLUS_INSTRUCTIONS
