#!/usr/bin/env bash
# Container entrypoint: prepares assets on first run, then keeps the overlay
# watcher and the ffmpeg stream running. If either dies the container exits,
# and Docker's restart policy brings the whole thing back.
set -uo pipefail

ASSETS=/home/pondlife/assets
SCRIPTS=/home/pondlife/scripts
echo $$ > /tmp/entrypoint.pid

PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
  pkill -P $$ 2>/dev/null || true
  exit 0
}
trap cleanup TERM INT

if [ ! -f "$ASSETS/watermark_loop.wav" ]; then
  echo "Building watermark loop..."
  "$SCRIPTS/02_build_watermark_loop.sh" || { echo "Watermark build failed"; exit 1; }
fi
if [ ! -f "$ASSETS/playlist.txt" ]; then
  echo "Building playlist..."
  "$SCRIPTS/03_generate_playlist.sh" || { echo "Playlist build failed"; exit 1; }
fi

"$SCRIPTS/05_nowplaying_watcher.sh" >> /home/pondlife/logs/nowplaying.log 2>&1 &
PIDS+=($!)
"$SCRIPTS/04_stream.sh" &
PIDS+=($!)

# Exit as soon as either process stops so the restart policy takes over.
wait -n
echo "A stream process exited, stopping container so it restarts."
cleanup
