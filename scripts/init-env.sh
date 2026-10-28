#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
set -o noclobber
if [[ -e .env || -L .env ]]; then
  printf '.env already exists; refusing to overwrite it.\n' >&2
  exit 1
fi
{
  for key in ELASTIC_PASSWORD KIBANA_SYSTEM_PASSWORD KIBANA_ENCRYPTION_KEY KIBANA_SECURITY_ENCRYPTION_KEY KIBANA_REPORTING_ENCRYPTION_KEY; do
    secret=$(openssl rand -hex 32)
    printf '%s=%s\n' "$key" "$secret"
  done
  cat <<'ENV'
ES_HEAP=2g
ES_BIND_IP=127.0.0.1
ES_PORT=9200
KIBANA_BIND_IP=127.0.0.1
KIBANA_PORT=5601
KIBANA_PUBLIC_BASE_URL=http://localhost:5601
ENV
} > .env
printf 'Created private .env. Keep these secrets for subsequent restarts.\n'
