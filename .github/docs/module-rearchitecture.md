# Module Rearchitecture Plan

## Goal

Refactor feature modules from monolithic event-handler-to-element pipelines into a layered architecture:

```
WoW API Adapter → Service Layer → Payload → Generic Element Factory → LootDisplay
```

Each layer has a single responsibility:

| Layer                                                 | Responsibility                                                     | Testability                              |
| ----------------------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------- |
| **WoW API Adapter** (`G_RLF.WoWAPI.*`)                | Wrap raw WoW C\_ APIs; shared across modules                       | Mock at this boundary for busted tests   |
| **Service Layer** (in each module)                    | Receive event args, call adapter, compute deltas, build payload    | Fully unit-testable with mocked adapters |
| **Element Factory** (`LootElementBase:fromPayload()`) | Map uniform payload → element; generic, no per-module constructors | One set of tests covers all modules      |
| **LootDisplay / Row**                                 | Render element; calls payload-provided fns for display             | No type-switches; module-agnostic        |

## Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│  G_RLF.WoWAPI.*  (shared adapters)                   │
│  Pure wrappers, no logic, easily mocked              │
└────────────────────┬─────────────────────────────────┘
                     │ raw API returns
                     ▼
┌──────────────────────────────────────────────────────┐
│  Module Service Layer                                │
│  - Thin event handler: extract args, delegate        │
│  - Service methods: call adapter, compute delta,     │
│    build payload table                               │
│  - Closures in payload capture adapter refs          │
│    for deferred calls (itemCountFn, etc.)            │
└────────────────────┬─────────────────────────────────┘
                     │ RLF_ElementPayload table
                     ▼
┌──────────────────────────────────────────────────────┐
│  LootElementBase:fromPayload(payload)                │
│  - Generic: maps payload fields → element fields     │
│  - No per-module Element:new() needed                │
└────────────────────┬─────────────────────────────────┘
                     │ element:Show()
                     ▼
┌──────────────────────────────────────────────────────┐
│  LootDisplay / Row Rendering                         │
│  - No type-switches                                  │
│  - Calls payload-provided fns (textFn, itemCountFn,  │
│    secondaryTextFn, colorFn, etc.)                   │
└──────────────────────────────────────────────────────┘
```

## Payload Contract

The uniform payload maps directly to row visual components. Full type definition lives in `LootElementBase.lua` as `RLF_ElementPayload`.

| Component          | Payload Fields                                                | Purpose                                                 |
| ------------------ | ------------------------------------------------------------- | ------------------------------------------------------- |
| **Routing**        | `key`, `type`, `eventChannel`                                 | Row identity + message bus channel                      |
| **Icon**           | `icon`, `quality`, `topLeftText`, `topLeftColor`              | Left-side icon, border color, overlay text              |
| **Primary Line**   | `textFn`, `quantity`, `isLink`, `amountTextFn`, `itemCountFn` | Main text, quantity delta, link behavior, count display |
| **Secondary Line** | `secondaryTextFn`, `secondaryText`, `secondaryTextColor`      | Below primary; context info                             |
| **Color**          | `r`/`g`/`b`/`a`, `colorFn`                                    | Primary text color, dynamic recomputation               |
| **Effects**        | `highlight`, `sound`                                          | Border glow, sound playback                             |
| **Interaction**    | `isCustomLink`, `customBehavior`                              | Custom tooltip / click behavior                         |
| **Party**          | `unit`                                                        | Unit token for portrait display                         |
| **Lifecycle**      | `showForSeconds`, `isSampleRow`, `logFn`, `IsEnabled`         | Display timing, test mode, logging, permission gate     |
| **Compat**         | `itemCount`                                                   | Backwards compat for non-migrated modules               |

### Key Design: `itemCountFn` replaces type-switch

Instead of the rendering layer checking `self.type` against every module name, each module provides an `itemCountFn` closure:

```lua
-- Module builds this during payload construction:
payload.itemCountFn = function()
    if not G_RLF.db.global.rep.enableRepLevel then return nil end
    return rankValue, { color = hexColor, wrapChar = wrapChar }
end

-- Row rendering becomes module-agnostic:
function RLF_RowTextMixin:UpdateItemCount()
    if not self.itemCountFn then return end
    RunNextFrame(function()
        local value, options = self.itemCountFn()
        if value then self:ShowItemCountText(value, options) end
    end)
end
```

### Text Generation Strategy

- **TextTemplateEngine** is the default/preferred approach (declarative, testable)
- Raw `textFn` closures are a valid escape hatch for complex cases (e.g., ItemLoot stat deltas)
- Modules under `fromPayload()` can use either approach — the element consumer only calls `textFn()`

## Migration Status

Modules are migrated one at a time. Each migration includes:

1. Extract adapter to `G_RLF.WoWAPI.*` (if not already shared)
2. Refactor module: thin event handler → service layer → payload construction
3. Replace per-module `Element:new()` with `LootElementBase:fromPayload()`
4. Update TestMode / IntegrationTest to construct payloads directly
5. Update SmokeTest element constructor assertions
6. Verify busted tests + in-game smoke/integration tests pass

| Module         | Status         | Notes                                                                                                           |
| -------------- | -------------- | --------------------------------------------------------------------------------------------------------------- |
| **Reputation** | ✅ Complete    | Proof-of-concept; dual event path (Retail/Classic)                                                              |
| Experience     | ✅ Complete    | Simple scalar; adapter moved to WoWAPI.Experience                                                               |
| Money          | ✅ Complete    | Simple scalar; adapter to WoWAPI.Money; `PlaySoundIfEnabled` promoted to module method                          |
| ItemLoot       | ⏳ Not Started | Complex; ItemInfo object, stat deltas, async                                                                    |
| Currency       | ✅ Complete    | 3-tuple API data; hidden currency filtering; `itemCountFn` replaces type-switch                                 |
| PartyLoot      | ✅ Complete    | Unit-aware; routes to separate frame; filter logic consolidated into service layer; adapter to WoWAPI.PartyLoot |
| Professions    | ✅ Complete    | Chat-parsed; `itemCountFn` replaces Professions type-switch; adapter to WoWAPI.Professions                      |
| Transmog       | ⏳ Not Started | Async item loading; custom link behavior                                                                        |
| TravelPoints   | ✅ Complete    | Simple; two inline adapters consolidated to WoWAPI.TravelPoints                                                 |

## Key Decisions

1. **One module at a time** — Each migration is self-contained and testable. No big-bang rewrite.
2. **Generic `fromPayload()` over per-module `Element:new()`** — Enforces uniform contract, reduces code duplication, builds test confidence in the generic path.
3. **Shared adapters (`G_RLF.WoWAPI.*`)** — Single place to update for API deprecations/changes. Centralizes mock boundary for testing.
4. **`itemCountFn` on payload** — Moves type-specific rendering logic from the row layer back to the module that owns it. Row rendering becomes module-agnostic.
5. **Backwards compatibility** — `LootElementBase:new()` still works. Non-migrated modules continue to function. `itemCount` field preserved on payload for compat.
6. **TextTemplateEngine as default, closures as escape hatch** — Don't force all modules through templates if their text logic is genuinely complex.

## Files Created/Modified So Far

### Created

- `LootElementBase:fromPayload()` + `RLF_ElementPayload` type in [Features/\_Internals/LootElementBase.lua](../../RPGLootFeed/Features/_Internals/LootElementBase.lua)
- Shared `G_RLF.WoWAPI.Reputation` and `G_RLF.WoWAPI.Experience` adapters in [utils/WoWAPIAdapters.lua](../../RPGLootFeed/utils/WoWAPIAdapters.lua)

### Modified (Reputation Migration)

- [Reputation.lua](../../RPGLootFeed/Features/Reputation/Reputation.lua) — Removed `Rep.Element:new()`, added `Rep:BuildPayload()`, all call sites use `LootElementBase:fromPayload(payload)`
- [RowTextMixin.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua) — `UpdateItemCount()` checks `self.itemCountFn` first (payload-provided), falls back to legacy type-switch for non-migrated modules
- [LootDisplayRow.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow.lua) — `BootstrapFromElement` and `UpdateQuantity` now store `element.itemCountFn` on the row
- [utils.xml](../../RPGLootFeed/utils/utils.xml) — Added `WoWAPIAdapters.lua` to load order
- [Reputation_spec.lua](../../RPGLootFeed_spec/Features/Reputation_spec.lua) — Updated spies from `Element.new` to `BuildPayload`; added `repLevelColor`/`repLevelTextWrapChar` to test db config; added `WoWAPI` namespace mock
- [ReputationRegressions_spec.lua](../../RPGLootFeed_spec/Features/ReputationRegressions_spec.lua) — Same spy updates + namespace mock

### Modified (Experience Migration)

- [Experience.lua](../../RPGLootFeed/Features/Experience.lua) — Removed `Xp.Element:new()`, added `Xp:BuildPayload()`, adapter changed from inline `UnitXpAdapter`/`_unitXpAdapter` to shared `G_RLF.WoWAPI.Experience`/`_xpAdapter`, added `itemCountFn` closure for current level display
- [RowTextMixin.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua) — Removed `if self.type == "Experience"` branch from legacy type-switch
- [LootElementBase.lua](../../RPGLootFeed/Features/_Internals/LootElementBase.lua) — Removed `Xp.Element` from `RLF_LootElement` type alias
- [Experience_spec.lua](../../RPGLootFeed_spec/Features/Experience_spec.lua) — Updated to `BuildPayload`/`fromPayload`, `_xpAdapter` naming, `WoWAPI` mock, added `itemCountFn` tests
- [SmokeTest.lua](../../RPGLootFeed/GameTesting/SmokeTest.lua) — XP smoke test uses `BuildPayload` → `fromPayload`; Rep smoke test added
- [IntegrationTest.lua](../../RPGLootFeed/GameTesting/IntegrationTest.lua) — XP integration test uses `BuildPayload` → `fromPayload`; Rep integration test refactored to cover Retail via direct payload construction

### Modified (Money Migration)

- [Money.lua](../../RPGLootFeed/Features/Money.lua) — Removed `Money.Element:new()`, added `Money:BuildPayload()`; inline `MoneyAdapter` replaced with `G_RLF.WoWAPI.Money`; `PlaySoundIfEnabled` promoted from element method to module method
- [WoWAPIAdapters.lua](../../RPGLootFeed/utils/WoWAPIAdapters.lua) — Added `G_RLF.WoWAPI.Money` (`GetCoinTextureString`, `GetMoney`, `PlaySoundFile`)
- [LootElementBase.lua](../../RPGLootFeed/Features/_Internals/LootElementBase.lua) — Removed `Money.Element` from `RLF_LootElement` type alias
- [Money_spec.lua](../../RPGLootFeed_spec/Features/Money_spec.lua) — Updated to `BuildPayload`/`fromPayload` pattern; `PlaySoundIfEnabled` tests use `Money:PlaySoundIfEnabled()` not element method; added `WoWAPI` mock
- [SmokeTest.lua](../../RPGLootFeed/GameTesting/SmokeTest.lua) — Money smoke test uses `BuildPayload` → `fromPayload`
- [IntegrationTest.lua](../../RPGLootFeed/GameTesting/IntegrationTest.lua) — Money integration test uses `BuildPayload` → `fromPayload`

### Modified (TravelPoints Migration)

- [TravelPoints.lua](../../RPGLootFeed/Features/TravelPoints.lua) — Removed `TravelPoints.Element:new()`, added `TravelPoints:BuildPayload()`; two inline adapters (`_perksActivitiesAdapter`, `_globalStringsAdapter`) consolidated into `G_RLF.WoWAPI.TravelPoints`/`_travelPointsAdapter`; `PERKS_ACTIVITY_COMPLETED` handler uses `BuildPayload` → `fromPayload` → `Show`
- [WoWAPIAdapters.lua](../../RPGLootFeed/utils/WoWAPIAdapters.lua) — Added `G_RLF.WoWAPI.TravelPoints` (`GetPerksActivitiesInfo`, `GetPerksActivityInfo`, `GetMonthlyActivitiesPointsLabel`)
- [LootElementBase.lua](../../RPGLootFeed/Features/_Internals/LootElementBase.lua) — Removed `TravelPoints.Element` from `RLF_LootElement` type alias
- [TravelPoints_spec.lua](../../RPGLootFeed_spec/Features/TravelPoints_spec.lua) — Updated to `BuildPayload`/`fromPayload` pattern; `_perksActivitiesAdapter`/`_globalStringsAdapter` combined into `_travelPointsAdapter`; added `WoWAPI` mock
- [SmokeTest.lua](../../RPGLootFeed/GameTesting/SmokeTest.lua) — TravelPoints smoke test uses `BuildPayload` → `fromPayload`
- [IntegrationTest.lua](../../RPGLootFeed/GameTesting/IntegrationTest.lua) — Added `runTravelPointsIntegrationTest()` (Retail-only, direct payload construction)

### Modified (Currency Migration)

- [Currency.lua](../../RPGLootFeed/Features/Currency/Currency.lua) — Removed `Currency.Element:new()`, added `Currency:BuildPayload(currencyLink, info, basicInfo)`; inline `CurrencyAdapter` replaced with `G_RLF.WoWAPI.Currency`; both `Process` and `CHAT_MSG_CURRENCY` handlers use `BuildPayload` → `fromPayload` → `Show`; `itemCountFn` replaces legacy `itemCount` field for currency total display
- [WoWAPIAdapters.lua](../../RPGLootFeed/utils/WoWAPIAdapters.lua) — Added `G_RLF.WoWAPI.Currency` (full adapter: C_Everywhere unified queries, Honor tracking, Constants, classic locale patterns, Ethereal Strands UI); added `LibStub` local for `C_Everywhere` resolution
- [RowTextMixin.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua) — Removed `if self.type == "Currency"` branch from legacy `UpdateItemCount` type-switch
- [LootElementBase.lua](../../RPGLootFeed/Features/_Internals/LootElementBase.lua) — Removed `Currency.Element` from `RLF_LootElement` type alias
- [Currency_spec.lua](../../RPGLootFeed_spec/Features/Currency_spec.lua) — Updated all spies/stubs from `Element.new` to `BuildPayload`; `Element` describe block renamed to `BuildPayload`; replaced `LibStub` require with `WoWAPI = { Currency = {} }` ns mock
- [SmokeTest.lua](../../RPGLootFeed/GameTesting/SmokeTest.lua) — Currency smoke test uses `BuildPayload` → `fromPayload`
- [IntegrationTest.lua](../../RPGLootFeed/GameTesting/IntegrationTest.lua) — Currency integration test uses `BuildPayload` → `fromPayload`

### Modified (Professions Migration)

- [Professions.lua](../../RPGLootFeed/Features/Professions.lua) — Removed `Professions.Element:new()`, added `Professions:BuildPayload(key, name, icon, level, quantity)`; inline `ProfessionsAdapter` replaced with `G_RLF.WoWAPI.Professions`; `CHAT_MSG_SKILL` handler uses `BuildPayload` → `fromPayload` → `Show`; `itemCountFn` replaces `Professions` branch in legacy `UpdateItemCount` type-switch
- [WoWAPIAdapters.lua](../../RPGLootFeed/utils/WoWAPIAdapters.lua) — Added `G_RLF.WoWAPI.Professions` (GetProfessions, GetProfessionInfo, IssecretValue, GetSkillRankUpPattern)
- [RowTextMixin.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua) — Removed `if self.type == "Professions"` branch from legacy `UpdateItemCount` type-switch; only `ItemLoot` branch remains
- [LootElementBase.lua](../../RPGLootFeed/Features/_Internals/LootElementBase.lua) — Removed `Professions.Element` from `RLF_LootElement` type alias
- [Professions_spec.lua](../../RPGLootFeed_spec/Features/Professions_spec.lua) — Added `WoWAPI = { Professions = {} }` ns mock; `showSkillChange`/`skillTextWrapChar` added to test db; `Element` describe → `BuildPayload`; all `Element:new` calls → `BuildPayload`; two new `itemCountFn` tests added (enabled/disabled)
- [SmokeTest.lua](../../RPGLootFeed/GameTesting/SmokeTest.lua) — Professions smoke test uses `BuildPayload` → `fromPayload`; added `itemCountFn` assertion
- [IntegrationTest.lua](../../RPGLootFeed/GameTesting/IntegrationTest.lua) — Professions integration test uses `BuildPayload` → `fromPayload`

### Modified (PartyLoot Migration)

- [PartyLoot.lua](../../RPGLootFeed/Features/PartyLoot/PartyLoot.lua) — Removed `PartyLoot.Element:new()`, added `PartyLoot:BuildPayload(info, amount, unit)`; inline `PartyLootAdapter` + `LibStub("C_Everywhere")` removed; replaced with `G_RLF.WoWAPI.PartyLoot`; `OnPartyReadyToShow` now consolidates all filter logic (quality filter nil = blocked, same as false; ignoreItemIds check) before calling `BuildPayload` → `fromPayload` → `Show`; `unitClass` (vestigial) and `itemId` (moved to service-layer filter) dropped from element
- [WoWAPIAdapters.lua](../../RPGLootFeed/utils/WoWAPIAdapters.lua) — Added `G_RLF.WoWAPI.PartyLoot` (UnitName, UnitClass, IssecretValue, GetNumGroupMembers, IsInRaid, IsInInstance, GetExpansionLevel, GetPlayerGuid, GetClassColor, GetRaidClassColor, GetItemInfo via C_Everywhere)
- [LootElementBase.lua](../../RPGLootFeed/Features/_Internals/LootElementBase.lua) — Removed `PartyLoot.Element` from `RLF_LootElement` type alias
- [PartyLoot_spec.lua](../../RPGLootFeed_spec/Features/PartyLoot_spec.lua) — Added `WoWAPI = { PartyLoot = {} }` ns mock; removed `LibStub` require (no longer needed); filter tests use `spy.on(PartyLoot, "BuildPayload")`; CHAT_MSG_LOOT/GET_ITEM_INFO_RECEIVED tests check `sendMessageSpy` instead of stub on `Element.new`; `Element` describe → `BuildPayload`; `unitClass` test removed; all `Element:new` calls → `BuildPayload`
- [IntegrationTest.lua](../../RPGLootFeed/GameTesting/IntegrationTest.lua) — PartyLoot integration test uses `BuildPayload` → `fromPayload` → `Show`

## Future Considerations

- **Midnight API changes**: WoW Midnight locks down `CHAT_MSG_*` processing in combat/instances. Modules relying on chat parsing (Reputation legacy, Professions, ItemLoot) will need to move to first-class events. The adapter layer isolates this migration.
- **Replay/regression framework**: With adapters, it becomes possible to record adapter outputs and replay them in tests to reproduce specific scenarios.
- **Adapter-level integration tests**: A future testing tier could exercise adapter → service → payload without the full WoW client, using recorded adapter outputs.
