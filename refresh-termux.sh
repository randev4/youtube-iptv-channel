#!/data/data/com.termux/files/usr/bin/bash
#
# refresh.sh - Resolve the YouTube playlist from your home IP and push the
# result to GitHub. Run this on the always-on phone (Termux), not on a
# datacenter host: YouTube blocks GitHub's runner IPs from extracting links,
# but a residential connection works fine.
#
# One-time setup:
#   pkg install git python
#   pip install -U yt-dlp
#   git clone https://github.com/<you>/youtube-iptv-channel.git ~/yt-channel
#
# Push credentials (only needed once, inside the clone):
#   git config credential.helper store
#   git remote set-url origin https://<USER>:<TOKEN>@github.com/<you>/youtube-iptv-channel.git
#   (create a fine-grained token limited to this repo, Contents: read+write)
#
# Schedule it (every 2 hours):
#   pkg install cronie
#   crontab -e      ->  0 */2 * * * ~/refresh.sh >> ~/refresh.log 2>&1
#   crond
#   termux-wake-lock     # stop Android from freezing the cron daemon
#
set -uo pipefail

REPO_DIR="${REPO_DIR:-$HOME/yt-channel}"
PLAYLIST="${PLAYLIST:-https://www.youtube.com/playlist?list=PL87398570A6DD45C0}"
CHANNEL_NAME="${CHANNEL_NAME:-Bizarre Foods}"
MAX_MINUTES="${MAX_MINUTES:-180}"

cd "$REPO_DIR" || { echo "repo dir not found: $REPO_DIR"; exit 1; }

# Pick up anything committed elsewhere (e.g. a manual fix from a PC).
git pull --rebase --quiet || echo "warning: pull failed, continuing"

python make_playlist.py \
  --url "$PLAYLIST" \
  --name "$CHANNEL_NAME" \
  --max-minutes "$MAX_MINUTES" \
  --out channel.m3u

# make_playlist.py exits non-zero when too few lookups succeed, so reaching
# here means we have a usable file. Still, guard against an empty one.
if [ ! -s channel.m3u ]; then
  echo "error: channel.m3u is empty - not committing"
  exit 1
fi

if git diff --quiet -- channel.m3u; then
  echo "no change"
  exit 0
fi

COUNT=$(grep -c '^#EXTINF' channel.m3u)
git add channel.m3u
git commit -q -m "refresh $(date -u +%Y-%m-%dT%H:%M:%SZ) ($COUNT channels)"
git push --quiet && echo "pushed $COUNT channels"
