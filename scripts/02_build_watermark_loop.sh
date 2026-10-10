#!/usr/bin/env bash
# Builds a rotating watermark loop from every .wav clip in assets/watermarks/.
# Each clip is first normalized to a consistent peak level (so a quietly
# recorded tag doesn't sit far below a hot one), then padded to exactly 60
# seconds of silence, then all padded clips are joined into one file. The
# stream loops that whole file continuously, so a different tag fires every
# 60 seconds, cycling through everything in the folder before repeating.
set -euo pipefail

ASSETS=/home/pondlife/assets
WATERMARKS_DIR="$ASSETS/watermarks"
TMP_DIR="$ASSETS/.watermark_tmp"
OUTPUT="$ASSETS/watermark_loop.wav"
CONCAT_LIST="$ASSETS/.watermark_concat.txt"
TARGET_PEAK="-1"   # dB — every clip gets normalized to peak at roughly this level

if [ ! -d "$WATERMARKS_DIR" ]; then
  echo "Missing $WATERMARKS_DIR — put your watermark .wav clips there first."
  exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
> "$CONCAT_LIST"

i=0
while IFS= read -r f; do
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" </dev/null)
  if (( $(echo "$DURATION >= 60" | bc -l) )); then
    echo "Skipping $f — 60s or longer, trim it shorter first."
    continue
  fi

  MAXVOL=$(ffmpeg -nostdin -hide_banner -i "$f" -af volumedetect -f null - </dev/null 2>&1 | grep "max_volume:" | awk '{print $5}')
  GAIN=$(echo "$TARGET_PEAK - ($MAXVOL)" | bc)
  echo "$(basename "$f"): peak ${MAXVOL}dB, applying ${GAIN}dB gain"

  i=$((i+1))
  PADDED="$TMP_DIR/padded_$i.wav"
  ffmpeg -nostdin -y -hide_banner -loglevel error -i "$f" -af "volume=${GAIN}dB,apad" -t 60 -ar 44100 -ac 2 "$PADDED"
  echo "file '$PADDED'" >> "$CONCAT_LIST"
done < <(find "$WATERMARKS_DIR" -name "*.wav" | sort)

ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$CONCAT_LIST" -c copy "$OUTPUT"

COUNT=$(find "$WATERMARKS_DIR" -name "*.wav" | wc -l)
echo "Built $OUTPUT — rotates through $COUNT watermark clips, one per 60s slot"
echo "(full rotation takes $(echo "$COUNT * 1" | bc) minutes before repeating)."
