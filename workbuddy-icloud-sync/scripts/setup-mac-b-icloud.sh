#!/bin/bash
#
# WorkBuddy Mac B One-Click Setup Script (iCloud Sync)
#
# No tokens, no SSH keys — just needs the same iCloud account.
#
# Usage (on Mac B):
#   1. Install WorkBuddy, launch once, then quit (to create ~/.workbuddy/)
#   2. Ensure iCloud Drive is enabled and WorkBuddy-sync.git has downloaded
#   3. Run: bash setup-mac-b-icloud.sh
#

set -e

WB_DIR="$HOME/.workbuddy"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
BARE_REPO="$ICLOUD_DIR/WorkBuddy-sync.git"
REMOTE_NAME="icloud"
BRANCH="main"

# Check ~/.workbuddy exists
if [ ! -d "$WB_DIR" ]; then
  echo "ERROR: ~/.workbuddy does not exist"
  echo "Install WorkBuddy first, launch it once, then quit and run this script"
  exit 1
fi

# Check iCloud Drive and bare repo
if [ ! -d "$ICLOUD_DIR" ]; then
  echo "ERROR: iCloud Drive not found"
  echo "Enable iCloud Drive: System Preferences → Apple ID → iCloud → iCloud Drive"
  exit 1
fi

if [ ! -d "$BARE_REPO" ]; then
  echo "ERROR: WorkBuddy-sync.git not found in iCloud Drive"
  echo "Make sure Mac A has pushed, and iCloud has finished syncing."
  echo "Check: ls ~/Library/Mobile\\ Documents/com~apple~CloudDocs/WorkBuddy-sync.git"
  exit 1
fi

# Backup existing config (if any)
if [ -f "$WB_DIR/SOUL.md" ] || [ -f "$WB_DIR/MEMORY.md" ]; then
  BACKUP_DIR="$WB_DIR.backup.$(date +%Y%m%d%H%M%S)"
  echo ">> Backing up existing config to $BACKUP_DIR ..."
  mkdir -p "$BACKUP_DIR"
  for f in SOUL.md IDENTITY.md USER.md MEMORY.md mcp.json settings.json skills; do
    if [ -e "$WB_DIR/$f" ]; then
      cp -r "$WB_DIR/$f" "$BACKUP_DIR/"
    fi
  done
  echo ">> Backup complete"
fi

# Configure git (if not already set)
if [ -z "$(git config --global user.name)" ]; then
  git config --global user.name "$(whoami)"
  git config --global user.email "$(whoami)@workbuddy.local"
  git config --global init.defaultBranch main
fi

# Initialize git and pull from iCloud
cd "$WB_DIR"

if [ -d ".git" ]; then
  echo ">> Git repo exists, switching remote to iCloud..."
  git remote remove "$REMOTE_NAME" 2>/dev/null || true
  git remote remove origin 2>/dev/null || true
  git remote add "$REMOTE_NAME" "$BARE_REPO"
  git fetch "$REMOTE_NAME"
  git reset --hard "$REMOTE_NAME/$BRANCH"
else
  echo ">> Initializing git and pulling from iCloud..."
  git init
  git remote add "$REMOTE_NAME" "$BARE_REPO"
  git fetch "$REMOTE_NAME"
  git checkout -f -B "$BRANCH" "$REMOTE_NAME/$BRANCH"
fi

chmod +x "$WB_DIR/auto-sync.sh" 2>/dev/null || true
chmod +x "$WB_DIR/start-sync-daemon.sh" 2>/dev/null || true

echo ""
echo ">> Setting up aliases + terminal auto-sync..."
PROFILE="$HOME/.bash_profile"
if [ ! -f "$PROFILE" ]; then
  PROFILE="$HOME/.zshrc"
fi

# Write aliases + auto-sync hook (skip if already present)
if grep -q "wbsync" "$PROFILE" 2>/dev/null; then
  echo ">> Aliases already present, skipping"
else
  cat >> "$PROFILE" << 'PROFILE_EOF'

# WorkBuddy iCloud sync shortcuts
alias wbsync='cd ~/.workbuddy && git add -A && git commit -m "sync $(date +%m%d-%H%M)" && git push icloud main'
alias wbpull='cd ~/.workbuddy && git pull icloud main'

# WorkBuddy auto-sync — daemon keepalive + sync on terminal open
if [ -f ~/.workbuddy/start-sync-daemon.sh ]; then
  bash ~/.workbuddy/start-sync-daemon.sh 2>/dev/null
fi
if [ -t 1 ] && [ -f ~/.workbuddy/auto-sync.sh ]; then
  _wb_now=$(date +%s)
  _wb_last=$(cat ~/.workbuddy/.last-auto-sync 2>/dev/null || echo 0)
  if [ $((_wb_now - _wb_last)) -gt 300 ]; then
    bash ~/.workbuddy/auto-sync.sh >/dev/null 2>&1 &
    echo $_wb_now > ~/.workbuddy/.last-auto-sync
  fi
  unset _wb_now _wb_last
fi
PROFILE_EOF
  echo ">> Added to $PROFILE"
fi

echo ""
echo ">> Starting background sync daemon..."
bash "$WB_DIR/start-sync-daemon.sh" 2>/dev/null
sleep 1
_wb_pid=$(cat "$WB_DIR/.sync-daemon.pid" 2>/dev/null)
if [ -n "$_wb_pid" ] && kill -0 "$_wb_pid" 2>/dev/null; then
  echo ">> [OK] Background sync daemon started (PID: $_wb_pid)"
else
  echo ">> [!] Daemon not started, will auto-retry when terminal opens"
fi

echo ""
echo "========================================"
echo "  Mac B setup complete! (iCloud Sync)"
echo "========================================"
echo ""
echo "Verify:"
echo "  cat ~/.workbuddy/SOUL.md   # should show Mac A content"
echo "  ls ~/.workbuddy/skills/    # should show synced skills"
echo ""
echo "Now fully automatic:"
echo "  - Background sync every 5 minutes (iCloud)"
echo "  - Terminal open also triggers sync + daemon keepalive"
echo "  - Manual: wbsync (push) / wbpull (pull)"
echo ""
echo "If backed up old config: ls ~/.workbuddy.backup.*"
echo ""
