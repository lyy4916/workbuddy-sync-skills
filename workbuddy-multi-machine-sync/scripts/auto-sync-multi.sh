#!/bin/bash
#
# WorkBuddy Multi-Machine Auto-Sync Script
# Enhanced for 3+ machines: machine tagging, registry update, conflict handling
#
# Called by daemon every 5 minutes
# Pull remote → update registry → commit local → push, all silent
#

WB_DIR="$HOME/.workbuddy"
LOG_FILE="$WB_DIR/.auto-sync.log"
CONFLICT_LOG="$WB_DIR/.sync-conflicts.log"
MACHINE_NAME_FILE="$WB_DIR/.machine-name"
REGISTRY_FILE="$WB_DIR/machines.json"

# Remote name: try "origin" (GitHub) first, then "icloud"
REMOTE=""
BRANCH="main"
for r in origin icloud; do
  if git -C "$WB_DIR" remote get-url "$r" >/dev/null 2>&1; then
    REMOTE="$r"
    break
  fi
done
[ -z "$REMOTE" ] && exit 0

# Ensure git config exists
if [ -z "$(git config --global user.name)" ]; then
  git config --global user.name "$(whoami)"
  git config --global user.email "$(whoami)@workbuddy.local"
  git config --global init.defaultBranch main
fi

cd "$WB_DIR" || exit 0
[ -d ".git" ] || exit 0

# Get machine name
MACHINE_NAME=$(cat "$MACHINE_NAME_FILE" 2>/dev/null || echo "$(hostname)")
TS=$(date '+%Y-%m-%d %H:%M:%S')
TS_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 1. Pull remote changes with conflict handling
git pull --rebase "$REMOTE" "$BRANCH" >/dev/null 2>&1
PULL_EXIT=$?

if [ $PULL_EXIT -ne 0 ]; then
  # Rebase conflict — stash, pull, pop
  git rebase --abort 2>/dev/null
  git stash >/dev/null 2>&1
  git pull "$REMOTE" "$BRANCH" >/dev/null 2>&1
  git stash pop >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    # Stash pop conflict — keep remote, log conflict
    git checkout --theirs . 2>/dev/null
    git stash drop >/dev/null 2>&1
    echo "[${TS}] CONFLICT on $(hostname) — kept remote version" >> "$CONFLICT_LOG"
    tail -50 "$CONFLICT_LOG" > "$CONFLICT_LOG.tmp" && mv "$CONFLICT_LOG.tmp" "$CONFLICT_LOG" 2>/dev/null
  fi
fi

# 2. Update machine registry
if [ -f "$REGISTRY_FILE" ]; then
  # Use Python to safely update JSON
  PYTHON=""
  for p in \
    "$WB_DIR/binaries/python/versions/3.13.12/bin/python3" \
    "$WB_DIR/binaries/python/versions/3.12"*/bin/python3 \
    /usr/local/bin/python3 \
    /opt/homebrew/bin/python3 \
    /usr/bin/python3; do
    [ -x "$p" ] 2>/dev/null && PYTHON="$p" && break
  done

  if [ -n "$PYTHON" ]; then
    "$PYTHON" -c "
import json, os, datetime
wb = os.path.expanduser('~/.workbuddy')
reg_path = os.path.join(wb, 'machines.json')
name_path = os.path.join(wb, '.machine-name')
machine_name = open(name_path).read().strip() if os.path.exists(name_path) else os.uname().nodename
hostname = os.uname().nodename
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

try:
    with open(reg_path) as f:
        reg = json.load(f)
except:
    reg = {'machines': []}

machines = reg.get('machines', [])
found = False
for m in machines:
    if m.get('name') == machine_name or m.get('hostname') == hostname:
        m['last_sync'] = now
        m['status'] = 'active'
        m['hostname'] = hostname
        found = True
        break
if not found:
    machines.append({
        'name': machine_name,
        'hostname': hostname,
        'registered': now,
        'last_sync': now,
        'status': 'active'
    })

# Update stale status for other machines
for m in machines:
    if m.get('name') != machine_name and m.get('hostname') != hostname:
        last = m.get('last_sync', '')
        if last:
            try:
                last_dt = datetime.datetime.fromisoformat(last.replace('Z', '+00:00'))
                age = (datetime.datetime.now(datetime.timezone.utc) - last_dt).total_seconds()
                if age > 86400:
                    m['status'] = 'offline'
                elif age > 1800:
                    m['status'] = 'stale'
            except:
                pass

reg['machines'] = machines
with open(reg_path, 'w') as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)
" 2>/dev/null
  fi
fi

# 3. Commit local changes
git add -A
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "auto-sync ${TS} from ${MACHINE_NAME}" >/dev/null 2>&1
fi

# 4. Push
git push "$REMOTE" "$BRANCH" >/dev/null 2>&1

# Log (keep last 50 lines only)
echo "[${TS}] synced (${MACHINE_NAME})" >> "$LOG_FILE"
tail -50 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
