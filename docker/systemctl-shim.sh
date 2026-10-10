#!/usr/bin/env bash
# The helper scripts (09, 10, 10b, 11) call "systemctl restart pondlife-stream pondlife-nowplaying".
# Inside the container there is no systemd, so this shim stops the entrypoint, and
# Docker's restart policy (restart: unless-stopped) starts the stream again with the new playlist.
if [ "${1:-}" = "restart" ] && [ -f /tmp/entrypoint.pid ]; then
  echo "[shim] restarting container via entrypoint"
  kill -TERM "$(cat /tmp/entrypoint.pid)"
  exit 0
fi
echo "[shim] systemctl $* ignored inside the container"
