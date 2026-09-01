#!/usr/bin/env bash
# =============================================================================
# KURA CP4 · verify.sh — valida o ambiente já implantado
#
# Roda DEPOIS de deploy.sh terminar. Testa os endpoints de health por HTTP
# EXTERNO (FQDN público do ACI, nunca localhost — é isso que prova que o
# ambiente responde de fora, não só "de dentro do container"), com retry e
# timeout generoso — Oracle XE demora a subir na primeira vez, mesmo padrão
# de espera do script-azure.sh original.
#
# Uso: ./azure/verify.sh
# Saída: exit 0 se o núcleo (Oracle + .NET) está saudável; exit 1 caso
# contrário. O 3º ACI opcional (Java) é verificado mas NÃO derruba o exit
# code — é bônus, fora da rubrica.
# =============================================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$ROOT_DIR/.env" ]; then
    echo "❌ ERRO: $ROOT_DIR/.env não encontrado. Rode deploy.sh primeiro."
    exit 1
fi
# shellcheck disable=SC1091
set -a
. "$ROOT_DIR/.env"
set +a

RM="${RM:-RM562999}"
RM_LOWER="$(printf '%s' "$RM" | tr '[:upper:]' '[:lower:]')"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-${RM_LOWER}-kura-cp4-rg}"
DEPLOY_JAVA_BONUS="${DEPLOY_JAVA_BONUS:-false}"
ACI_ORACLE_NAME="${RM_LOWER}-kura-oracle-db"
ACI_DOTNET_NAME="${RM_LOWER}-kura-clinica-api"
ACI_JAVA_NAME="${RM_LOWER}-kura-tutor-api"

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

echo "========================================================"
echo " KURA CP4 · verify.sh — validação externa do ambiente"
echo "========================================================"

FALHOU=false

# ─── Oracle — TCP na 1521 (não fala HTTP) ─────────────────────────────────────
echo ""
echo "[1/3] Oracle ($ACI_ORACLE_NAME)..."
ORACLE_FQDN=$(az container show --name "$ACI_ORACLE_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query "ipAddress.fqdn" -o tsv 2>/dev/null || echo "")
if [ -z "$ORACLE_FQDN" ]; then
    echo "  ❌ Container group $ACI_ORACLE_NAME não encontrado no RG $AZURE_RESOURCE_GROUP."
    FALHOU=true
else
    echo "  FQDN: $ORACLE_FQDN"
    if aguardar_porta_tcp "$ORACLE_FQDN" 1521 10 15; then
        echo "  ✅ Oracle aceitando conexões em $ORACLE_FQDN:1521 (validado de fora, não localhost)."
    else
        echo "  ❌ Oracle não respondeu na porta 1521."
        FALHOU=true
    fi
fi

# ─── .NET — GET /health ──────────────────────────────────────────────────────
echo ""
echo "[2/3] .NET API ($ACI_DOTNET_NAME)..."
DOTNET_FQDN=$(az container show --name "$ACI_DOTNET_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query "ipAddress.fqdn" -o tsv 2>/dev/null || echo "")
if [ -z "$DOTNET_FQDN" ]; then
    echo "  ❌ Container group $ACI_DOTNET_NAME não encontrado no RG $AZURE_RESOURCE_GROUP."
    FALHOU=true
else
    URL_DOTNET="http://$DOTNET_FQDN:8080/health"
    echo "  URL: $URL_DOTNET"
    if aguardar_http_ok "$URL_DOTNET" 10 15; then
        echo "  ✅ .NET saudável (validado de fora, não localhost)."
    else
        echo "  ❌ .NET não respondeu 200 em $URL_DOTNET."
        echo "     Ver logs: az container logs --name $ACI_DOTNET_NAME --resource-group $AZURE_RESOURCE_GROUP"
        FALHOU=true
    fi
fi

# ─── Java (bônus, opcional — não derruba o exit code) ────────────────────────
echo ""
echo "[3/3] Java API — 3º ACI OPCIONAL, fora da rubrica ($ACI_JAVA_NAME)..."
if [ "$DEPLOY_JAVA_BONUS" != "true" ]; then
    echo "  DEPLOY_JAVA_BONUS=false no .env — pulando (esperado)."
else
    JAVA_FQDN=$(az container show --name "$ACI_JAVA_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query "ipAddress.fqdn" -o tsv 2>/dev/null || echo "")
    if [ -z "$JAVA_FQDN" ]; then
        echo "  ⚠️  Container group $ACI_JAVA_NAME não encontrado — bônus não implantado, não afeta o resultado."
    else
        URL_JAVA="http://$JAVA_FQDN:8081/api/actuator/health"
        echo "  URL: $URL_JAVA"
        if aguardar_http_ok "$URL_JAVA" 10 15; then
            echo "  ✅ Java saudável (bônus — validado de fora, não localhost)."
        else
            echo "  ⚠️  Java (bônus) não respondeu 200. Não derruba o resultado do verify.sh"
            echo "     porque é extra, fora da rubrica do CP4."
        fi
    fi
fi

echo ""
echo "========================================================"
if [ "$FALHOU" = "true" ]; then
    echo " ❌ VERIFICAÇÃO FALHOU — núcleo exigido (Oracle + .NET) não está 100% saudável."
    echo "========================================================"
    exit 1
fi
echo " ✅ VERIFICAÇÃO OK — núcleo exigido (Oracle + .NET) saudável, validado por"
echo "    IP/FQDN público, sem depender de localhost."
echo "========================================================"
