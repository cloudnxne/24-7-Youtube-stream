#!/usr/bin/env bash
# Isolated test: does file_packet_meta on the concat demuxer actually reach
# the ametadata filter in THIS ffmpeg build, for THIS exact codec path
# (pcm_s16le, same as the real tracks_normalized files)?
#
# Builds two throwaway 4-second sine-wave WAVs, concatenates them with a
# metadata tag on each, and checks whether "title=" prints exactly once
# per file. Doesn't touch the live stream at all.
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ffmpeg -y -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=4" -ar 44100 -ac 2 -c:a pcm_s16le "$TMP/tone_a.wav"
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "sine=frequency=880:duration=4" -ar 44100 -ac 2 -c:a pcm_s16le "$TMP/tone_b.wav"

echo "=== Trying 'file_packet_meta' (current directive name) ==="
cat > "$TMP/playlist.txt" << EOF
file '$TMP/tone_a.wav'
file_packet_meta title TONE_A
file '$TMP/tone_b.wav'
file_packet_meta title TONE_B
EOF

OUT1=$(ffmpeg -hide_banner -f concat -safe 0 -i "$TMP/playlist.txt" -map 0:a -af "ametadata=mode=print:key=title" -f null - 2>&1 || true)
COUNT1=$(echo "$OUT1" | grep -c "title=" || true)
echo "$OUT1" | grep "title=" || echo "(no title= lines at all)"
echo "--- lines matched: $COUNT1 ---"
echo ""

echo "=== Trying 'file_packet_metadata' (older directive name) ==="
cat > "$TMP/playlist2.txt" << EOF
file '$TMP/tone_a.wav'
file_packet_metadata title TONE_A
file '$TMP/tone_b.wav'
file_packet_metadata title TONE_B
EOF

OUT2=$(ffmpeg -hide_banner -f concat -safe 0 -i "$TMP/playlist2.txt" -map 0:a -af "ametadata=mode=print:key=title" -f null - 2>&1 || true)
COUNT2=$(echo "$OUT2" | grep -c "title=" || true)
echo "$OUT2" | grep "title=" || echo "(no title= lines at all)"
echo "--- lines matched: $COUNT2 ---"
echo ""

echo "=== VERDICT ==="
if [ "$COUNT1" -eq 2 ]; then
  echo "PASS — 'file_packet_meta' works, exactly 2 lines for 2 tracks."
elif [ "$COUNT2" -eq 2 ]; then
  echo "PASS — 'file_packet_metadata' (older name) works, exactly 2 lines for 2 tracks."
elif [ "$COUNT1" -gt 2 ] || [ "$COUNT2" -gt 2 ]; then
  echo "FAIL — printed more than once per track (per-frame flood, not per-file)."
else
  echo "FAIL — no title= output from either directive spelling. Same dead end as -segment_time_metadata."
fi
