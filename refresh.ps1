# refresh.ps1 - Resolve the YouTube playlist from this machine and push the
# result to GitHub. GitHub's runner IPs are blocked by YouTube, so resolution
# has to happen from a residential connection - this laptop.
#
# Manual run:   powershell -ExecutionPolicy Bypass -File refresh.ps1
# Scheduled:    registered as the task "YouTubeIPTV Refresh" (every 2 hours)
#
# The playlist inside channel.m3u expires ~6 h after it is generated, so the
# task intervals must stay comfortably under that.

$ErrorActionPreference = "Continue"

$Repo     = "C:\Users\RANDEV\Documents\GitHub\YouTubeIPTV\cloud"
$Playlist = "https://www.youtube.com/playlist?list=PL87398570A6DD45C0"
$Name     = "Bizarre Foods"
$Log      = Join-Path $Repo "refresh.log"

function Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $Log -Value $line
    Write-Host $line
}

Set-Location $Repo

# Keep the log from growing without bound.
if ((Test-Path $Log) -and ((Get-Item $Log).Length -gt 512KB)) {
    Move-Item $Log "$Log.old" -Force
}

Log "--- refresh start ---"

# Pull anything committed elsewhere first (e.g. from the phone).
git pull --rebase --quiet 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Log "warning: git pull failed, continuing" }

Log "resolving playlist (this takes ~4-6 minutes)"
$tmp = "$Log.tmp"
python make_playlist.py --url $Playlist --name $Name --max-minutes 180 --out channel.m3u *> $tmp
$pyExit = $LASTEXITCODE
# Python's output lands in UTF-16 via *>; re-append as text so the log stays readable.
Get-Content $tmp | Add-Content -Path $Log
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

if ($pyExit -ne 0) {
    Log "resolve failed (exit $pyExit) - previous playlist left untouched"
    exit 1
}
if (-not (Test-Path "channel.m3u") -or (Get-Item "channel.m3u").Length -eq 0) {
    Log "channel.m3u missing or empty - not committing"
    exit 1
}

$count = (Select-String -Path "channel.m3u" -Pattern "^#EXTINF" | Measure-Object).Count
Log "resolved $count channels"

git add channel.m3u
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Log "no change - nothing to push"
    exit 0
}

git commit --quiet -m "refresh $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') ($count channels)"
if ($LASTEXITCODE -ne 0) { Log "commit failed"; exit 1 }

git push --quiet
if ($LASTEXITCODE -ne 0) {
    # Someone else pushed (phone, another machine) - rebase once and retry.
    Log "push rejected - rebasing and retrying"
    git pull --rebase --quiet 2>&1 | Out-Null
    git push --quiet
    if ($LASTEXITCODE -ne 0) { Log "push failed"; exit 1 }
}

Log "pushed $count channels"
