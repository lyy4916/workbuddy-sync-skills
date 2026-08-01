# iCloud Sync Architecture & Troubleshooting

## How It Works

```
Mac A ~/.workbuddy/ → git push → iCloud Drive/WorkBuddy-sync.git (bare repo)
                                              ↓ (iCloud auto-syncs the file)
Mac B ~/.workbuddy/ ← git pull ← iCloud Drive/WorkBuddy-sync.git (bare repo)
```

iCloud Drive treats the bare git repo as a regular folder. When Mac A pushes,
the bare repo files update; iCloud propagates the changes to Mac B's local
iCloud Drive copy; Mac B's daemon then pulls from that local copy.

## Data Layers

### Layer 1: Server-Side Synced (automatic)
- Conversation history
- Cloud user profile

### Layer 2: Git-Synced via iCloud (this skill)
- `SOUL.md`, `IDENTITY.md`, `USER.md`
- `MEMORY.md`
- `mcp.json`, `settings.json`
- `skills/`

### Layer 3: Machine-Local (never synced)
- `binaries/`, `workbuddy.db`, `.mcp.json`, `sessions/`, `logs/`, `traces/`,
  `credentials/`, `memory/`

## Daemon Architecture

```
.bash_profile → start-sync-daemon.sh → Python subprocess → bash loop
                                                      ↓
                                              auto-sync.sh (every 300s)
                                                      ↓
                                              git pull → commit → push (icloud remote)
```

## iCloud vs GitHub Comparison

| Aspect | iCloud | GitHub |
|--------|--------|--------|
| Account | Apple ID (same on all Macs) | GitHub account |
| Auth | None (local file access) | Token or SSH key |
| Network | Apple iCloud | GitHub.com |
| China speed | Moderate (Apple CDN) | Slow (needs proxy) |
| Setup time | ~2 minutes | ~5 minutes |
| Concurrent access | Safe (iCloud serializes file writes) | Safe (git protocol) |
| Storage limit | iCloud Drive quota (5GB free) | GitHub repo limit |
| Best for | All Macs share Apple ID | Different Apple IDs or need web access |

## Common Issues

### iCloud hasn't synced the bare repo yet
**Symptom**: Mac B can't find `WorkBuddy-sync.git` in iCloud Drive
**Fix**: On Mac A, verify the push succeeded. On Mac B, open Finder → iCloud
Drive and check if the folder appears. Force iCloud sync:
```bash
killall bird && killall cloudd  # restart iCloud daemons
```

### Merge conflicts during auto-sync
**Symptom**: `git pull --rebase` fails
**Fix**:
```bash
cd ~/.workbuddy
git status
# resolve conflicts...
git add -A
git rebase --continue
git push icloud main
```

### Daemon not running
**Check**:
```bash
cat ~/.workbuddy/.sync-daemon.pid
kill -0 $(cat ~/.workbuddy/.sync-daemon.pid) && echo "ALIVE" || echo "DEAD"
```
**Restart**:
```bash
bash ~/.workbuddy/start-sync-daemon.sh
```

### Switching from GitHub to iCloud
```bash
cd ~/.workbuddy
git remote remove origin 2>/dev/null
git remote add icloud "$HOME/Library/Mobile Documents/com~apple~CloudDocs/WorkBuddy-sync.git"
git push -u icloud main
```
Then update `auto-sync.sh` to use `icloud` remote instead of `origin`.

### Automations not syncing
Automations live in `workbuddy.db` (excluded from sync). Recreate on each
machine using the `automation_update` tool.

## Daemon Recovery After Reboot
The daemon dies on reboot but auto-restarts when:
1. User opens Terminal (`.bash_profile` calls `start-sync-daemon.sh`)
2. WorkBuddy executes any bash command (triggers `.bash_profile`)
