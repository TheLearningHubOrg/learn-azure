#!/usr/bin/env bash
# Delete everything the guide created by removing the resource group.
# Usage: scripts/teardown.sh <resource-group>
set -euo pipefail

RG="${1:?usage: teardown.sh <resource-group>}"

az resource list --resource-group "$RG" --query "[].{name:name, type:type}" -o table
read -r -p "Delete resource group '$RG' and everything above? Type the name to confirm: " answer
[[ "$answer" == "$RG" ]] || { echo "aborted"; exit 1; }

az group delete --name "$RG" --yes --no-wait
echo "Deletion of $RG started. Track it with: az group show -n $RG"
