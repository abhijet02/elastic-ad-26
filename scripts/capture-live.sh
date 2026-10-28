#!/bin/bash
set -euo pipefail
umask 077
ROOT=$(cd "$(dirname "$0")/.." && pwd)
host=${1:-admiral@10.42.65.171}
case "$host" in -*|'') echo 'Invalid SSH destination' >&2; exit 1 ;; esac
ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" true
mkdir -p "$ROOT/private"
dest=$(mktemp -d "$ROOT/private/live.XXXXXXXX")
# Shellwords escapes the Python source, never a password.
command=$(ruby -rshellwords -e 'print "sudo -S -p \"\" python3 -c " + Shellwords.escape(File.read(ARGV.fetch(0)))' "$ROOT/scripts/export-live-remote.py")
trap 'unset password' EXIT
IFS= read -r -s -p 'VM sudo password: ' password
printf '\n'
if ! printf '%s\n' "$password" | ssh -o ConnectTimeout=15 "$host" "$command" > "$dest/live.tar.gz"; then
  echo "Export failed. Partial output in $dest" >&2
  exit 1
fi
tar -tzf "$dest/live.tar.gz" > "$dest/archive-list.txt"
mkdir "$dest/source"
tar -xzf "$dest/live.tar.gz" -C "$dest/source"
printf 'Live export saved to %s\nNo running services changed. Keep this capture private.\n' "$dest"
