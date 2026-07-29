#!/bin/sh
set -eu

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="/backups/mongo_${TIMESTAMP}.gz"

mongodump --host mongodb --port 27017 --db LibreChat --gzip --archive > "$ARCHIVE"
echo "mongodump OK: $ARCHIVE"