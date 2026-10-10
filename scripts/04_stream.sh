#!/usr/bin/env bash
# Main streaming process — loops the video, mixes shuffled tracks with the
# 60-second watermark loop, and pushes the result to YouTube over RTMP.
set -euo pipefail

ASSETS=/home/pondlife/assets
LOGS=/home/pondlife/logs

# Stream key lives in its own file, never in this script or in git.
# Create it once with:
#   echo "your-stream-key" > /home/pondlife/.stream_key
#   chmod 600 /home/pondlife/.stream_key
STREAM_KEY_FILE=/home/pondlife/.stream_key
if [ ! -f "$STREAM_KEY_FILE" ]; then
  echo "Missing $STREAM_KEY_FILE — put your YouTube stream key in there first."
  exit 1
fi
STREAM_KEY=$(cat "$STREAM_KEY_FILE")

VIDEO="$ASSETS/loop.m4v"
PLAYLIST="$ASSETS/playlist.txt"
WATERMARK="$ASSETS/watermark_loop.wav"
NOWPLAYING="$ASSETS/nowplaying.txt"
PROGRESS_FILE="$ASSETS/progress.log"
RAW_META_LOG="$ASSETS/nowplaying_raw.log"
# --- Watermark mixing ---
# The music ducks automatically whenever the watermark is actually
# playing (sidechaincompress uses the watermark as a trigger signal, not
# something that gets output itself), then swells back up naturally once
# it finishes, same technique radio uses under a DJ voiceover. This is
# what makes the tag genuinely function as a watermark rather than a
# pleasant blend — it needs to interrupt the track enough to be a
# deterrent, not just add texture underneath it.
FONT="$ASSETS/fonts/sequel-sans-bold-disp.ttf"
RTMP_URL="rtmp://a.rtmp.youtube.com/live2/${STREAM_KEY}"

# drawtext needs the file to exist before ffmpeg starts, even if empty.
touch "$NOWPLAYING"

# Reset both logs on every start. progress.log stops it growing unbounded
# across a long-running stream. nowplaying_raw.log is what the overlay
# watcher tails for the real per-track metadata tag — see
# 05_nowplaying_watcher.sh.
: > "$PROGRESS_FILE"
: > "$RAW_META_LOG"

if [ ! -f "$FONT" ]; then
  echo "Missing $FONT — upload the licensed font file there first."
  exit 1
fi

# --- Bitrate / frame rate ---
# Set to 30fps / 4500k by default to stay well inside the droplet's 2TB
# monthly transfer cap for a stream that never stops. Bump FPS to 60 and
# BITRATE up to 6000k-12000k only once you've checked real usage against
# your transfer allowance (DigitalOcean shows this in the droplet dashboard).
FPS=30
BITRATE="4500k"
MAXRATE="4500k"
BUFSIZE="9000k"

# Overlay: black text on a white box, top-right corner. Adjust fontsize/position
# to taste once you see it against loop.m4v.
DRAWTEXT="drawtext=fontfile=${FONT}:textfile=${NOWPLAYING}:reload=1:expansion=none:fontcolor=black:fontsize=64:box=1:boxcolor=0xFFFFFF@0.92:boxborderw=24:x=w-text_w-40:y=40"

ffmpeg \
  -re -stream_loop -1 -i "$VIDEO" \
  -stream_loop -1 -f concat -safe 0 -i "$PLAYLIST" \
  -stream_loop -1 -i "$WATERMARK" \
  -filter_complex "[0:v]${DRAWTEXT}[vout];[1:a]ametadata=mode=print:key=title:file=${RAW_META_LOG}:direct=1[a1m];[a1m][2:a]sidechaincompress=threshold=0.03:ratio=8:attack=50:release=800[ducked];[ducked][2:a]amix=inputs=2:duration=first:dropout_transition=0:weights='1 0.7':normalize=0[aout]" \
  -map "[vout]" -map "[aout]" \
  -c:v libx264 -preset ultrafast \
  -b:v "$BITRATE" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
  -pix_fmt yuv420p -g $((FPS * 2)) -r "$FPS" \
  -c:a aac -b:a 160k -ar 44100 \
  -progress "$PROGRESS_FILE" -stats_period 1 \
  -f flv "$RTMP_URL" \
  >> "$LOGS/stream.log" 2>&1
