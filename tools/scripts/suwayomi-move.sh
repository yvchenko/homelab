#!/bin/bash
#
# suwayomi-move.sh
#
# Flattens Suwayomi's per-source download structure into a single
# per-series structure that Komga can scan as a library.
#
# Suwayomi stores downloads as:
#   /mnt/media/suwayomi/mangas/<source-site>/<series-name>/<chapter files>
#
# This script merges all source-site variants of a series into:
#   /mnt/media/manga/<series-name>/<chapter files>
#
# Original files are MOVED (not copied) — Suwayomi's originals are not
# preserved. Empty source-site folders are cleaned up after the move.
#
# Usage:
#   Run manually:      ./suwayomi-move.sh
#   Run via cron:       0 4 * * * /path/to/suwayomi-move.sh
#
# Config:
#   SRC  - Suwayomi's download root (per-source-site folders)
#   DEST - Komga library root (flat per-series folders)
#   LOG  - transfer log file
#
# Notes:
#   - If the same series exists under two different source-site
#     folders, their chapters are merged into one destination folder.
#     Chapter filename collisions across sources will overwrite silently.
#   - Series names must match exactly across sources to merge correctly;
#     inconsistent naming from different scrapers will produce separate
#     Komga series entries.

SRC="/mnt/media/suwayomi/mangas"
DEST="/mnt/media/manga"
LOG="/var/log/suwayomi-move.log"

echo "$(date): starting transfer" >> "$LOG"

for source_dir in "$SRC"/*/; do
  for series_dir in "$source_dir"*/; do
    [ -d "$series_dir" ] || continue
    series_name=$(basename "$series_dir")
    mkdir -p "$DEST/$series_name"
    mv "$series_dir"* "$DEST/$series_name/" 2>> "$LOG"
    echo "$(date): moved $series_name" >> "$LOG"
  done
done

find "$SRC" -mindepth 1 -type d -empty -delete

echo "$(date): done" >> "$LOG"