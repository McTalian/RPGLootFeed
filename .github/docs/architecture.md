# Architecture

## Project Structure

```
RPGLootFeed/
├── Core.lua                  # Main addon entry point, initialization, event handling
├── embeds.xml               # Ace3 library embeds
├── RPGLootFeed.toc          # AddOn metadata and load order
├── BlizzOverrides/          # Blizzard UI modifications
│   ├── BossBanner.lua       # Boss banner customizations
│   ├── LootToasts.lua       # Loot toast frame overrides
│   ├── MoneyAlerts.lua      # Money alert overrides
│   └── retryHook.lua        # Hook retry utility
├── config/                   # Configuration & options UI
│   ├── ConfigOptions.lua    # Base options structure
│   ├── About.lua            # About panel
│   ├── Animations.lua       # Animation settings
│   ├── BlizzardUI.lua       # Blizzard UI override settings
│   ├── Positioning.lua      # Frame positioning options
│   ├── Sizing.lua           # Frame sizing options
│   ├── Styling.lua          # Visual styling options
│   ├── Features/            # Feature-specific configs
│   │   ├── Features.lua     # Main feature toggles
│   │   ├── CurrencyConfig.lua
│   │   ├── ExperienceConfig.lua
│   │   ├── ItemLootConfig.lua
│   │   ├── MoneyConfig.lua
│   │   ├── PartyLootConfig.lua
│   │   ├── ProfessionConfig.lua
│   │   ├── ReputationConfig.lua
│   │   ├── TransmogConfig.lua
│   │   └── TravelPointsConfig.lua
│   ├── common/              # Shared config utilities
│   │   ├── common.lua       # Common config helpers
│   │   ├── db.utils.lua     # Database utilities
│   │   └── styling.base.lua # Shared styling logic
│   └── Migrations/          # Database migrations
│       └── v*.lua
├── Features/                 # Feature implementations
│   ├── ItemLoot/            # Item looting
│   │   ├── ItemAuction.lua  # Auction/sell value display
│   │   └── ItemLoot.lua     # Core item loot handling
│   ├── PartyLoot/           # Group/raid loot
│   │   └── PartyLoot.lua
│   ├── Currency/            # Currency gains
│   │   └── Currency.lua
│   ├── Reputation/          # Reputation gains
│   │   ├── LegacyChatParsingImpl.lua  # Classic/non-Retail chat parsing for faction rep
│   │   └── Reputation.lua
│   ├── Experience.lua       # XP gains
│   ├── Money.lua            # Gold/money looting
│   ├── Professions.lua      # Profession skill-ups
│   ├── Transmog.lua         # Transmog notifications
│   ├── TravelPoints.lua     # Flight points discovered
│   └── _Internals/          # Internal feature utilities
│       ├── FeatureBase.lua       # AceModule factory (wraps G_RLF.RLF:NewModule)
│       ├── LootElementBase.lua   # Mixin factory for loot row data
│       ├── LootDisplayProperties.lua  # ⚠️ DEPRECATED — use LootElementBase:fromPayload() instead
│       ├── TextTemplateEngine.lua
│       ├── RLF_Notifications.lua
│       └── RLF_Communications.lua
├── LootDisplay/             # UI display layer
│   ├── LootDisplay.lua      # Main display manager (Ace module, queue management)
│   ├── LootDisplay.xml      # XML include chain entrypoint
│   ├── LootHistory.lua      # Loot history tracking
│   └── LootDisplayFrame/    # Frame mixin and row templates
│       ├── LootDisplayFrame.lua    # Frame mixin (RLF_LootDisplayFrameTemplate)
│       ├── LootDisplayFrame.xml
│       └── LootDisplayRow/  # Row sub-component mixins (WoW mixin pattern)
│           ├── LootDisplayRowTemplate.xml   # Virtual frame template; inherits all row sub-templates
│           ├── LootDisplayRow.lua           # LootDisplayRowMixin — coordinator/lifecycle (~437 lines)
│           ├── RowAnimation.lua        # RLF_RowAnimationMixin — enter/exit/hover animations
│           ├── RowAnimation.xml        # RLF_RowAnimationTemplate (virtual, script-only)
│           ├── RowTooltip.lua          # RLF_RowTooltipMixin — tooltip + click handling
│           ├── RowTooltip.xml          # RLF_RowTooltipTemplate (virtual; owns ClickableButton)
│           ├── RowText.lua             # RLF_RowTextMixin — font styling, text layout, item count
│           ├── RowText.xml             # RLF_RowTextTemplate (virtual; owns PrimaryText, ItemCountText, SecondaryText)
│           ├── RowBackdrop.lua         # RLF_RowBackdropMixin — gradient background + backdrop border
│           ├── RowBackdrop.xml         # RLF_RowBackdropTemplate (virtual; owns Background, border textures)
│           ├── RowScriptedEffects.lua  # RLF_RowScriptedEffectsMixin — transmog particle effects
│           ├── RowScriptedEffects.xml  # RLF_RowScriptedEffectsTemplate (virtual, script-only)
│           ├── RowIcon.lua             # RLF_RowIconMixin — icon sizing, positioning, texture updates
│           ├── RowIcon.xml             # RLF_RowIconTemplate (virtual; owns Icon ItemButton)
│           ├── RowUnitPortrait.lua     # RLF_RowUnitPortraitMixin — party unit portrait
│           └── RowUnitPortrait.xml     # RLF_RowUnitPortraitTemplate (virtual; owns UnitPortrait, RLFUser)
├── utils/                    # Utility modules
│   ├── Enums.lua            # Enumerations and constants
│   ├── Logger.lua           # Logging utilities
│   ├── Notifications.lua    # User notifications
│   ├── Queue.lua            # Queue data structure
│   └── Utils.lua            # General utilities
├── GameTesting/             # In-game testing support
│   ├── GameTestRunner.lua   # Pure-Lua test runner (busted-tested)
│   ├── TestMode.lua         # Test data initialization & readiness
│   ├── SmokeTest.lua        # Automated smoke tests (alpha only)
│   └── IntegrationTest.lua  # Visual integration tests (alpha only)
├── locale/                   # Localization strings
│   ├── enUS.lua             # English (base)
│   ├── deDE.lua, esES.lua, frFR.lua, etc.
├── Fonts/                    # Custom font files
├── Icons/                    # Addon icons and assets
└── Sounds/                   # Audio files
```

## Directory Conventions

### `/BlizzOverrides`

**Purpose**: Modifications to Blizzard's default UI behavior

**Contains**:

- Hooks into Blizzard UI frames
- Overrides for default loot notifications
- Optional modifications based on user settings

**Key Principle**: All modifications must be optional and configurable. Never force UI changes.

**Example**: `LootToasts.lua` disables the default loot toast frames when the user enables that option

**Dependencies**: Must handle missing Blizzard frames gracefully (different WoW versions may have different UI)

### `/config`

**Purpose**: All configuration options and data structures

**Contains**:

- AceConfig option tables
- Database schema definitions (defaults)
- User-facing configuration UI panels
- Database migrations

**Structure**:

- Top-level files handle general settings (positioning, sizing, styling, animations)
- `Features/` subdirectory contains feature-specific configuration
- `common/` contains shared configuration utilities
- `Migrations/` contains versioned database migrations

**Key Pattern**: Each config module defines its portion of `G_RLF.defaults` and `G_RLF.options`

**Example**: `CurrencyConfig.lua` defines `G_RLF.defaults.global.currency` and `G_RLF.options.args.features.args.currencyConfig`

### `/Features`

**Purpose**: Core feature logic and event handling

**Contains**:

- Event listeners (CHAT_MSG_LOOT, CHAT_MSG_CURRENCY, etc.)
- Data processing and formatting
- Integration with WoW APIs
- Loot message creation

**Does NOT contain**:

- UI rendering (use LootDisplay instead)
- Configuration UI (use config instead)

**Pattern**: Each feature module:

1. Captures all `G_RLF` dependencies as locals at the top ("External dependency locals" block)
2. Calls `FeatureBase:new(name, mixins...)` instead of `G_RLF.RLF:NewModule()` directly
3. Defines WoW API adapter in `utils/WoWAPIAdapters.lua` under `G_RLF.WoWAPI.*`, exposed on the module as `_someAdapter` for test injection
4. Implements `Module:BuildPayload(...)` which returns an `RLF_ElementPayload`; call sites do `LootElementBase:fromPayload(self:BuildPayload(...)):Show()`
5. Calls external API/logging functions through the captured locals, NOT through `G_RLF.*` directly

**Layered architecture** (migration complete — all feature modules follow this pattern):

All modules follow a four-layer pipeline:

```
G_RLF.WoWAPI.* (shared adapter) → Module service layer → RLF_ElementPayload → LootElementBase:fromPayload() → element:Show()
```

- **Shared adapters** live in `utils/WoWAPIAdapters.lua` under `G_RLF.WoWAPI.*`. They are pure wrappers around WoW C\_ APIs with no logic — the central mock boundary for tests.
- **Service layer** (e.g., `Rep:BuildPayload(unifiedFactionData)`) transforms domain data into an `RLF_ElementPayload` table — the uniform payload contract.
- **`LootElementBase:fromPayload(payload)`** is the generic element constructor. No per-module `Element:new()` needed.
- **`itemCountFn`** on the payload drives `ItemCountText` display. Each module provides its own closure that returns `(value, options)` for count display.

**Migration status**: All feature modules have been migrated to this pattern, including `ItemLoot/ItemLoot.lua` (migrated Feb 2026). The Migration is complete — `G_RLF.RLF:NewModule()` is no longer used in any feature module.

**`fn` deprecation**: The `self:fn(func, ...)` xpcall wrapper on the module prototype is being phased out. It silently swallows errors. Features should use direct calls with explicit guard clauses instead.

**`G_RLF.db` exception**: Database access is intentionally NOT captured as a local — it is nil until AceDB runs in `OnInitialize` and must remain a runtime lookup inside function bodies.

**Example**: `TravelPoints.lua` is the reference implementation of this pattern.

### `/LootDisplay`

**Purpose**: UI rendering and display management

**Contains**:

- Frame creation and management
- Row pooling and recycling
- Queue processing
- Animation coordination
- Loot history tracking

**Responsibilities**:

- Process the loot queue
- Display items in available rows
- Handle frame positioning and sizing
- Manage row animations (fade in/out, slide)
- Track loot history for the history panel

**Key Component**: `LootDisplayFrame` and `LootDisplayRow` mixins provide the frame behavior. `LootDisplayRow` has been fully decomposed into 7 focused sub-mixins (`RLF_RowAnimationMixin`, `RLF_RowTooltipMixin`, `RLF_RowTextMixin`, `RLF_RowBackdropMixin`, `RLF_RowScriptedEffectsMixin`, `RLF_RowIconMixin`, `RLF_RowUnitPortraitMixin`) following the WoW XML mixin composition pattern. `LootDisplayRow.lua` itself is now a pure coordinator/lifecycle file (~430 lines).

**Primary line layout**: `RLF_RowTextMixin` creates a programmatic `PrimaryLineLayout` frame (mixed with `LayoutMixin, HorizontalLayoutMixin`) once per physical pooled frame via `CreatePrimaryLineLayout()` (guarded so it is idempotent across pool Acquire/Release cycles). Three FontStrings live inside the container as layout children:

| `layoutIndex` | FontString      | Role                                     | Truncatable? |
| ------------- | --------------- | ---------------------------------------- | ------------ |
| 1             | `PrimaryText`   | Item/currency link only                  | Yes          |
| 2             | `AmountText`    | Quantity suffix (`"x2"`) — non-link text | No           |
| 3             | `ItemCountText` | Bag count / skill delta / rep level      | No           |

`PrimaryText` and `ItemCountText` are re-parented from the XML template; `AmountText` is created programmatically inside the layout frame (same pattern as `PrimaryLineLayout` itself). `AmountText` is driven by the optional `element.amountTextFn(existingQuantity)` field — features that produce a quantity suffix (`ItemLoot`, `PartyLoot`, `Currency`) set this; all others leave it `nil` and `AmountText` stays hidden.

`ItemCountText` display is driven by `element.itemCountFn` — a closure on the payload that returns `(value, options)` where `options = { color, wrapChar, showSign }`. The row calls it inside `RunNextFrame` and passes the result to `ShowItemCountText()`.

The unified layout entry point `LayoutPrimaryLine()` is called from `ShowText()`, `ShowAmountText()`, and `ShowItemCountText()`:

- First pass (from `ShowText()`): `AmountText` and `ItemCountText` hidden → `PrimaryText` gets `min(naturalWidth, availableWidth)`.
- Second pass (from `ShowAmountText()`): `AmountText` shown → `PrimaryText` budget shrinks by `AmountText:GetUnboundedStringWidth() + spacing`.
- Third pass (from `ShowItemCountText()`): `ItemCountText` shown → budget shrinks further. Engine-native truncation fires if needed (`SetWidth` + `SetWordWrap(false)`).

**Text alignment**: The `textAlignment` config value (`G_RLF.TextAlignment` enum: `LEFT`, `CENTER`, `RIGHT`) replaced the legacy `leftAlign` boolean (v7 migration). `LEFT` and `CENTER` place the icon on the left; `RIGHT` places it on the right. `CENTER` currently behaves like `LEFT` for row-internal layout — full centering within the row requires a future OuterLayout container. `childLayoutDirection = "rightToLeft"` on the layout containers handles the `RIGHT` case without reordering children. `ClickableButton` geometry is owned exclusively by `LayoutPrimaryLine()` (not `SetupTooltip()`).

**Secondary line layout**: `RLF_RowTextMixin` also creates a `SecondaryLineLayout` frame via `CreateSecondaryLineLayout()` (same pool-guard pattern). `SecondaryText` is re-parented into it as `layoutIndex=1`. `LayoutSecondaryLine()` applies the same `availableWidth` + engine-truncation logic as `LayoutPrimaryLine()`, without any sub-element budget splits. Additional secondary-line children can be added in the future without layout surgery.

`ShowText()` shows/hides `SecondaryLineLayout` (not `SecondaryText` directly) and calls `LayoutSecondaryLine()` when the secondary text is non-empty.

**Available width formula** (used by both `LayoutPrimaryLine` and `LayoutSecondaryLine`):

```
iconOffset = iconSize + 2 × (iconSize / 4)      -- gap + icon + gap
portraitOffset (when avatar enabled) = portraitSize + (iconSize / 4)  -- portrait + gap before layout
                                       where portraitSize = iconSize × 0.8
availableWidth = feedWidth - iconOffset - portraitOffset
```

The portrait offset formula was corrected in this session: the old formula (`portraitSize / 2`) under-counted. The correct value accounts for the full portrait width **plus** the `iconSize/4` gap between the icon's right edge and the portrait's left anchor.

**Spacing**: `PrimaryLineLayout.spacing` and `SecondaryLineLayout.spacing` are both set to the user-configurable `rowTextSpacing` DB value (under `global.styling`). `0` (default) means auto = `iconSize / 4`. The slider is in the Styling → Custom Fonts panel.

`LootDisplay.lua` no longer contains `TruncateItemLink`, `CalculateTextWidth`, or `tempFontString` — all superseded by native engine truncation via `FontString:SetWidth()` + `SetWordWrap(false)`.

**Does NOT contain**: Feature-specific logic (that belongs in Features/)

### `/utils`

**Purpose**: Shared utilities and helper functions

**Contains**:

- Enumerations and constants
- Common helper functions
- Data structures (Queue)
- Logging infrastructure
- User notifications
- `WoWAPIAdapters.lua` — Shared WoW API adapter namespace (`G_RLF.WoWAPI.*`), the central mock boundary for feature module tests

**Pattern**: Pure functions and utilities with no side effects where possible

**Example**: `Queue.lua` provides a generic queue data structure used by LootDisplay

### `/locale`

**Purpose**: Internationalization and localization

**Contains**:

- Localized strings for all supported languages
- `enUS.lua` is the base locale (always loaded)
- Other locale files override base strings for their language

**Pattern**: Use `G_RLF.L["Key"]` to access localized strings throughout the addon

### `/GameTesting`

**Purpose**: In-game testing utilities (alpha builds only, guarded by `--@alpha@` preprocessor blocks)

**Contains**:

- `GameTestRunner.lua` — Pure-Lua test runner class (no WoW API deps); supports `section()` for grouped output, `assertEqual()`, `runTestSafely()`, and `displayResults()`. Busted-tested in `RPGLootFeed_spec/GameTesting/GameTestRunner_spec.lua`.
- `TestMode.lua` — AceModule that initializes test data (items, currencies, factions) and coordinates readiness signals for smoke/integration tests.
- `SmokeTest.lua` — Comprehensive programmatic validation suite (10 sections) that runs automatically on addon load. Validates WoW globals, module registration, DB structure, migrations, LootDisplay frame state, element constructors, locale keys, and event handler wiring.
- `IntegrationTest.lua` — Visual integration tests that render sample loot rows for manual inspection. Triggered after all test data is cached and LootDisplay signals readiness.

**Key Principle**: Smoke tests must not render UI or trigger side effects — they validate internal state only. Integration tests may render rows but should be idempotent and re-runnable via `/rlf test integration`.

**Note**: This is for in-game testing, not unit tests (those are in `RPGLootFeed_spec/`)

## Key Architectural Patterns

### Event-Driven Architecture

Features listen for WoW events (like `CHAT_MSG_LOOT`) and respond by processing data and enqueuing loot messages.

### Queue-Based Display

Loot messages are enqueued and processed asynchronously by LootDisplay. This prevents UI blocking and allows for smooth animations.

### Modular Configuration

Each feature and setting is isolated in its own module, making it easy to enable/disable features and maintain configuration separately.

### Namespace Pattern

All addon code uses a shared namespace (`G_RLF`) passed via `local addonName, ns = ...` to avoid global pollution.

### Mixin Pattern

UI frames use mixins to encapsulate frame-specific behavior. `LootDisplayFrame` and `LootDisplayRow` are the primary frame mixins. `LootDisplayRow` has been fully decomposed into 7 focused sub-mixins declared in the XML `mixin=` attribute — matching the pattern used by Blizzard's own UI frames (see `wow-ui-source` reference).

All row sub-mixin globals are prefixed `RLF_` to avoid global `_G` namespace collisions with other addons. File names are kept short (no prefix needed since they're local to this addon's directory).

Each sub-mixin follows this structure:

1. `local addonName, ns = ...` / `local G_RLF = ns` header
2. Optional `---@class` annotations for helper types owned by this mixin
3. `RLF_XxxMixin = {}` global table declaration
4. Method definitions on that table
5. `G_RLF.RLF_XxxMixin = RLF_XxxMixin` namespace bookkeeping line at the bottom

The `LootDisplayRowTemplate.xml` `mixin=` attribute lists all mixins:

```
mixin="LootDisplayRowMixin,RLF_RowAnimationMixin,RLF_RowTooltipMixin,RLF_RowTextMixin,
       RLF_RowBackdropMixin,RLF_RowScriptedEffectsMixin,RLF_RowIconMixin,RLF_RowUnitPortraitMixin"
```

### Feature Module Pattern (established in TravelPoints spike)

Each feature module follows a strict structure to maximise testability:

```lua
-- 1. Capture all external deps as locals (visible dependency surface)
local LootElementBase = G_RLF.LootElementBase
local FeatureBase     = G_RLF.FeatureBase
local FeatureModule   = G_RLF.FeatureModule
local LogWarn = function(...) G_RLF:LogWarn(...) end
-- NOTE: G_RLF.db intentionally absent – nil until OnInitialize

-- 2. WoW API adapter tables (per-feature seam for test injection)
local SomeApiAdapter = {
    GetThing = function(id) return C_Some.GetThing(id) end,
}
local GlobalStringsAdapter = {
    GetLabel = function() return _G["SOME_KEY"] end,
}

-- 3. Module creation through FeatureBase (not G_RLF.RLF:NewModule directly)
local MyFeature = FeatureBase:new(FeatureModule.MyFeature, "AceEvent-3.0")
MyFeature._someApiAdapter = G_RLF.WoWAPI.MyFeature

-- 4. Build a payload and show it
function MyFeature:BuildPayload(...)
    ---@type RLF_ElementPayload
    local payload = { key = ..., type = FeatureModule.MyFeature, ... }
    return payload
end
```

Tests inject mocks by:

- Providing a minimal `ns` table to `loadfile("MyFeature.lua")("TestAddon", ns)`
- Overriding `TravelPointsModule._someApiAdapter = { ... }` after load

### WoW API Abstraction Adapter Pattern

All direct WoW API calls (`C_*`, `_G["STRING_KEY"]`) are consolidated in `utils/WoWAPIAdapters.lua` under the `G_RLF.WoWAPI.*` namespace. Each feature module captures its adapter at module-load time (e.g. `ItemLoot._itemLootAdapter = G_RLF.WoWAPI.ItemLoot`) — this is the per-test injection seam. Tests override the adapter field after `loadfile` to mock API calls without patching `_G`.

## Data Flow

1. **WoW Event Triggered** (e.g., player loots an item)
2. **Feature Module** listens for the event and processes it
3. **Message Builder** formats the loot message with styling
4. **Queue** stores the message for display
5. **LootDisplay** dequeues messages and assigns them to available rows
6. **Row Animation** fades in, displays, then fades out
7. **Loot History** (optional) records the loot for later viewing

## Ace3 Framework Integration

RPGLootFeed uses the Ace3 framework extensively:

- **AceAddon-3.0**: Core addon structure and module system
- **AceDB-3.0**: Configuration database with profiles
- **AceConfig-3.0**: Configuration UI generation
- **AceConfigDialog-3.0**: Configuration dialog display
- **AceEvent-3.0**: Event handling
- **AceHook-3.0**: Secure hooking of Blizzard functions
- **AceTimer-3.0**: Timer management
- **AceBucket-3.0**: Event bucketing for performance
- **AceConsole-3.0**: Slash command handling

## Load Order

The load order is defined in `RPGLootFeed.toc` and is critical:

1. **Library embeds** (`embeds.xml`)
2. **Type definitions** (`_global_types.lua`, `_lib_types.lua`)
3. **Core.lua** — sets up `G_RLF.RLF` (AceAddon instance) **first**, before any feature files
4. **Utils** (Enums, Logger, Notifications, Queue, Utils)
5. **Config base** (ConfigOptions)
6. **Config modules** (Positioning, Sizing, Styling, Animations, Features, etc.)
7. **BlizzOverrides**
8. **Feature internals** (`_Internals/`: TextTemplateEngine → LootElementBase → FeatureBase → LootDisplayProperties → ...)
9. **Feature implementations** (ItemLoot, Currency, Money, TravelPoints, etc.)
10. **LootDisplay** (Frame mixins, display manager, history)
11. **GameTesting** (loaded last for test mode)
