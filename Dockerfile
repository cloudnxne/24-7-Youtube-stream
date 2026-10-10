# 24/7 YouTube live stream: ffmpeg loop video + shuffled tracks + watermark + now-playing overlay.
# Runs the same scripts as the systemd version, inside one container.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg bc procps ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/pondlife -s /bin/bash pondlife \
 && mkdir -p /home/pondlife/assets/tracks /home/pondlife/assets/watermarks /home/pondlife/assets/fonts \
             /home/pondlife/scripts /home/pondlife/logs

COPY scripts/ /home/pondlife/scripts/
COPY docker/systemctl-shim.sh /usr/local/bin/systemctl
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /home/pondlife/scripts/*.sh /usr/local/bin/systemctl /usr/local/bin/entrypoint.sh \
 && chown -R pondlife:pondlife /home/pondlife

USER pondlife
WORKDIR /home/pondlife
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
