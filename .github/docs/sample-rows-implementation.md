# Multi-Type Sample Rows — Tactical Implementation Plan

**Status**: In progress  
**Branch**: `feature-module-rearch`  
**Prerequisite**: `fromPayload` already copies `isSampleRow` — verified in `LootElementBase.lua` ✅

---

## Answered Open Questions

| #   | Question                       | Answer                                                                                                                                 |
| --- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | PARTY frame row count          | One row only (PartyLoot only)                                                                                                          |
| 2   | Sample item link               | `\|cff0070dd\|Hitem:14344::::::::60:::::\|h[Large Brilliant Shard]\|h\|r` — item ID 14344, Rare quality, exists across all WoW flavors |
| 3   | `amountTextFn`                 | Omit for now; all sample quantities = 1. The visual preview is about styling, not quantity mechanics.                                  |
| 4   | `itemCountFn`                  | Provide hardcoded closures (e.g. rep rank, bag count) but still gate behind the feature's own db flag so the preview is honest.        |
| 5   | `isSampleRow` in `fromPayload` | Already handled ✅                                                                                                                     |

---

## Synthetic Data Reference

```
-- Large Brilliant Shard (item 14344, Rare/blue)
local SAMPLE_ITEM_LINK = "|cff0070dd|Hitem:14344::::::::60:::::|h[Large Brilliant Shard]|h|r"

-- Sample transmog appearance (Retail only)
local SAMPLE_TRANSMOG_LINK = "|cff9d9d9d|Htransmogappearance:285269|h[Sample Transmog]|h|r"

-- Sample currency link (Conquest, ID 2, exists since Classic)
local SAMPLE_CURRENCY_LINK = "|cff00aaff|Hcurrency:2|h[Sample Currency]|h|r"
```

Icon for item row: `GetItemIcon(14344)` (global function, all flavors). Fall back to `nil` (no icon) if it returns nil — the row still renders correctly without an icon.

---

## Phases

### Phase 1 — `LeaseRow` isSampleRow bypass (LootDisplayFrame.lua)

**Goal**: Sample rows must never be dropped by the `maxRows` cap, regardless of the user's configured row limit.

**Change 1**: Add `isSampleRow` as an optional second parameter to `LeaseRow`:

```lua
-- Before:
function LootDisplayFrameMixin:LeaseRow(key)
    local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
    if self:getNumberOfRows() >= sizingDb.maxRows then
        return nil
    end
    ...

-- After:
function LootDisplayFrameMixin:LeaseRow(key, isSampleRow)
    local sizingDb = G_RLF.DbAccessor:Sizing(self.frameType)
    if self:getNumberOfRows() >= sizingDb.maxRows and not isSampleRow then
        return nil
    end
    ...
```

**Change 2**: Update `processRow` in `LootDisplay.lua` to thread `element.isSampleRow` through:

```lua
-- Before:
row = lootFrames[frame]:LeaseRow(key)

-- After:
row = lootFrames[frame]:LeaseRow(key, element.isSampleRow)
```

**Test impact**: `LootDisplayFrame_spec.lua` — add test case: LeaseRow does not return nil for sample rows when frame is at maxRows capacity.

---

### Phase 2 — `sampleRowsVisible` flag (LootDisplay.lua)

**Goal**: Replace the fragile `GetRow("sample_preview_item")` key lookup in `RefreshSampleRowsIfShown` with a simple boolean flag.

**Change**: Add a module-level local:

```lua
local sampleRowsVisible = false
```

Set it in `ShowSampleRows` and `HideSampleRows`:

```lua
function LootDisplay:ShowSampleRows()
    sampleRowsVisible = true
    ...
end

function LootDisplay:HideSampleRows()
    sampleRowsVisible = false
    ...
end
```

Simplify `RefreshSampleRowsIfShown`:

```lua
function LootDisplay:RefreshSampleRowsIfShown()
    if sampleRowsVisible then
        self:UpdateSampleRows()
    end
end
```

No test changes needed for this phase (it's a pure simplification).

---

### Phase 3 — Replace `CreateSampleRow` with `CreateSampleRows` (LootDisplay.lua)

**Goal**: Show one representative row per enabled feature type instead of the generic placeholder.

#### 3a. PARTY frame path

Only one row: PartyLoot. Check `PartyLoot:IsEnabled()` before creating it.

```lua
if frame == G_RLF.Frames.PARTY then
    local partyModule = G_RLF.RLF:GetModule(G_RLF.FeatureModule.PartyLoot)
    if partyModule:IsEnabled() then
        -- build and show PartyLoot sample payload
    end
    return
end
```

#### 3b. MAIN frame row order and synthetic payloads

Rows are shown in order. Skip any whose module is disabled. Key naming avoids collisions with real rows.

| #   | Module       | Sample key             | Synthetic data highlights                                                                                                                                                  |
| --- | ------------ | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | ItemLoot     | `sample_item_loot`     | Large Brilliant Shard link, `quality=Rare`, `isLink=true`, `icon=GetItemIcon(14344)`, `itemCountFn` returns hardcoded bag count when `db.global.item.showBagCount` enabled |
| 2   | Money        | `sample_money_loot`    | `quantity=12345` (1g 23s 45c), `icon=DefaultIcons.MONEY`, `quality=Poor`, `textFn` calls `Money:GenerateTextElements` — or inlined equivalent                              |
| 3   | Currency     | `sample_currency`      | `isLink=true`, `textFn` returns `SAMPLE_CURRENCY_LINK`, `icon=134400` (a generic coin icon), `amountTextFn` omitted                                                        |
| 4   | Reputation   | `sample_rep`           | `textFn` returns `"+668 Stormwind"`, `r/g/b` from a golden color, `itemCountFn` returns `"Honored"` when rep level enabled                                                 |
| 5   | Experience   | `sample_xp`            | `quantity=1500`, `textFn` returns `"+1500 XP"`, `secondaryTextFn` returns level % string when secondary text enabled                                                       |
| 6   | Professions  | `sample_professions`   | `textFn` returns `"Cooking 300"`, icon=`DefaultIcons.PROFESSION`, `itemCountFn` returns `+5` skill delta when skill change shown                                           |
| 7   | TravelPoints | `sample_travel_points` | `quantity=500`, `textFn` returns `"Travel Points + 500"`, `secondaryTextFn` returns hardcoded progress when Traveler's Journey enabled                                     |
| 8   | Transmog     | `sample_transmog`      | Retail-only; `Transmog:IsEnabled()` is false on Classic so automatically skipped. Uses `SAMPLE_TRANSMOG_LINK`, `icon=DefaultIcons.TRANSMOG`, `isLink=true`                 |

#### 3c. Sample payload shell (all rows)

Every sample payload must include:

```lua
isSampleRow = true,
IsEnabled = function() return true end,  -- already gated by module check above
```

The `isSampleRow = true` on the payload is then copied to the element by `fromPayload`, which causes the row to never fade out (set in `LootDisplayRow:Reset()`).

#### 3d. Money `textFn` — avoid calling `Money:BuildPayload`

`Money:BuildPayload` guards on `quantity == 0` and reads db config for icon. For samples, build the payload inline and replicate only what the text function needs:

```lua
local quantity = 12345
local textElements = G_RLF.RLF:GetModule(G_RLF.FeatureModule.Money):GenerateTextElements(quantity)
local elementData = { key = "sample_money_loot", type = FeatureModule.Money, textElements = textElements, quantity = quantity, ... }
payload.textFn = function(existingCopper)
    return TextTemplateEngine:ProcessRowElements(1, elementData, existingCopper)
end
```

If `TextTemplateEngine` is inaccessible from `LootDisplay.lua`, fall back to a simple hardcoded string: `"1g 23s 45c"`. This is a sample row — pixel-perfect parity with real money display isn't required.

#### 3e. Update `ShowSampleRows` call site

`ShowSampleRows` calls `CreateSampleRow` (singular) today. Rename and update:

```lua
function LootDisplay:ShowSampleRows()
    sampleRowsVisible = true
    if lootFrames[G_RLF.Frames.MAIN] then
        self:CreateSampleRows(G_RLF.Frames.MAIN)
    end
    if lootFrames[G_RLF.Frames.PARTY] and G_RLF.db.global.partyLoot.separateFrame then
        self:CreateSampleRows(G_RLF.Frames.PARTY)
    end
end
```

---

### Phase 4 — Tests

**`LootDisplayFrame_spec.lua`**  
Add one new LeaseRow test case:

- "does not drop sample row when frame is at maxRows capacity" — stub `getNumberOfRows` to return `maxRows`, call `LeaseRow(key, true)`, assert result is non-nil.

**`LootDisplay_spec.lua`** (if it exists / covers this surface)

- Verify `RefreshSampleRowsIfShown` uses the flag rather than key lookup (if there are existing tests for it).

No spec needed for `CreateSampleRows` itself — the payload construction is thin plumbing from already-tested building blocks. In-game smoke/integration tests serve as verification for the full visual path.

---

## Files Changed

| File                                                                      | What changes                                                                                                                                        |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayFrame.lua`           | `LeaseRow(key, isSampleRow?)` — bypass `maxRows` for sample rows                                                                                    |
| `RPGLootFeed/LootDisplay/LootDisplay.lua`                                 | `processRow` threads `element.isSampleRow`; `sampleRowsVisible` flag; `CreateSampleRow` → `CreateSampleRows`; simplified `RefreshSampleRowsIfShown` |
| `RPGLootFeed_spec/LootDisplay/LootDisplayFrame/LootDisplayFrame_spec.lua` | One new LeaseRow test case                                                                                                                          |

No new files. No TOC/XML changes. No locale changes.

---

## Known Limitations / Future Work

- **Frame height**: With 8 rows the frame may visually overflow its `maxRows`-driven height. The `isSampleRow` bypass in `LeaseRow` means rows still render, but they may stack beyond the bounding box. A `previewMode` that temporarily expands frame height is deferred.
- **Multi-frame support**: Users being able to configure arbitrary feeds per frame is planned post-rearchitecture. At that point `CreateSampleRows` will need to be parameterized by frame feed config.
- **Money text**: If `TextTemplateEngine` is not accessible from `LootDisplay.lua`, the Money sample uses a hardcoded string `"1g 23s 45c"` as an acceptable placeholder.
