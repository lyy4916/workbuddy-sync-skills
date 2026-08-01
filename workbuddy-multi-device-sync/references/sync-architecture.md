# Sync Architecture & Troubleshooting

## Three-Layer Data Model

WorkBuddy data in `~/.workbuddy/` falls into three categories:

### Layer 1: Server-Side Synced (automatic, no action needed)
- Conversation history — searchable across devices
- Cloud user profile — auto-injected at session start

### Layer 2: Git-Synced (this skill handles)
- `SOUL.md`, `IDENTITY.md`, `USER.md` — agent identity
- `MEMORY.md` — cross-project user memory
- `mcp.json` — MCP server config (NOT `.mcp.json`)
- `settings.json` — WorkBuddy settings
- `skills/` — installed skills
- `wb-setup-mac-b.sh` — Mac B setup script (stored in repo for easy download)

### Layer 3: Machine-Local (never synced)
- `binaries/` — 300MB+ runtimes, platform-specific
- `workbuddy.db` — SQLite, automations + runtime state (concurrent access corrupts)
- `.mcp.json` — localhost port mappings, differ per machine
- `sessions/`, `logs/`, `traces/` — ephemeral runtime data
- `credentials/` — auth tokens, each machine independent
- `memory/` — daily work logs, project-specific

## Sync Flow

```
Mac A changes → git commit → git push → GitHub repo
                                          ↓
Mac B ← git pull ← git rebase ← auto-sync daemon (every 5 min)
```

## Daemon Architecture

The sync daemon uses Python's `subprocess.Popen` with `start_new_session=True`
to create a truly detached process that survives terminal close.

```
.bash_profile → start-sync-daemon.sh → Python subprocess → bash loop
                                                      ↓
                                              auto-sync.sh (every 300s)
                                                      ↓
                                              git pull → commit → push
```

### Why not LaunchAgent?
On macOS 12+, `launchctl load` frequently fails with "Input/output error" under
sandbox restrictions. The Python daemon approach is more reliable and doesn't
require elevated permissions.

### Recovery After Reboot
The daemon dies on reboot but auto-restarts when:
1. User opens Terminal (`.bash_profile` calls `start-sync-daemon.sh`)
2. WorkBuddy executes any bash command (triggers `.bash_profile`)

## Common Issues

### GitHub SSH port 22 blocked
**Symptom**: `ssh -T git@github.com` hangs or times out
**Fix**: Use HTTPS + token instead of SSH
```bash
git remote set-url origin https://github.com/<user>/wb-sync.git
```

### Token expired or revoked
**Symptom**: `git push` returns 403 Forbidden
**Fix**: Generate new token at https://github.com/settings/tokens/new
```bash
echo "https://<user>:<new_token>@github.com" > ~/.git-credentials
```

### Merge conflicts during auto-sync
**Symptom**: `git pull --rebase` fails, daemon stops syncing
**Fix**: Manually resolve and push
```bash
cd ~/.workbuddy
git status              # see conflicted files
# resolve conflicts...
git add -A
git rebase --continue
git push origin main
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

### Automations not syncing
Automations live in `workbuddy.db` (excluded from sync). To replicate on Mac B:
use the `automation_update` tool with `mode="list"` on Mac A to see all
automations, then `mode="create"` on Mac B to recreate each one.

## Alternative Sync Backends

### iCloud Drive (bare repo)
Instead of GitHub, create a bare repo in iCloud:
```bash
git clone --bare ~/.workbuddy ~/Library/Mobile\ Documents/com~apple~CloudDocs/WorkBuddy-sync.git
cd ~/.workbuddy
git remote add icloud ~/Library/Mobile\ Documents/com~apple~CloudDocs/WorkBuddy-sync.git
git push -u icloud main
```
Pros: No external service needed. Cons: Requires same iCloud account on all machines.

### Gitee (China-friendly)
Same as GitHub but use `gitee.com` instead. Faster access in China.

### Syncthing (P2P)
Direct machine-to-machine sync, no cloud. Both machines must be online simultaneously.
