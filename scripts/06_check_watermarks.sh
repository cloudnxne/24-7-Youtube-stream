#!/usr/bin/env bash
# Checks each 30-second slot of watermark_loop.wav for actual audio content,
# rather than just trusting that the build script ran without errors.
# Run this any time after 02_build_watermark_loop.sh to confirm every clip
# genuinely made it into the rotation.
set -euo pipefail

ASSETS=/home/pondlife/assets
WATERMARK="$ASSETS/watermark_loop.wav"
WATERMARKS_DIR="$ASSETS/watermarks"

if [ ! -f "$WATERMARK" ]; then
  echo "Missing $WATERMARK — run 02_build_watermark_loop.sh first."
  exit 1
fi

TOTAL_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WATERMARK" </dev/null)
SLOT_COUNT=$(echo "$TOTAL_DURATION / 30" | bc)
CLIP_COUNT=$(find "$WATERMARKS_DIR" -name "*.wav" | wc -l)

echo "watermark_loop.wav is ${TOTAL_DURATION}s long (${SLOT_COUNT} slots of 30s)."
echo "There are ${CLIP_COUNT} clips in $WATERMARKS_DIR."
if [ "$SLOT_COUNT" -ne "$CLIP_COUNT" ]; then
  echo "MISMATCH — one or more clips likely got skipped (probably for being 30s or longer)."
fi
echo ""

i=0
find "$WATERMARKS_DIR" -name "*.wav" | sort | while read -r f; do
  START=$((i * 30))
  echo "=== Slot $i — should be '$(basename "$f")', starts at ${START}s ==="
  ffmpeg -nostdin -hide_banner -loglevel info -ss "$START" -t 30 -i "$WATERMARK" -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume" || echo "  (no volume data — slot may be empty)"
  echo ""
  i=$((i + 1))
done
