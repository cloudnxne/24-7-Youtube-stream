#!/usr/bin/env bash
# Follow-up test: does file_packet_meta handle a multi-word value with
# spaces and dashes correctly (our real titles look like "ARTIST - TITLE"),
# or does it need quoting, or get mangled/truncated at the first space?
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ffmpeg -y -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=3" -ar 44100 -ac 2 -c:a pcm_s16le "$TMP/tone_a.wav"
ffmpeg -y -hide_banner -loglevel error -f lavfi -i "sine=frequency=880:duration=3" -ar 44100 -ac 2 -c:a pcm_s16le "$TMP/tone_b.wav"

echo "=== Unquoted multi-word value ==="
cat > "$TMP/p1.txt" << EOF
file '$TMP/tone_a.wav'
file_packet_meta title DJ PANTHA - A MILLE
file '$TMP/tone_b.wav'
file_packet_meta title ENIGMA - JUMANJI
EOF
ffmpeg -hide_banner -f concat -safe 0 -i "$TMP/p1.txt" -map 0:a -af "ametadata=mode=print:key=title" -f null - 2>&1 | grep "title=" | sort -u

echo ""
echo "=== Single-quoted multi-word value ==="
cat > "$TMP/p2.txt" << EOF
file '$TMP/tone_a.wav'
file_packet_meta title 'DJ PANTHA - A MILLE'
file '$TMP/tone_b.wav'
file_packet_meta title 'ENIGMA - JUMANJI'
EOF
ffmpeg -hide_banner -f concat -safe 0 -i "$TMP/p2.txt" -map 0:a -af "ametadata=mode=print:key=title" -f null - 2>&1 | grep "title=" | sort -u
