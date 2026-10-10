#!/usr/bin/env bash
# Pond Life Party — 24/7 stream droplet bootstrap
# Run once, as root or with sudo, right after first SSH login.
set -euo pipefail

echo "== Updating system =="
apt-get update && apt-get -y upgrade

echo "== Installing ffmpeg and dependencies =="
apt-get install -y ffmpeg ufw bc

echo "== Creating directory structure =="
mkdir -p /home/pondlife/assets/tracks
mkdir -p /home/pondlife/assets/watermarks
mkdir -p /home/pondlife/assets/fonts
mkdir -p /home/pondlife/scripts
mkdir -p /home/pondlife/logs

echo "== Basic firewall (SSH only inbound — this box only pushes outbound to YouTube) =="
ufw allow OpenSSH
ufw --force enable

echo ""
echo "== Done. Next steps: =="
echo "1. Upload to /home/pondlife/assets/:"
echo "     - loop.m4v"
echo "2. Upload your watermark clips (any number, each under 60s) into"
echo "   /home/pondlife/assets/watermarks/"
echo "3. Upload your .wav tracks into /home/pondlife/assets/tracks/"
echo "4. Upload your licensed font .ttf into /home/pondlife/assets/fonts/"
echo "5. Save your YouTube stream key:"
echo "     echo \"YOUR-STREAM-KEY\" > /home/pondlife/.stream_key"
echo "     chmod 600 /home/pondlife/.stream_key"
echo "6. Copy 02, 03, 04, 05 scripts into /home/pondlife/scripts/ and chmod +x them"
echo "7. Run 02_build_watermark_loop.sh, then 03_generate_playlist.sh"
echo "8. Install both systemd services (pondlife-stream, pondlife-nowplaying)"
