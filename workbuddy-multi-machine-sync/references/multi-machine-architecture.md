# Multi-Machine Sync Architecture

## Overview

Extends the two-machine sync to support 3+ Macs with machine naming,
registry tracking, and enhanced conflict handling.

## Architecture

```
                 GitHub / iCloud
                      ↕
    ┌─────────────────┼─────────────────┐
    ↓                 ↓                 ↓
 Machine A         Machine B         Machine C
 (studio)          (laptop)          (office)
    ↕                 ↕                 ↕
 auto-sync.sh     auto-sync.sh     auto-sync.sh
 (every 5 min)    (every 5 min)    (every 5 min)
    ↕                 ↕                 ↕
 machines.json ←──→ machines.json ←──→ machines.json
```

Each machine:
1. Pulls remote changes (rebase)
2. Updates its own entry in `machines.json` (last_sync timestamp)
3. Commits local changes (tagged with machine name)
4. Pushes to remote

## Machine Naming

Each machine has a `.machine-name` file containing a short label:
- `studio`, `laptop`, `office`, `home`, etc.
- Must be unique across all machines
- No spaces (use hyphens)

This name appears in:
- Git commit messages: `auto-sync 2026-08-01 12:30 from studio`
- `machines.json` registry
- `wbstatus` output

## Machine Registry (`machines.json`)

A shared JSON file (synced via git) that tracks all registered machines:

```json
{
  "machines": [
    {
      "name": "studio",
      "hostname": "pascalliu-mac-studio",
      "registered": "2026-08-01T00:00:00Z",
      "last_sync": "2026-08-01T12:30:15Z",
      "status": "active"
    }
  ]
}
```

Each machine updates ONLY its own entry. Stale/offline status is computed
dynamically based on `last_sync` age:
- **active**: < 30 minutes since last sync
- **stale**: 30 min - 24 hours
- **offline**: > 24 hours

## Conflict Handling

With 3+ machines, the probability of concurrent edits increases.

### Auto-Sync Conflict Strategy

1. `git pull --rebase` — replay local commits on top of remote
2. If rebase fails (same file modified):
   - `git rebase --abort`
   - `git stash` — save local changes
   - `git pull` — accept remote (no rebase)
   - `git stash pop` — attempt to reapply local changes
   - If stash pop fails: keep remote, log to `.sync-conflicts.log`
3. Conflicts are logged (not silently lost) for manual review

### When to Resolve Manually

```bash
cd ~/.workbuddy
git status                    # see conflicts
# edit files...
git add -A
git rebase --continue
git push origin main
```

Check conflict log:
```bash
cat ~/.workbuddy/.sync-conflicts.log
```

## Status Command (`wbstatus`)

Run `wbstatus` in terminal to see:

```
  WorkBuddy Multi-Machine Sync Status
  ====================================
  This machine: studio (pascalliu-mac-studio)
  Daemon: RUNNING (PID 10034)
  Last sync: [2026-08-01 12:30:15] synced (studio)
  Conflicts: none

  Machine    Hostname               Status   Last Sync
  ----------------------------------------------------------
  laptop     pascalliu-mbp          active   2026-08-01 12:28 UTC
  office     pascalliu-imac         stale    2026-07-30 18:15 UTC
  studio     pascalliu-mac-studio   active   2026-08-01 12:30 UTC ←

  Total: 3 machines | Active: 2 | Stale: 1 | Offline: 0
```

## Migrating from Two-Machine to Multi-Machine

1. On Mac A (already synced):
```bash
# Set machine name
echo "studio" > ~/.workbuddy/.machine-name

# Replace auto-sync.sh with multi-machine version
cp ~/.workbuddy/skills/workbuddy-multi-machine-sync/scripts/auto-sync-multi.sh \
   ~/.workbuddy/auto-sync.sh
chmod +x ~/.workbuddy/auto-sync.sh

# Copy machine-status.sh
cp ~/.workbuddy/skills/workbuddy-multi-machine-sync/scripts/machine-status.sh \
   ~/.workbuddy/machine-status.sh
chmod +x ~/.workbuddy/machine-status.sh

# Add wbstatus alias to ~/.bash_profile
echo 'alias wbstatus="bash ~/.workbuddy/machine-status.sh"' >> ~/.bash_profile

# Update .gitignore — ensure .machine-name and machines.json are NOT ignored
# Remove start-sync-daemon.sh from .gitignore if present (it should stay ignored)

# Commit and push
cd ~/.workbuddy
git add -A
git commit -m "upgrade: multi-machine sync"
git push origin main
```

2. On Mac B:
```bash
cd ~/.workbuddy
git pull origin main
echo "laptop" > ~/.workbuddy/.machine-name

# Restart daemon to pick up new auto-sync.sh
kill $(cat ~/.workbuddy/.sync-daemon.pid)
bash ~/.workbuddy/start-sync-daemon.sh

git add -A
git commit -m "register: laptop"
git push origin main
```

3. For Mac C+ (new machines):
Use `setup-machine.sh.template` as described in the SKILL.md workflow.

## Best Practices for 3+ Machines

1. **One active machine at a time**: The sync handles concurrency, but
   editing the same file on two machines simultaneously will cause conflicts.
   Finish work on one machine before starting on another.

2. **Descriptive machine names**: Use location or purpose-based names
   (`studio`, `office`, `laptop`) rather than generic ones (`mac1`, `mac2`).

3. **Periodic cleanup**: Remove stale entries from `machines.json` for
   machines no longer in use:
```bash
# Edit machines.json manually, remove unused machine entries
cd ~/.workbuddy && git add machines.json && git commit -m "cleanup: remove old machines" && git push
```

4. **Check status before starting work**: Run `wbstatus` to see if another
   machine has recent unsynced changes.

5. **Conflict log review**: Periodically check `.sync-conflicts.log` for
   any auto-resolved conflicts that might need manual attention.
