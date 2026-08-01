#!/bin/bash
#
# WorkBuddy Machine Status — display all registered machines and sync status
#
# Usage: wbstatus  (or: bash ~/.workbuddy/machine-status.sh)
#

WB_DIR="$HOME/.workbuddy"
REGISTRY_FILE="$WB_DIR/machines.json"
DAEMON_PID_FILE="$WB_DIR/.sync-daemon.pid"
LOG_FILE="$WB_DIR/.auto-sync.log"
CONFLICT_LOG="$WB_DIR/.sync-conflicts.log"

# Machine name
MACHINE_NAME=$(cat "$WB_DIR/.machine-name" 2>/dev/null || echo "$(hostname)")

echo ""
echo "  WorkBuddy Multi-Machine Sync Status"
echo "  ===================================="
echo "  This machine: $MACHINE_NAME ($(hostname))"
echo ""

# Daemon status
if [ -f "$DAEMON_PID_FILE" ]; then
  PID=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
  if kill -0 "$PID" 2>/dev/null; then
    echo "  Daemon: RUNNING (PID $PID)"
  else
    echo "  Daemon: DEAD (PID $PID no longer alive)"
  fi
else
  echo "  Daemon: NOT STARTED"
fi

# Last sync
if [ -f "$LOG_FILE" ]; then
  LAST_SYNC=$(tail -1 "$LOG_FILE" 2>/dev/null)
  echo "  Last sync: $LAST_SYNC"
else
  echo "  Last sync: never"
fi

# Conflicts
if [ -f "$CONFLICT_LOG" ] && [ -s "$CONFLICT_LOG" ]; then
  CONFLICT_COUNT=$(wc -l < "$CONFLICT_LOG" 2>/dev/null)
  echo "  Conflicts: $CONFLICT_COUNT (see .sync-conflicts.log)"
else
  echo "  Conflicts: none"
fi

echo ""

# Machine registry
if [ ! -f "$REGISTRY_FILE" ]; then
  echo "  No machine registry found."
  echo "  Run multi-machine setup first."
  echo ""
  exit 0
fi

# Use Python to parse JSON and display table
PYTHON=""
for p in \
  "$WB_DIR/binaries/python/versions/3.13.12/bin/python3" \
  "$WB_DIR/binaries/python/versions/3.12"*/bin/python3 \
  /usr/local/bin/python3 \
  /opt/homebrew/bin/python3 \
  /usr/bin/python3; do
  [ -x "$p" ] 2>/dev/null && PYTHON="$p" && break
done

if [ -z "$PYTHON" ]; then
  echo "  (Python not found — showing raw registry:)"
  cat "$REGISTRY_FILE"
  echo ""
  exit 0
fi

"$PYTHON" -c "
import json, os, datetime, sys

reg_path = os.path.expanduser('~/.workbuddy/machines.json')
this_machine = os.path.expanduser('~/.workbuddy/.machine-name')
this_name = open(this_machine).read().strip() if os.path.exists(this_machine) else os.uname().nodename

try:
    with open(reg_path) as f:
        reg = json.load(f)
except:
    print('  Error reading machines.json')
    sys.exit(1)

machines = reg.get('machines', [])
if not machines:
    print('  No machines registered.')
    sys.exit(0)

# Update status based on last_sync
now = datetime.datetime.now(datetime.timezone.utc)
for m in machines:
    last = m.get('last_sync', '')
    if last:
        try:
            last_dt = datetime.datetime.fromisoformat(last.replace('Z', '+00:00'))
            age = (now - last_dt).total_seconds()
            if age > 86400:
                m['status'] = 'offline'
            elif age > 1800:
                m['status'] = 'stale'
            else:
                m['status'] = 'active'
        except:
            m['status'] = 'unknown'
    else:
        m['status'] = 'unknown'

# Print table
name_w = max(len(m.get('name', '?')) for m in machines)
host_w = max(len(m.get('hostname', '?')) for m in machines)
stat_w = 8

header = f'  {{:<{name_w}}}  {{:<{host_w}}}  {{:<{stat_w}}}  {}'.format
print(header('Machine', 'Hostname', 'Status', 'Last Sync'))
print('  ' + '-' * (name_w + host_w + stat_w + 20))

for m in sorted(machines, key=lambda x: x.get('name', '')):
    name = m.get('name', '?')
    host = m.get('hostname', '?')
    status = m.get('status', '?')
    last = m.get('last_sync', '?')
    if last != '?':
        try:
            dt = datetime.datetime.fromisoformat(last.replace('Z', '+00:00'))
            last = dt.strftime('%Y-%m-%d %H:%M UTC')
        except:
            pass
    marker = ' ←' if name == this_name else ''
    print(f'  {name:<{name_w}}  {host:<{host_w}}  {status:<{stat_w}}  {last}{marker}')

print()
total = len(machines)
active = sum(1 for m in machines if m.get('status') == 'active')
stale = sum(1 for m in machines if m.get('status') == 'stale')
offline = sum(1 for m in machines if m.get('status') == 'offline')
print(f'  Total: {total} machines | Active: {active} | Stale: {stale} | Offline: {offline}')
print()
"
