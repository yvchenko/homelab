#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/opt/backups
RCLONE_CONF=/opt/rclone/rclone.conf
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
docker run --rm \
  -v "$RCLONE_CONF":/config/rclone/rclone.conf:ro \
  -v "$BACKUP_DIR":/data:ro \
  rclone/rclone \
  copy /data "$REMOTE" \
  --include "mongo_${TIMESTAMP}.gz" \
  --log-level INFO \
  --log-file /dev/stderr 2>> "$LOG"
echo "[$TIMESTAMP] rclone upload OK" >> "$LOG"

# --- cleanup local (keep last N days) ---
find "$BACKUP_DIR" -name "mongo_*.gz" -mtime +"$KEEP_DAYS" -delete
echo "[$TIMESTAMP] local cleanup done (kept last ${KEEP_DAYS} days)" >> "$LOG"

# --- cleanup remote ---
docker run --rm \
  -v "$RCLONE_CONF":/config/rclone/rclone.conf:ro \
  rclone/rclone \
  delete "$REMOTE" \
  --min-age 30d \
  --include "mongo_*.gz" \
  --log-level INFO 2>> "$LOG"