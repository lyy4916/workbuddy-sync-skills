#!/bin/bash
#
# WorkBuddy Auto-Sync Script — called by daemon every 5 minutes
# Pull remote → commit local changes → push, all silent
#

WB_DIR="$HOME/.workbuddy"
LOG_FILE="$WB_DIR/.auto-sync.log"

# Ensure git config exists
if [ -z "$(git config --global user.name)" ]; then
  git config --global user.name "$(whoami)"
  git config --global user.email "$(whoami)@workbuddy.local"
  git config --global init.defaultBranch main
fi

cd "$WB_DIR" || exit 0

# Skip if not a git repo
[ -d ".git" ] || exit 0

# Skip if no origin remote
git remote get-url origin >/dev/null 2>&1 || exit 0

TS=$(date '+%Y-%m-%d %H:%M:%S')

# 1. Pull remote changes (rebase on conflict, skip on failure)
git pull --rebase origin main >/dev/null 2>&1

# 2. Commit local changes (skip if nothing staged)
git add -A
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "auto-sync ${TS}" >/dev/null 2>&1
fi

# 3. Push
git push origin main >/dev/null 2>&1

# Log (keep last 50 lines only)
echo "[${TS}] synced" >> "$LOG_FILE"
tail -50 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
