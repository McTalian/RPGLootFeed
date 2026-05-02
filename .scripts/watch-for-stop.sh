#!/usr/bin/env bash
# .gsd/scripts/watch-for-stop.sh
#
# Watches .gsd/runtime/paused-session.json for unexpected auto-mode stops
# and fires a Discord webhook notification via notify-auto-stop.sh.
#
# Run this in a background terminal before starting /gsd auto:
#   bash .gsd/scripts/watch-for-stop.sh &
#
# Or add to your shell startup for the project:
#   cd /path/to/RPGLootFeed && bash .gsd/scripts/watch-for-stop.sh > /dev/null 2>&1 &
#
# The watcher exits cleanly when the paused-session file disappears (auto-mode
# resumed or completed normally).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || dirname "$SCRIPT_DIR")"
PAUSED_FILE="$PROJECT_ROOT/.gsd/runtime/paused-session.json"
LAST_MTIME=""

echo "[watch-for-stop] Watching $PAUSED_FILE for unexpected stops..."

while true; do
  sleep 5

  if [ ! -f "$PAUSED_FILE" ]; then
    LAST_MTIME=""
    continue
  fi

  CURRENT_MTIME=$(stat -c %Y "$PAUSED_FILE" 2>/dev/null || stat -f %m "$PAUSED_FILE" 2>/dev/null || echo "0")

  if [ "$CURRENT_MTIME" = "$LAST_MTIME" ]; then
    continue
  fi

  LAST_MTIME="$CURRENT_MTIME"

  # Parse paused-session.json for context
  MILESTONE=$(python3 -c "import json,sys; d=json.load(open('$PAUSED_FILE')); print(d.get('milestoneId','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  UNIT_ID=$(python3 -c "import json,sys; d=json.load(open('$PAUSED_FILE')); print(d.get('unitId','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  UNIT_TYPE=$(python3 -c "import json,sys; d=json.load(open('$PAUSED_FILE')); print(d.get('unitType','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  PAUSED_AT=$(python3 -c "import json,sys; d=json.load(open('$PAUSED_FILE')); print(d.get('pausedAt',''))" 2>/dev/null || echo "")

  # Parse slice and task from unitId (format: M002/S02/T01)
  SLICE=$(echo "$UNIT_ID" | cut -d'/' -f2 2>/dev/null || echo "UNKNOWN")
  TASK=$(echo "$UNIT_ID" | cut -d'/' -f3 2>/dev/null || echo "UNKNOWN")

  REASON="Auto-mode paused at ${PAUSED_AT} during ${UNIT_TYPE} (${UNIT_ID})"

  echo "[watch-for-stop] Detected pause: $UNIT_ID at $PAUSED_AT — sending notification"

  bash "$SCRIPT_DIR/notify-auto-stop.sh" \
    "$MILESTONE" "$SLICE" "$TASK" "$REASON" "interrupted" || true
done
