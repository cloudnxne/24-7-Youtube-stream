#!/usr/bin/env bash
# Builds a shuffled ffmpeg concat playlist from the normalized tracks, with
# each track's display name embedded directly in the playlist itself via
# file_packet_meta. cue.txt is still written alongside for reference/
# debugging, but the overlay no longer depends on it — the name travels
# with the actual audio now, so there's nothing to predict or count, and
# nothing that can drift.
#
# Re-run any time you want a fresh shuffle order (e.g. via cron, or before
# a scheduled restart of the stream).
#
# Upload wav or mp3 files to assets/tracks/ as normal — this script runs
# 07_normalize_tracks.sh first, which converts anything new into a uniform
# WAV format in assets/tracks_normalized/. That's what actually gets built
# into the playlist, since mixing raw WAV and compressed MP3 directly in
# one concat playlist causes decoder errors and audible static.
#
# Expects files named "Artist - Title.wav" or "Artist - Title.mp3". Anything
# without a " - " in the name just gets shown as-is.
set -euo pipefail

ASSETS=/home/pondlife/assets
TRACKS_DIR="$ASSETS/tracks_normalized"
PLAYLIST="$ASSETS/playlist.txt"
CUE="$ASSETS/cue.txt"
REPEATS=${1:-20}   # number of shuffled passes concatenated together —
                    # bigger means longer before the running order repeats

# Escapes a value for safe embedding inside a single-quoted concat-demuxer
# string — every literal ' becomes '\'' (close quote, escaped quote, reopen
# quote). Needed for both file paths and metadata values, since real
# filenames in this library do contain apostrophes.
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
# nowplaying_raw.log getting split across the watcher's read buffer, which
# can make it miss the "title=" line and momentarily fall through to
# unrelated ametadata output (e.g. raw frame/pts lines) instead of the
# real title. Same protection used in 10_start_guest_set.sh and
# 11_start_special_rotation.sh — applied here too since a long title
# anywhere in the main catalogue can trigger the exact same issue.
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

/home/pondlife/scripts/07_normalize_tracks.sh

if [ ! -d "$TRACKS_DIR" ]; then
  echo "Missing $TRACKS_DIR — normalization didn't run correctly."
  exit 1
fi

> "$PLAYLIST"
> "$CUE"

for i in $(seq 1 "$REPEATS"); do
  find "$TRACKS_DIR" -iname "*.wav" | shuf | while read -r f; do
    BASENAME=$(basename "$f")
    BASENAME="${BASENAME%.*}"   # strip whatever extension it actually has
    DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" </dev/null)

    # Strip a leading vinyl side/track prefix like "A1. " or "B2. "
    if [[ "$BASENAME" =~ ^[A-Z]+[0-9]+\.\ (.*)$ ]]; then
      BASENAME="${BASH_REMATCH[1]}"
    fi

    # Strip the "pondlifeparty™ - <collection name> - NN " EP/compilation
    # prefix some batch exports carry, leaving the real track's own
    # "Artist - Title" (which is whatever follows the last "- NN " track
    # number, or the whole remainder if there's no track number at all).
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
      # Drop anything from the first "[" onwards — catalogue/mastering tags
      TITLE="${REST%% \[*}"
      DISPLAY="${ARTIST^^} - ${TITLE^^}"
    else
      DISPLAY="${BASENAME^^}"
    fi

    DISPLAY="$(sanitize_title "$DISPLAY")"

    echo "file '$(escape_sq "$f")'" >> "$PLAYLIST"
    echo "file_packet_meta title '$(escape_sq "$DISPLAY")'" >> "$PLAYLIST"

    printf "%s\t%s\n" "$DURATION" "$DISPLAY" >> "$CUE"
  done
done

TRACK_COUNT=$(find "$TRACKS_DIR" -iname "*.wav" | wc -l)
echo "Playlist built: $TRACK_COUNT tracks shuffled across $REPEATS passes."
echo "Written to $PLAYLIST and $CUE"
echo ""
echo "Note: the stream loops this whole file with -stream_loop -1, so once"
echo "you restart the stream after regenerating this, the new order takes over."
echo "Restart pondlife-nowplaying.service too to pick up the fresh order."
