#!/usr/bin/env bash
# Swaps the stream over to a single guest mix (looped for the duration),
# optionally with a different video too, backing up the normal shuffled
# rotation (and the normal video, if swapped) first so both can be
# restored afterwards with 10b_restore_rotation.sh.
#
# Usage:
#   10_start_guest_set.sh "/path/to/guest_mix.wav" "GUEST NAME - SET TITLE"
#   10_start_guest_set.sh "/path/to/guest_mix.wav" "GUEST NAME - SET TITLE" "/path/to/guest_video.mp4"
set -euo pipefail

ASSETS=/home/pondlife/assets
GUEST_FILE="${1:-}"
GUEST_DISPLAY="${2:-GUEST SET}"
GUEST_VIDEO="${3:-}"

if [ -z "$GUEST_FILE" ] || [ ! -f "$GUEST_FILE" ]; then
  echo "Usage: $0 \"/path/to/guest_mix.wav\" \"GUEST NAME - SET TITLE\" [\"/path/to/guest_video.mp4\"]"
  echo "File not found: $GUEST_FILE"
  exit 1
fi

if [ -n "$GUEST_VIDEO" ] && [ ! -f "$GUEST_VIDEO" ]; then
  echo "Video file not found: $GUEST_VIDEO"
  exit 1
fi

# Back up the normal rotation, but only if a backup doesn't already exist —
# running this twice in a row (e.g. by mistake) shouldn't overwrite your
# real backup with another guest set's files.
if [ ! -f "$ASSETS/playlist.txt.normal" ]; then
  cp "$ASSETS/playlist.txt" "$ASSETS/playlist.txt.normal"
  cp "$ASSETS/cue.txt" "$ASSETS/cue.txt.normal"
  echo "Backed up normal rotation."
else
  echo "Backup already exists (normal rotation), not overwriting it."
  echo "If you meant to start a fresh guest set, run 10b_restore_rotation.sh first."
  exit 1
fi

# If a custom video was given, swap loop.m4v out too, backing up the
# original the same way.
if [ -n "$GUEST_VIDEO" ]; then
  cp "$ASSETS/loop.m4v" "$ASSETS/loop.m4v.normal"
  cp "$GUEST_VIDEO" "$ASSETS/loop.m4v"
  echo "Backed up normal video, swapped in guest video."
fi

# Escape single quotes for safe embedding, same as 03_generate_playlist.sh.
escape_sq() {
  local s="$1"
  local sq="'"
  local esc="'\\''"
  echo "${s//$sq/$esc}"
}

# Sanitizes a display title before it gets embedded via file_packet_meta.
# Strips newlines/control characters (which could otherwise inject extra
# lines into the metadata log the watcher tails) and caps the length —
# an unusually long title increases the odds of the write to
# nowplaying_raw.log getting split across the watcher's read buffer,
# which can make it miss the "title=" line and momentarily fall through
# to unrelated ametadata output (e.g. raw frame/pts lines) instead.
# Especially relevant here since GUEST_DISPLAY comes straight from a
# free-form command-line argument, with no length or content checks.
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

GUEST_DISPLAY="$(sanitize_title "${GUEST_DISPLAY^^}")"

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$GUEST_FILE" </dev/null)

> "$ASSETS/playlist.txt"
echo "file '$(escape_sq "$GUEST_FILE")'" >> "$ASSETS/playlist.txt"
echo "file_packet_meta title '$(escape_sq "$GUEST_DISPLAY")'" >> "$ASSETS/playlist.txt"

> "$ASSETS/cue.txt"
printf "%s\t%s\n" "$DURATION" "$GUEST_DISPLAY" >> "$ASSETS/cue.txt"

systemctl restart pondlife-stream pondlife-nowplaying

echo ""
echo "Guest set is live: $GUEST_DISPLAY"
echo "It will loop (-stream_loop -1 covers a single file same as a full playlist)."
if [ -n "$GUEST_VIDEO" ]; then
  echo "Custom video is live too."
fi
echo "Run 10b_restore_rotation.sh when the set is over."
