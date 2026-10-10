#!/usr/bin/env bash
# Converts every track in assets/tracks/ (wav or mp3) into a uniform WAV
# format in assets/tracks_normalized/, with a short fade baked into the
# start and end of each track.
#
# The uniform-format conversion exists because ffmpeg's concat demuxer is
# unreliable when segments have different codecs/sample specs mixed
# directly together — feeding raw WAV and compressed MP3 into the same
# concat playlist causes the decoder to desync and produces audible
# static/garbage audio at the transitions. Normalizing every track to the
# same spec up front avoids that entirely.
#
# The fade exists so tracks dip to silence and back at each boundary
# rather than cutting abruptly. This isn't a true overlapping crossfade
# (that would need to know the next track while the current one is still
# playing, which the sequential concat playlist doesn't support) — it's a
# fade-out into a fade-in, the standard radio-automation approach, and it
# works cleanly with how tracks are actually played here.
#
# Safe to re-run any time — already-normalized tracks are skipped, so
# adding a handful of new tracks doesn't mean reconverting everything.
set -euo pipefail

ASSETS=/home/pondlife/assets
TRACKS_DIR="$ASSETS/tracks"
NORM_DIR="$ASSETS/tracks_normalized"
FADE_DUR=2   # seconds of fade in/out at each track boundary

mkdir -p "$NORM_DIR"

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

  # Clamp the fade for very short tracks so the in-fade and out-fade never
  # overlap — cap each one at a quarter of the track's own length.
  FADE=$(awk -v d="$DURATION" -v f="$FADE_DUR" 'BEGIN{q=d/4; print (q<f)?q:f}')
  FADE_OUT_START=$(awk -v d="$DURATION" -v f="$FADE" 'BEGIN{print d-f}')

  ffmpeg -nostdin -y -hide_banner -loglevel error -i "$f" \
    -af "afade=t=in:d=${FADE},afade=t=out:st=${FADE_OUT_START}:d=${FADE}" \
    -ar 44100 -ac 2 -c:a pcm_s16le "$OUT"
  COUNT=$((COUNT + 1))
done < <(find "$TRACKS_DIR" \( -iname "*.wav" -o -iname "*.mp3" \) | sort)

echo "Normalized $COUNT new track(s), skipped $SKIPPED already up to date."
echo "Normalized tracks live in $NORM_DIR — 03_generate_playlist.sh reads from here."
