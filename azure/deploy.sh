#!/usr/bin/env bash
# =============================================================================
# KURA CP4 · deploy.sh — Imagem e Containers em Nuvem (ACR/ACI)
# FIAP · DevOps Tools & Cloud Computing
#
# ORDEM EXATA DE EXECUÇÃO ESPERADA (leia antes de rodar qualquer coisa):
#
#   1. cp .env.example .env   e preencher todos os segredos (openssl rand...)
#   2. az login                (autenticar a CLI nesta máquina)
#   3. ./azure/deploy.sh       (ESTE script — cria RG, ACR, build+push das 2
#                                imagens obrigatórias, storage account + file
#                                share, sobe o ACI do Oracle, ESPERA ele ficar
#                                saudável, só então sobe o ACI do .NET)
#   4. (opcional/bônus) se DEPLOY_JAVA_BONUS=true no .env, este mesmo script
#      builda+sobe o 3º ACI (Java) DEPOIS do .NET — o Java aplica sozinho as
#      migrations Flyway (V1→V19) contra o Oracle já no ar, criando o schema
#      inteiro (~27 tabelas). Não é preciso rodar Flyway manualmente à parte.
#   5. ./azure/verify.sh       (valida os endpoints públicos por HTTP externo,
#                                nunca localhost — roda depois do deploy.sh
#                                terminar, com o ambiente já de pé)
#   6. gravar o vídeo de demonstração exigido pela rubrica
#   7. ./azure/teardown.sh     (OBRIGATÓRIO — apaga o resource group inteiro
#                                para não deixar recurso cobrando sem necessidade)
#
# Este script NÃO usa `az acr build` (build remoto) de propósito — a rubrica
# pede `docker build`/`docker push` explícitos, então o build acontece nesta
# máquina e só o PUSH vai para o ACR.
#
# Idempotência: resource group, ACR e storage account só são criados se ainda
# não existirem (checados via `az ... show` antes). Os container groups (ACI)
# são recriados do zero a cada run (delete-se-existir + create), porque ACI
# não suporta update in-place de env vars/imagem — é mais simples e mais
# barato (poucos MB de rede) do que tentar um update parcial.
# =============================================================================
set -eu

# ─── Força UTF-8 no Python que o `az` CLI usa internamente ──────────────────
# Achado rodando este script de verdade: `az container create --file <yaml>`
# falhou com "'charmap' codec can't decode byte 0x81" ao ler
# azure/.generated/aci-oracle-db.yaml — o arquivo está em UTF-8 (comentários em
# português com acento), mas o Python do `az` CLI usa
# locale.getpreferredencoding() como default, que nesta máquina Windows é
# cp1252, não utf-8. PYTHONUTF8=1 força UTF-8 como encoding padrão de I/O de
# texto (Python 3.7+, PEP 540) sem precisar tocar em nenhum arquivo do `az`.
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

# ─── Localização deste script e raiz do repo ─────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GERADOS_DIR="$SCRIPT_DIR/.generated"

# ─── Carrega o .env (obrigatório) ────────────────────────────────────────────
if [ ! -f "$ROOT_DIR/.env" ]; then
    echo "❌ ERRO: $ROOT_DIR/.env não encontrado."
    echo "   Rode: cp .env.example .env   e preencha os segredos antes de continuar."
    exit 1
fi
# shellcheck disable=SC1091
set -a
. "$ROOT_DIR/.env"
set +a
echo "✅ .env carregado."

# ─── RM — ÚNICA fonte da verdade do prefixo do grupo. Nunca hardcode de novo
#     abaixo neste script nem nos YAML — tudo referencia $RM/$RM_LOWER. ──────
RM="${RM:-RM562999}"
RM_LOWER="$(printf '%s' "$RM" | tr '[:upper:]' '[:lower:]')"
echo "✅ Prefixo do grupo: $RM (usado em minúsculo — $RM_LOWER — onde Azure/Docker exigem)"

# ─── Defaults derivados de $RM_LOWER, sobrepostos pelo .env quando presente ──
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-${RM_LOWER}-kura-cp4-rg}"
AZURE_LOCATION="${AZURE_LOCATION:-centralus}"
ACR_NAME="${ACR_NAME:-${RM_LOWER}kuraacr}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-${RM_LOWER}kurastorage}"
STORAGE_FILE_SHARE_NAME="${STORAGE_FILE_SHARE_NAME:-kura-oracle-data}"
STORAGE_FILE_SHARE_QUOTA_GB="${STORAGE_FILE_SHARE_QUOTA_GB:-10}"
DEPLOY_JAVA_BONUS="${DEPLOY_JAVA_BONUS:-false}"
ORACLE_APP_USER="${ORACLE_APP_USER:-$RM}"
ORACLE_PDB_SERVICE="${ORACLE_PDB_SERVICE:-XEPDB1}"
ASPNETCORE_ENVIRONMENT="${ASPNETCORE_ENVIRONMENT:-Production}"
SRC_DOTNET_REPO_PATH="${SRC_DOTNET_REPO_PATH:-$ROOT_DIR/../backend-clinica-dotnet}"
SRC_JAVA_REPO_PATH="${SRC_JAVA_REPO_PATH:-$ROOT_DIR/../backend-tutor-java}"

# Nomes de recurso — sempre derivados de $RM_LOWER, nunca hardcoded soltos
ACI_ORACLE_NAME="${RM_LOWER}-kura-oracle-db"
ACI_DOTNET_NAME="${RM_LOWER}-kura-clinica-api"
ACI_JAVA_NAME="${RM_LOWER}-kura-tutor-api"
IMAGE_REPO_ORACLE="${RM_LOWER}/kura-oracle-db"
IMAGE_REPO_DOTNET="${RM_LOWER}/kura-clinica-api"
IMAGE_REPO_JAVA="${RM_LOWER}/kura-tutor-api"

# ─── Validação de segredos obrigatórios (sem isto, falha aqui é melhor do
#     que falhar 10 minutos depois no meio da criação do ACI) ────────────────
exigir_var() {
    local nome="$1"
    local valor="${!nome:-}"
    if [ -z "$valor" ]; then
        echo "❌ ERRO: variável $nome vazia ou ausente no .env."
        exit 1
    fi
}
for VAR_OBRIGATORIA in ORACLE_SYS_PASSWORD ORACLE_APP_PASSWORD DOTNET_JWT_KEY \
    IOT_API_KEY LUNA_API_KEY LUNA_INBOUND_API_KEY; do
    exigir_var "$VAR_OBRIGATORIA"
done
if [ "$DEPLOY_JAVA_BONUS" = "true" ]; then
    for VAR_OBRIGATORIA in JAVA_JWT_SECRET; do
        exigir_var "$VAR_OBRIGATORIA"
    done
fi
echo "✅ Segredos obrigatórios presentes no .env."

mkdir -p "$GERADOS_DIR"

# ─── Resolve um interpretador Python que funcione de verdade ────────────────
# Em algumas instalações Windows, `python3` existe no PATH só como o stub de
# App Execution Alias da Microsoft Store (falha ao executar, mesmo com
# `command -v python3` retornando sucesso) — achado rodando este script nesta
# máquina. Testa a EXECUÇÃO, não só a presença, e cai para `python` se preciso.
resolver_python() {
    local candidato
    for candidato in python3 python; do
        if command -v "$candidato" >/dev/null 2>&1 && "$candidato" -c "print(1)" >/dev/null 2>&1; then
            echo "$candidato"
            return 0
        fi
    done
    echo "❌ ERRO: nenhum interpretador Python funcional encontrado (tentado: python3, python)." >&2
    exit 1
}
PYTHON_BIN="$(resolver_python)"
echo "✅ Interpretador Python: $PYTHON_BIN"

# ─── Helper: substituição de placeholders __CHAVE__ por valor real ───────────
# Usa Python (não sed) de propósito — os valores incluem connection strings
# Oracle com ';'/'=' e senhas base64 com '/'+, que quebram delimitador de sed
# com facilidade. Mesmo espírito do script-azure.sh: evitar `jq`, usar python3
# nativo do sistema para qualquer coisa que não seja um one-liner trivial.
#
# Cada valor é passado ao Python em base64 (não como texto puro), e decodificado
# lá dentro — achado rodando este script: o Git Bash reescreve silenciosamente
# qualquer argumento que PAREÇA um caminho absoluto (ex.: o valor default de
# STORAGE_BASE_PATH, "/data/kura/receituarios", virava
# "C:/Program Files/Git/data/kura/receituarios" antes mesmo de chegar ao
# Python). Isso é a mesma armadilha de MSYS_NO_PATHCONV documentada no
# CLAUDE.md do workspace, só que aqui `export MSYS_NO_PATHCONV=1` não dava
# para usar: os caminhos do PRÓPRIO template/saída (que são reais e PRECISAM
# ser convertidos para o Python nativo do Windows resolver) estariam no mesmo
# comando. Codificar em base64 evita a ambiguidade — nenhum caminho ambíguo
# passa em texto puro para dentro deste `python`.
substituir_placeholders() {
    local template="$1"
    local saida="$2"
    shift 2
    local args=() par chave valor valor_b64
    for par in "$@"; do
        chave="${par%%=*}"
        valor="${par#*=}"
        valor_b64=$(printf '%s' "$valor" | base64 -w 0)
        args+=("${chave}=${valor_b64}")
    done
    "$PYTHON_BIN" - "$template" "$saida" "${args[@]}" <<'PYEOF'
import base64
import re
import sys
template_path, saida_path = sys.argv[1], sys.argv[2]
pares = sys.argv[3:]
with open(template_path, "r", encoding="utf-8") as f:
    conteudo = f.read()
for par in pares:
    chave, _, valor_b64 = par.partition("=")
    valor = base64.b64decode(valor_b64).decode("utf-8")
    conteudo = conteudo.replace("__" + chave + "__", valor)
# Placeholder real é __TUDO_MAIUSCULO__ (ex.: __ACR_LOGIN_SERVER__). Não confundir
# com convenção .NET de nome de env var com "__" no meio em case misto, tipo
# "ConnectionStrings__DefaultConnection" ou "Jwt__Key" — essas são valores
# legítimos do YAML final, não placeholders esquecidos.
PADRAO_PLACEHOLDER = re.compile(r"__[A-Z][A-Z0-9_]*__")
# Ignora linhas de comentário (YAML usa '#') — o cabeçalho dos templates cita
# "__ALGO__" como exemplo genérico de placeholder, o que bateria com o próprio
# padrão de detecção sem essa exclusão.
restantes = [
    l for l in conteudo.splitlines()
    if not l.strip().startswith("#") and PADRAO_PLACEHOLDER.search(l)
]
with open(saida_path, "w", encoding="utf-8") as f:
    f.write(conteudo)
if restantes:
    print("⚠️  Placeholders __..__ não substituídos restaram em " + saida_path + ":", file=sys.stderr)
    for l in restantes:
        print("    " + l, file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ─── Helper: espera porta TCP responder (usado para o Oracle, que não fala
#     HTTP) ────────────────────────────────────────────────────────────────
aguardar_porta_tcp() {
    local host="$1" porta="$2" max_tentativas="$3" espera_s="$4"
    local i
    for i in $(seq 1 "$max_tentativas"); do
        if (exec 3<>"/dev/tcp/${host}/${porta}") 2>/dev/null; then
            exec 3>&- 2>/dev/null || true
            exec 3<&- 2>/dev/null || true
            return 0
        fi
        echo "  ... tentativa $i/$max_tentativas — $host:$porta ainda não responde (aguardando ${espera_s}s)"
        sleep "$espera_s"
    done
    return 1
}

# ─── Helper: espera endpoint HTTP responder 200 (mesmo padrão de espera do
#     script-azure.sh original — Oracle/apps demoram a estabilizar) ──────────
aguardar_http_ok() {
    local url="$1" max_tentativas="$2" espera_s="$3"
    local i codigo
    for i in $(seq 1 "$max_tentativas"); do
        codigo=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
        echo "  ... tentativa $i/$max_tentativas — GET $url → HTTP $codigo"
        if [ "$codigo" = "200" ]; then
            return 0
        fi
        sleep "$espera_s"
    done
    return 1
}

echo ""
echo "========================================================"
echo " KURA CP4 · ACR/ACI · Deploy"
echo "========================================================"
echo " Resource Group : $AZURE_RESOURCE_GROUP"
echo " Região         : $AZURE_LOCATION"
echo " ACR            : $ACR_NAME"
echo " Storage Account: $STORAGE_ACCOUNT_NAME"
echo " Bônus Java ACI : $DEPLOY_JAVA_BONUS"
echo "========================================================"
echo ""

# ─── [0] Sanidade — az CLI autenticado ────────────────────────────────────────
echo "[0/9] Verificando login da Azure CLI..."
if ! az account show -o none 2>/dev/null; then
    echo "❌ ERRO: não autenticado na Azure CLI. Rode 'az login' antes."
    exit 1
fi
echo "  ✅ Autenticado."

# ─── [1/9] Resource Group (idempotente por natureza) ─────────────────────────
echo ""
echo "[1/9] Criando/confirmando Resource Group: $AZURE_RESOURCE_GROUP..."
az group create \
    --name "$AZURE_RESOURCE_GROUP" \
    --location "$AZURE_LOCATION" \
    --output none
echo "  ✅ Resource Group pronto."

# Providers necessários — registro é idempotente e rápido se já registrado
# em runs anteriores desta subscription.
for PROVIDER in Microsoft.ContainerInstance Microsoft.ContainerRegistry Microsoft.Storage; do
    ESTADO=$(az provider show --namespace "$PROVIDER" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
    if [ "$ESTADO" != "Registered" ]; then
        echo "  Registrando provider $PROVIDER (estado atual: $ESTADO)..."
        az provider register --namespace "$PROVIDER" -o none
    fi
done

# ─── [2/9] ACR — cria só se ainda não existir ────────────────────────────────
echo ""
echo "[2/9] Criando/confirmando Azure Container Registry: $ACR_NAME..."
if az acr show --name "$ACR_NAME" --resource-group "$AZURE_RESOURCE_GROUP" -o none 2>/dev/null; then
    echo "  ACR já existe, reaproveitando."
else
    az acr create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$ACR_NAME" \
        --sku Basic \
        --output none
    echo "  ✅ ACR criado."
fi
# Admin habilitado para o ACI conseguir puxar a imagem via
# --registry-login-server/--registry-username/--registry-password (ver YAML).
az acr update --name "$ACR_NAME" --admin-enabled true --output none
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
ACR_USERNAME=$(az acr credential show --name "$ACR_NAME" --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" -o tsv)
echo "  ✅ ACR pronto: $ACR_LOGIN_SERVER"

# ─── [3/9] docker build + docker push — 2 imagens obrigatórias ──────────────
# EXPLÍCITO de propósito: a rubrica pede docker build/push, não `az acr build`
# (que builda remoto e esconderia o passo). Login no ACR via `az acr login`
# (que autentica o Docker CLI local usando as credenciais da CLI do Azure —
# não é `az acr build`, é só autenticação para o `docker push` de verdade).
echo ""
echo "[3/9] Login no ACR + build/push das imagens obrigatórias (Oracle + .NET)..."
az acr login --name "$ACR_NAME" --output none
echo "  ✅ Login no ACR OK."

echo "  → docker build: banco (imagem fina, contexto = $ROOT_DIR/db)"
docker build -t "${ACR_LOGIN_SERVER}/${IMAGE_REPO_ORACLE}:latest" "$ROOT_DIR/db"

if [ ! -d "$SRC_DOTNET_REPO_PATH" ]; then
    echo "❌ ERRO: SRC_DOTNET_REPO_PATH ($SRC_DOTNET_REPO_PATH) não existe."
    echo "   Ajuste no .env — o Dockerfile de app-dotnet/ faz COPY relativo à"
    echo "   raiz do repo backend-clinica-dotnet, não a esta pasta."
    exit 1
fi
echo "  → docker build: .NET (contexto = $SRC_DOTNET_REPO_PATH, Dockerfile = app-dotnet/Dockerfile)"
docker build \
    -f "$ROOT_DIR/app-dotnet/Dockerfile" \
    -t "${ACR_LOGIN_SERVER}/${IMAGE_REPO_DOTNET}:latest" \
    "$SRC_DOTNET_REPO_PATH"

echo "  → docker push: banco"
docker push "${ACR_LOGIN_SERVER}/${IMAGE_REPO_ORACLE}:latest"
echo "  → docker push: .NET"
docker push "${ACR_LOGIN_SERVER}/${IMAGE_REPO_DOTNET}:latest"
echo "  ✅ 2 imagens obrigatórias no ACR."

# ─── EXTRA — 3º ACI opcional (Java), FORA da rubrica do CP4 ──────────────────
if [ "$DEPLOY_JAVA_BONUS" = "true" ]; then
    echo ""
    echo "  [EXTRA/BÔNUS] DEPLOY_JAVA_BONUS=true — build/push da imagem Java (3º ACI,"
    echo "  não faz parte do que a rubrica exige: só Oracle + .NET contam para a nota)."
    if [ ! -d "$SRC_JAVA_REPO_PATH" ]; then
        echo "❌ ERRO: SRC_JAVA_REPO_PATH ($SRC_JAVA_REPO_PATH) não existe."
        exit 1
    fi
    docker build \
        -f "$ROOT_DIR/app-java/Dockerfile" \
        -t "${ACR_LOGIN_SERVER}/${IMAGE_REPO_JAVA}:latest" \
        "$SRC_JAVA_REPO_PATH"
    docker push "${ACR_LOGIN_SERVER}/${IMAGE_REPO_JAVA}:latest"
    echo "  ✅ Imagem Java (bônus) no ACR."
fi

# ─── [4/9] Storage Account (idempotente) ─────────────────────────────────────
echo ""
echo "[4/9] Criando/confirmando Storage Account: $STORAGE_ACCOUNT_NAME..."
if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$AZURE_RESOURCE_GROUP" -o none 2>/dev/null; then
    echo "  Storage Account já existe, reaproveitando."
else
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    echo "  ✅ Storage Account criada."
fi
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "[0].value" -o tsv)

# ─── [5/9] Azure Files share — persistência REAL do Oracle (RUBRICA) ────────
echo ""
echo "[5/9] Criando/confirmando Azure Files share: $STORAGE_FILE_SHARE_NAME..."
az storage share create \
    --name "$STORAGE_FILE_SHARE_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --quota "$STORAGE_FILE_SHARE_QUOTA_GB" \
    --output none
echo "  ✅ File share pronto (idempotente — 'az storage share create' não falha se já existir)."

# ─── [6/9] Sobe o ACI do Oracle ───────────────────────────────────────────────
echo ""
echo "[6/9] Subindo ACI do Oracle: $ACI_ORACLE_NAME..."
if az container show --name "$ACI_ORACLE_NAME" --resource-group "$AZURE_RESOURCE_GROUP" -o none 2>/dev/null; then
    echo "  Container group já existe — apagando para recriar do zero (ACI não"
    echo "  suporta update in-place de env var/imagem)."
    az container delete --name "$ACI_ORACLE_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --yes --output none
fi
substituir_placeholders \
    "$SCRIPT_DIR/aci-oracle-db.yaml" \
    "$GERADOS_DIR/aci-oracle-db.yaml" \
    "LOCATION=$AZURE_LOCATION" \
    "ORACLE_ACI_NAME=$ACI_ORACLE_NAME" \
    "RM=$RM" \
    "RM_LOWER=$RM_LOWER" \
    "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER" \
    "ACR_USERNAME=$ACR_USERNAME" \
    "ACR_PASSWORD=$ACR_PASSWORD" \
    "ORACLE_SYS_PASSWORD=$ORACLE_SYS_PASSWORD" \
    "ORACLE_APP_USER=$ORACLE_APP_USER" \
    "ORACLE_APP_PASSWORD=$ORACLE_APP_PASSWORD" \
    "STORAGE_FILE_SHARE_NAME=$STORAGE_FILE_SHARE_NAME" \
    "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME" \
    "STORAGE_ACCOUNT_KEY=$STORAGE_KEY"
az container create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --file "$GERADOS_DIR/aci-oracle-db.yaml" \
    --output none
echo "  ✅ ACI do Oracle criado, aguardando provisionamento..."

ORACLE_FQDN=$(az container show \
    --name "$ACI_ORACLE_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "ipAddress.fqdn" -o tsv)
ORACLE_IP=$(az container show \
    --name "$ACI_ORACLE_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "ipAddress.ip" -o tsv)
echo "  FQDN: $ORACLE_FQDN — IP: $ORACLE_IP"

echo "  Aguardando o listener Oracle responder na porta 1521 (pode levar"
echo "  vários minutos — Oracle XE cria o PDB na primeira subida)..."
if ! aguardar_porta_tcp "$ORACLE_FQDN" 1521 30 30; then
    echo "❌ Oracle não respondeu em 15 min. Verifique os logs:"
    echo "   az container logs --name $ACI_ORACLE_NAME --resource-group $AZURE_RESOURCE_GROUP"
    exit 1
fi
echo "  ✅ Oracle aceitando conexões em $ORACLE_FQDN:1521."

# ─── Persistência real em Conta de Armazenamento (RUBRICA) ─────────────────
# Oracle não roda com oradata direto num Azure Files (ver nota grande em
# aci-oracle-db.yaml) — o container usa disco local do ACI para operar, e este
# passo copia os datafiles já criados e saudáveis para o volume Azure Files
# real (/mnt/kura-backup), montado no mesmo container group. É cópia
# sequencial pós-boot, não E/S ao vivo do banco — por isso funciona sobre SMB
# sem esbarrar no mesmo problema de locking/O_DIRECT.
echo ""
echo "  Copiando datafiles para a Conta de Armazenamento (persistência real)..."
if az container exec \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$ACI_ORACLE_NAME" \
    --exec-command "/bin/sh -c 'mkdir -p /mnt/kura-backup/oradata-snapshot && cp -a /opt/oracle/oradata/. /mnt/kura-backup/oradata-snapshot/ && echo BACKUP_OK'" \
    --output tsv 2>&1 | tee "$GERADOS_DIR/backup-oracle.log" | grep -q "BACKUP_OK"; then
    echo "  ✅ Datafiles copiados para a Storage Account (kura-oracle-data/oradata-snapshot/)."
else
    echo "  ⚠️  Cópia para a Storage Account não confirmou 'BACKUP_OK' — ver $GERADOS_DIR/backup-oracle.log."
    echo "     Não aborta o deploy (o núcleo funcional não depende disto), mas revisar antes de gravar o vídeo."
fi

# ─── [7/9] Sobe o ACI do .NET (depende do Oracle já estar de pé) ────────────
echo ""
echo "[7/9] Subindo ACI do .NET: $ACI_DOTNET_NAME..."
ORACLE_CONNECTION_STRING="User Id=${ORACLE_APP_USER};Password=${ORACLE_APP_PASSWORD};Data Source=${ORACLE_FQDN}:1521/${ORACLE_PDB_SERVICE}"

if az container show --name "$ACI_DOTNET_NAME" --resource-group "$AZURE_RESOURCE_GROUP" -o none 2>/dev/null; then
    echo "  Container group já existe — apagando para recriar do zero."
    az container delete --name "$ACI_DOTNET_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --yes --output none
fi
substituir_placeholders \
    "$SCRIPT_DIR/aci-dotnet-api.yaml" \
    "$GERADOS_DIR/aci-dotnet-api.yaml" \
    "LOCATION=$AZURE_LOCATION" \
    "DOTNET_ACI_NAME=$ACI_DOTNET_NAME" \
    "RM=$RM" \
    "RM_LOWER=$RM_LOWER" \
    "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER" \
    "ACR_USERNAME=$ACR_USERNAME" \
    "ACR_PASSWORD=$ACR_PASSWORD" \
    "ASPNETCORE_ENVIRONMENT=$ASPNETCORE_ENVIRONMENT" \
    "ORACLE_CONNECTION_STRING=$ORACLE_CONNECTION_STRING" \
    "DOTNET_JWT_KEY=$DOTNET_JWT_KEY" \
    "IOT_API_KEY=$IOT_API_KEY" \
    "LUNA_API_KEY=$LUNA_API_KEY" \
    "DAILY_API_KEY=${DAILY_API_KEY:-kura-daily-dummy-key-2026}" \
    "LUNA_BASE_URL=${LUNA_BASE_URL:-http://luna-ai-nao-implantada-neste-cp4:8000}" \
    "LUNA_INBOUND_API_KEY=$LUNA_INBOUND_API_KEY" \
    "STORAGE_BASE_PATH=${STORAGE_BASE_PATH:-/data/kura/receituarios}"
az container create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --file "$GERADOS_DIR/aci-dotnet-api.yaml" \
    --output none
echo "  ✅ ACI do .NET criado, aguardando provisionamento..."

DOTNET_FQDN=$(az container show \
    --name "$ACI_DOTNET_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "ipAddress.fqdn" -o tsv)
DOTNET_IP=$(az container show \
    --name "$ACI_DOTNET_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "ipAddress.ip" -o tsv)
echo "  FQDN: $DOTNET_FQDN — IP: $DOTNET_IP"

echo "  Aguardando GET http://$DOTNET_FQDN:8080/health responder 200..."
if ! aguardar_http_ok "http://$DOTNET_FQDN:8080/health" 20 30; then
    echo "⚠️  .NET não respondeu 200 em 10 min. Verifique os logs:"
    echo "   az container logs --name $ACI_DOTNET_NAME --resource-group $AZURE_RESOURCE_GROUP"
    echo "   (não abortando o script por isto — pode ser só lentidão; rode verify.sh depois)"
fi

# ─── [8/9] EXTRA — sobe o 3º ACI opcional (Java), se pedido ─────────────────
JAVA_FQDN=""
if [ "$DEPLOY_JAVA_BONUS" = "true" ]; then
    echo ""
    echo "[8/9] [EXTRA/BÔNUS] Subindo ACI do Java: $ACI_JAVA_NAME..."
    DB_URL_JAVA="jdbc:oracle:thin:@//${ORACLE_FQDN}:1521/${ORACLE_PDB_SERVICE}"

    if az container show --name "$ACI_JAVA_NAME" --resource-group "$AZURE_RESOURCE_GROUP" -o none 2>/dev/null; then
        echo "  Container group já existe — apagando para recriar do zero."
        az container delete --name "$ACI_JAVA_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --yes --output none
    fi
    substituir_placeholders \
        "$SCRIPT_DIR/aci-java-api.yaml" \
        "$GERADOS_DIR/aci-java-api.yaml" \
        "LOCATION=$AZURE_LOCATION" \
        "JAVA_ACI_NAME=$ACI_JAVA_NAME" \
        "RM=$RM" \
        "RM_LOWER=$RM_LOWER" \
        "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER" \
        "ACR_USERNAME=$ACR_USERNAME" \
        "ACR_PASSWORD=$ACR_PASSWORD" \
        "DB_URL=$DB_URL_JAVA" \
        "ORACLE_APP_USER=$ORACLE_APP_USER" \
        "ORACLE_APP_PASSWORD=$ORACLE_APP_PASSWORD" \
        "JAVA_JWT_SECRET=$JAVA_JWT_SECRET" \
        "JWT_ACCESS_EXPIRATION_MINUTES=${JWT_ACCESS_EXPIRATION_MINUTES:-15}" \
        "CORS_ALLOWED_ORIGINS=${CORS_ALLOWED_ORIGINS:-http://localhost:8081,http://localhost:19006}"
    az container create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --file "$GERADOS_DIR/aci-java-api.yaml" \
        --output none
    echo "  ✅ ACI do Java criado, aguardando provisionamento..."

    JAVA_FQDN=$(az container show \
        --name "$ACI_JAVA_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --query "ipAddress.fqdn" -o tsv)
    echo "  FQDN: $JAVA_FQDN"
    echo "  Aguardando GET http://$JAVA_FQDN:8081/api/actuator/health responder 200..."
    echo "  (o Flyway aplica V1→V19 sozinho na primeira subida — pode levar mais tempo)"
    if ! aguardar_http_ok "http://$JAVA_FQDN:8081/api/actuator/health" 20 30; then
        echo "⚠️  Java não respondeu 200 em 10 min. Verifique os logs:"
        echo "   az container logs --name $ACI_JAVA_NAME --resource-group $AZURE_RESOURCE_GROUP"
    fi
else
    echo ""
    echo "[8/9] DEPLOY_JAVA_BONUS=false — pulando o 3º ACI opcional (fora da rubrica)."
fi

# ─── [9/9] Resumo final ───────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo " DEPLOY CONCLUÍDO"
echo "========================================================"
echo ""
echo "  NÚCLEO EXIGIDO PELA RUBRICA:"
echo "  Oracle (ACI) : $ACI_ORACLE_NAME"
echo "    FQDN: $ORACLE_FQDN"
echo "    IP  : $ORACLE_IP"
echo "    Porta: 1521 (XEPDB1)"
echo ""
echo "  .NET API (ACI): $ACI_DOTNET_NAME"
echo "    FQDN: $DOTNET_FQDN"
echo "    IP  : $DOTNET_IP"
echo "    Health : http://$DOTNET_FQDN:8080/health"
echo "    Swagger: http://$DOTNET_FQDN:8080/swagger"
echo ""
if [ "$DEPLOY_JAVA_BONUS" = "true" ]; then
    echo "  [EXTRA/BÔNUS — fora da rubrica] Java API (ACI): $ACI_JAVA_NAME"
    echo "    FQDN: $JAVA_FQDN"
    echo "    Health : http://$JAVA_FQDN:8081/api/actuator/health"
    echo "    Swagger: http://$JAVA_FQDN:8081/api/swagger-ui.html"
    echo ""
fi
echo "  Próximo passo: ./azure/verify.sh"
echo "  Ao terminar a correção/gravação: ./azure/teardown.sh (OBRIGATÓRIO)"
echo "========================================================"
