#!/bin/bash
#
# WorkBuddy Sync Daemon — check and start (iCloud version)
# Runs auto-sync.sh every 5 minutes in background, survives terminal close
# Safe to call repeatedly (PID dedup)
# Called by .bash_profile or manually
#

WB_DIR="$HOME/.workbuddy"
PID_FILE="$WB_DIR/.sync-daemon.pid"

# Exit if already running
if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
  if kill -0 "$OLD_PID" 2>/dev/null; then
    exit 0
  fi
fi

# Find a working Python
PYTHON=""
for p in \
  "$WB_DIR/binaries/python/versions/3.13.12/bin/python3" \
  "$WB_DIR/binaries/python/versions/3.12"*/bin/python3 \
  /usr/local/bin/python3 \
  /opt/homebrew/bin/python3 \
  /usr/bin/python3; do
  if [ -x "$p" ] 2>/dev/null; then
    if "$p" -c "import subprocess" 2>/dev/null; then
      PYTHON="$p"
      break
    fi
  fi
done

if [ -z "$PYTHON" ]; then
  # No Python available, use pure bash background mode
  nohup /bin/bash -c "
    while true; do
      /bin/bash '$WB_DIR/auto-sync.sh' 2>/dev/null
      sleep 300
    done
  " >/dev/null 2>&1 &
  echo $! > "$PID_FILE"
  exit 0
fi

# Use Python start_new_session=True for a true daemon
"$PYTHON" -c "
import subprocess, os
wb = os.path.expanduser('~/.workbuddy')
proc = subprocess.Popen(
    ['/bin/bash', '-c', \"while true; do /bin/bash '\" + wb + \"/auto-sync.sh' 2>/dev/null; sleep 300; done\"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    stdin=subprocess.DEVNULL,
    start_new_session=True
)
with open(wb + '/.sync-daemon.pid', 'w') as f:
    f.write(str(proc.pid))
" 2>/dev/null
