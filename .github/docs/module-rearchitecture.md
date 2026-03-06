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

| Module         | Status         | Notes                                                   |
| -------------- | -------------- | ------------------------------------------------------- |
| **Reputation** | ✅ Complete    | Proof-of-concept; dual event path (Retail/Classic)      |
| Experience     | ⏳ Not Started | Simple scalar; already has adapter pattern              |
| Money          | ⏳ Not Started | Simple scalar; already has adapter + TextTemplateEngine |
| ItemLoot       | ⏳ Not Started | Complex; ItemInfo object, stat deltas, async            |
| Currency       | ⏳ Not Started | 3-tuple API data; hidden currency filtering             |
| PartyLoot      | ⏳ Not Started | Routes to separate frame; unit-aware                    |
| Professions    | ⏳ Not Started | Chat-parsed; `itemCount` used for skill delta display   |
| Transmog       | ⏳ Not Started | Async item loading; custom link behavior                |
| TravelPoints   | ⏳ Not Started | Simple; discovery-based                                 |

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
- Shared `G_RLF.WoWAPI.Reputation` adapter in [utils/WoWAPIAdapters.lua](../../RPGLootFeed/utils/WoWAPIAdapters.lua)

### Modified (Reputation Migration)

- [Reputation.lua](../../RPGLootFeed/Features/Reputation/Reputation.lua) — Removed `Rep.Element:new()`, added `Rep:BuildPayload()`, all call sites use `LootElementBase:fromPayload(payload)`
- [RowTextMixin.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua) — `UpdateItemCount()` checks `self.itemCountFn` first (payload-provided), falls back to legacy type-switch for non-migrated modules
- [LootDisplayRow.lua](../../RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow.lua) — `BootstrapFromElement` and `UpdateQuantity` now store `element.itemCountFn` on the row
- [utils.xml](../../RPGLootFeed/utils/utils.xml) — Added `WoWAPIAdapters.lua` to load order
- [Reputation_spec.lua](../../RPGLootFeed_spec/Features/Reputation_spec.lua) — Updated spies from `Element.new` to `BuildPayload`; added `repLevelColor`/`repLevelTextWrapChar` to test db config; added `WoWAPI` namespace mock
- [ReputationRegressions_spec.lua](../../RPGLootFeed_spec/Features/ReputationRegressions_spec.lua) — Same spy updates + namespace mock

## Future Considerations

- **Midnight API changes**: WoW Midnight locks down `CHAT_MSG_*` processing in combat/instances. Modules relying on chat parsing (Reputation legacy, Professions, ItemLoot) will need to move to first-class events. The adapter layer isolates this migration.
- **Replay/regression framework**: With adapters, it becomes possible to record adapter outputs and replay them in tests to reproduce specific scenarios.
- **Adapter-level integration tests**: A future testing tier could exercise adapter → service → payload without the full WoW client, using recorded adapter outputs.
