#!/usr/bin/env bash
# =============================================================================
# KURA CP4 · teardown.sh
#
# ⚠️ OBRIGATÓRIO RODAR ISTO DEPOIS DA CORREÇÃO/GRAVAÇÃO DO VÍDEO. ⚠️
# Mesmo sem penalidade explícita listada na rubrica para "recurso deixado
# ligado", é prática básica de custo em nuvem não deixar Oracle XE + 2-3 ACIs
# rodando indefinidamente — apaga o Resource Group inteiro (todos os recursos
# dentro dele: ACR, storage account, file share, os container groups).
#
# Uso:
#   ./azure/teardown.sh            → pede confirmação interativa (digite o
#                                     nome do resource group para confirmar)
#   ./azure/teardown.sh --yes      → sem confirmação, para uso em CI/script
# =============================================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$ROOT_DIR/.env" ]; then
    echo "❌ ERRO: $ROOT_DIR/.env não encontrado. Sem ele não dá para saber qual"
    echo "   resource group apagar com segurança."
    exit 1
fi
# shellcheck disable=SC1091
set -a
. "$ROOT_DIR/.env"
set +a

RM="${RM:-RM562999}"
RM_LOWER="$(printf '%s' "$RM" | tr '[:upper:]' '[:lower:]')"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-${RM_LOWER}-kura-cp4-rg}"

PULAR_CONFIRMACAO=false
if [ "${1:-}" = "--yes" ]; then
    PULAR_CONFIRMACAO=true
fi

echo "========================================================"
echo " KURA CP4 · teardown.sh"
echo "========================================================"
echo ""
echo "  Isto vai apagar TODO o Resource Group: $AZURE_RESOURCE_GROUP"
echo "  (ACR, Storage Account, File Share, todos os ACIs dentro dele)."
echo ""

if ! az group show --name "$AZURE_RESOURCE_GROUP" -o none 2>/dev/null; then
    echo "  ℹ️  Resource Group $AZURE_RESOURCE_GROUP não existe (já foi apagado?)."
    echo "  Nada a fazer."
    exit 0
fi

if [ "$PULAR_CONFIRMACAO" = "false" ]; then
    echo "  Digite o nome do resource group para confirmar (ou Ctrl+C para cancelar):"
    read -r CONFIRMACAO
    if [ "$CONFIRMACAO" != "$AZURE_RESOURCE_GROUP" ]; then
        echo "❌ Nome não confere. Abortando — nada foi apagado."
        exit 1
    fi
fi

echo ""
echo "  Apagando $AZURE_RESOURCE_GROUP (--no-wait — não bloqueia o terminal;"
echo "  a exclusão continua em background no Azure)..."
az group delete --name "$AZURE_RESOURCE_GROUP" --yes --no-wait

echo ""
echo "  ✅ Exclusão disparada. Para confirmar quando terminar:"
echo "     az group exists --name $AZURE_RESOURCE_GROUP   (deve devolver 'false')"
echo "========================================================"
