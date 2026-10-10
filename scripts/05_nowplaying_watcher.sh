#!/usr/bin/env bash
# Updates nowplaying.txt from the real per-track metadata tag embedded
# directly in the playlist (via file_packet_meta in 03_generate_playlist.sh)
# and printed by ffmpeg's ametadata filter as it actually decodes each
# track (see 04_stream.sh).
#
# This is not a prediction of any kind — the value comes from the same
# frames actually being decoded and streamed, so it cannot drift, count
# wrong, or fall out of sync, regardless of how many hours or days the
# stream runs. ametadata prints on every frame that carries the tag (not
# just once per track), so this just ignores repeats and only writes when
# the value actually changes.
set -euo pipefail

ASSETS=/home/pondlife/assets
NOWPLAYING="$ASSETS/nowplaying.txt"
RAW_META_LOG="$ASSETS/nowplaying_raw.log"

while [ ! -f "$RAW_META_LOG" ]; do
  sleep 1
done

LAST=""
tail -F -n0 "$RAW_META_LOG" 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *title=*)
      VAL="${line#*title=}"
      if [ "$VAL" != "$LAST" ]; then
        printf '%s\n' "$VAL" > "$NOWPLAYING"
        LAST="$VAL"
      fi
      ;;
  esac
done
