#!/usr/bin/env sh
# One-time setup of pull-based CD on this Mac:
#   1. a separate DEPLOY clone of this repo (default ~/Deploy/news-app-platform).
#      Your working copy stays yours to edit; the deploy clone only ever checks out
#      commits from origin/main, like a server would.
#   2. moves backups/ there and creates certs/ there (both git-ignored)
#   3. deploys origin/main from it (the running "news-app" stack moves over)
#   4. a launchd agent that runs scripts/updater.sh every UPDATER_INTERVAL seconds (120)
# Run it from your working copy:  ./scripts/install-updater.sh
# Remove the agent:               launchctl bootout gui/$(id -u)/com.news-app.updater
set -eu
src=$(cd "$(dirname "$0")/.." && pwd)
dir="${DEPLOY_DIR:-$HOME/Deploy/news-app-platform}"
label=com.news-app.updater
plist="$HOME/Library/LaunchAgents/$label.plist"
interval="${UPDATER_INTERVAL:-120}"

if [ ! -d "$dir/.git" ]; then
  mkdir -p "$(dirname "$dir")"
  git clone -q "${DEPLOY_REMOTE:-$(git -C "$src" remote get-url origin)}" "$dir"
  echo "Cloned deploy copy into $dir"
fi
if [ -d "$src/backups" ] && [ ! -e "$dir/backups" ]; then
  mv "$src/backups" "$dir/backups"
  echo "Moved backups/ to $dir/backups"
fi
[ -f "$dir/certs/tls.yml" ] || PATH="$HOME/.local/bin:$PATH" "$dir/scripts/make-local-cert.sh"

"$dir/scripts/deploy.sh" origin/main

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>/bin/sh</string><string>$dir/scripts/updater.sh</string></array>
  <key>StartInterval</key><integer>$interval</integer>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StandardOutPath</key><string>$dir/.deploy/updater.out</string>
  <key>StandardErrorPath</key><string>$dir/.deploy/updater.out</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Updater installed: checks origin/main every ${interval}s. Logs: $dir/.deploy/deploy.log"
