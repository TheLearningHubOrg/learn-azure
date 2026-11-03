#!/usr/bin/env bash
# Build, test and publish the Functions code to the app created by provision.sh.
# Usage: scripts/deploy-code.sh <resource-group>
# Requires: Node.js 22+, Azure Functions Core Tools v4 (`func`), az CLI.
set -euo pipefail

RG="${1:?usage: deploy-code.sh <resource-group>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1. Resolve the Function App name from the latest deployment in the group.
APP="$(az functionapp list --resource-group "$RG" --query "[0].name" -o tsv)"
[[ -n "$APP" ]] || { echo "no function app found in $RG" >&2; exit 1; }

# 2. Reproducible install, tests as a release gate, then compile.
npm ci
npm test
npm run build

# 3. Ship only runtime dependencies (typescript and tsx stay out of the package).
#    The next `npm ci` restores the dev dependencies.
npm prune --omit=dev

# 4. Publish. For Flex Consumption the package lands in the deployment blob container.
func azure functionapp publish "$APP"

echo "Deployed to https://$(az functionapp show -g "$RG" -n "$APP" --query defaultHostName -o tsv)"
