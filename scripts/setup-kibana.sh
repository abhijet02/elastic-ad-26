#!/bin/bash
set -euo pipefail
# Generated secrets are hex so they can be safely encoded in this JSON string.
[[ "$KIBANA_SYSTEM_PASSWORD" =~ ^[a-fA-F0-9]{64}$ ]] || {
  echo 'KIBANA_SYSTEM_PASSWORD must be 64 hexadecimal characters.' >&2; exit 1;
}
curl -fsS -u "elastic:$ELASTIC_PASSWORD" \
  -H 'Content-Type: application/json' \
  -X POST http://elasticsearch:9200/_security/user/kibana_system/_password \
  --data-binary "{\"password\":\"$KIBANA_SYSTEM_PASSWORD\"}"
printf '\nKibana system user configured.\n'
