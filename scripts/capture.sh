#!/bin/bash
# Run in Mac Terminal. Capture configuration without changing VM services.
set -euo pipefail
umask 077
ROOT=$(cd "$(dirname "$0")/.." && pwd)
host=${1:-admiral@10.42.65.171}
case "$host" in -*|'') printf 'Invalid SSH destination\n' >&2; exit 1 ;; esac
ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" true || {
  printf 'SSH key login must work first. See README section 1.\n' >&2
  exit 1
}
mkdir -p "$ROOT/private"
dest=$(mktemp -d "$ROOT/private/capture.XXXXXXXX")
trap 'unset password' EXIT
IFS= read -r -s -p 'VM sudo password: ' password
printf '\n'
remote() {
  if ! printf '%s\n' "$password" | ssh -o ConnectTimeout=15 "$host" "$1" > "$dest/$2"; then
    printf 'Capture failed: %s. Partial files: %s\n' "$2" "$dest" >&2
    exit 1
  fi
}
remote 'sudo -S -p "" sh -c '\''cd /root/elastic-ad && find . -maxdepth 4 -type f ! -path "*/data/*" ! -path "*/.git/*" ! -path "*/node_modules/*" -print'\''' file-list.txt
remote 'sudo -S -p "" tar --exclude=./data --exclude=./esdata --exclude=./elasticsearch-data --exclude=./kibanadata --exclude=./logs --exclude=./.git --exclude=./node_modules --exclude="*.log" -czf - -C /root/elastic-ad .' source.tar.gz
remote 'sudo -S -p "" sh -c '\''set -e; docker version; docker compose version; docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"; docker volume ls; docker ps -aq | xargs -r docker inspect --format "{{.Name}} {{json .Mounts}} {{json .Config.Labels}}"'\''' inventory.txt
tar -tzf "$dest/source.tar.gz" > "$dest/archive-list.txt"
printf 'Captured to %s\nContains private configuration. Do not commit. No services were changed.\n' "$dest"
