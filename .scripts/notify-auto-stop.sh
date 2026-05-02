#!/usr/bin/env bash
# .gsd/scripts/notify-auto-stop.sh
#
# Sends a Discord webhook notification when GSD auto-mode stops unexpectedly.
# Covers: commit hook failures, context exhaustion, engine errors, and any
# other unclean exit that leaves work uncommitted.
#
# Usage:
#   notify-auto-stop.sh <milestone> <slice> <task> <reason> [status]
#
#   status: "complete" | "blocker" | "error" | "interrupted" | "commit_failed"
#   Default status is "interrupted" (covers any unexpected stop).
#
# Called manually after a detected stop, or from a file watcher on
# .gsd/runtime/paused-session.json (see watch-for-stop.sh).

set -euo pipefail

MILESTONE="${1:-UNKNOWN}"
SLICE="${2:-UNKNOWN}"
TASK="${3:-UNKNOWN}"
REASON="${4:-Unexpected stop — check .gsd/runtime/paused-session.json}"
STATUS="${5:-interrupted}"

# ── Webhook URL resolution ───────────────────────────────────────────────────

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ -f "$PROJECT_ROOT/.scripts/export_discord_webhook_var.sh" ]; then
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/.scripts/export_discord_webhook_var.sh"
fi

WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

if [ -z "$WEBHOOK_URL" ]; then
  exit 0
fi

# ── Detect uncommitted changes ───────────────────────────────────────────────

if git -C "$PROJECT_ROOT" diff --quiet HEAD 2>/dev/null && \
   [ -z "$(git -C "$PROJECT_ROOT" status --short 2>/dev/null)" ]; then
  UNCOMMITTED="None (clean tree)"
else
  UNCOMMITTED=$(git -C "$PROJECT_ROOT" status --short 2>/dev/null | head -10 || echo "Unable to read git status")
fi

# ── Determine color by status ────────────────────────────────────────────────

case "$STATUS" in
  blocker)       COLOR=16711680 ;; # red
  commit_failed) COLOR=16711680 ;; # red
  error)         COLOR=16744272 ;; # orange
  interrupted)   COLOR=16776960 ;; # yellow
  *)             COLOR=10066329 ;; # grey
esac

# ── Escape for JSON ──────────────────────────────────────────────────────────

escape_json() {
  printf '%s' "$1" | python3 -c 'import sys,json; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null \
    || printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n'
}

REASON_ESC="$(escape_json "$REASON")"
UNCOMMITTED_ESC="$(escape_json "$UNCOMMITTED")"

# ── Build and send embed ─────────────────────────────────────────────────────

PAYLOAD=$(cat <<EOF
{
  "content": "⚠️ **GSD Auto-Mode Stopped**",
  "embeds": [{
    "title": "Auto-Mode Unexpected Stop",
    "color": ${COLOR},
    "fields": [
      { "name": "Milestone",            "value": "${MILESTONE}",             "inline": true },
      { "name": "Slice",                "value": "${SLICE}",                 "inline": true },
      { "name": "Task",                 "value": "${TASK}",                  "inline": true },
      { "name": "Status",               "value": "${STATUS}",                "inline": true },
      { "name": "Reason",               "value": "\`\`\`${REASON_ESC}\`\`\`","inline": false },
      { "name": "Uncommitted Changes",  "value": "\`\`\`${UNCOMMITTED_ESC}\`\`\`", "inline": false }
    ],
    "footer": { "text": "Check .gsd/runtime/paused-session.json and .gsd/activity/ for details" }
  }]
}
EOF
)

curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" > /dev/null 2>&1

exit 0
