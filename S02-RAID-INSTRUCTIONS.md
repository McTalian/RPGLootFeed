# S02 Live Raid Validation — Instructions

**Milestone:** M004 — playerSelection live raid operational proof  
**Slice:** S02 — Live Raid Validation  
**Prerequisite:** T01 complete (addon built via `make dev`, playerSelection pipeline confirmed)

---

## Overview

This document walks you through setting up for and executing a live raid validation of the RPGLootFeed addon's **playerSelection recording feature**. The goal is to confirm that:

1. Loot roll action buttons submit reliably in a real raid environment.
2. Result rows display your roll type ("You: NEED", "You: GREED", etc.) alongside winner info.
3. Multi-drop same-item scenarios match correctly.
4. Dismiss gating (row lock/unlock) works at each phase.
5. No UI artifacts (orphaned rows, stale timers, Lua errors) appear.

**Important boundary rule:** If you discover any issue during this session, **document it but do not attempt a fix**. All fixes are deferred to a follow-up milestone. The goal of this session is observation and documentation only.

---

## Part 1: Pre-Raid Setup

### Step 1 — Rebuild and Deploy the Addon

1. Open a terminal and navigate to the project root:
   ```
   cd /home/mctalian/code/RPGLootFeed
   ```
2. Run the development build:
   ```
   make dev
   ```
3. Confirm the build completes with no errors. You should see output containing "packaged" or "Copied". If the build fails, stop and investigate before raiding.

### Step 2 — Verify the Addon Loads in WoW

1. Launch World of Warcraft.
2. Log in on a character that has access to raid content.
3. Open the AddOn manager (Character Select screen → "AddOns" button or in-game via `/addons`) and confirm **RPGLootFeed** is enabled and shows no load error.
4. Type `/rlf` or your configured slash command to confirm the addon responds.

### Step 3 — Enable Debug Logging (Recommended)

If the addon has a debug or verbose logging option in its settings, enable it now. This will produce diagnostic output in the chat log and/or the saved variables file that can be inspected after the session.

In-game, check the RPGLootFeed settings panel for any "Debug" or "Verbose" toggle and enable it.

### Step 4 — Prepare Your Logging Method

Choose one of the following methods to capture diagnostic output during the raid:

**Option A — Chat Log file** (easiest):  
WoW writes all chat (including addon output printed to DEFAULT_CHAT_FRAME) to:

```
<WoW installation>/Logs/WoWChatLog.txt
```

You can open this file after the raid to see any addon messages that printed to chat.

**Option B — BugSack / BugGrabber** (for Lua error capture):  
If you have BugSack installed, Lua errors are captured automatically. After the raid, use `/bugsack` to review any errors.

**Option C — Manual notes**:  
Keep a notepad open (physical or digital) and jot observations immediately after each loot event.

### Step 5 — Open the Checklist

Print or open `S02-VALIDATION-CHECKLIST.md` so you can mark items during the raid. Keep it accessible.

---

## Part 2: During the Raid

### Step 6 — Watch for Each Loot Event

When a loot roll window appears (a bonus roll, group loot, or raid roll):

1. **Before clicking anything:** Note whether the row appears in RPGLootFeed, and check whether the dismiss control is inactive (V6 check).
2. **Click an action button** (Need, Greed, Pass, or Transmog). Check V1 — does the button become non-clickable after clicking? Does any Lua error appear?
3. **Wait for resolution.** After the roll resolves, note whether a result row appears (V2 check).
4. **Inspect the result row.** Look for both the winner name/roll value AND a "You: <TYPE>" label (V3 check).
5. **Check dismiss gating.** During the result display countdown, try to dismiss the row (V7 check). After the timer expires or the row enters the resolved phase, try again (V8 check).

### Step 7 — Target at Least 3 Loot Events

To have meaningful data, aim to interact with at least 3 distinct loot roll events during the session. More is better. If you cannot get 3 events in one raid, note how many events occurred.

### Step 8 — Test Multiple Roll Types if Possible

If the opportunity arises, vary your roll type across events:

- Roll NEED on at least one item.
- Roll PASS (or GREED) on at least one item.

This tests V4 (all roll types produce correct labels).

### Step 9 — Watch for the Multi-Drop Scenario

If two copies of the same item drop simultaneously (common in Raid Finder or when using bonus rolls), or two rapid consecutive rolls of the same item occur:

- Note whether result rows appear for each drop separately.
- Verify each row shows the correct winner and your selection for that specific roll (V5 check).

If this scenario does not occur naturally during your session, mark V5 as `[-]` (skip) in the checklist.

### Step 10 — Monitor for UI Artifacts

After each dismissed or expired row, glance at the RPGLootFeed display:

- Are any rows still visible that should have cleared? (V9 check)
- Do any timers show stale values from a previous roll?

At the end of the session, if the feed is empty, confirm it looks clean.

---

## Part 3: After the Raid

### Step 11 — Complete the Checklist

Fill in all observation fields in `S02-VALIDATION-CHECKLIST.md`:

- Mark each item `[x]` PASS, `[!]` ISSUE FOUND, or `[-]` SKIP.
- Write at least one sentence in each Observations field, even if it just says "Confirmed as expected."

### Step 12 — Save the WoW Chat Log

Copy the WoW chat log file to a location where it can be retrieved:

```
cp "<WoW install>/Logs/WoWChatLog.txt" /tmp/S02_raid_session_log.txt
```

If you don't have the chat log path handy, you can find it at:

- **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Logs\WoWChatLog.txt`
- **macOS:** `/Applications/World of Warcraft/_retail_/Logs/WoWChatLog.txt`

If no log was written, create a manual log file at `/tmp/S02_raid_session_log.txt` containing your text observations and the items you clicked.

### Step 13 — Save WoW SavedVariables (Optional but Valuable)

The addon's SavedVariables file may contain recorded loot roll data:

- **Windows:** `C:\...\World of Warcraft\_retail_\WTF\Account\<account>\SavedVariables\RPGLootFeed.lua`
- **macOS:** `/Applications/.../WTF/Account/<account>/SavedVariables/RPGLootFeed.lua`

Copy this file to `/tmp/S02_savedvariables_snapshot.lua` for later inspection.

### Step 14 — Screenshot / Recording (Optional)

If you captured any screenshots or a screen recording showing result rows with the "You: NEED/GREED/PASS" label visible, save them to:

```
/tmp/S02_screenshots/
```

Name them descriptively (e.g., `S02_need_roll_result.png`, `S02_multiitem_drop.png`).

---

## Part 4: If Issues Are Discovered

**Rule: Document, don't fix.** If you observe a problem during the session:

1. Mark the relevant checklist item as `[!]` ISSUE FOUND.
2. Write a clear description in the Observations field:
   - What you expected to see.
   - What you actually saw.
   - The exact sequence of actions that led to it.
   - Any Lua error text (copy verbatim).
3. If it's reproducible, note what triggers it.
4. **Do not attempt code changes.** All fixes are deferred to a post-M004 follow-up milestone.

### Common Issue Patterns to Document

| Symptom                             | What to record                                                         |
| ----------------------------------- | ---------------------------------------------------------------------- |
| Button click has no effect          | Roll type attempted, item name, whether any error appeared             |
| Result row shows blank "You:" label | Roll type, item name, whether the roll resolved normally               |
| Result rows swapped in multi-drop   | Both item names, roll types for each, which result showed which winner |
| Row can be dismissed too early      | Phase when dismiss succeeded (pending vs. result display)              |
| Orphaned row stays visible          | How long it remained, item name, whether dismiss eventually worked     |
| Lua error popup                     | Full error text including file:line reference                          |

---

## Part 5: Handoff to T04

After completing the checklist and saving logs, the executor (T04) will:

1. Collect and organize the logs and checklist into the slice directory.
2. Map your observations to each checklist item.
3. Produce `S02-VALIDATION-RESULTS.md` with an overall PASS/FAIL verdict.

The raid session is complete when:

- `S02-VALIDATION-CHECKLIST.md` has every item marked (PASS, ISSUE, or SKIP).
- `/tmp/S02_raid_session_log.txt` exists (even if it's manual notes).

---

_Questions? Issues with the addon not loading at all? Stop and escalate before raiding — a pre-raid Lua error that prevents the addon from loading is a blocker, not a validation observation._
