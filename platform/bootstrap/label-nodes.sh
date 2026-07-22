#!/usr/bin/env bash
set -euo pipefail

sudo k3s kubectl label node nat-server disk=nat-media --overwrite
sudo k3s kubectl label node nat-server gpu=nvidia-gtx1060 --overwrite
sudo k3s kubectl label node gwserver disk=kostyan-media --overwrite
sudo k3s kubectl label node gwserver kubernetes.io/role=worker --overwrite

sudo k3s kubectl get nodes --show-labels