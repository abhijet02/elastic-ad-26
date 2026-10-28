#!/bin/bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Run deployment on your Linux VM.' >&2; exit 1; }
cd "$(dirname "$0")/.."
docker compose version >/dev/null
docker info >/dev/null
[[ $(cat /proc/sys/vm/max_map_count) -ge 262144 ]] || {
  echo 'Set vm.max_map_count to at least 262144; see scripts/prepare-ubuntu.sh.' >&2
  exit 1
}
if [[ ! -e .env ]]; then bash scripts/init-env.sh; fi
docker compose config --quiet
docker compose up -d --wait --wait-timeout 300 elasticsearch kibana
if [[ ! -e .restore-complete ]]; then
  docker compose --profile restore run --rm --no-deps restore
  touch .restore-complete
fi
docker compose ps
echo 'Stack is ready. Credentials are in .env. See README for SSH access and dashboard restore.'
