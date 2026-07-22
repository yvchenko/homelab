#!/usr/bin/env bash
set -euo pipefail

# k3s server bootstrap — nat-server (control-plane)

curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip=100.83.164.52 \
  --advertise-address=100.83.164.52 \
  --flannel-iface=tailscale0 \
  --tls-san=nat-server.salmon-halfmoon.ts.net

sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes