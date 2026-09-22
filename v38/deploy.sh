#!/usr/bin/env bash
# Deployar Novatrix-miljon (v38, G-niva) fran repot.
# Anvandning i Cloud Shell:   bash deploy.sh
# Valfritt: RG=rg-namn LOCATION=swedencentral bash deploy.sh
set -euo pipefail

RG="${RG:-rg-novatrix-iac}"
LOCATION="${LOCATION:-swedencentral}"

cd "$(dirname "$0")/templates"

echo ">> Resursgrupp $RG i $LOCATION"
az group create --name "$RG" --location "$LOCATION" --output none

ARGS=(
  --resource-group "$RG"
  --template-file azuredeploy.json
  --parameters @azuredeploy.parameters.json
)

echo ">> What-if (forhandsgranskning)"
az deployment group what-if "${ARGS[@]}"

read -rp "Deploya pa riktigt? (j/n) " svar
[[ "$svar" == "j" ]] || { echo "Avbrutet."; exit 0; }

echo ">> Deploy"
az deployment group create --name "novatrix-$(date +%Y%m%d-%H%M)" "${ARGS[@]}" \
  --query properties.outputs --output json
