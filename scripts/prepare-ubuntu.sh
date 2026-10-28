#!/bin/bash
# Run on a fresh Ubuntu VM. Installs Docker and configures Elasticsearch's mmap limit.
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Run this on the Linux VM.' >&2; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu ]] || { echo 'Automatic host preparation supports Ubuntu only.' >&2; exit 1; }
if [[ $EUID -eq 0 ]]; then SUDO=(); else SUDO=(sudo); fi
if ! command -v docker >/dev/null 2>&1; then
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y ca-certificates curl openssl
  "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
  "${SUDO[@]}" curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  "${SUDO[@]}" chmod a+r /etc/apt/keyrings/docker.asc
  arch=$(dpkg --print-architecture)
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
    "${UBUNTU_CODENAME:-$VERSION_CODENAME}" "$arch" | "${SUDO[@]}" tee /etc/apt/sources.list.d/docker.sources >/dev/null
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  docker compose version >/dev/null || {
    echo 'Docker exists but Compose v2 is missing. Install the Compose plugin for this Docker installation.' >&2
    exit 1
  }
  command -v openssl >/dev/null || "${SUDO[@]}" apt-get install -y openssl
fi
"${SUDO[@]}" systemctl enable --now docker
printf 'vm.max_map_count=262144\n' | "${SUDO[@]}" tee /etc/sysctl.d/99-elastic-ad.conf >/dev/null
"${SUDO[@]}" sysctl -p /etc/sysctl.d/99-elastic-ad.conf
echo 'Host prepared. Run sudo bash scripts/deploy-linux.sh from the project directory.'
