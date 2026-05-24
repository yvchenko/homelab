#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/opt/backups
COMPOSE_FILE=/home/nat/homelab/services/rclone/docker-compose.yml
REMOTE="nat:homelab-backups/nat-server"
LOG=/var/log/mongo_backup.log
KEEP_DAYS=5
MONGO_CONTAINER=chat-mongodb

echo "[$TIMESTAMP] === backup start ===" >> "$LOG"

# --- dump ---
ARCHIVE="$BACKUP_DIR/mongo_${TIMESTAMP}.gz"
docker exec "$MONGO_CONTAINER" mongodump --archive --gzip > "$ARCHIVE" 2>> "$LOG"
echo "[$TIMESTAMP] mongodump OK: $ARCHIVE ($(du -sh "$ARCHIVE" | cut -f1))" >> "$LOG"

# --- upload ---
docker compose -f "$COMPOSE_FILE" run --rm rclone \
  copy /data "$REMOTE" \
  --include "mongo_${TIMESTAMP}.gz" \
  --log-level INFO 2>> "$LOG"
echo "[$TIMESTAMP] rclone upload OK" >> "$LOG"

# --- local cleanup ---
find "$BACKUP_DIR" -name "mongo_*.gz" -mtime +"$KEEP_DAYS" -delete
echo "[$TIMESTAMP] local cleanup done (kept last ${KEEP_DAYS} days)" >> "$LOG"

# --- remote cleanup ---
docker compose -f "$COMPOSE_FILE" run --rm rclone \
  delete "$REMOTE" \
  --min-age 30d \
  --include "mongo_*.gz" \
  --log-level INFO 2>> "$LOG"
echo "[$TIMESTAMP] remote cleanup done" >> "$LOG"