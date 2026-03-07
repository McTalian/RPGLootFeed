# Multi-Frame Loot Display — Design & Planning

## Vision

Replace the current two-frame model (a fixed Main frame plus an optional Party
frame) with a fully dynamic, user-managed collection of named Loot Frames.
Each frame is a **fully self-contained unit**: its own positioning, sizing,
styling, animation settings, and feature configurations. From the user's
perspective, configuring a frame means selecting it and seeing all of its
appearance and feature settings in one place — there is no separate "Loot
Feeds" section.

The **Main frame is always present and protected from deletion** (frame ID 1
can never be removed), but it can be renamed. All other frames are freely
created, renamed, and deleted by the user.

A migration script promotes existing global appearance and feature settings
into the new per-frame DB structure, and optionally creates a "Party" frame
when a user previously had `separateFrame = true`.

---

## Goals

- Allow users to create purpose-specific feeds (e.g. "Gear", "Currency",
  "Group", "Currencies + Money").
- Each frame is fully independent: its own appearance AND feature settings.
  The same feature (e.g. Reputation) can appear in multiple frames with
  different settings per frame.
- Simplify the options UI: top-level is Global / Frames / Blizz / About.
  All per-frame settings live under each frame's entry.
- Open the door for future features: per-frame loot history, global
  appearance defaults, addon module split.
- Maintain backward compatibility: users who never touch the new feature
  should see no change.

---

## Decisions

### Q1 — Frame identity: integer IDs ✅

Integer IDs (1, 2, 3 …) with a separate `name` display string. Frame ID 1 is
always the Main frame. New frames get `nextFrameId` then the counter
increments. **IDs are never reused after deletion** — `nextFrameId` is
monotonically increasing — to prevent stale DB references from bleeding into
a newly created frame that happens to get the same number.

---

### Q2 — Feature routing: per-frame broker ✅

~~Each frame owns a `subscribedFeatures` table (a set of feature keys).~~

**Revised**: Each frame owns a `features` table containing full per-feature
configuration (enable flag + all settings). Feature modules are pure event
detectors — they fire a unified `RLF_NEW_LOOT` message. Each
`LootDisplayFrame` has its own broker that:

1. Listens for `RLF_NEW_LOOT`
2. Checks whether the feature is enabled in **this frame's** config
3. Applies this frame's per-feature filters (quality thresholds, etc.)
4. Displays or discards the element

A feature can appear in multiple frames simultaneously with **different
settings per frame** (e.g. Frame A shows commons+, Frame B shows epics only).

There is **no global master override** for features. Each frame is its own
unit. A feature module stays active (registered for WoW events) as long as
at least one frame has that feature enabled; otherwise the module is disabled.

---

### Q3 — Maximum number of frames: 5 (initial) ✅

Hard cap of **5 frames** to start. Gather user feedback before raising or
removing the limit. Five gives power users meaningful flexibility (e.g. Main,
Party, Currencies, Reputation, Professions) without risking performance issues.

---

### Q4 — Main frame rename: allowed ✅

Frame ID 1 is the only frame that cannot be **deleted**. Renaming is
permitted — if a user wants to call it "Gear", that's fine. The code guards
deletion by checking `id == 1`, not by storing an `isProtected` flag.

---

### Q5 — Animations: per-frame ✅

`animations` moves into the per-frame DB structure alongside positioning,
sizing, and styling. Each frame is a fully isolated unit.

---

### Q6 — Deletion safety ✅

Deleting a frame destroys its widget and removes its DB entry. Feature modules
don't need to know about frames — they broadcast events; frames self-manage.
The only guard is that frame ID 1 cannot be deleted.

---

### Q7 — WoW frame names: anonymous ✅

All dynamically created frames use `nil` as the WoW frame name
(`CreateFrame("Frame", nil, UIParent, "RLF_LootDisplayFrameTemplate")`).
Internal references are held in the `lootFrames[id]` table.
`G_RLF.RLF_MainLootFrame` remains as a global alias for frame ID 1 for
backward compatibility. The former `G_RLF.RLF_PartyLootFrame` alias was
removed in Phase 6b — no new named globals are introduced.

---

### Q8 — AceConfig dynamic options: full args rebuild ✅

Use the standard `AceConfigRegistry:NotifyChange(addonName)` + full `args`
table rebuild approach whenever the frame list changes (add, delete, rename).
Closure-driven state is avoided to keep the config code maintainable.

---

### Q9 — Loot History: per-frame in a later phase ✅

The current global Loot History remains unchanged. Per-frame history is
explicitly deferred to a future phase — each frame is architecturally its
own unit, so the door is left open.

---

### Q10 — Per-frame features (not global) ✅

Feature settings (quality filters, sounds, text colors, etc.) live inside each
frame's `features` table rather than at the top-level DB. This means:

- Each frame can have different quality thresholds, sounds, text styles, etc.
- The old `db.global.item`, `db.global.partyLoot`, `db.global.currency`, etc.
  top-level keys are migrated into `frames[1].features.*` and removed.
- New frames start with **all features disabled** (clean slate). The user
  enables what they want.
- The "Loot Feeds" top-level config tab is **removed**. Feature settings live
  inside each frame's config tab.

---

### Q11 — Unified loot message channel ✅

`RLF_NEW_PARTY_LOOT` is collapsed into `RLF_NEW_LOOT`. All feature modules
fire a single message. The element's `type` field distinguishes party loot
from other types. Per-frame brokers decide what to display based on their
own config.

---

### Q12 — No global feature master override ✅

Each frame independently controls whether a feature is enabled. There is no
global kill switch. A feature module is active if **any** frame has it enabled;
otherwise the module disables itself (stops listening for WoW events).

---

### Q13 — New frame defaults: all features disabled ✅

When a user creates a new frame, all features default to **disabled**. The
appearance settings (positioning, sizing, styling, animations) are copied from
Main to give a reasonable starting point. The user then enables the features
they want on the new frame.

---

## Config UI Structure

### Top-level options

```
Root (group, childGroups = "select")
├── ⚙ Global
│   ├── Quick Actions (test mode, clear rows, loot history)
│   ├── Show '1' Quantity, Hide All Icons, Minimap Icon, etc.
│   ├── Blizzard Overrides
│   └── About
├── Main (frame 1, childGroups = "tree")
│   ├── Appearance (sub-group, childGroups = "tree")
│   │   ├── Positioning
│   │   ├── Sizing
│   │   ├── Styling
│   │   └── Animations
│   └── Loot Feeds (sub-group, childGroups = "tree")
│       ├── Item Loot (enable toggle + all settings)
│       ├── Party Loot
│       ├── Currency
│       ├── Money
│       ├── Experience
│       ├── Reputation
│       ├── Professions
│       ├── Travel Points
│       └── Transmog
├── [User Frame 2] (same structure as Main)
├── + New Frame (input + execute button)
└── Manage Frames (rename/delete controls)
```

Each frame child uses `childGroups = "tree"` so Appearance and Loot Feeds
appear as a sidebar tree. Within each sub-group, `childGroups = "tree"`
continues the tree navigation for individual sections. Tab grouping is
reserved for very limited, specific cases only.

- AceConfig's `select` childGroups does **not** support dividers in the
  dropdown. We use ordering and naming conventions (e.g. "⚙ Global") to
  visually group items.
- "Manage Frames" and "+ New Frame" are always sorted to the end.

---

## DB Schema

```lua
db.global.frames = {
    [1] = {
        name        = "Main",
        positioning = { … },   -- same shape as current db.global.positioning
        sizing      = { … },   -- same shape as current db.global.sizing
        styling     = { … },   -- same shape as current db.global.styling
        animations  = { … },   -- same shape as current db.global.animations
        features    = {
            itemLoot = {
                enabled = true,
                -- all settings from current db.global.item
                itemCountTextEnabled = true,
                itemCountTextColor = { 0.737, 0.737, 0.737, 1 },
                itemCountTextWrapChar = PARENTHESIS,
                itemQualitySettings = { … },
                itemHighlights = { … },
                auctionHouseSource = "None",
                pricesForSellableItems = "Vendor",
                vendorIconTexture = "…",
                auctionHouseIconTexture = "…",
                sounds = { … },
                textStyleOverrides = { … },
                enableIcon = true,
            },
            partyLoot = {
                enabled = false,
                -- all settings from current db.global.partyLoot
                itemQualityFilter = { … },
                hideServerNames = false,
                onlyEpicAndAboveInRaid = true,
                onlyEpicAndAboveInInstance = true,
                ignoreItemIds = {},
                enableIcon = true,
                enablePartyAvatar = true,
            },
            currency = {
                enabled = true,
                -- all settings from current db.global.currency
                currencyTotalTextEnabled = true,
                currencyTotalTextColor = { 0.737, 0.737, 0.737, 1 },
                currencyTotalTextWrapChar = PARENTHESIS,
                lowerThreshold = 0.7,
                upperThreshold = 0.9,
                lowestColor = { 1, 1, 1, 1 },
                midColor = { 1, 0.608, 0, 1 },
                upperColor = { 1, 0, 0, 1 },
                enableIcon = true,
            },
            money = {
                enabled = true,
                -- all settings from current db.global.money
                showMoneyTotal = true,
                moneyTotalColor = { 0.333, 0.333, 1.0, 1.0 },
                moneyTextWrapChar = BAR,
                abbreviateTotal = true,
                accountantMode = false,
                onlyIncome = false,
                overrideMoneyLootSound = false,
                moneyLootSound = "",
                enableIcon = true,
            },
            experience = {
                enabled = true,
                -- all settings from current db.global.xp
                experienceTextColor = { 1, 0, 1, 0.8 },
                showCurrentLevel = true,
                currentLevelColor = { 0.749, 0.737, 0.012, 1 },
                currentLevelTextWrapChar = ANGLE,
                enableIcon = true,
            },
            reputation = {
                enabled = true,
                -- all settings from current db.global.rep
                defaultRepColor = { 0.5, 0.5, 1 },
                secondaryTextAlpha = 0.7,
                enableRepLevel = true,
                repLevelColor = { 0.5, 0.5, 1, 1 },
                repLevelTextWrapChar = ANGLE,
                enableIcon = true,
            },
            profession = {
                enabled = true,
                -- all settings from current db.global.prof
                showSkillChange = true,
                skillColor = { 0.333, 0.333, 1.0, 1.0 },
                skillTextWrapChar = BRACKET,
                enableIcon = true,
            },
            travelPoints = {
                enabled = true,
                -- all settings from current db.global.travelPoints
                textColor = { 1, 0.988, 0.498, 1 },
                enableIcon = true,
            },
            transmog = {
                enabled = true,
                -- all settings from current db.global.transmog
                enableTransmogEffect = true,
                enableBlizzardTransmogSound = true,
                enableIcon = true,
            },
        },
    },
    -- Frame 2 created by migration only if partyLoot.separateFrame == true
    [2] = {
        name        = "Party",
        positioning = { … },   -- migrated from db.global.partyLoot.positioning
        sizing      = { … },   -- migrated from db.global.partyLoot.sizing
        styling     = { … },   -- migrated from db.global.partyLoot.styling
        animations  = { … },   -- copied from db.global.animations
        features    = {
            -- All features disabled except partyLoot
            partyLoot = {
                enabled = true,
                -- settings from db.global.partyLoot
            },
            itemLoot = { enabled = false, … },
            currency = { enabled = false, … },
            -- … etc
        },
    },
}
db.global.nextFrameId = 3   -- monotonically increasing; never reused
```

### What gets removed from the old schema

Migration v8 promotes the following into `db.global.frames[1].*`:

**Appearance** (→ `frames[1].positioning/sizing/styling/animations`):

- `db.global.positioning`
- `db.global.sizing`
- `db.global.styling`
- `db.global.animations`

**Feature settings** (→ `frames[1].features.*`):

- `db.global.item` → `frames[1].features.itemLoot`
- `db.global.partyLoot` → `frames[1].features.partyLoot` (minus appearance keys)
- `db.global.currency` → `frames[1].features.currency`
- `db.global.money` → `frames[1].features.money`
- `db.global.xp` → `frames[1].features.experience`
- `db.global.rep` → `frames[1].features.reputation`
- `db.global.prof` → `frames[1].features.profession`
- `db.global.travelPoints` → `frames[1].features.travelPoints`
- `db.global.transmog` → `frames[1].features.transmog`

**Party frame appearance** (→ `frames[2].*` if separate frame existed):

- `db.global.partyLoot.separateFrame`
- `db.global.partyLoot.positioning`
- `db.global.partyLoot.sizing`
- `db.global.partyLoot.styling`

Old top-level keys are preserved in SavedVariables by migration v8 (it does
not delete them) for migration compatibility. The old AceDB default
declarations were removed in Phase 6b after Phase 6a migrated all production
reads to per-frame paths. The canonical defaults now live exclusively in the
`"**"` wildcard under `defaults.global.frames` (see Phase 5c).

---

## Event & Routing Architecture

### Before (current)

```
Feature module → registers for WoW events
Feature module → fires RLF_NEW_LOOT or RLF_NEW_PARTY_LOOT
LootDisplay (central) → receives message
LootDisplay → checks subscribedFeatures per frame → routes to frame(s)
```

### After (this branch)

```
Feature module → registers for WoW events (active if ANY frame needs it)
Feature module → fires RLF_NEW_LOOT (unified channel, no separate party msg)
LootDisplayFrame broker → receives RLF_NEW_LOOT
LootDisplayFrame broker → checks frames[id].features[key].enabled
LootDisplayFrame broker → applies per-frame filters (quality, etc.)
LootDisplayFrame broker → displays row or discards
```

Each `LootDisplayFrame` is a self-contained subscriber. Adding/removing a frame
automatically adds/removes a broker. `LootDisplay` remains as the lifecycle
manager (creates/destroys frames, manages row pools) but is no longer the
central routing authority.

### Feature module lifecycle

A feature module should be **enabled** when at least one frame has that feature
enabled, and **disabled** when no frame has it enabled. This is checked:

- At startup (`OnInitialize`)
- When a frame's feature enable flag changes in the config
- When a frame is created or deleted

```lua
local function isFeatureNeededByAnyFrame(featureKey)
    for _, frameConfig in pairs(db.global.frames) do
        if frameConfig.features[featureKey]
           and frameConfig.features[featureKey].enabled then
            return true
        end
    end
    return false
end
```

---

## Implementation Status

| Phase | Description                                             | Status     |
| ----- | ------------------------------------------------------- | ---------- |
| 1     | DB schema + migration v8                                | ✅ Done    |
| 2     | Per-frame broker + unified message channel              | ✅ Done    |
| 3     | Feature configs → per-frame builders                    | ✅ Done    |
| 4a    | Config UI: Global group consolidation                   | ✅ Done    |
| 4b    | Config UI: Per-frame groups (Appearance + Loot Feeds)   | ✅ Done    |
| 4c    | Config UI: Root select + frame management controls      | ✅ Done    |
| 5     | Feature module lifecycle (enable if any frame needs it) | ✅ Done    |
| 5b    | Harden migration v8 with legacy defaults                | ✅ Done    |
| 5c    | Register `"**"` wildcard defaults for frames            | ✅ Done    |
| 5d    | Fix integration tests for multi-frame routing           | ✅ Done    |
| 6a    | Migrate reads to per-frame DB paths                     | ✅ Done    |
| 6b    | Dead code removal                                       | ✅ Done    |
| 6c    | Documentation updates                                   | 🔲 Planned |

### Prior work carried forward

The following infrastructure from the earlier iteration remains valid and will
be built upon (not rewritten):

- **`BuildPositioningArgs(id, order)`**, **`BuildSizingArgs(id, order)`**,
  **`BuildAnimationsArgs(id, order)`**, **`Styling.MakeHandler(frameId)`** —
  all already parameterized by frame ID.
- **`DbAccessor:Positioning/Sizing/Styling/Animations(frameId)`** — read
  directly from `db.global.frames[id].*` (legacy fallbacks removed in
  Phase 6b).
- **`LootDisplay:InitFrame(id)`**, **`LootDisplay:DestroyFrame(id)`** —
  already manage arbitrary frame IDs.
- **`G_RLF.Frames.MAIN = 1`** enum value.
- **Locale keys** added for frame management UI (Add Frame, Delete Frame, etc.).

---

## Proposed Phases

### Phase 1 — DB schema + migration v8 (rework) ✅

**Status**: Complete. Migration v8 copies all 9 feature configs + appearance
settings into `frames[1].*`. `DbAccessor:Feature(frameId, featureKey)` added.
Old top-level keys preserved in SavedVariables (AceDB default declarations
removed in Phase 6b).

---

### Phase 2 — Per-frame broker + unified message channel ✅

**Status**: Complete. `RLF_NEW_PARTY_LOOT` collapsed into `RLF_NEW_LOOT`.
Each `LootDisplayFrame` owns a broker via `IsFeatureEnabled()`. `LootDisplay`
retains lifecycle management only.

---

### Phase 3 — Feature configs → per-frame builders ✅

**Status**: Complete. All 9 `*Config.lua` files export `Build*Args(frameId,
order)` builder functions. Builders read/write
`db.global.frames[frameId].features.<key>`. `lootFeeds` top-level group
removed from `Features.lua`. Enable toggles call
`DbAccessor:UpdateFeatureModuleState()`. All specs updated.

---

### Phase 4a — Config UI: Global group consolidation ✅

**Status**: Complete. `general`, `blizz`, `about` consolidated into a single
`⚙ Global` top-level group (`G_RLF.options.args.global`, `childGroups =
"tab"`). `level1OptionsOrder` simplified to `global` + `frames`. General.lua,
BlizzardUI.lua, and About.lua now register into `options.args.global.args.*`.
Mock namespace and General_spec updated.

---

### Phase 4b — Config UI: Per-frame groups (Appearance + Loot Feeds) ✅

**Status**: Complete. `buildFrameGroup()` rewritten with `childGroups = "tree"`
at the frame level. Appearance sub-group (positioning, sizing, styling,
animations) and Loot Feeds sub-group (all 9 feature builders) added with
`childGroups = "tree"` within each. `featureSubscriptions` table,
`buildSubscriptionsGroup()`, and `RepairBrokenV8Migration()` removed.
`OnInitialize` simplified to call only `RebuildArgs()`. All 804 tests pass.

**Goal**: Rewrite `buildFrameGroup()` in `FramesConfig.lua` so each frame
entry has two sub-groups — Appearance and Loot Feeds — using `childGroups =
"tree"` at the frame level and `childGroups = "tab"` within each sub-group.
Replace the flat `buildSubscriptionsGroup()` (feature-enable toggles only)
with the full per-frame feature builders from Phase 3.

#### Current state (what exists)

`FramesConfig.lua` contains:

| Symbol                                   | Purpose                                                                                                             | Disposition                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `featureSubscriptions` (local table)     | Drives `buildSubscriptionsGroup` toggle list                                                                        | **Remove**                                                                       |
| `buildSubscriptionsGroup(id)`            | Inline toggle-only group                                                                                            | **Remove** — replaced by full Loot Feeds sub-group                               |
| `buildFrameGroup(id)`                    | Flat per-frame group (`childGroups = "tab"`) with positioning/sizing/styling/animations/features all as direct tabs | **Rewrite**                                                                      |
| `FramesConfig:RebuildArgs()`             | Populates `options.args.frames.args`                                                                                | **Keep logic, reuses new `buildFrameGroup`**                                     |
| `FramesConfig:RepairBrokenV8Migration()` | One-time v8 repair                                                                                                  | **Remove** — served its purpose, users on this branch have already been repaired |
| `FramesConfig:OnInitialize()`            | Calls repair then rebuild                                                                                           | **Update** — remove repair call                                                  |

#### Target structure per frame

```
frame_<id> (group, childGroups = "tree")
├── frameName (input, order 1)
├── deleteFrame (execute, order 2, hidden for id == MAIN)
├── appearance (group, childGroups = "tree", order 3)
│   ├── positioning  — G_RLF.BuildPositioningArgs(id, 1)
│   ├── sizing       — G_RLF.BuildSizingArgs(id, 2)
│   ├── styling      — G_RLF.ConfigCommon.StylingBase.CreateStylingGroup(handler, 3)
│   └── animations   — G_RLF.BuildAnimationsArgs(id, 4)
└── lootFeeds (group, childGroups = "tree", order 4)
    ├── itemLoot     — G_RLF.BuildItemLootArgs(id, 1)
    ├── partyLoot    — G_RLF.BuildPartyLootArgs(id, 2)
    ├── currency     — G_RLF.BuildCurrencyArgs(id, 3)
    ├── money        — G_RLF.BuildMoneyArgs(id, 4)
    ├── experience   — G_RLF.BuildExperienceArgs(id, 5)
    ├── reputation   — G_RLF.BuildReputationArgs(id, 6)
    ├── profession   — G_RLF.BuildProfessionArgs(id, 7)
    ├── travelPoints — G_RLF.BuildTravelPointsArgs(id, 8)
    └── transmog     — G_RLF.BuildTransmogArgs(id, 9)
```

#### What to implement

1. **Delete `featureSubscriptions` table and `buildSubscriptionsGroup(id)`**.

2. **Rewrite `buildFrameGroup(id)`**:

   - Change `childGroups` from `"tab"` to `"tree"`.
   - Keep `frameName` input (order 1) and `deleteFrame` execute (order 2).
   - Create `appearance` sub-group (order 3, `childGroups = "tree"`) containing
     the 4 appearance builders that already exist.
   - Create `lootFeeds` sub-group (order 4, `childGroups = "tree"`) calling all
     9 `Build*Args(id, order)` functions.
   - Use existing locale keys: `L["Appearance"]`, `L["AppearanceDesc"]`,
     `L["Loot Feeds"]`, `L["LootFeedsDesc"]`.

3. **Remove `RepairBrokenV8Migration()`** and its call from `OnInitialize()`.

4. **Leave `RebuildArgs()` intact** — it already loops over frame IDs and
   calls `buildFrameGroup(id)`. No changes needed there.

#### Existing builder references

All appearance builders are already called in the current `buildFrameGroup`:

```lua
positioning = G_RLF.BuildPositioningArgs(id, 3)
sizing      = G_RLF.BuildSizingArgs(id, 4)
styling     = G_RLF.ConfigCommon.StylingBase.CreateStylingGroup(stylingHandler, 5)
animations  = G_RLF.BuildAnimationsArgs(id, 6)
```

All 9 feature builders were created in Phase 3:

```lua
G_RLF.BuildItemLootArgs(frameId, order)
G_RLF.BuildPartyLootArgs(frameId, order)
G_RLF.BuildCurrencyArgs(frameId, order)
G_RLF.BuildMoneyArgs(frameId, order)
G_RLF.BuildExperienceArgs(frameId, order)
G_RLF.BuildReputationArgs(frameId, order)
G_RLF.BuildProfessionArgs(frameId, order)
G_RLF.BuildTravelPointsArgs(frameId, order)
G_RLF.BuildTransmogArgs(frameId, order)
```

#### Files to modify

- `config/FramesConfig.lua` — rewrite `buildFrameGroup`, remove dead code
- `RPGLootFeed_spec/config/FramesConfig_spec.lua` — if it exists, update
  assertions for new tree/tab structure

#### Testing checklist

- [ ] Each frame group uses `childGroups = "tree"`
- [ ] Appearance sub-group contains all 4 appearance tabs
- [ ] Loot Feeds sub-group contains all 9 feature tabs
- [ ] `buildSubscriptionsGroup` is gone
- [ ] `featureSubscriptions` table is gone
- [ ] `RepairBrokenV8Migration` is gone
- [ ] `make test` passes (804+ tests)

#### Dead locale keys (deferred to Phase 6b)

The following locale keys become unused after this phase but should be removed
in Phase 6b alongside other dead code cleanup:

- `L["Subscribed Features"]`, `L["SubscribedFeaturesDesc"]`
- `L["ItemLootSubscribeDesc"]`, `L["PartyLootSubscribeDesc"]`,
  `L["CurrencySubscribeDesc"]`, `L["MoneySubscribeDesc"]`,
  `L["ExperienceSubscribeDesc"]`, `L["ReputationSubscribeDesc"]`,
  `L["ProfessionSubscribeDesc"]`, `L["TravelPointsSubscribeDesc"]`,
  `L["TransmogSubscribeDesc"]`

---

### Phase 4c — Config UI: Root select + frame management controls ✅

**Status**: Complete. Root `G_RLF.options` set to `childGroups = "select"`.
`options.args.frames` wrapper group removed — per-frame groups (`frame_<id>`)
are now direct children of `options.args` with `order = 10 + id`. `frameName`
and `deleteFrame` removed from inside each frame group. Frame management moved
to two root-level groups: `newFrame` (order 98, name input + add button) and
`manageFrames` (order 99, per-frame rename/delete controls). Frame 1 shows
rename only; others show rename + delete. `level1OptionsOrder` table removed.
Mock namespace updated to remove `frames` wrapper and `level1OptionsOrder`.
All 804 tests pass.

**Goal**: Switch the root options group to `childGroups = "select"` (dropdown
navigation). Move frame creation/deletion out of the `frames` sub-group and
into dedicated top-level entries ("+ New Frame", "Manage Frames"). The `frames`
sub-group wrapper is removed — per-frame groups become direct root-level
children.

#### What to implement

- `ConfigOptions.lua`: Set root `G_RLF.options` to `childGroups = "select"`.
  Remove the `options.args.frames` wrapper group — `FramesConfig:RebuildArgs`
  now populates `options.args` directly with `frame_<id>` entries.
- `FramesConfig.lua`: Move "New Frame Name" input + "Add Frame" button into a
  `newFrame` top-level group (order = 98). Move rename/delete controls into a
  `manageFrames` top-level group (order = 99). Frame ID 1 shows rename only;
  others show rename + delete.
- Remove `frameName` and `deleteFrame` from inside each `frame_<id>` group
  (they now live in Manage Frames).
- `level1OptionsOrder` is already simplified to `global` + `frames` (Phase 4a).
  Either remove the table entirely or repurpose it for the new entries.

#### Current state details (from Phase 4a/4b)

`ConfigOptions.lua`:

- `G_RLF.options` root has no `childGroups` set (implicit `"tab"`).
- `options.args.global` (order 1, `childGroups = "tab"`) — keep as-is.
- `options.args.frames` (order 5, `childGroups = "select"`) — this wrapper
  group goes away; its children become root-level `options.args.frame_<id>`.
- `level1OptionsOrder` table is consumed only by
  `options.args.global.order` and `options.args.frames.order`. Once `frames`
  is gone, the table can be removed and static order values used instead.

`FramesConfig.lua` (after Phase 4b):

- `RebuildArgs()` currently writes to `G_RLF.options.args.frames.args`.
  Must change to `G_RLF.options.args` directly, being careful to preserve
  `global` and any other root-level entries (don't wipe the whole table).
- `newFrameName` + `addFrame` controls currently live inside
  `framesTab.args` with fractional orders (0.1, 0.2). Must move to a
  `newFrame` root-level group (order 98).
- `frameName` + `deleteFrame` currently live inside each `frame_<id>` group.
  Must move to a `manageFrames` root-level group (order 99) which
  dynamically builds per-frame rename/delete controls.
- Frame ordering: frame groups use `order = id` (integers 1–5). These sit
  between `global` (order 1) and `newFrame`/`manageFrames` (98/99). To
  avoid collision with `global`'s order 1, frame orders should be offset
  (e.g. `order = 10 + id`).

Mock namespace (`addonNamespace.lua`):

- Currently sets up `ns.options.args.frames = { args = {} }`. Must be
  updated to remove the `frames` wrapper — tests populate `options.args`
  directly with `frame_<id>` entries.
- `ns.level1OptionsOrder` can be removed if the table is deleted.

#### Locale keys needed

Existing keys that can be reused:

- `L["New Frame Name"]`, `L["NewFrameNameDesc"]`, `L["Add Frame"]`,
  `L["AddFrameDesc"]`, `L["Frame Name"]`, `L["FrameNameDesc"]`,
  `L["Delete Frame"]`, `L["DeleteFrameConfirm"]`

New keys needed:

- `L["+ New Frame"]` / `L["NewFrameGroupDesc"]` — for the `newFrame`
  root-level group name/desc
- `L["Manage Frames"]` / `L["ManageFramesDesc"]` — for the `manageFrames`
  root-level group name/desc

#### Manage Frames dynamic content

The `manageFrames` group should dynamically build sub-groups per frame:

- Frame 1 (Main): rename input only (no delete)
- Frame 2+: rename input + delete button
- Must rebuild when frames are added or deleted (call from `RebuildArgs`)

#### Files

- `config/ConfigOptions.lua` (root restructure, remove `frames` wrapper)
- `config/FramesConfig.lua` (move frame management args to root level)
- `RPGLootFeed_spec/_mocks/Internal/addonNamespace.lua` (remove `frames`
  wrapper from mock)
- `RPGLootFeed_spec/config/ConfigOptions_spec.lua` (update if affected)
- `RPGLootFeed/locale/enUS.lua` (add new locale keys)
- Other locale files (add commented-out stubs for new keys)

#### Testing checklist

- [ ] Root options use `childGroups = "select"`
- [ ] `options.args.frames` wrapper group is gone
- [ ] Per-frame groups are direct children of `options.args`
- [ ] "New Frame" group appears at order 98
- [ ] "Manage Frames" group appears at order 99
- [ ] `frameName` and `deleteFrame` no longer inside `frame_<id>` groups
- [ ] Frame 1 cannot be deleted from Manage Frames
- [ ] `level1OptionsOrder` removed or repurposed
- [ ] Mock namespace updated
- [ ] `make test` passes

---

### Phase 5 — Feature module lifecycle ✅

**Status**: Complete. All 9 feature modules' `OnInitialize` methods now use
`DbAccessor:IsFeatureNeededByAnyFrame(featureKey)` instead of reading the old
`db.global.<key>.enabled` flag. `UpdateFeatureModuleState` (already called by
all 9 config builders from Phase 3) correctly enables/disables modules at
runtime when per-frame feature toggles change. The remaining
`db.global.partyLoot.enabled` guard in `PartyLoot:CHAT_MSG_LOOT` was also
updated. All specs updated with `DbAccessor` mocks. 804 tests pass.

---

### Phase 5b — Harden migration v8 with legacy defaults ✅

**Status**: Complete. `LEGACY_DEFAULTS` table added to `v8.lua` mirroring
all old AceDB defaults. All copy helpers use `pick()` with per-key fallbacks.
Migration produces correct output even when old `defaults.global.*`
declarations are absent. Tests cover nil-source and sparse-source scenarios.

**Goal**: Make migration v8 fully self-contained so it produces correct
output regardless of whether the old AceDB defaults are still registered.
Users may jump from any prior version (e.g. v6 → v10), meaning the old
`defaults.global.item`, `defaults.global.positioning`, etc. may already be
gone by the time v8 runs. Without those defaults, AceDB's `__index` returns
`nil` and the migration silently writes `nil` for every field.

#### What to implement

1. Add a local `LEGACY_DEFAULTS` table inside `v8.lua` that mirrors the old
   AceDB defaults for all 9 feature configs + 4 appearance configs.

2. Update all `copy*Feature` and `copy*` helpers to use `pick()` with
   per-key fallbacks from `LEGACY_DEFAULTS`, so every field resolves to
   either the user's saved value or the historical default.

3. The `source = source or {}` guards remain for when the entire old table
   is absent, but `pick(source.field, LEGACY_DEFAULTS.key.field)` handles
   individual nil keys within a present-but-sparse table.

#### Files

- `config/Migrations/v8.lua` (add `LEGACY_DEFAULTS`, update copy helpers)
- `RPGLootFeed_spec/config/Migrations/v8_spec.lua` (add tests for nil-source
  and sparse-source scenarios)

---

### Phase 5c — Register `"**"` wildcard defaults for frames ✅

**Status**: Complete. The `"**"` wildcard is registered under
`defaults.global.frames` in `ConfigOptions.lua` with the full canonical frame
schema (positioning, sizing, styling, animations, and all 9 feature
sub-tables). All feature `enabled` flags default to `false` per Q13. Values
match `LEGACY_DEFAULTS` in v8.lua. 21 tests added in
`ConfigOptions_spec.lua` covering structure, values, and the Q13 contract.
836 tests pass. In-game validation confirmed proxy depth works through 5
levels of nesting — no nested `"**"` keys needed.

**Migration v8 interaction fix**: The `"**"` wildcard caused migration v8's
`if global.frames[1] == nil` guard to fail — AceDB's proxy returns a table
for any key under `"**"`, so `frames[1]` was never nil even when no data had
been written. Fixed by checking `f1 == nil or f1.name == ""` instead, since
the wildcard default for `name` is `""` and migration v8 writes `"Main"`.
Same fix applied to the `frames[2]` guard. Also fixed two stale DB path
references in `IntegrationTest.lua` (`db.global.partyLoot.enabled` and
`db.global.transmog.enabled` → module `IsEnabled()` checks).

**Goal**: Register AceDB `"**"` wildcard defaults under
`defaults.global.frames` so that every frame (including Main) automatically
inherits default values for any key not explicitly saved.

AceDB's `"**"` key provides inherited defaults for _all_ sibling keys in the
same table — unlike `"*"`, which only applies to keys not explicitly defined
in the defaults table. `"**"` means that even frame 1 (explicitly created by
migration v8) will inherit defaults for any _new_ config keys added in later
versions, without requiring a migration.

This does **not** replace `LEGACY_DEFAULTS` in v8.lua. The migration is a
sealed, self-contained one-shot transform that must produce correct output
independently. The `"**"` defaults serve the _runtime_ code path — ensuring
that `db.global.frames[N]` always resolves to sensible values during normal
addon operation.

#### Key decisions & open questions

- **`"**"`vs`"_"`**: We chose `"\*\*"`because frame 1 is explicitly written
by migration v8, and`"_"`would not provide fallback defaults for
explicitly-defined keys. `"\*\*"` inherits into all siblings, so even
  frame 1 gets defaults for new keys added in future versions.

- **AceDB proxy depth**: AceDB tutorial examples only show one level of
  nesting under `"*"`/`"**"` (e.g. `modules.moduleA.enabled`). Our frame
  schema is deeper: `frames[1].positioning.anchorPoint` (3 levels under
  `"**"`). We need to verify that AceDB creates proxy tables recursively
  through `"**"`. If it doesn't, we may need nested `"**"` at multiple
  levels, or fall back to a different approach.

- **AceDB set-then-reset behavior**: When a user changes a value and then
  changes it back to the default, does AceDB remove the explicit write from
  SavedVariables (reverting to `__index`)? Or does it persist the
  now-redundant explicit value? This affects whether future default changes
  propagate to "reset" users. This is lower priority but worth answering
  while we're testing.

- **Default-change migration rule**: AceDB's `__index` means unsaved keys
  automatically track code-side default changes — no migration needed.
  Migrations are only required when changing defaults for data that was
  **explicitly written** to SavedVariables (e.g. by migration v8).
  See `config.instructions.md` for the full rule.

#### What to implement

1. In `ConfigOptions.lua`, replace the empty `frames = {}` default with a
   `"**"` wildcard that mirrors the canonical frame schema (positioning,
   sizing, styling, animations, features with all 9 sub-tables). The
   default values should match `LEGACY_DEFAULTS` in v8.lua exactly.

2. Verify proxy depth behavior in-game using the WowLua scripts below.

3. When a new config key is added to the frame schema in the future, add it
   to the `"**"` defaults — existing frames will automatically inherit it
   with no migration needed (unless the new key needs a non-default value
   for existing users).

#### In-game validation (WowLua scripts)

Run these **after** the addon loads and migration v8 has completed.

**Script 1 — Verify `"**"` proxy depth (existing frame)\*\*

```lua
-- Does frame 1 (explicitly written by v8) still resolve defaults
-- via "**" for keys that were NOT explicitly saved?
-- After running this, add a NEW key to the "**" defaults,
-- reload, and re-run to see if it appears.

local db = G_RLF.db.global
local f1 = db.frames[1]
print("=== Frame 1 (migration-created) ===")
-- Level 1 (direct key)
print("name:", f1.name)                          -- "Main" (explicit)
-- Level 2 (one sub-table)
print("positioning.anchorPoint:", f1.positioning and f1.positioning.anchorPoint)
print("sizing.feedWidth:", f1.sizing and f1.sizing.feedWidth)
print("styling.growUp:", f1.styling and f1.styling.growUp)
-- Level 3 (two sub-tables)
print("animations.enter.type:", f1.animations and f1.animations.enter and f1.animations.enter.type)
print("features.itemLoot.enabled:", f1.features and f1.features.itemLoot and f1.features.itemLoot.enabled)
-- Level 4 (three sub-tables — critical depth test)
print("animations.enter.slide.direction:", f1.animations and f1.animations.enter and f1.animations.enter.slide and f1.animations.enter.slide.direction)
print("styling.backdropInsets.left:", f1.styling and f1.styling.backdropInsets and f1.styling.backdropInsets.left)
print("features.itemLoot.sounds.mounts.enabled:", f1.features and f1.features.itemLoot and f1.features.itemLoot.sounds and f1.features.itemLoot.sounds.mounts and f1.features.itemLoot.sounds.mounts.enabled)
print("features.itemLoot.itemQualitySettings[0].enabled:", f1.features and f1.features.itemLoot and f1.features.itemLoot.itemQualitySettings and f1.features.itemLoot.itemQualitySettings[0] and f1.features.itemLoot.itemQualitySettings[0].enabled)
-- Level 5 (four sub-tables — deepest path in schema)
print("features.itemLoot.textStyleOverrides.quest.color[1]:", f1.features and f1.features.itemLoot and f1.features.itemLoot.textStyleOverrides and f1.features.itemLoot.textStyleOverrides.quest and f1.features.itemLoot.textStyleOverrides.quest.color and f1.features.itemLoot.textStyleOverrides.quest.color[1])
```

**Script 2 — Verify `"**"` on a non-existent frame ID\*\*

```lua
-- Access a frame ID that was never explicitly created.
-- If "**" works, all keys should resolve to the wildcard defaults.
-- If not, this will return nil/error.

local db = G_RLF.db.global
local f99 = db.frames[99]
print("=== Frame 99 (never created) ===")
print("type:", type(f99))                        -- should be "table" if ** works
if type(f99) == "table" then
    -- Level 1
    print("name:", f99.name)                     -- "" (wildcard default)
    -- Level 2
    print("positioning.anchorPoint:", f99.positioning and f99.positioning.anchorPoint)
    print("sizing.feedWidth:", f99.sizing and f99.sizing.feedWidth)
    -- Level 3
    print("features.itemLoot.enabled:", f99.features and f99.features.itemLoot and f99.features.itemLoot.enabled)
    print("animations.enter.type:", f99.animations and f99.animations.enter and f99.animations.enter.type)
    -- Level 4 (critical depth test)
    print("animations.enter.slide.direction:", f99.animations and f99.animations.enter and f99.animations.enter.slide and f99.animations.enter.slide.direction)
    print("styling.backdropInsets.left:", f99.styling and f99.styling.backdropInsets and f99.styling.backdropInsets.left)
    print("features.itemLoot.sounds.mounts.enabled:", f99.features and f99.features.itemLoot and f99.features.itemLoot.sounds and f99.features.itemLoot.sounds.mounts and f99.features.itemLoot.sounds.mounts.enabled)
    print("features.itemLoot.itemQualitySettings[0].enabled:", f99.features and f99.features.itemLoot and f99.features.itemLoot.itemQualitySettings and f99.features.itemLoot.itemQualitySettings[0] and f99.features.itemLoot.itemQualitySettings[0].enabled)
    -- Level 5 (deepest path in schema)
    print("features.itemLoot.textStyleOverrides.quest.color[1]:", f99.features and f99.features.itemLoot and f99.features.itemLoot.textStyleOverrides and f99.features.itemLoot.textStyleOverrides.quest and f99.features.itemLoot.textStyleOverrides.quest.color and f99.features.itemLoot.textStyleOverrides.quest.color[1])
else
    print("** defaults did NOT create a proxy for frame 99")
end
```

**Script 3 — Verify new key inheritance (add after reload)**

```lua
-- BEFORE running this, add a test key to the "**" defaults:
--   defaults.global.frames["**"]._testKey = "hello"
-- Then /reload and run this script.

local db = G_RLF.db.global
print("=== New key inheritance test ===")
print("frame 1 _testKey:", db.frames[1]._testKey)  -- "hello" if ** inherits
print("frame 99 _testKey:", db.frames[99]._testKey) -- "hello" if ** works
-- After verifying, REMOVE _testKey from defaults.
```

**Script 4 — Set-then-reset behavior**

```lua
-- Does AceDB remove explicit writes when value matches the default?

local db = G_RLF.db.global
local f1 = db.frames[1]

-- Read the default
local original = f1.positioning.anchorPoint
print("original anchorPoint:", original)

-- Write a different value
f1.positioning.anchorPoint = "TOPRIGHT"
print("after set:", f1.positioning.anchorPoint)

-- Reset to what the default would be
f1.positioning.anchorPoint = "BOTTOMLEFT"
print("after reset to default:", f1.positioning.anchorPoint)

-- Now /reload and check:
--   If SavedVariables still has anchorPoint = "BOTTOMLEFT" → explicit write persists
--   If SavedVariables does NOT have anchorPoint → AceDB cleaned it up
-- Check: RPGLootFeedDB.global.frames["1"].positioning.anchorPoint in SavedVariables
print("Reload and check SavedVariables to see if the explicit write persists")
```

#### Files

- `config/ConfigOptions.lua` (register `"**"` defaults under `frames`)
- `RPGLootFeed_spec/config/ConfigOptions_spec.lua` or integration test
  (verify inheritance behavior)
- Remove `_testKey` after validation

#### Decision tree after validation

- **If `"**"`proxies deeply and frame 99 resolves nested defaults**:
Proceed as planned. The`"\*\*"` defaults become the runtime safety net.
- **If `"**"`only proxies one level (e.g.`frames[99]`is a table but`frames[99].positioning`is nil)**:  Use nested`"**"`at each sub-level
(e.g.`frames["**"].positioning`also needs a`"\*\*"` or explicit keys).
- **If `"**"`doesn't interact well with explicitly-written tables**:
Fall back to registering explicit defaults for known frame IDs at startup
(e.g. in`FramesConfig:OnInitialize`, loop over existing frame IDs and
  ensure defaults are seeded).

---

### Phase 6a — Migrate reads to per-frame DB paths

**Status**: Complete. All production code now reads from per-frame DB paths
via `DbAccessor`. Key changes:

- **Row mixins** (RowAnimationMixin, RowTextMixin, RowUnitPortraitMixin,
  RowScriptedEffectsMixin, LootDisplayRow) — migrated to use
  `DbAccessor:Animations(self.frameType)` and
  `DbAccessor:Feature(self.frameType, featureKey)`.
- **Feature modules** (ItemLoot, PartyLoot, Currency, Money, Experience,
  Reputation, Professions, TravelPoints, Transmog) — migrated to use
  `DbAccessor:AnyFeatureConfig(featureKey)`, a transitional helper that
  returns the config from the first frame with the feature enabled
  (Approach B from below). This maintains exact behavior since migration v8
  copied identical values to all frames.
- **HistoryService** — now iterates all frames via
  `LootDisplay:GetAllFrames()` instead of hardcoding Main + Party.
- **SampleRows** — now reads per-frame feature config via
  `DbAccessor:Feature(frame, featureKey)`.
- **LootElementBase** — uses `DbAccessor:Animations(Frames.MAIN)` for
  default element showForSeconds.
- **Core.lua** — money sound read migrated to `AnyFeatureConfig("money")`.
- **config/General.lua** — secondary row text toggle reads/writes via
  `DbAccessor:Styling()` and iterates all frames on set.
- **DbAccessor** — removed legacy PARTY fallback paths from `Sizing()`,
  `Positioning()`, and `Styling()`. Added `AnyFeatureConfig()` helper.
  Added `GetAllFrames()` to LootDisplay.
- **All 836 unit tests pass** (0 failures, 0 errors).
- Remaining: in-game integration test validation (deferred to manual QA).

**Goal**: All production code that currently reads old top-level DB keys
(`db.global.item`, `db.global.partyLoot`, `db.global.animations`, etc.)
must be migrated to read from the per-frame paths
(`db.global.frames[id].features.*`, `db.global.frames[id].animations`, etc.)
via `DbAccessor`. This is a prerequisite for removing the old AceDB default
declarations in Phase 6b — removing defaults before migrating reads would
cause nil dereferences.

#### Why this must come first

The old `G_RLF.defaults.global.item = { … }` declarations in each config
file cause AceDB to create proxy tables at `db.global.item.*` that serve as
\_\_index fallbacks. Production code in Features/, LootDisplay/, and utils/
still reads from these old paths. If we remove the defaults (Phase 6b)
before migrating the reads, every access becomes nil.

#### Scope: HistoryService

`HistoryService` hardcodes `G_RLF.RLF_MainLootFrame` and
`G_RLF.RLF_PartyLootFrame`. It should instead iterate all live frames via
`LootDisplay:GetFrame(id)` over `db.global.frames`. This makes it
frame-count-agnostic and eliminates the last meaningful consumer of
`RLF_PartyLootFrame`.

#### Scope: Feature modules (reads of `db.global.<featureKey>`)

Each feature module reads its config directly from the old top-level key.
These must be migrated to read via `DbAccessor:Feature(frameId, featureKey)`
or equivalent. The challenge is that feature modules are frame-agnostic —
they don't know which frame they're building a payload for. Two approaches:

**Approach A — Read at row render time (preferred for per-frame settings)**:
Move feature-specific config reads into the row rendering layer (which knows
its `frameType`). The payload carries raw data; the row applies per-frame
formatting.

**Approach B — Read from any-frame consensus**: For settings where per-frame
variation doesn't make sense at the payload level (e.g. `enableIcon` — a
feature either includes an icon or doesn't), read from "any frame that has
this feature enabled" as a single source of truth. This is a transitional
pattern until the payload/render split is cleaner.

**Approach C — Keep global fallback for now**: For settings that every frame
shares identically (because migration v8 copied the same value to all frames
and the config UI doesn't support per-frame variation yet), continue reading
from the old top-level key temporarily. Mark these with `-- TODO(6b): migrate`
comments. This defers their migration to Phase 6b when the old defaults are
removed.

The exact approach per setting will be decided during implementation.

#### Feature module reads to migrate

| File                                        | Line(s)                                            | Old path                 | Setting(s)                                                                                                                                      |
| ------------------------------------------- | -------------------------------------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `Features/ItemLoot/ItemLoot.lua`            | 135, 160, 192, 206-207, 212, 254-255, 291-294, 336 | `db.global.item`         | itemQualitySettings, enableIcon, itemHighlights, textStyleOverrides, sounds, vendorIconTexture, auctionHouseIconTexture, pricesForSellableItems |
| `Features/ItemLoot/AuctionIntegrations.lua` | 56, 73                                             | `db.global.item`         | auctionHouseSource                                                                                                                              |
| `Features/PartyLoot/PartyLoot.lua`          | 68, 96, 180, 185, 201, 205                         | `db.global.partyLoot`    | enableIcon, hideServerNames, onlyEpicAndAboveInRaid, onlyEpicAndAboveInInstance, itemQualityFilter, ignoreItemIds                               |
| `Features/Currency/Currency.lua`            | 92, 119, 141                                       | `db.global.currency`     | enableIcon, currencyDb (total text, colors)                                                                                                     |
| `Features/Money.lua`                        | 39-49, 65, 70, 78, 101, 152-153, 229               | `db.global.money`        | overrideMoneyLootSound, moneyLootSound, accountantMode, showMoneyTotal, abbreviateTotal, enableIcon, onlyIncome                                 |
| `Features/Experience.lua`                   | 79, 106, 111-112, 131                              | `db.global.xp`           | enableIcon, showCurrentLevel, currentLevelColor, currentLevelTextWrapChar, experienceTextColor                                                  |
| `Features/Reputation/Reputation.lua`        | 98, 113, 127, 132-133, 142                         | `db.global.rep`          | defaultRepColor, enableIcon, enableRepLevel, repLevelColor, repLevelTextWrapChar, secondaryTextAlpha                                            |
| `Features/Professions.lua`                  | 55, 64, 80                                         | `db.global.prof`         | skillColor, enableIcon, profDb (showSkillChange, skillTextWrapChar)                                                                             |
| `Features/TravelPoints.lua`                 | 49, 52                                             | `db.global.travelPoints` | textColor, enableIcon                                                                                                                           |
| `Features/Transmog.lua`                     | 59                                                 | `db.global.transmog`     | enableIcon                                                                                                                                      |

#### Display/animation reads to migrate

| File                                          | Line(s)                                   | Old path                                                            | Setting(s)                                        |
| --------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------- |
| `LootDisplay/SampleRows.lua`                  | 30, 81, 129, 158, 204, 248, 294, 332, 368 | `db.global.{item,money,currency,rep,xp,prof,travelPoints,transmog}` | All feature settings for sample row rendering     |
| `LootDisplay/.../RowAnimationMixin.lua`       | 179, 243, 326, 516-517, 614, 659          | `db.global.animations`                                              | enter/exit/hover/update animation settings        |
| `LootDisplay/.../LootDisplayRow.lua`          | 73, 326                                   | `db.global.animations`                                              | fadeOutDelay, disableHighlight                    |
| `LootDisplay/.../RowTextMixin.lua`            | 270, 284, 420, 481                        | `db.global.partyLoot`                                               | enablePartyAvatar                                 |
| `LootDisplay/.../RowUnitPortraitMixin.lua`    | 49                                        | `db.global.partyLoot`                                               | enablePartyAvatar                                 |
| `LootDisplay/.../RowScriptedEffectsMixin.lua` | 87, 91                                    | `db.global.transmog`                                                | enableBlizzardTransmogSound, enableTransmogEffect |
| `Features/_Internals/LootElementBase.lua`     | 61                                        | `db.global.animations`                                              | exit.fadeOutDelay                                 |
| `config/General.lua`                          | 185, 188                                  | `db.global.styling`                                                 | enabledSecondaryRowText                           |
| `Core.lua`                                    | 203                                       | `db.global.money`                                                   | overrideMoneyLootSound                            |

#### HistoryService migration

| File                       | Line(s)      | Old reference                             | New approach                                                      |
| -------------------------- | ------------ | ----------------------------------------- | ----------------------------------------------------------------- |
| `utils/HistoryService.lua` | 23-35, 40-48 | `RLF_MainLootFrame`, `RLF_PartyLootFrame` | Iterate all frames via `LootDisplay:GetAllFrames()` or equivalent |

#### DbAccessor fallback removal

| File                     | Line(s) | Fallback                                            | New behavior                                                               |
| ------------------------ | ------- | --------------------------------------------------- | -------------------------------------------------------------------------- |
| `config/DbAccessors.lua` | 17-19   | `Sizing()` → `db.global.partyLoot.sizing`           | Remove PARTY fallback; keep `db.global.sizing` fallback for nil frame      |
| `config/DbAccessors.lua` | 31-33   | `Positioning()` → `db.global.partyLoot.positioning` | Remove PARTY fallback; keep `db.global.positioning` fallback for nil frame |
| `config/DbAccessors.lua` | 45-47   | `Styling()` → `db.global.partyLoot.styling`         | Remove PARTY fallback; keep `db.global.styling` fallback for nil frame     |
| `config/DbAccessors.lua` | 58-60   | `Animations()` → `db.global.animations`             | Keep nil-frame fallback until all callers pass frame ID                    |

#### Key challenge: frame context propagation

Many of these reads happen inside functions that don't currently receive a
frame ID. The row mixins (`RowAnimationMixin`, `RowTextMixin`, etc.) have
access to `self.frameType`, so they can resolve per-frame settings directly.
Feature module `BuildPayload()` functions don't know the frame — they build
a frame-agnostic element. The payload → render boundary is where per-frame
settings should be applied.

This means some reads naturally migrate to the row layer (animations,
avatars, scripted effects) while others stay in the feature module reading
from a consensus or transitional path.

#### Files

- `utils/HistoryService.lua`
- `LootDisplay/LootDisplay.lua` (add `GetAllFrames()` or iterator)
- `LootDisplay/SampleRows.lua`
- `LootDisplay/LootDisplayFrame/LootDisplayRow/RowAnimationMixin.lua`
- `LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow.lua`
- `LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua`
- `LootDisplay/LootDisplayFrame/LootDisplayRow/RowUnitPortraitMixin.lua`
- `LootDisplay/LootDisplayFrame/LootDisplayRow/RowScriptedEffectsMixin.lua`
- `Features/_Internals/LootElementBase.lua`
- `Features/ItemLoot/ItemLoot.lua`
- `Features/ItemLoot/AuctionIntegrations.lua`
- `Features/PartyLoot/PartyLoot.lua`
- `Features/Currency/Currency.lua`
- `Features/Money.lua`
- `Features/Experience.lua`
- `Features/Reputation/Reputation.lua`
- `Features/Professions.lua`
- `Features/TravelPoints.lua`
- `Features/Transmog.lua`
- `config/General.lua`
- `config/DbAccessors.lua`
- `Core.lua`
- Spec files for all affected modules

#### Testing checklist

- [x] All feature modules read from per-frame paths (no `db.global.<featureKey>` reads)
- [x] RowAnimationMixin reads from `DbAccessor:Animations(self.frameType)`
- [x] HistoryService iterates all living frames (not hardcoded Main + Party)
- [x] SampleRows reads from per-frame feature config
- [x] DbAccessor PARTY fallback paths removed
- [x] `make test` passes (836/836)
- [ ] In-game integration tests pass (20/20)

---

### Phase 6b — Dead code removal ✅

**Status**: Complete. All legacy code removed. 825 tests pass (0 failures,
0 errors). Grep verification confirms zero remaining references to removed
symbols in production and test code.

**Goal**: Remove legacy code that is no longer referenced after Phase 6a
migrates all reads to per-frame paths.

**Prerequisite**: Phase 6a must be complete — all production reads must use
per-frame DB paths before the old defaults and fallbacks can be removed.

#### What was removed

- `G_RLF.Frames.PARTY` constant from `utils/Enums.lua`.
- `LootDisplay:CreatePartyFrame()` / `LootDisplay:DestroyPartyFrame()`
  (~160 lines of frame creation/teardown/routing logic).
- `G_RLF.RLF_PartyLootFrame` global alias (all assignment and read sites).
- `frameType == G_RLF.Frames.PARTY` check in `LootDisplayFrame.lua`
  (`CreateHistoryFrame` title logic — now uses frame name from DB).
- Old AceDB default declarations (`defaults.global.item`,
  `defaults.global.partyLoot`, `defaults.global.currency`,
  `defaults.global.money`, `defaults.global.xp`, `defaults.global.rep`,
  `defaults.global.prof`, `defaults.global.travelPoints`,
  `defaults.global.transmog`, `defaults.global.positioning`,
  `defaults.global.sizing`, `defaults.global.styling`,
  `defaults.global.animations`) from their respective config files.
- Legacy fallback paths in `DbAccessor` (`Sizing`, `Positioning`,
  `Styling`, `Animations`) — accessors now directly index
  `db.global.frames[id].*` with no nil-frame fallback.
- Dead locale keys from Phase 4b (`L["Subscribed Features"]`,
  `L["SubscribedFeaturesDesc"]`, and all 9 `*SubscribeDesc` keys).
- `L["Party Loot History"]` locale key from all 13 locale files.
- Test mocks for removed functions (`CreatePartyFrame`, `DestroyPartyFrame`
  stubs in `addonNamespace.lua`).
- `G_RLF.RLF_PartyLootFrame` references in spec files.
- `G_RLF.db.defaults.global.item` references in ItemConfig.lua (replaced
  with `G_RLF.db.defaults.global.frames["**"].features.itemLoot`).

#### Test/mock updates

- `addonNamespace.lua` mock now loads `ConfigOptions.lua` at the
  `ConfigOptions` load section to get the canonical `frames["**"]` defaults.
- All feature config specs updated to assert against
  `defaults.global.frames["**"].features.*` paths.
- `DbAccessors_spec.lua` simplified — fallback tests removed, replaced
  with direct per-frame path assertions.
- `LootDisplay_spec.lua` uses literal `2` instead of `ns.Frames.PARTY`.
- `PartyLootConfig_spec.lua` updated to use wildcard defaults path.

#### SmokeTest update

`SmokeTest.lua` updated to replace the hardcoded `G_RLF.Frames.PARTY` /
`RLF_PartyLootFrame` assertions with a generic loop over all configured
frame IDs in `db.global.frames`, asserting that each has a live widget via
`LootDisplay:GetFrame(id)` with correct `frameType`.

Additionally, the `featureDbKeyMap`, `testFeatureEnabledState()`, and
`testDbStructure()` functions were migrated from the old flat DB schema
(`db.global.item`, `db.global.xp`, etc.) to the new per-frame structure:

- `featureDbKeyMap` keys renamed to match canonical feature keys
  (`"item"` → `"itemLoot"`, `"xp"` → `"experience"`, `"rep"` →
  `"reputation"`, `"prof"` → `"profession"`).
- `testFeatureEnabledState()` now uses
  `DbAccessor:IsFeatureNeededByAnyFrame(featureKey)` instead of
  `db.global[dbKey].enabled`.
- `testDbStructure()` validates the per-frame structure
  (`frames[1].positioning`, `.sizing`, `.styling`, `.animations`,
  `.features`) and uses `DbAccessor:Feature(1, featureKey)` for
  per-feature assertions. Old flat feature keys and appearance keys
  removed from `requiredGlobalKeys`.

#### Files

- `LootDisplay/LootDisplay.lua`
- `LootDisplay/LootDisplayFrame/LootDisplayFrame.lua`
- `utils/Enums.lua`
- `utils/HistoryService.lua` (remove any remaining PARTY references)
- `config/DbAccessors.lua`
- `config/Positioning.lua`
- `config/Sizing.lua`
- `config/Styling.lua`
- `config/Animations.lua`
- All 9 `config/Features/*Config.lua`
- `GameTesting/SmokeTest.lua`
- `locale/enUS.lua` + all other locale files
- `RPGLootFeed_spec/_mocks/Internal/addonNamespace.lua`
- `RPGLootFeed_spec/utils/HistoryService_spec.lua`

#### Testing checklist

- [x] No references to `G_RLF.Frames.PARTY` outside design doc
- [x] No `G_RLF.RLF_PartyLootFrame` references outside design doc
- [x] No `defaults.global.item` (etc.) declarations remain
- [x] No `db.global.sizing` / `db.global.positioning` / `db.global.styling`
      / `db.global.animations` fallback reads in DbAccessor
- [x] No `db.global[featureKey].enabled` reads in SmokeTest
      (migrated to `DbAccessor:IsFeatureNeededByAnyFrame`)
- [x] All `*SubscribeDesc` and `SubscribedFeatures*` locale keys removed
- [x] `L["Party Loot History"]` removed from all locale files
- [x] `make test` passes (825/825)
- [ ] In-game smoke + integration tests pass

---

### Phase 6c — Documentation updates

**Goal**: Update all documentation to reflect the new multi-frame architecture.

#### What to update

- Wiki pages: LootFeeds, Visual, GeneralFeatures, and sub-pages.
- `.github/docs/architecture.md` module map.
- `docs/options-reorganization.md` (mark as superseded or update).
- This design doc: mark all phases as done, clean up "working copy items
  replaced" sections that are no longer relevant.

#### Files

- `RPGLootFeed.wiki/*.md`
- `.github/docs/architecture.md`
- `docs/options-reorganization.md`
- `docs/multi-frame-design.md`

---

### Future: Loot history architecture

**Status**: Discussion primer — not yet designed.

#### Current behavior

`LootDisplayFrameMixin:StoreRowHistory(row)` is called when a row is
**released** (exits the feed via animation/dismissal). It captures the final
visual state of the row — post-aggregation, post-update. History is stored
per-frame in `self.rowHistory` and capped at `db.global.lootHistory.historyLimit`.

#### Tension points

1. **Aggregation lossy**: If 3 currency events fire and aggregate into one
   row, history records 1 entry with the final total. The individual events
   are lost.

2. **Timing-dependent**: History depends on the display lifecycle. If a frame
   is hidden, destroyed, or rows are cleared, those events may never reach
   history.

3. **Per-frame but not per-event**: In the multi-frame world, the same event
   fires to all frames. Frame A may show it, Frame B may filter it. History
   is frame-scoped, meaning the same loot event can appear in Frame A's
   history but not Frame B's — which is correct for "what this frame showed"
   but confusing for "what happened".

#### Two possible models

**Model A — Record on display (current)**

- History = "what the user saw on this frame"
- Aggregation is reflected (one row = one history entry)
- Dismissal timestamps are meaningful
- Problem: timing-coupled, lossy for individual events

**Model B — Record on event acceptance**

- History = "what loot events were accepted by this frame"
- Each `OnLootReady` acceptance creates a history entry immediately
- No timing dependency — synchronous recording
- Aggregated rows would have multiple history entries
- Problem: history diverges from visual (user saw 1 row, history shows 3)

**Model C — Hybrid (global event log + per-frame display log)**

- Global `lootEventLog` records every event at fire time (Model B)
- Per-frame `rowHistory` stays as-is (Model A) for "what was displayed"
- UI can show either view
- Problem: more complexity, more storage

#### Questions to answer

- Is history meant to be "what I saw" or "what happened"?
- Should history survive frame deletion? (Currently: no, history dies with the frame)
- Should aggregated events be individual entries or collapsed?
- Is a global event log worth the storage/complexity?
- Does per-frame history still make sense, or should there be one global history?

#### Relationship to integration tests

The Phase 5d acceptance counter (`_testAcceptCount`) is _not_ history — it's
a test-only diagnostic counter. It doesn't affect the history architecture
decision. Whichever history model is chosen, the integration tests should
continue using acceptance counters for assertions.

---

## Key Files Affected (by Phase)

| Phase | Files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | `config/Migrations/v8.lua`, `config/ConfigOptions.lua`, `config/DbAccessors.lua`, `_global_types.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| 2     | `LootDisplay/LootDisplay.lua`, `LootDisplay/LootDisplayFrame/LootDisplayFrame.lua`, `LootDisplay/SampleRows.lua`, `Features/_Internals/LootElementBase.lua`, `Features/PartyLoot/PartyLoot.lua`                                                                                                                                                                                                                                                                                                                                                                                    |
| 3     | All 9 `config/Features/*Config.lua`, `config/Features/Features.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| 4a    | `config/ConfigOptions.lua`, `config/General.lua`, `config/BlizzardUI.lua`, `config/About.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 4b    | `config/FramesConfig.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| 4c    | `config/ConfigOptions.lua`, `config/FramesConfig.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| 5     | All 9 feature module files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| 5b    | `config/Migrations/v8.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| 5c    | `config/ConfigOptions.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| 5d    | `LootDisplay/LootDisplay.lua`, `GameTesting/IntegrationTest.lua`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| 6a    | All 9 feature modules, `LootDisplay/SampleRows.lua`, `LootDisplay/.../RowAnimationMixin.lua`, `LootDisplay/.../LootDisplayRow.lua`, `LootDisplay/.../RowTextMixin.lua`, `LootDisplay/.../RowUnitPortraitMixin.lua`, `LootDisplay/.../RowScriptedEffectsMixin.lua`, `Features/_Internals/LootElementBase.lua`, `config/General.lua`, `config/DbAccessors.lua`, `utils/HistoryService.lua`, `Core.lua`                                                                                                                                                                               |
| 6b    | `LootDisplay/LootDisplay.lua`, `LootDisplay/LootDisplayFrame/LootDisplayFrame.lua`, `utils/Enums.lua`, `config/DbAccessors.lua`, `config/Positioning.lua`, `config/Sizing.lua`, `config/Styling.lua`, `config/Animations.lua`, all 9 `config/Features/*Config.lua`, `locale/*.lua`, `GameTesting/SmokeTest.lua`, `RPGLootFeed_spec/_mocks/Internal/addonNamespace.lua`, `RPGLootFeed_spec/config/DbAccessors_spec.lua`, `RPGLootFeed_spec/LootDisplay/LootDisplay_spec.lua`, `RPGLootFeed_spec/config/Features/*Config_spec.lua`, `RPGLootFeed_spec/utils/HistoryService_spec.lua` |
| 6c    | Wiki, `architecture.md`, `options-reorganization.md`, this doc                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

---

## Non-Goals / Out of Scope

- Per-frame loot history (deferred — architecture supports it).
- Global appearance defaults with per-frame override (deferred —
  see `docs/future-global-appearance.md`).
- Feature module TOC split / sub-addon architecture (deferred —
  see `docs/future-module-rearchitecture.md`).
- Cross-frame drag-and-drop row re-ordering.
- Frame sharing between AceDB profiles or characters.
- More than 5 frames in the initial release (revisit after user feedback).
- Cleanup of orphaned top-level DB keys (`db.global.item`, `db.global.xp`,
  `db.global.rep`, `db.global.prof`, `db.global.partyLoot`,
  `db.global.currency`, `db.global.money`, `db.global.travelPoints`,
  `db.global.transmog`, `db.global.positioning`, `db.global.sizing`,
  `db.global.styling`, `db.global.animations`). Migration v8 copies these
  into `frames[1]` but does not delete the originals. A future migration
  could nil them out to reduce SavedVariables size.

---

## References

- [Global Appearance Defaults](future-global-appearance.md) — future work
- [Module Rearchitecture](future-module-rearchitecture.md) — future work
- [Options Reorganization](options-reorganization.md) — prior phases this
  builds on
- [Architecture](../.github/docs/architecture.md)
- [Glossary](../.github/docs/glossary.md)
- `loot-display.instructions.md` — frame/row pooling patterns
- `config.instructions.md` — AceConfig option table conventions
