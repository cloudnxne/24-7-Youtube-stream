# Pond Life stream

A 24/7 YouTube live stream built on ffmpeg and Docker. It loops a video, plays a shuffled playlist of tracks, mixes in a watermark that ducks the music, and shows a now-playing overlay driven by metadata carried in the audio itself.

## How it works
- `03_generate_playlist.sh` builds a shuffled ffmpeg concat playlist and embeds each track's display name with `file_packet_meta`, so the overlay can never drift out of sync.
- `07_normalize_tracks.sh` converts every upload to one uniform WAV format with fades, which avoids decoder errors from mixing formats.
- `04_stream.sh` runs the ffmpeg pipeline: looped video, concat audio, a sidechain-compressed watermark and an RTMP push to YouTube.
- `05_nowplaying_watcher.sh` tails ffmpeg's `ametadata` output and writes the current title for the overlay.
- `10_start_guest_set.sh`, `11_start_special_rotation.sh` and `10b_restore_rotation.sh` swap in themed sets and restore the normal rotation.

## Run it with Docker
1. Put `loop.m4v`, tracks, watermark clips (each under 60 seconds) and your licensed font in `data/assets/` (`tracks/`, `watermarks/`, `fonts/`).
2. Save your YouTube stream key to `secrets/stream_key` before starting. Never commit it.
3. `docker compose up -d --build`
4. After adding tracks: `docker compose exec stream /home/pondlife/scripts/09_refresh_stream.sh`

The scripts originally ran as systemd services on a DigitalOcean droplet (`01_setup_droplet.sh` is that bootstrap, with a firewall limited to SSH). Inside the container a small `systemctl` shim restarts the container so a new playlist takes effect.

## Notes
- The Docker files have not been through a full live-stream test from this repo, so treat them as a first draft.
- Audio files, fonts and stream keys are git-ignored.
