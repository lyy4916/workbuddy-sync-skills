---
name: workbuddy-icloud-sync
description: "Set up automatic WorkBuddy config sync across multiple Macs using iCloud Drive. No GitHub account, no token, no SSH key needed — just log into the same iCloud account on all machines. Triggers: iCloud 同步, iCloud 版同步, 不用 GitHub 同步, 苹果云同步 WorkBuddy, iCloud sync WorkBuddy, sync without GitHub. Uses a bare git repo inside iCloud Drive with a background daemon syncing every 5 minutes."
agent_created: true
---

# WorkBuddy iCloud Sync

## Overview

Synchronize WorkBuddy configuration across multiple Macs using a **bare Git
repository stored in iCloud Drive**. No external service required — just log
into the same iCloud account on every machine. After setup, identity, memory,
skills, and settings stay in sync automatically via a background daemon.

## When to Use This vs GitHub Sync

| Factor | iCloud Sync | GitHub Sync |
|--------|-------------|-------------|
| Account needed | iCloud (Apple ID) | GitHub account |
| Network | Apple iCloud (may be slow in China) | GitHub (may need proxy in China) |
| Token/SSH | Not needed | Personal Access Token or SSH key |
| Setup complexity | Very simple | Medium |
| Version history | Yes (git log) | Yes (git log) |
| Best for | Same Apple ID on all Macs | Different accounts or cross-platform |

## What Syncs vs What Doesn't

### Syncs (via Git)
- Identity files: `SOUL.md`, `IDENTITY.md`, `USER.md`
- Memory: `MEMORY.md` (user-level, NOT `memory/` daily logs)
- Skills: `skills/` directory
- Config: `mcp.json`, `settings.json`
- Setup scripts stored in repo

### Does NOT Sync (machine-specific)
- `binaries/` — 300MB+ platform-specific runtimes
- `workbuddy.db` — SQLite database (automations, runtime state)
- `.mcp.json` — localhost port numbers differ per machine
- `sessions/`, `logs/`, `traces/` — runtime data
- `credentials/` — each machine logs in independently
- `memory/` — daily work logs, project-specific

### Already Synced (server-side)
- Conversation history
- Cloud user profile (auto-injected at session start)

## Workflow

### Phase 1: Set Up Mac A (Primary Machine)

#### Step 1: Verify iCloud Drive

```bash
# Check iCloud Drive is available
ls -d ~/Library/Mobile\ Documents/com~apple~CloudDocs && echo "ICLOUD_OK" || echo "NO_ICLOUD"
```

If `NO_ICLOUD`: System Preferences → Apple ID → iCloud → enable iCloud Drive.

#### Step 2: Initialize Git in `~/.workbuddy/`

```bash
git config --global user.name "$(whoami)"
git config --global user.email "$(whoami)@workbuddy.local"
git config --global init.defaultBranch main

cd ~/.workbuddy
git init
```

#### Step 3: Create `.gitignore`

Copy `references/gitignore-template` to `~/.workbuddy/.gitignore`.
This excludes all machine-specific files (binaries, workbuddy.db, .mcp.json,
sessions, logs, traces, credentials, memory, daemon state files).

#### Step 4: Create iCloud Bare Repo and Push

```bash
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

# Create bare repo in iCloud
git clone --bare ~/.workbuddy "$ICLOUD_DIR/WorkBuddy-sync.git"

# Add as remote and push
cd ~/.workbuddy
git remote add icloud "$ICLOUD_DIR/WorkBuddy-sync.git"
git add -A
git commit -m "init: WorkBuddy config from $(hostname)"
git push -u icloud main
```

#### Step 5: Install Auto-Sync

1. Copy `scripts/auto-sync-icloud.sh` to `~/.workbuddy/auto-sync.sh`
2. Copy `scripts/start-sync-daemon.sh` to `~/.workbuddy/start-sync-daemon.sh`
3. Make both executable:
```bash
chmod +x ~/.workbuddy/auto-sync.sh ~/.workbuddy/start-sync-daemon.sh
```
4. Start the daemon:
```bash
osascript -e 'do shell script "/bin/bash ~/.workbuddy/start-sync-daemon.sh"'
```

#### Step 6: Add Terminal Hook

Append to `~/.bash_profile` (or `~/.zshrc`):

```bash
# WorkBuddy iCloud 同步快捷命令
alias wbsync='cd ~/.workbuddy && git add -A && git commit -m "sync $(date +%m%d-%H%M)" && git push icloud main'
alias wbpull='cd ~/.workbuddy && git pull icloud main'

# WorkBuddy 自动同步 — 守护进程保活 + 终端打开时即时同步
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
```

#### Step 7: Commit and Push Everything

```bash
cd ~/.workbuddy
git add -A
git commit -m "add: auto-sync scripts + terminal hook"
git push icloud main
```

### Phase 2: Set Up Mac B (Additional Machines)

#### Prerequisites
- WorkBuddy installed and launched once (creates `~/.workbuddy/`), then quit
- **Same iCloud account** logged in, iCloud Drive enabled
- Wait for iCloud to sync the `WorkBuddy-sync.git` folder (check with
  `ls ~/Library/Mobile\ Documents/com~apple~CloudDocs/WorkBuddy-sync.git`)

#### Setup

Run `scripts/setup-mac-b-icloud.sh` on Mac B. Or manually:

```bash
WB_DIR="$HOME/.workbuddy"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

# Backup existing config
if [ -f "$WB_DIR/SOUL.md" ]; then
  cp -r "$WB_DIR" "$WB_DIR.backup.$(date +%Y%m%d%H%M%S)"
fi

# Configure git
git config --global user.name "$(whoami)"
git config --global user.email "$(whoami)@workbuddy.local"
git config --global init.defaultBranch main

# Clone from iCloud
cd "$WB_DIR"
if [ -d ".git" ]; then
  git remote remove icloud 2>/dev/null
  git remote add icloud "$ICLOUD_DIR/WorkBuddy-sync.git"
  git fetch icloud
  git reset --hard icloud/main
else
  git init
  git remote add icloud "$ICLOUD_DIR/WorkBuddy-sync.git"
  git fetch icloud
  git checkout -f -B main icloud/main
fi

# Make scripts executable
chmod +x "$WB_DIR/auto-sync.sh" "$WB_DIR/start-sync-daemon.sh" 2>/dev/null

# Start daemon
bash "$WB_DIR/start-sync-daemon.sh"
```

Then add the terminal hook from Step 6 to Mac B's `~/.bash_profile`.

### Phase 3: Verification

```bash
# Check daemon
cat ~/.workbuddy/.sync-daemon.pid
kill -0 $(cat ~/.workbuddy/.sync-daemon.pid) && echo "ALIVE" || echo "DEAD"

# Check sync log
tail -5 ~/.workbuddy/.auto-sync.log

# Check git
cd ~/.workbuddy && git log --oneline -3 && git remote -v
```

## Important Notes

- **iCloud sync latency**: iCloud Drive may take 30-60 seconds to propagate
  changes between machines. The 5-minute daemon interval is sufficient.
- **First-time iCloud download**: Mac B must wait for iCloud to fully download
  the `WorkBuddy-sync.git` folder before cloning. Check with `ls`.
- **LaunchAgent** (`launchctl load`) often fails with "Input/output error" on
  macOS 12+ under sandbox. The Python subprocess daemon approach is more reliable.
- **Automations** (scheduled tasks) are stored in `workbuddy.db` and do NOT sync.
  Recreate them on each machine using the `automation_update` tool.
- **Project workspace memory** (`<project>/.workbuddy/memory/`) is NOT inside
  `~/.workbuddy/` and must be synced separately.
- **Daemon recovery**: After reboot, the daemon restarts when the user opens
  a terminal or when WorkBuddy runs any bash command.
- **iCloud storage**: The bare repo is typically < 5 MB. No storage concerns.

## Resources

### scripts/
- `auto-sync-icloud.sh` — Sync script using `icloud` remote (pull → commit → push)
- `start-sync-daemon.sh` — Daemon launcher with PID dedup and Python auto-detection
- `setup-mac-b-icloud.sh` — Mac B one-click setup (clones from iCloud Drive)

### references/
- `gitignore-template` — The `.gitignore` file for `~/.workbuddy/`
- `sync-architecture-icloud.md` — Architecture, troubleshooting, and comparison with GitHub
