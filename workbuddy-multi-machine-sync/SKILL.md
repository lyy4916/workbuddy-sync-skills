---
name: workbuddy-multi-machine-sync
description: "Set up WorkBuddy config sync across 3+ Macs with machine naming, conflict resolution, and status tracking. Supports GitHub or iCloud as backend. Triggers: 多机同步, 三台电脑同步, 多台 Mac 同步 WorkBuddy, multi-machine sync, 3+ devices sync, 多台电脑配置同步, team sync WorkBuddy. Includes machine registry, per-machine commit tagging, stale lock detection, and a status command to see which machines are active."
agent_created: true
---

# WorkBuddy Multi-Machine Sync (3+ Devices)

## Overview

Extend WorkBuddy config sync to **three or more Macs**. Built on top of the
two-machine sync skill, this adds:

- **Machine naming** — each Mac gets a human-readable label (e.g. `studio`,
  `laptop`, `office`) for easy identification in commit logs
- **Machine registry** — a `machines.json` file tracks all registered machines
  and their last-sync timestamps
- **Conflict-aware sync** — more aggressive rebase + auto-resolve strategy for
  the higher conflict probability with 3+ machines
- **Status command** — `wbstatus` shows which machines are registered, when
  they last synced, and which is currently active
- **Backend agnostic** — works with GitHub or iCloud

## When to Use This vs Two-Machine Sync

| Factor | Two-Machine Sync | Multi-Machine Sync |
|--------|------------------|---------------------|
| Machine count | 2 | 3+ |
| Machine naming | Not needed | Yes (human-readable labels) |
| Machine registry | Not needed | `machines.json` |
| Conflict probability | Low | Higher (more concurrent edits) |
| Status tracking | Manual | `wbstatus` command |
| Backend | GitHub or iCloud | GitHub or iCloud |

If you only have 2 machines, use `workbuddy-multi-device-sync` (simpler).
Upgrade to this skill when adding a 3rd machine.

## What Syncs vs What Doesn't

Same as the two-machine skill. Additionally:

### Syncs (new)
- `.machine-name` — this machine's label
- `machines.json` — registry of all machines

### Does NOT Sync (same as before)
- `binaries/`, `workbuddy.db`, `.mcp.json`, `sessions/`, `logs/`, `traces/`,
  `credentials/`, `memory/`, daemon state files

## Workflow

### Phase 1: Set Up Machine 1 (Primary)

Follow the two-machine skill (`workbuddy-multi-device-sync`) for Mac A setup,
then add multi-machine enhancements:

#### Step 1: Register Machine Name

```bash
# Set a human-readable name for this machine
echo "studio" > ~/.workbuddy/.machine-name
```

Choose short, descriptive names: `studio`, `laptop`, `office`, `home`, etc.

#### Step 2: Initialize Machine Registry

```bash
# Create machines.json with this machine registered
MACHINE_NAME=$(cat ~/.workbuddy/.machine-name)
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > ~/.workbuddy/machines.json << EOF
{
  "machines": [
    {
      "name": "$MACHINE_NAME",
      "hostname": "$HOSTNAME",
      "registered": "$TIMESTAMP",
      "last_sync": "$TIMESTAMP",
      "status": "active"
    }
  ]
}
EOF
```

#### Step 3: Install Multi-Machine Auto-Sync

1. Copy `scripts/auto-sync-multi.sh` to `~/.workbuddy/auto-sync.sh`
2. Copy `scripts/start-sync-daemon.sh` to `~/.workbuddy/start-sync-daemon.sh`
3. Copy `scripts/machine-status.sh` to `~/.workbuddy/machine-status.sh`
4. Make all executable:
```bash
chmod +x ~/.workbuddy/auto-sync.sh ~/.workbuddy/start-sync-daemon.sh ~/.workbuddy/machine-status.sh
```

The `auto-sync-multi.sh` script differs from the two-machine version:
- Tags each commit with machine name: `auto-sync <timestamp> from <machine>`
- Updates `machines.json` with `last_sync` timestamp on each sync
- Auto-resolves non-conflicting changes (accept theirs for non-overlapping files)
- Handles rebase failures gracefully (stashes, pulls, pops)

#### Step 4: Add Terminal Hooks

Append to `~/.bash_profile` (or `~/.zshrc`):

```bash
# WorkBuddy multi-machine sync shortcuts
alias wbsync='cd ~/.workbuddy && git add -A && git commit -m "sync $(date +%m%d-%H%M) from $(cat ~/.workbuddy/.machine-name 2>/dev/null || echo $(hostname))" && git push origin main'
alias wbpull='cd ~/.workbuddy && git pull --rebase origin main'
alias wbstatus='bash ~/.workbuddy/machine-status.sh'

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
```

#### Step 5: Update .gitignore

Ensure these are NOT in .gitignore (they should be synced):
- `.machine-name` — machine label
- `machines.json` — machine registry

Ensure these ARE in .gitignore (already covered by template):
- `.auto-sync.log`, `.sync-daemon.pid`, `.last-auto-sync`, `start-sync-daemon.sh`

#### Step 6: Commit and Push

```bash
cd ~/.workbuddy
git add -A
git commit -m "init: multi-machine sync setup on $(cat .machine-name)"
git push origin main
```

### Phase 2: Add Machine 2, 3, 4...

For each additional machine:

#### Prerequisites
- WorkBuddy installed and launched once, then quit
- GitHub repo accessible (or iCloud Drive synced)

#### Setup

Use `scripts/setup-machine.sh.template` as the setup script. Replace:
- `<REMOTE_URL>` → GitHub repo URL or iCloud bare repo path
- `<REMOTE_NAME>` → `origin` for GitHub, `icloud` for iCloud
- `<GITHUB_USERNAME>` / `<GITHUB_TOKEN>` → only for GitHub backend

Then on the new machine:

```bash
# For GitHub backend:
curl -sSL -H "Authorization: token <TOKEN>" \
  "https://raw.githubusercontent.com/<USER>/wb-sync/main/wb-setup-machine.sh" | bash

# For iCloud backend:
bash wb-setup-machine.sh  # after AirDrop or manual copy
```

The setup script will:
1. Ask for a machine name (or accept a default based on hostname)
2. Back up existing config
3. Pull from remote
4. Register itself in `machines.json`
5. Install auto-sync daemon
6. Start syncing

### Phase 3: Daily Usage

```bash
# Check status of all machines
wbstatus

# Output example:
# ┌──────────┬──────────────────────┬──────────┬─────────────────────┐
# │ Machine  │ Hostname             │ Status   │ Last Sync           │
# ├──────────┼──────────────────────┼──────────┼─────────────────────┤
# │ studio   │ pascalliu-mac-studio │ active   │ 2026-08-01 12:30:15 │
# │ laptop   │ pascalliu-mbp        │ active   │ 2026-08-01 12:28:42 │
# │ office   │ pascalliu-imac       │ stale    │ 2026-07-30 18:15:00 │
# └──────────┴──────────────────────┴──────────┴─────────────────────┘
```

- **active**: synced within the last 30 minutes
- **stale**: last sync > 30 minutes ago (machine may be offline)
- **offline**: last sync > 24 hours ago

## Conflict Handling

With 3+ machines, conflicts are more likely. The auto-sync script uses this
strategy:

1. **`git pull --rebase`** — replays local commits on top of remote
2. **If rebase fails** (conflicting changes to the same file):
   - Stash local changes
   - Pull (accept remote)
   - Pop stash (attempt merge)
   - If merge fails: keep remote version, log the conflict
3. **Conflict log**: conflicts are logged to `~/.workbuddy/.sync-conflicts.log`
   for manual review

### Resolving Conflicts Manually

```bash
cd ~/.workbuddy
git status                    # see conflicted files
# edit files to resolve...
git add -A
git rebase --continue
git push origin main
```

## Machine Registry Format

`machines.json`:
```json
{
  "machines": [
    {
      "name": "studio",
      "hostname": "pascalliu-mac-studio",
      "registered": "2026-08-01T00:00:00Z",
      "last_sync": "2026-08-01T12:30:15Z",
      "status": "active"
    },
    {
      "name": "laptop",
      "hostname": "pascalliu-mbp",
      "registered": "2026-08-01T01:00:00Z",
      "last_sync": "2026-08-01T12:28:42Z",
      "status": "active"
    }
  ]
}
```

Each machine updates its own entry on every sync. Stale entries (machines
not seen for > 30 days) can be cleaned up manually.

## Important Notes

- **Only one machine should be actively used at a time** for best results.
  The daemon handles concurrent sync, but real-time simultaneous editing of
  the same config files will cause conflicts.
- **Machine names must be unique**. If two machines have the same name, the
  registry will show duplicate entries.
- **Automations** (scheduled tasks) do NOT sync. Set them up on each machine.
- **GitHub SSH port 22 may be blocked** in China. Use HTTPS + token.
- **LaunchAgent** fails under sandbox. Use the Python daemon approach.
- **Daemon recovery**: After reboot, opens terminal or WorkBuddy bash command
  to restart daemon.

## Resources

### scripts/
- `auto-sync-multi.sh` — Enhanced sync script with machine tagging and conflict handling
- `start-sync-daemon.sh` — Daemon launcher (same as two-machine version)
- `machine-status.sh` — Display registered machines and their sync status
- `setup-machine.sh.template` — Setup script template for any new machine (Nth machine)

### references/
- `gitignore-template` — .gitignore for multi-machine setup
- `multi-machine-architecture.md` — Architecture, conflict handling, and migration guide
