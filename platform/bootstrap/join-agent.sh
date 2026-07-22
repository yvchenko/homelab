#!/usr/bin/env bash
set -euo pipefail

# k3s agent join — gwserver (worker)

TOKEN="$1"  # pass the current token from nat-server:/var/lib/rancher/k3s/server/node-token

curl -sfL https://get.k3s.io | \
  K3S_URL=https://nat-server.salmon-halfmoon.ts.net:6443 \
  K3S_TOKEN="${TOKEN}" \
  INSTALL_K3S_EXEC="--node-ip=100.83.127.86 --flannel-iface=tailscale0" \
  sh -

sudo systemctl status k3s-agent --no-pager