#!/usr/bin/env bash
# S04 fixture verification: confirms dismiss gating + phase timers work across
# the full M003 pipeline (pending → result → resolved).
#
# Strategy: delegates to busted (the same runner used by `make test`).
# Individual S04 spec files each drive real event handlers and assert:
#   • phase transitions   (_dropStates.phase at each event)
#   • dismiss lock/unlock (rowPhase in dispatched payload)
#   • timer restarts      (showForSeconds in dispatched payload)
#   • LogDebug emissions  (structured phase-transition logging)
#
# Exit 0 → all fixtures passed; non-zero → failure count printed, exit 1.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
RESULTS=()

run_spec() {
  local label="$1"
  local file="$2"
  local output
  output=$(make test-file FILE="$file" 2>&1)
  local exit_code=$?
  local summary
  summary=$(echo "$output" | grep -E '[0-9]+ successes' | tail -1)
  local failures
  failures=$(echo "$summary" | grep -oE '[0-9]+ failures' | grep -oE '[0-9]+' || echo "0")
  local successes
  successes=$(echo "$summary" | grep -oE '[0-9]+ successes' | grep -oE '[0-9]+' || echo "0")

  if [[ $exit_code -eq 0 && "${failures:-0}" -eq 0 ]]; then
    PASS=$((PASS + 1))
    RESULTS+=("  ✅  $label — ${successes} tests passed")
  else
    FAIL=$((FAIL + 1))
    RESULTS+=("  ❌  $label — FAILED (exit $exit_code; $summary)")
    echo "--- Output for: $label ---"
    echo "$output" | tail -20
  fi
}

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  S04 Fixture Verification  —  Dismiss Gating + Timers"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Phase tracking (T01) ─────────────────────────────────────────────────────
run_spec "Phase tracking (pending/result/resolved/cancelled)" \
  "RPGLootFeed_spec/Features/LootRolls_phase_tracking_spec.lua"

# ── Dismiss lock / unlock (T02) ──────────────────────────────────────────────
run_spec "Dismiss gating: SetClickThrough lock/unlock via rowPhase" \
  "RPGLootFeed_spec/Features/LootRolls_dismiss_lock_spec.lua"

# ── Timer phasing (T03) ──────────────────────────────────────────────────────
run_spec "Timer phasing: rollTime+buffer vs fadeOutDelay per phase" \
  "RPGLootFeed_spec/Features/LootRolls_timer_phasing_spec.lua"

# ── Full pipeline E2E (T04) ──────────────────────────────────────────────────
run_spec "E2E lifecycle: pending→result→resolved + cancel + multi-drop" \
  "RPGLootFeed_spec/Features/LootRolls_lifecycle_e2e_spec.lua"

echo ""
echo "───────────────────────────────────────────────────────────"
echo "  Results:"
for r in "${RESULTS[@]}"; do
  echo "$r"
done
echo ""

TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo "  All fixtures passed ($PASS/$TOTAL suites)"
  echo "───────────────────────────────────────────────────────────"
  echo ""
  exit 0
else
  echo "  FAILED: $FAIL/$TOTAL suites had failures"
  echo "───────────────────────────────────────────────────────────"
  echo ""
  exit 1
fi
