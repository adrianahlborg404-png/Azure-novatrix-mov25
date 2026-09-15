#!/usr/bin/env bash
# =====================================================================
# v35 — Identiteter i Entra ID
#
# Entra ID-objekt (användare, grupper, medlemskap) är INTE Azure-resurser
# och kan därför inte skapas med Bicep. De ligger i Microsoft Graph, inte
# i Resource Manager. Därför sköts den här delen med Azure CLI.
#
# RBAC-tilldelningarna och den hanterade identiteten ligger i rbac.bicep.
# =====================================================================

set -euo pipefail

# --- Konfiguration ---------------------------------------------------
DOMAN="adrianahlborg404gmail.onmicrosoft.com"

# Läs lösenordet in vid körning istället för att lägga det i filen
read -rsp "Tillfälligt lösenord för de nya användarna: " LOSENORD
echo

# --- Grupper ---------------------------------------------------------
echo "Skapar säkerhetsgrupper..."

az ad group create \
  --display-name "Novatrix-Drift" \
  --mail-nickname "Novatrix-Drift" \
  --description "Drift och serverunderhåll" \
  --output none

az ad group create \
  --display-name "Novatrix-Utveckling" \
  --mail-nickname "Novatrix-Utveckling" \
  --description "Applikationsutveckling" \
  --output none

# --- Användare -------------------------------------------------------
echo "Skapar användare..."

az ad user create \
  --display-name "Anna Drift" \
  --user-principal-name "Anna-Drift@${DOMAN}" \
  --password "$LOSENORD" \
  --force-change-password-next-sign-in true \
  --output none

az ad user create \
  --display-name "Erik Dev" \
  --user-principal-name "Erik-Dev@${DOMAN}" \
  --password "$LOSENORD" \
  --force-change-password-next-sign-in true \
  --output none

# --- Medlemskap ------------------------------------------------------
echo "Kopplar användare till grupper..."

ANNA_ID=$(az ad user show --id "Anna-Drift@${DOMAN}" --query id -o tsv)
ERIK_ID=$(az ad user show --id "Erik-Dev@${DOMAN}" --query id -o tsv)

az ad group member add --group "Novatrix-Drift"      --member-id "$ANNA_ID" --output none
az ad group member add --group "Novatrix-Utveckling" --member-id "$ERIK_ID" --output none

# --- Objekt-ID:n till nästa steg -------------------------------------
DRIFT_GRUPP_ID=$(az ad group show --group "Novatrix-Drift" --query id -o tsv)
UTV_GRUPP_ID=$(az ad group show --group "Novatrix-Utveckling" --query id -o tsv)

echo
echo "======================================================================"
echo "Klart. Använd dessa objekt-ID:n när du rullar ut rbac.bicep:"
echo
echo "  driftGruppObjectId=${DRIFT_GRUPP_ID}"
echo "  utvecklingGruppObjectId=${UTV_GRUPP_ID}"
echo "======================================================================"
