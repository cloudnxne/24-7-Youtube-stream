#!/usr/bin/env bash
# Rebuilds the shuffled playlist (which also runs normalization for any
# new tracks) and restarts both services in one go, so adding new tracks
# is a single command instead of two.
#
# Stops on failure rather than restarting with a broken playlist — if
# 03_generate_playlist.sh errors out, this exits before touching the
# running services at all.
set -euo pipefail

echo "== Rebuilding playlist (includes normalizing any new tracks) =="
/home/pondlife/scripts/03_generate_playlist.sh

echo ""
echo "== Restarting stream and overlay =="
systemctl restart pondlife-stream pondlife-nowplaying

echo ""
echo "Done. New tracks are live."
