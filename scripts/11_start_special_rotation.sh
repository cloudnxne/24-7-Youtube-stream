#!/usr/bin/env bash
# Temporarily takes over the stream with a themed track set, played in
# strict file order (no shuffle), looping via the stream's normal
# -stream_loop -1 mechanism (a single ordered pass is enough — the stream
# already loops the whole playlist back to the start on its own).
#
# Backs up the normal rotation first, the SAME way 10_start_guest_set.sh
# does, so 10b_restore_rotation.sh restores things afterwards (including
# the video, if swapped) regardless of which of the two was used.
#
# Usage:
#   11_start_special_rotation.sh "/path/to/source_folder" ["LABEL PREFIX"]
#   11_start_special_rotation.sh "/path/to/source_folder" ["LABEL PREFIX"] "/path/to/video.mp4"
#
# The source folder should contain wav and/or mp3 files, named however
# they came (e.g. "01 Artist - Title.wav" or just "Artist - Title.mp3").
# They get normalized (uniform format + fade, same treatment as the main
# catalogue) into their own cache folder, then built into a single
# strictly-ordered playlist sorted by filename.
#
# If you pass a LABEL PREFIX (e.g. "STYN USB"), it's prepended to every
# track's on-screen name, e.g. "STYN USB: ARTIST - TITLE". Leave it off
# (pass "") for plain "ARTIST - TITLE".
set -euo pipefail

ASSETS=/home/pondlife/assets
SOURCE_DIR="${1:-}"
LABEL_PREFIX="${2:-}"
CUSTOM_VIDEO="${3:-}"
NORM_DIR="$ASSETS/special_normalized"
PLAYLIST="$ASSETS/playlist.txt"
CUE="$ASSETS/cue.txt"
FADE_DUR=2

if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
  echo "Usage: $0 \"/path/to/source_folder\" [\"LABEL PREFIX\"] [\"/path/to/video.mp4\"]"
  echo "Folder not found: $SOURCE_DIR"
  exit 1
fi

if [ -n "$CUSTOM_VIDEO" ] && [ ! -f "$CUSTOM_VIDEO" ]; then
  echo "Video file not found: $CUSTOM_VIDEO"
  exit 1
fi

if [ ! -f "$ASSETS/playlist.txt.normal" ]; then
  cp "$PLAYLIST" "$ASSETS/playlist.txt.normal"
  cp "$CUE" "$ASSETS/cue.txt.normal"
  echo "Backed up normal rotation."
else
  echo "Backup already exists (normal rotation), not overwriting it."
  echo "Run 10b_restore_rotation.sh first if you meant to start a fresh takeover."
  exit 1
fi

if [ -n "$CUSTOM_VIDEO" ]; then
  cp "$ASSETS/loop.m4v" "$ASSETS/loop.m4v.normal"
  cp "$CUSTOM_VIDEO" "$ASSETS/loop.m4v"
  echo "Backed up normal video, swapped in custom video."
fi

escape_sq() {
  local s="$1"
  local sq="'"
  local esc="'\\''"
  echo "${s//$sq/$esc}"
}

# Sanitizes a display title before it gets embedded via file_packet_meta.
# Transliterates accented characters (é, ñ, ü, etc.) to their plain ASCII
# equivalent first — the overlay font doesn't have full Unicode coverage,
# so an accented character can render as a missing glyph or vanish
# entirely rather than showing anything sensible. Then strips newlines/
# control characters (which could otherwise inject extra lines into the
# metadata log the watcher tails) and caps the length — an unusually long
# title increases the odds of the write to nowplaying_raw.log getting
# split across the watcher's read buffer, which can make it miss the
# "title=" line and momentarily fall through to unrelated ametadata
# output (e.g. raw frame/pts lines) instead.
MAX_TITLE_LEN=80
sanitize_title() {
  local s="$1"
  s="$(printf '%s' "$s" | iconv -f utf8 -t ascii//TRANSLIT 2>/dev/null || printf '%s' "$s")"
  s="$(printf '%s' "$s" | tr -d '\r\n' | tr -dc '[:print:]')"
  if [ "${#s}" -gt "$MAX_TITLE_LEN" ]; then
    s="${s:0:$((MAX_TITLE_LEN - 3))}..."
  fi
  echo "$s"
}

mkdir -p "$NORM_DIR"

echo "== Normalizing tracks from $SOURCE_DIR (uniform format + fade) =="
COUNT=0
SKIPPED=0
while IFS= read -r f; do
  BASENAME=$(basename "$f")
  BASENAME="${BASENAME%.*}"
  OUT="$NORM_DIR/${BASENAME}.wav"
  if [ -f "$OUT" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" </dev/null)
  FADE=$(awk -v d="$DURATION" -v f="$FADE_DUR" 'BEGIN{q=d/4; print (q<f)?q:f}')
  FADE_OUT_START=$(awk -v d="$DURATION" -v f="$FADE" 'BEGIN{print d-f}')
  ffmpeg -nostdin -y -hide_banner -loglevel error -i "$f" \
    -af "afade=t=in:d=${FADE},afade=t=out:st=${FADE_OUT_START}:d=${FADE}" \
    -ar 44100 -ac 2 -c:a pcm_s16le "$OUT"
  COUNT=$((COUNT + 1))
done < <(find "$SOURCE_DIR" \( -iname "*.wav" -o -iname "*.mp3" \) | sort -V)
echo "Normalized $COUNT new track(s), skipped $SKIPPED already up to date."

echo "== Building strictly-ordered playlist (no shuffle, single pass) =="
> "$PLAYLIST"
> "$CUE"

find "$NORM_DIR" -iname "*.wav" | sort -V | while read -r f; do
  BASENAME=$(basename "$f")
  BASENAME="${BASENAME%.*}"
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" </dev/null)

  # Strip a leading track-number prefix like "01 " or "A1. "
  if [[ "$BASENAME" =~ ^[A-Z]*[0-9]+[\.\ ]+(.*)$ ]]; then
    BASENAME="${BASH_REMATCH[1]}"
  fi

  if [[ "$BASENAME" =~ ^pondlifeparty(™)?[[:space:]]*-[[:space:]]*(.*)$ ]]; then
    REST="${BASH_REMATCH[2]}"
    if [[ "$REST" =~ ^.*-[[:space:]]*[0-9]{1,2}[[:space:]]+(.*)$ ]]; then
      BASENAME="${BASH_REMATCH[1]}"
    else
      BASENAME="$REST"
    fi
  fi

  if [[ "$BASENAME" == *" - "* ]]; then
    ARTIST="${BASENAME%% - *}"
    REST="${BASENAME#* - }"
    TITLE="${REST%% \[*}"
    DISPLAY="${ARTIST^^} - ${TITLE^^}"
  else
    DISPLAY="${BASENAME^^}"
  fi

  if [ -n "$LABEL_PREFIX" ]; then
    DISPLAY="${LABEL_PREFIX^^}: ${DISPLAY}"
  fi

  DISPLAY="$(sanitize_title "$DISPLAY")"

  echo "file '$(escape_sq "$f")'" >> "$PLAYLIST"
  echo "file_packet_meta title '$(escape_sq "$DISPLAY")'" >> "$PLAYLIST"

  printf "%s\t%s\n" "$DURATION" "$DISPLAY" >> "$CUE"
done

TRACK_COUNT=$(find "$NORM_DIR" -iname "*.wav" | wc -l)
echo "Built ordered playlist: $TRACK_COUNT tracks, no shuffle, single pass."
echo "(The stream loops this back to the start automatically once it reaches the end.)"

systemctl restart pondlife-stream pondlife-nowplaying

echo ""
echo "Special rotation is live."
if [ -n "$CUSTOM_VIDEO" ]; then
  echo "Custom video is live too."
fi
echo "Run 10b_restore_rotation.sh when it's time to switch back to the normal shuffle."
