# YouTube playlist → live IPTV channel (cloud, no server)

Turns a YouTube playlist into an `.m3u` that OTT Navigator can play, with no
laptop, no downloads, and no streaming server. A GitHub Action rebuilds the
playlist every 2 hours because YouTube's links expire after ~6.

## Why this works

Verified on the actual TV:

- The progressive 360p stream (`itag 18`) is served with a URL that **any client
  can use** — any User-Agent, no cookies, no special headers.
- It is **not IP-enforced** in practice, so a link resolved on GitHub's runner
  plays fine from your home TV. (The URL is *signature-bound* to an IP in
  theory — `sparams` contains `ip` — but YouTube does not appear to enforce it
  here. If it ever starts, the playlist will simply 403 and this approach stops
  working.)
- Every format above 360p is split video/audio DASH, and YouTube caps anonymous
  clients at ~6 MB per URL for those. **360p is the ceiling** without cookies.

It helped that OTT Navigator requests **no storage permissions at all**, so
pointing it at local files is impossible; it can only consume `http(s)` URLs.
This design sidesteps that entirely.

## Setup

1. Create a GitHub repository (public is simplest — OTT must fetch the raw file
   without auth).
2. Push this folder:

   ```powershell
   cd C:\Users\RANDEV\Documents\GitHub\YouTubeIPTV\cloud
   git init
   git add .
   git commit -m "channel"
   git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```

3. Repo → **Settings → Actions → General → Workflow permissions** →
   *Read and write permissions* → Save. (The job commits the refreshed file.)
4. Repo → **Actions** → *Refresh channel* → **Run workflow** to build it once.
5. Wait for `channel.m3u` to appear in the repo.

## Add it to OTT Navigator

Add Provider → **URL**:

```
https://raw.githubusercontent.com/<you>/<repo>/main/channel.m3u
```

You'll get one channel per episode, named and numbered, under the group
`Bizarre Foods`.

## Keeping it fresh

- The Action runs every 2 hours automatically.
- OTT caches playlists, so **refresh the playlist in OTT** when links have gone
  stale (it will fail to play / show errors). Most players refresh on app start.
- `raw.githubusercontent.com` caches for ~5 minutes, so a brand-new refresh may
  take a minute to appear.

If a run fails, `make_playlist.py` refuses to overwrite the playlist when fewer
than half the lookups succeed, so a broken run won't destroy a working file.

## Important: GitHub runners are blocked by YouTube

The workflow resolves **0 of 253** videos when run on GitHub's infrastructure —
YouTube refuses extraction from datacenter IPs ("Sign in to confirm you're not a
bot"). The job fails rather than committing garbage, so the existing playlist
survives, but nothing refreshes.

**Resolution has to happen from a residential connection.** This is handled by
`refresh.ps1` on the home laptop, which resolves the playlist and pushes the
result here. GitHub then acts purely as a static host — which is all it needs to
be for OTT Navigator.

It is registered as the Windows scheduled task **`YouTubeIPTV Refresh`**, running
every 2 hours, well inside the ~6 h link lifetime. The task uses
"start when available", so if the laptop is asleep at a scheduled time it runs
as soon as it wakes rather than skipping.

```
# run it by hand
powershell -ExecutionPolicy Bypass -File refresh.ps1

# inspect / change the schedule
Get-ScheduledTask -TaskName "YouTubeIPTV Refresh"
Unregister-ScheduledTask -TaskName "YouTubeIPTV Refresh"
```

Logs go to `refresh.log` (gitignored).

`refresh-termux.sh` is an equivalent for an always-on Android phone, if the
laptop is going to be off for long stretches. The GitHub workflow in
`.github/workflows/refresh.yml` is kept for reference only and stays disabled —
it cannot work from datacenter IPs.

## Optional: the clock

A static playlist has no concept of time — you pick an episode and it starts at
0:00. To get "what should be on air now", something has to reorder or select
entries by the clock at the moment you open it. That needs a small dynamic
endpoint (Tasker's HTTP server can do it, since the playlists are only text).

## Tunables

| Variable | Where | Default |
| --- | --- | --- |
| `PLAYLIST_URL` | repo → Settings → Variables | the Bizarre Foods playlist |
| `CHANNEL_NAME` | repo → Settings → Variables | `Bizarre Foods` |
| `--max-minutes` | `refresh.yml` | 180 (skips the 261 h upload) |
| cron schedule | `refresh.yml` | every 2 hours |
