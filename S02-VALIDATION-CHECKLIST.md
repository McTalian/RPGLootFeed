# S02 Live Raid Validation Checklist

**Milestone:** M004 — playerSelection live raid operational proof  
**Slice:** S02 — Live Raid Validation  
**Status:** ☐ In Progress / ☐ Complete  
**Raid Date:** **\*\***\_**\*\***  
**Raid Name / Zone:** **\*\***\_**\*\***  
**Tester:** **\*\***\_**\*\***

---

## Instructions

Work through each item during your raid session. For each item, mark:

- `[x]` — **PASS**: Behavior confirmed as expected
- `[!]` — **ISSUE FOUND**: Note what happened in the "Observations" field below
- `[-]` — **SKIP**: Item could not be tested (explain why in Observations)

Record observations immediately after each loot roll while the details are fresh.

---

## Validation Items

- [ ] **V1 — Button Submission (Need/Greed/Pass/Transmog):** Click at least one button (Need, Greed, or Pass) on a loot roll row during a real raid drop. Confirm the button click registers without silent failure — the button should become unclickable after pressing and no lua error should flash on screen.

- [ ] **V2 — Result Row Appears After Roll Resolution:** After rolling, wait for the loot master or random roll to resolve. Confirm that a result row appears in the RPGLootFeed display showing: (a) the item name, (b) the winner's name and roll value, (c) your roll type (e.g., "You: NEED").

- [ ] **V3 — playerSelection Displays Correctly in Result Row:** In the result row, confirm your chosen roll type is shown as "You: NEED", "You: GREED", "You: PASS", or "You: TRANSMOG" (Retail) / "You: DISENCHANT" (Classic). The label must appear alongside the winner info, not be blank or show nil/Unknown.

- [ ] **V4 — All Roll Types Produce Correct playerSelection Label:** Across the session, test at least two different roll types (e.g., one NEED and one PASS, or one GREED and one PASS). Confirm each roll type produces the correct "You: <TYPE>" label in its result row — labels must not be swapped or show the wrong type.

- [ ] **V5 — Multi-Drop Same-Item Scenario (if available):** If two or more copies of the same item drop in a single roll window (or two rapid consecutive rolls of the same item occur), confirm that each result row correctly shows the winner and roll value for its own roll — they must not be swapped or show another player's selection.

- [ ] **V6 — Dismiss Gating — Rows Locked During Pending Phase:** Immediately after an item drops (before rolling), verify that the dismiss button on that loot row is NOT active (locked/greyed or non-clickable). You should not be able to dismiss the row before the roll resolves.

- [ ] **V7 — Dismiss Gating — Rows Locked During Result Phase:** Immediately after rolling (result row appears), verify the row remains non-dismissable for the result display duration. Attempting to click dismiss during this phase should have no effect.

- [ ] **V8 — Dismiss Gating — Row Becomes Dismissable After Resolution:** After the result display timer expires (or the resolved phase is reached), verify the row CAN be dismissed. Clicking dismiss at this point should remove the row cleanly without leaving an orphaned row behind.

- [ ] **V9 — No UI Artifacts (Orphaned Rows, Stale Timers):** After dismissing or after rows auto-expire, confirm no orphaned rows remain in the feed. Also confirm that any visible countdown timers reflect the actual remaining time (not stale values from a previous roll that should have cleared).

- [ ] **V10 — No Lua Errors During Session:** Confirm no Lua error popup (red "!" or BugSack notification) appears at any point during loot roll button interactions or result display. If any Lua error appears, capture the full error text in Observations.

---

## Observations

### V1 — Button Submission

_What happened:_

---

### V2 — Result Row Appears

_What happened:_

---

### V3 — playerSelection Label

_What happened:_

---

### V4 — All Roll Types

_What happened:_

---

### V5 — Multi-Drop Same Item

_What happened (or reason skipped):_

---

### V6 — Dismiss Locked (Pending)

_What happened:_

---

### V7 — Dismiss Locked (Result)

_What happened:_

---

### V8 — Dismiss Unlocked (Resolved)

_What happened:_

---

### V9 — UI Artifacts

_What happened:_

---

### V10 — Lua Errors

_Errors observed (copy full text) or "None":_

---

## Overall Verdict

☐ **ALL PASS** — All tested items confirmed working. Milestone M004 eligible for closure.  
☐ **ISSUES FOUND** — See items above marked `[!]`. Issues deferred to follow-up milestone per S02 boundary contract.  
☐ **INCOMPLETE** — Insufficient loot events occurred to test all items. Note which items were untestable.

**Summary notes:**

---

_After completing this checklist, hand results to T04 (executor) for result collection and documentation._
