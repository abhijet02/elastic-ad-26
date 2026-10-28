#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
parent=$(dirname "$ROOT")
name=$(basename "$ROOT")
output="$parent/elastic-ad-linux.tar.gz"
COPYFILE_DISABLE=1 tar --exclude='__pycache__' --exclude='*.pyc' \
  -czf "$output" -C "$parent" \
  "$name/README.md" "$name/.gitignore" "$name/.env.example" \
  "$name/docker-compose.yml" \
  "$name/config" "$name/dashboards" "$name/scripts" "$name/docs" \
  "$name/winlogbeat_2026-10-28_0539.zip"
printf 'Linux VM bundle: %s\n' "$output"
