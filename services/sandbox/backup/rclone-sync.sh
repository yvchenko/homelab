#!/bin/sh
set -eu

REMOTE="nat:homelab-backups/nat-server"
LATEST=$(ls -t /backups/mongo_*.gz | head -1)

rclone copy /backups "$REMOTE" --include "$(basename "$LATEST")" --log-level INFO
echo "rclone upload OK"

find /backups -name "mongo_*.gz" -mtime +5 -delete
echo "local cleanup done"

rclone delete "$REMOTE" --min-age 30d --include "mongo_*.gz" --log-level INFO
echo "remote cleanup done"