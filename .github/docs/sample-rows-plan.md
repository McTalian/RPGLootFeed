# Multi-Type Sample Rows — Feature Plan

**Status**: Not started  
**Branch target**: `feature-module-rearch` (or a follow-up branch)  
**Related**: `LootDisplay.lua`, `LootDisplayFrame.lua`, settings UI

---

## Motivation

The settings panel currently shows one generic "SamplePrimaryText" row that conveys nothing about what RPGLootFeed actually looks like in use. Users can't tell how item links, icons, secondary text, quality colouring, or quantity suffixes appear without looting something. The goal is to show one representative row per loot type — each using realistic synthetic data — so users can confidently tune visual settings.

---

## Current Implementation

`LootDisplay:CreateSampleRow(frame)` in `LootDisplay.lua` (around line 408):

- Calls `G_RLF.LootElementBase:new()` directly and fills hardcoded fields
- Shows exactly **one** row per frame (MAIN and optional PARTY)
- `isSampleRow = true` prevents history recording and bypasses the `maxRows` cap check in `LootDisplayFrame:ReleaseRow`

`LootDisplayFrame:LeaseRow()` enforces `maxRows` — if the frame is full, it returns `nil` and the row is silently dropped.

---

## Proposed Design

### 1. Replace `CreateSampleRow` with `CreateSampleRows`

Build **one payload per feature type** using synthetic data, then call `LootElementBase:fromPayload(payload):Show()` for each. This aligns with the payload contract and eliminates the last direct `LootElementBase:new()` call in non-foundational code.

Suggested row order (MAIN frame):
| # | Type | Key | Representative data |
|---|------|-----|---------------------|
| 1 | ItemLoot | `sample_item` | Synthetic item link, Epic quality, item level, icon |
| 2 | Money | `sample_money` | Gold/silver/copper breakdown |
| 3 | Currency | `sample_currency` | Valor Points or similar |
| 4 | Reputation | `sample_reputation` | Faction name, rep gain, secondary rep level |
| 5 | Experience | `sample_xp` | XP delta, secondary current level |
| 6 | Professions | `sample_profession` | Profession name, skill delta |
| 7 | TravelPoints | `sample_travelpoints` | Travel points delta, Travelers Journey secondary |
| 8 | Transmog | `sample_transmog` | Transmog link |

PARTY frame: one PartyLoot row with a synthetic unit name.

### 2. Bypass `maxRows` cap for sample rows

**Option A — Temporary maxRows override**: Before showing sample rows, store the current `maxRows`, set it to the sample count, then restore after. Simple but fragile if other code reads `maxRows` during the transition.

**Option B — `isSampleRow` bypass in `LeaseRow`**: Add the same `isSampleRow` guard to `LeaseRow` that already exists in `ReleaseRow`. The frame won't drop sample rows just because the configured maximum is low. This is the cleanest approach.

Recommendation: **Option B**. Change `LootDisplayFrame:LeaseRow()`:

```lua
-- Before:
if self:getNumberOfRows() >= sizingDb.maxRows then
    return nil
end
-- After:
if self:getNumberOfRows() >= sizingDb.maxRows and not isSampleRow then
    return nil
end
```

`isSampleRow` would need to be passed as a parameter, or checked from context. Alternatively, bump `maxRows` only for sample display via a private flag on the frame.

**Option C — second pass after current rows expire**: Show sample rows one-by-one after `HideLoot()`. Since `isSampleRow = true` rows never expire, they'll fill the frame. But this requires sequencing logic.

### 3. Number of rows shown

Show **all enabled, applicable types** automatically, not a fixed subset. On a fresh install (all features enabled), this is ~8 MAIN rows. If the user has XP disabled, skip that row. This makes the preview honest.

This requires checking `Feature:IsEnabled()` before constructing each sample payload.

For the PARTY frame, only show a PartyLoot row since that's the only type that goes there.

### 4. Synthetic data for each type

Payloads must not call live WoW APIs — all data must be hardcoded in `CreateSampleRows`. Key decisions:

- **ItemLoot**: Use a hardcoded item link string (e.g. `"|cff9d9d9d|Hitem:19:0:0:0:0:0:0:0:0|h[Sample Item]|h|r"` — a grey item) and synthetic `ItemInfo`-like table. Skip `BuildPayload` (which reads `G_RLF.db` and calls adapters) — build the payload table directly.
- **Money**: Hardcode `quantity = 12345` (1g 23s 45c) so the money formatter exercises the text path.
- **Currency**: Hardcode a link and name; skip `currencyTotal` since it's async.
- **Reputation**: Use `UnifiedFactionData`-like table with a known faction name.
- **All**: Set `isSampleRow = true` on the payload; `fromPayload` already passes it through.

### 5. `LootElementBase:fromPayload` change

`fromPayload` does not currently copy `isSampleRow` from the payload. Need to add:

```lua
element.isSampleRow = payload.isSampleRow or false
```

Verify this is already handled (check `LootElementBase.lua` around line 190).

### 6. UI / settings consideration

The settings panel trigger (`ShowSampleRows` / `HideSampleRows`) is called from `LootDisplay:UpdateSampleRows()` which is wired to config option changes. No changes needed there — `CreateSampleRows` is a drop-in replacement for `CreateSampleRow`.

**Potential issue**: With 8 rows, the frame height set by `maxRows` config might be shorter than the sample set. The `isSampleRow` bypass in `LeaseRow` handles this — rows still show, just overlap or extend past the frame boundary. A future improvement could temporarily expand frame height for the preview.

### 7. `RefreshSampleRowsIfShown`

`UpdateSize`, `UpdateRowStyles`, `UpdateEnterAnimation`, `UpdateFadeDelay` all call `RefreshSampleRowsIfShown`. This calls `HideSampleRows` + `ShowSampleRows`. The new `ShowSampleRows` → `CreateSampleRows` will rebuild all rows, so this keeps working correctly.

---

## Files to Change

| File                                                            | Change                                                                                                                                            |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `RPGLootFeed/LootDisplay/LootDisplay.lua`                       | Replace `CreateSampleRow(frame)` with `CreateSampleRows(frame)` containing one payload per active feature type; update `ShowSampleRows` call site |
| `RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayFrame.lua` | Add `isSampleRow` bypass to `LeaseRow` (Option B)                                                                                                 |
| `RPGLootFeed/Features/_Internals/LootElementBase.lua`           | Ensure `fromPayload` copies `isSampleRow` from payload                                                                                            |

No new files. No TOC/XML changes.

---

## Open Questions

1. **Should the PARTY frame show a subset or the full set?** Only PartyLoot rows go to the PARTY frame, so one row makes sense. But some users may want to see more types if they've configured everything to the party frame.
2. **Truncated/synthetic item link**: What format is safest for a sample item link that won't crash tooltip code? Test with an invalid link vs. an empty string vs. a known hardcoded retail item ID.
3. **`amountTextFn`**: ItemLoot and PartyLoot sample rows should show "x2" quantity suffix. This means `quantity` must be > 1 and `amountTextFn` must be set on the payload.
4. **`itemCountFn`**: Sample rows should show bag count / skill delta / rep level if the feature is enabled. The closure can return a hardcoded value for sample rows.
5. **Frame height expansion during preview**: Leave for a later follow-up? Or add a `previewMode` flag to the frame that temporarily ignores `maxRows` for both lease and height calculation?
