# Future: Feature Module Rearchitecture / TOC Split

## Context

This document captures a deferred architectural improvement discussed during
the multi-frame design review (2026-03-09). It was intentionally excluded from
the multi-frame branch to limit scope.

## Problem

Currently, all feature modules (ItemLoot, PartyLoot, Currency, Money,
Experience, Reputation, Profession, TravelPoints, Transmog) are bundled into
the main RPGLootFeed addon. Even if a user never uses a feature, its code is
loaded and (depending on config) may register for WoW events.

Additionally, some features share WoW event registrations (e.g. ItemLoot and
PartyLoot both listen to `CHAT_MSG_LOOT`), but each module registers
independently.

## Proposed Solution: Sub-Addon Split

Split features into separate WoW addon modules with their own TOC files.
This is a well-established WoW addon pattern (WeakAuras/WeakAuras_Options,
Details/Details_EncounterDetails, etc.).

### Option A: Per-Feature Addons (9 addons)

```
RPGLootFeed/                       -- Core: display, config framework, broker
RPGLootFeed_ItemLoot/              -- ## Dependencies: RPGLootFeed
RPGLootFeed_PartyLoot/             -- ## Dependencies: RPGLootFeed
RPGLootFeed_Currency/              -- ## Dependencies: RPGLootFeed
RPGLootFeed_Money/                 -- ## Dependencies: RPGLootFeed
RPGLootFeed_Experience/            -- ## Dependencies: RPGLootFeed
RPGLootFeed_Reputation/            -- ## Dependencies: RPGLootFeed
RPGLootFeed_Profession/            -- ## Dependencies: RPGLootFeed
RPGLootFeed_TravelPoints/          -- ## Dependencies: RPGLootFeed
RPGLootFeed_Transmog/              -- ## Dependencies: RPGLootFeed
```

**Pros**: Maximum granularity; users disable exactly what they don't need.
**Cons**: 10 entries in the addon list; potentially confusing for casual users.

### Option B: Grouped Sub-Addons (3-4 addons)

```
RPGLootFeed/                       -- Core + display + config
RPGLootFeed_Loot/                  -- ItemLoot + PartyLoot + Transmog
                                   --   (all CHAT_MSG_LOOT based)
RPGLootFeed_Tracking/              -- Currency + Money + XP + Rep + Prof + Travel
                                   --   (tracking/stat gain features)
```

**Pros**: Clean event overlap grouping; manageable addon list.
**Cons**: Less granular; disabling "Tracking" kills 6 features at once.

### Option C: Centralized Event Broker (No TOC Split)

Instead of splitting into sub-addons, introduce a centralized event broker
that registers each WoW event **once** and dispatches to handler functions.
Feature modules become pure data transformers (receive raw event data, produce
`RLF_ElementPayload`).

```lua
-- EventBroker registers all WoW events once
EventBroker:RegisterEvent("CHAT_MSG_LOOT", function(...)
    ItemLoot:HandleChatMsgLoot(...)
    PartyLoot:HandleChatMsgLoot(...)
end)
```

**Pros**: No packaging complexity; reduces duplicate event registrations.
**Cons**: No user-facing toggle to completely unload feature code; marginal
performance gain since WoW's event system handles duplicates efficiently.

## Current Event Overlap Analysis

| WoW Event                 | Current Listeners   |
| ------------------------- | ------------------- |
| `CHAT_MSG_LOOT`           | ItemLoot, PartyLoot |
| `GET_ITEM_INFO_RECEIVED`  | ItemLoot, PartyLoot |
| `CURRENCY_DISPLAY_UPDATE` | Currency            |
| `PLAYER_MONEY`            | Money               |
| `PLAYER_XP_UPDATE`        | Experience          |
| Various faction events    | Reputation          |
| `CHAT_MSG_SKILL`          | Profession          |
| Various taxi/FP events    | TravelPoints        |

The overlap is minimal (primarily the CHAT_MSG_LOOT pair). The performance
win from deduplication is negligible. The bigger value is **code clarity** and
**user control**.

## Config UI Integration

With sub-addons, the config UI would auto-discover loaded modules:

```lua
-- In FramesConfig, when building feature tabs for a frame:
for _, featureKey in ipairs(G_RLF.registeredFeatures) do
    -- Only build config tab if the feature module is loaded
    if G_RLF:GetModule(featureKey, true) then
        group.args[featureKey] = G_RLF["Build" .. featureKey .. "Args"](frameId, order)
    end
end
```

Features that are disabled at the addon level simply don't appear in the
frame's config tabs — clean and self-documenting.

## Why Deferred

1. The multi-frame feature already changes the DB schema, config UI, and
   event routing significantly. Adding a TOC split on top makes the
   changeset enormous and hard to validate.
2. The per-frame broker pattern designed for multi-frame works identically
   regardless of whether features are in the main addon or split out.
   The broker listens for `RLF_NEW_LOOT` — it doesn't care who sent it.
3. Once multi-frame is stable, splitting features into sub-addons is a
   clean follow-up: move files, create TOC files, adjust load order. The
   message-based interfaces don't change.
4. The actual performance gain from not loading unused feature code is
   likely negligible for most users.
5. wow-build-tools packaging needs investigation to confirm it handles
   multi-TOC addon structures correctly.

## Dependencies

- Multi-frame feature must be stable first
- Per-frame broker pattern must be established (features fire `RLF_NEW_LOOT`,
  frames self-manage)
- Feature configs must be refactored into `Build*Args(frameId, order)` pattern
  (prerequisite for auto-discovery)
- wow-build-tools must support the packaging structure

## Open Questions

- Is the performance gain meaningful enough to justify the packaging
  complexity?
- Should we survey users to see if anyone wants this level of control?
- Would Option B (grouped sub-addons) give enough benefit with less
  complexity than Option A?
- Could we use LoadOnDemand TOC flags to defer loading until a feature is
  first enabled, avoiding the packaging split while still saving memory?
