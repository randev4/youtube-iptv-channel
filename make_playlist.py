#!/usr/bin/env python3
"""
make_playlist.py - Resolve a YouTube playlist into a plain M3U of direct
googlevideo URLs, for playback in OTT Navigator (or any IPTV player).

Why this works: the progressive 360p format (itag 18) is served with a URL that
any client can use - no special headers, no cookies, and (verified) no IP
enforcement. Links expire after ~6 hours, so this is meant to be run on a
schedule, not once.

Only 360p is reachable: every format above that is split video/audio DASH, and
YouTube caps anonymous clients at ~6 MB per URL for those.

Usage:
    python make_playlist.py --url "<playlist url>" --out channel.m3u
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

CHUNK = 15           # URLs per yt-dlp invocation
FORMAT = "18/b[height<=360]/b"
MIN_OK_RATIO = 0.5   # refuse to write a playlist if most lookups failed


def log(msg: str = "") -> None:
    print(msg, flush=True)


def exe(name: str, module: str | None = None) -> list[str]:
    found = shutil.which(name)
    if found:
        return [found]
    if module:
        return [sys.executable, "-m", module]
    raise SystemExit(f"error: '{name}' not found")


def ytdlp() -> list[str]:
    return exe("yt-dlp", "yt_dlp")


def channel_target(url: str) -> str:
    u = url.strip()
    if "list=" in u or "/playlist" in u:
        return u
    u = u.split("?")[0].rstrip("/")
    if re.search(r"/(videos|shorts|streams)$", u):
        return u
    return u + "/videos"


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


def enumerate_videos(url: str, max_minutes: int) -> list[dict]:
    target = channel_target(url)
    log(f"Enumerating: {target}")
    p = run(ytdlp() + ["--flat-playlist", "--ignore-errors", "--no-warnings",
                       "--print", "%(id)s\t%(title)s\t%(duration)s", target])
    if not (p.stdout or "").strip():
        raise SystemExit("error: could not read that playlist")

    rows, seen = [], set()
    for line in p.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        vid, title = parts[0].strip(), parts[1].strip()
        if not vid or vid in seen:
            continue
        seen.add(vid)
        try:
            dur = float(parts[2])
        except (IndexError, ValueError):
            dur = 0.0
        if max_minutes and dur > max_minutes * 60:
            log(f"  skip (too long, {dur / 3600:.0f}h): {title[:60]}")
            continue
        rows.append({"id": vid, "title": title or vid, "duration": dur})
    return rows


def resolve_batch(ids: list[str]) -> dict[str, str]:
    """Return {video_id: direct_url} for the ids that resolved."""
    urls = [f"https://www.youtube.com/watch?v={i}" for i in ids]
    p = run(ytdlp() + ["-j", "-f", FORMAT, "--no-warnings", "--ignore-errors",
                       "--no-playlist", "--skip-download"] + urls)
    out: dict[str, str] = {}
    for line in (p.stdout or "").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            info = json.loads(line)
        except ValueError:
            continue
        vid, direct = info.get("id"), info.get("url")
        if vid and direct:
            out[vid] = direct
    return out


def clean(text: str, limit: int = 120) -> str:
    text = text.replace("\n", " ").replace("\r", " ").replace('"', "'")
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--out", default="channel.m3u")
    ap.add_argument("--name", default="YouTube Channel")
    ap.add_argument("--max-minutes", type=int, default=180)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    videos = enumerate_videos(a.url, a.max_minutes)
    if a.limit:
        videos = videos[:a.limit]
    if not videos:
        raise SystemExit("error: no videos found")
    log(f"{len(videos)} video(s) to resolve")

    resolved: dict[str, str] = {}
    for start in range(0, len(videos), CHUNK):
        batch = videos[start:start + CHUNK]
        got = resolve_batch([v["id"] for v in batch])
        resolved.update(got)
        log(f"  resolved {len(resolved)}/{min(start + CHUNK, len(videos))}")

    playable = [v for v in videos if v["id"] in resolved]
    ratio = len(playable) / len(videos)
    log(f"usable: {len(playable)}/{len(videos)} ({ratio:.0%})")
    if ratio < MIN_OK_RATIO:
        raise SystemExit("error: too many lookups failed - refusing to write a "
                         "broken playlist (keeping the previous one)")

    group = a.name.replace(",", " ")
    lines = ["#EXTM3U"]
    for i, v in enumerate(playable, 1):
        title = clean(v["title"])
        lines.append(
            f'#EXTINF:-1 tvg-id="yt.{v["id"]}" tvg-name="{title}" '
            f'group-title="{group}",{i:02d} - {title}'
        )
        lines.append(resolved[v["id"]])

    Path(a.out).write_text("\n".join(lines) + "\n", encoding="utf-8")
    log(f"wrote {a.out} with {len(playable)} channel(s)")


if __name__ == "__main__":
    main()
