#!/usr/bin/env bash
# Provision the learn-azure infrastructure with Bicep.
# Usage: scripts/provision.sh <resource-group> [location]
# Requires: az CLI (logged in with `az login`), Bicep (bundled with az).
set -euo pipefail

RG="${1:?usage: provision.sh <resource-group> [location]}"
LOCATION="${2:-eastus2}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/infra/main.bicep"
PARAMS="$ROOT/infra/main.bicepparam"

# 1. Confirm which subscription we are about to touch.
az account show --query "{subscription:name, id:id, user:user.name}" -o table

# 2. Lint and compile the templates locally before anything reaches ARM.
az bicep build --file "$TEMPLATE" --stdout > /dev/null

# 3. Create (or update) the resource group. This call is idempotent.
az group create --name "$RG" --location "$LOCATION" --tags project=learn-azure -o none

# 4. Preview the change set. Review it the way you would review a code diff.
az deployment group what-if \
  --resource-group "$RG" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS"

read -r -p "Apply these changes? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "aborted"; exit 1; }

# 5. Deploy and capture outputs for the next scripts.
az deployment group create \
  --name "learn-azure-$(date +%Y%m%d%H%M%S)" \
  --resource-group "$RG" \
  --template-file "$TEMPLATE" \
  --parameters "$PARAMS" \
  --query properties.outputs -o json | tee "$ROOT/.deploy-outputs.json"

echo "Provisioned. Next: scripts/deploy-code.sh $RG"
