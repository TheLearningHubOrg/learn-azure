#!/usr/bin/env bash
# Call the deployed API end to end: health check, then one valid and one invalid order.
# Usage: scripts/smoke-test.sh <resource-group>
set -euo pipefail

RG="${1:?usage: smoke-test.sh <resource-group>}"
APP="$(az functionapp list --resource-group "$RG" --query "[0].name" -o tsv)"
HOST="$(az functionapp show -g "$RG" -n "$APP" --query defaultHostName -o tsv)"

# 1. Anonymous health endpoint.
curl -fsS "https://$HOST/api/health"
echo

# 2. Function-level key for the protected route. Read into a variable, never echoed.
KEY="$(az functionapp function keys list -g "$RG" -n "$APP" \
  --function-name createOrder --query default -o tsv)"

# 3. A valid order should return 202 Accepted.
status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "https://$HOST/api/orders" \
  -H "x-functions-key: $KEY" -H 'content-type: application/json' \
  -d '{"customerId":"cust-42","region":"eastus2","lines":[{"sku":"BOOK-001","quantity":1,"unitPriceCents":1999}]}')"
[[ "$status" == "202" ]] || { echo "expected 202, got $status" >&2; exit 1; }

# 4. An invalid order should return 400 Bad Request.
status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "https://$HOST/api/orders" \
  -H "x-functions-key: $KEY" -H 'content-type: application/json' -d '{}')"
[[ "$status" == "400" ]] || { echo "expected 400, got $status" >&2; exit 1; }

echo "smoke test passed"
