#!/usr/bin/env bash
# Restores the normal shuffled rotation (and normal video, if it was
# swapped) after a guest set, using the backups 10_start_guest_set.sh
# made before switching over.
set -euo pipefail

ASSETS=/home/pondlife/assets

if [ ! -f "$ASSETS/playlist.txt.normal" ]; then
  echo "No backup found (playlist.txt.normal) — nothing to restore."
  echo "Either no guest set is currently running, or it's already been restored."
  exit 1
fi

mv "$ASSETS/playlist.txt.normal" "$ASSETS/playlist.txt"
mv "$ASSETS/cue.txt.normal" "$ASSETS/cue.txt"

if [ -f "$ASSETS/loop.m4v.normal" ]; then
  mv "$ASSETS/loop.m4v.normal" "$ASSETS/loop.m4v"
  echo "Restored normal video."
fi

systemctl restart pondlife-stream pondlife-nowplaying

echo "Normal rotation restored and live."
