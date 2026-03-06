# Testing Strategy & Guidelines

## Current Testing Approach

RPGLootFeed has a **hybrid testing strategy** combining automated unit tests with manual in-game testing. The automated tests are limited due to WoW's API dependencies, but provide value for logic that can be tested in isolation.

## Test Structure

### Unit Tests Location

**Directory**: `RPGLootFeed_spec/`

Mirrors the main addon structure with `_spec.lua` files for each module.

### Test Framework

**Busted**: Lua testing framework (https://olivinelabs.com/busted/)

**Installation**: Via LuaRocks or bundled with the project

**Running Tests**:

```bash
make test                                  # Run all tests
make test-cov                              # Run all tests with coverage report
make test-file FILE=path/to/spec.lua       # Run a specific test file
make test-pattern PATTERN="description"     # Run tests matching a pattern
make test-only                             # Run tests tagged with 'only'
```

> **Important**: Do not run `busted` directly — it is installed under `~/.luarocks/bin` and is not on `$PATH`. Always use the `make` targets above, which resolve the correct binary path automatically.

### Mock System

**Location**: `RPGLootFeed_spec/_mocks/`

Contains mocks for WoW APIs and the addon namespace.

**Key Mock**: `Internal/addonNamespace.lua` - Provides a mock version of `G_RLF` with controlled load order simulation.

**Suite-wide helper**: `.busted` (project root) configures busted to auto-run `RPGLootFeed_spec/_mocks/helper.lua` once before any spec. It pre-loads:

- `LuaCompat` — `unpack` / `format` global polyfills for Lua 5.2+
- `WoWGlobals` — core WoW global stubs (BossBanner, EventRegistry, CreateColor, etc.)
- `WoWGlobals/Functions` — WoW global function stubs (RunNextFrame, CreateFrame, UnitClass, etc.)
- `WoWGlobals/Enum` — `_G.Enum` table (Enum.ItemQuality, Enum.ItemBind, etc.)
- `WoWGlobals/Constants` — `_G.Constants` table (Constants.CurrencyConsts, etc.)
- `WoWGlobals/namespaces/C_Item` — `_G.C_Item` stubs
- `WoWGlobals/namespaces/C_CurrencyInfo` — `_G.C_CurrencyInfo` stubs
- `WoWGlobals/namespaces/C_TransmogCollection` — `_G.C_TransmogCollection` stubs
- `WoWGlobals/namespaces/C_CVar` — `_G.C_CVar` stubs
- `WoWGlobals/namespaces/C_ClassColor` — `_G.C_ClassColor` stubs
- `WoWGlobals/namespaces/C_GossipInfo` — `_G.C_GossipInfo` stubs
- `WoWGlobals/namespaces/C_MajorFactions` — `_G.C_MajorFactions` stubs
- `WoWGlobals/namespaces/C_PerksActivities` — `_G.C_PerksActivities` stubs
- `WoWGlobals/namespaces/C_Reputation` — `_G.C_Reputation` stubs
- `WoWGlobals/namespaces/C_DelvesUI` — `_G.C_DelvesUI` stubs

Spec files **do not need** to require any of these manually. Assignments like `itemMocks = require("WoWGlobals.namespaces.C_Item")` for spy access are still valid — the module cache returns the same table, so spy references resolve correctly.

**`addonNamespace.lua` additions worth noting**:

- `ns.PerfPixel` — stubbed at `LoadSections.Core` and above. `PerfPixel.PScale` is an identity function (returns its argument unchanged) so pixel-math in mixin methods produces predictable values in tests. Accessible as `nsMocks.PerfPixel.PScale` for call assertions.

**`Internal/LootDisplayRowFrame.lua`** — factory that builds a fully-stubbed row-frame `self` table for `RowXxxMixin` unit tests. All sub-elements (`Background`, `Icon`, `PrimaryText`, `UnitPortrait`, `ClickableButton`, etc.) carry busted stubs on every WoW method, so tests can call mixin methods and immediately assert against spies without any per-test frame setup.

Key mock details:

- `row.PrimaryText` / `row.AmountText` / `row.ItemCountText` / `row.SecondaryText` — `mockFontString()` with stubs for all layout + font methods. `GetUnboundedStringWidth` returns `80` (a plain function, not a busted stub, since `LayoutPrimaryLine` / `LayoutSecondaryLine` call it in the hot path). `IsShown` is also a plain function (returns `false` by default) for the same reason — tests that need a different return value reassign it directly: `row.AmountText.IsShown = function() return true end`.
- `row.PrimaryLineLayout` — `mockLayoutFrame()` with `Layout`, `Show`, `Hide`, `SetShown`, `SetAlpha`, `SetPoint`, `ClearAllPoints` stubs and writable `spacing`, `childLayoutDirection`, `fixedWidth` fields. Represents the `HorizontalLayoutMixin` container created programmatically by `CreatePrimaryLineLayout()`.
- `row.SecondaryLineLayout` — same `mockLayoutFrame()` shape. Represents the container created by `CreateSecondaryLineLayout()`. `ShowText` calls `Show()`/`Hide()` on this frame (not on `SecondaryText` directly) and calls `LayoutSecondaryLine()`.
- `row.ClickableButton` — `mockButton()` with `SetSize`, `SetPoint`, `ClearAllPoints`, `Show`, `Hide`, `SetScript`, `RegisterEvent`, `UnregisterEvent` stubs.

```lua
local rowFrameMocks = require("RPGLootFeed_spec._mocks.Internal.LootDisplayRowFrame")
local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")

describe("RLF_RowBackdropMixin", function()
    local ns, row
    before_each(function()
        ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.LootDisplay)
        loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowBackdropMixin.lua")("TestAddon", ns)
        row = rowFrameMocks.new()
    end)

    it("hides Background when rowBackgroundType is not GRADIENT", function()
        stub(ns.DbAccessor, "Styling").returns({ rowBackgroundType = ns.RowBackground.SOLID })
        RLF_RowBackdropMixin.StyleBackground(row)
        assert.stub(row.Background.Hide).was.called()
    end)
end)
```

## Testing Patterns

### Basic Test Structure

```lua
local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")

describe("MyModule", function()
    local ns, MyModule

    before_each(function()
        -- Load dependencies first
        ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.Utils)

        -- Load the module under test
        MyModule = assert(loadfile("RPGLootFeed/MyModule.lua"))("TestAddon", ns)
    end)

    it("should do something", function()
        assert.is_not_nil(MyModule)
        assert.are.equal(MyModule:SomeMethod(), expectedValue)
    end)
end)
```

### Lightweight Feature Module Tests (preferred pattern)

Feature modules expose their full dependency surface as locals at the top of the file and use `FeatureBase:new()` instead of `G_RLF.RLF:NewModule()` directly. This means tests can build `ns` as a plain hand-crafted table with **zero reliance on the `nsMocks` framework**.

**Fully migrated reference implementations** (in rough order of complexity):

| Spec file                        | Pattern highlights                                                                                                     |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `TravelPoints_spec.lua`          | Canonical baseline — simplest pattern                                                                                  |
| `Transmog_spec.lua`              | Canonical baseline                                                                                                     |
| `Experience_spec.lua`            | Bare WoW global fn adapter (`UnitXP` etc.)                                                                             |
| `Money_spec.lua`                 | C\_\* + bare globals + PlaySoundFile + TextTemplateEngine                                                              |
| `Professions_spec.lua`           | `GetProfessions/GetProfessionInfo`, locale globals                                                                     |
| `ReputationRegressions_spec.lua` | **Inline utility stub** (`ns.RepUtils`, `ns.LegacyRepParsing`), AceBucket mixin, `BuildPayload` spy pattern            |
| `PartyLoot_spec.lua`             | UnitName/UnitClass, GUID, expansion-gate, nameUnitMap                                                                  |
| `Currency_spec.lua`              | C_Everywhere + bare global fallbacks, Classic locale patterns, adapter factory                                         |
| `ItemLoot_spec.lua`              | Most complex: AceBucket mixin, `_itemLootAdapter` with 14 methods, `Enum` global, classical/Retail branching, 49 tests |
| `Money_spec.lua`                 | `colorFn` hook on `Element:new()` for net-quantity-aware row color on update                                           |

**Inline utility stub pattern** — for modules with large utility deps having deep WoW API chains (e.g. `RepUtils` → `C_Reputation` / `C_GossipInfo` / `C_MajorFactions`), stub the entire utility table inline on `ns` rather than loading the real file:

```lua
ns.RepUtils = {
    RepType = { BaseFaction = 0x0001, ... },
    GetCount = function() return 0 end,
    DetermineRepType = function() return 0x0001 end,
    ...
}
```

This completely isolates the module under test from transitive WoW dependencies.

```lua
local assert = require("luassert")
local busted = require("busted")
local spy = busted.spy
local stub = busted.stub

describe("MyFeature", function()
    local ns, MyFeatureModule
    local sendMessageSpy, logWarnSpy

    before_each(function()
        -- Fresh spies each test run.
        sendMessageSpy = spy.new(function() end)
        logWarnSpy = spy.new(function() end)

        -- Build ns from scratch – only fields the feature actually references.
        -- See the feature's "External dependency locals" block to know exactly
        -- what is needed.
        ns = {
            DefaultIcons  = { MY_FEATURE = "Interface/Icons/SomeIcon" },
            ItemQualEnum  = { Epic = 4 },
            FeatureModule = { MyFeature = "MyFeature" },
            LogDebug      = function() end,
            LogInfo       = function() end,
            LogWarn       = logWarnSpy,
            IsRetail      = function() return true end,
            SendMessage   = sendMessageSpy,
            -- Runtime lookup by LootElementBase:new() and lifecycle methods.
            db = {
                global = {
                    animations = { exit = { fadeOutDelay = 3 } },
                    myFeature  = { enableIcon = true, enabled = true },
                    misc       = { hideAllIcons = false },
                },
            },
        }

        -- Load real LootElementBase so elements are fully constructed.
        assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)

        -- Inline FeatureBase stub – no Ace plumbing needed.
        ns.FeatureBase = {
            new = function(_, name)
                return {
                    moduleName    = name,
                    Enable        = function() end,
                    Disable       = function() end,
                    IsEnabled     = function() return true end,
                    RegisterEvent = function() end,
                    UnregisterEvent = function() end,
                }
            end,
        }

        -- Load the feature – FeatureBase mock is captured at load time.
        MyFeatureModule = assert(loadfile("RPGLootFeed/Features/MyFeature.lua"))("TestAddon", ns)

        -- Inject default nil-returning adapters; individual tests override as needed:
        --   MyFeatureModule._someApiAdapter = { GetThing = function() return mockData end }
        MyFeatureModule._someApiAdapter = { GetThing = function() return nil end }
        MyFeatureModule._globalStringsAdapter = { GetLabel = function() return "Test Label" end }
    end)
end)
```

**Key rules for this pattern:**

- No manual `require` of `LuaCompat`, `WoWGlobals`, `WoWGlobals.Functions`, `WoWGlobals.Enum`, `WoWGlobals.Constants`, or any `WoWGlobals.namespaces.*` — all pre-loaded by `.busted` helper
- Build `ns` as a plain table — include only what the feature's "External dependency locals" block references
- `SendMessage` and `LogWarn` should be `spy.new(function() end)` so event tests can assert against them without needing stub cleanup
- Methods that some tests override (e.g. `IsRetail`) can be plain `function() end` — tests use `stub(ns, "IsRetail").returns(...)` and revert afterward
- Provide `ns.db` manually — never rely on AceDB being initialised
- Inline `ns.FeatureBase` stub so AceAddon is never invoked
- Inject fresh adapter tables _after_ `loadfile` (they're module-level fields, not captured locals)
- For modules migrated to `fromPayload()` architecture: include `WoWAPI = { ModuleName = {} }` in `ns` so the shared adapter reference resolves at load time. Tests still override `Module._repAdapter` (or equivalent) directly in `before_each`.
- Spy on `Module:BuildPayload` instead of `Module.Element:new` for migrated modules (e.g. Reputation)
- `G_RLF.db` is intentionally excluded from dependency locals in feature files — always runtime
- **Always capture the module from the `loadfile` return value** — see [Module Return Convention](#module-return-convention) below

### Module Return Convention

Every implementation module **must** end with a `return` of its public table in addition to (or instead of) registering itself on `G_RLF`. WoW ignores file return values at runtime, so the `return` statement has zero in-game cost — it exists solely to support testing via `loadfile`.

**Implementation side** (`*.lua`):

```lua
-- Register on the namespace for runtime WoW access:
G_RLF.MyModule = MyModule

-- Return for test loadfile capture:
return MyModule
```

**Spec side** (`*_spec.lua`) — always capture directly from `loadfile`, never read back off `ns`:

```lua
-- Correct: capture from return value
MyModule = assert(loadfile("RPGLootFeed/path/to/MyModule.lua"))("TestAddon", ns)

-- Wrong: reading off ns after the fact obscures intent and breaks if the
-- registration key ever changes
assert(loadfile("RPGLootFeed/path/to/MyModule.lua"))("TestAddon", ns)
MyModule = ns.MyModule  -- ← avoid this
```

All existing feature modules (`Reputation.lua`, `Currency.lua`, `LegacyChatParsingImpl.lua`, etc.) already follow this convention.

### FeatureBase Tests

`FeatureBase` itself is tested with an even simpler plain `ns` table (no nsMocks at all):

```lua
before_each(function()
    ns = { RLF = { NewModule = function() end } }
    newModuleStub = stub(ns.RLF, "NewModule").returns(mockModule)
    assert(loadfile("RPGLootFeed/Features/_Internals/FeatureBase.lua"))("TestAddon", ns)
end)
```

### Load Order Testing

The mock system provides load sections that simulate the addon's load order:

```lua
-- Available load sections
nsMocks.LoadSections = {
    Utils = 1,
    ConfigOptions = 2,
    ConfigFeatureItemLoot = 3.01,
    ConfigFeatureCurrency = 3.03,
    -- ... more sections
    ConfigFeaturesAll = 3.99,
    Config = 4,
    BlizzOverrides = 5,
    Features = 6,
    LootDisplay = 7,
    GameTesting = 8,
    All = 100,
}
```

**Usage**:

```lua
-- Load up to and including Utils section
local ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.Utils)

-- Load everything
local ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
```

### Testing Configuration Modules

Config modules define options and defaults. Test that they're properly structured:

```lua
describe("CurrencyConfig", function()
    local ns

    before_each(function()
        ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigOptions)
        assert(loadfile("RPGLootFeed/config/Features/CurrencyConfig.lua"))("TestAddon", ns)
    end)

    it("should define defaults", function()
        assert.is_not_nil(ns.defaults.global.currency)
        assert.is_boolean(ns.defaults.global.currency.enabled)
    end)

    it("should define options", function()
        assert.is_not_nil(ns.options.args.features.args.currencyConfig)
        assert.are.equal(ns.options.args.features.args.currencyConfig.type, "group")
    end)
end)
```

### Testing Utility Functions

Pure functions are the easiest to test:

```lua
describe("Utils", function()
    local ns, Utils

    before_each(function()
        ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.Utils)
        Utils = assert(loadfile("RPGLootFeed/utils/Utils.lua"))("TestAddon", ns)
    end)

    it("should format RGB to hex", function()
        local hex = ns:RGBAToHexFormat(1, 0.5, 0, 1)
        assert.are.equal(hex, "|cffff8000")
    end)

    it("should parse item link", function()
        local itemID = ns:GetItemIDFromLink("|Hitem:12345|h[Item]|h")
        assert.are.equal(itemID, "12345")
    end)
end)
```

## Test Coverage

**Current Coverage**: Limited (see coverage reports in `luacov-html/`)

**Goal**: Increase coverage as testing infrastructure improves

**Coverage Command**:

```bash
make test-cov
```

Generates an HTML report at `luacov-html/index.html` showing which lines are covered by tests.

## Limitations of Current Testing

### WoW API Dependencies

Many addon features depend on WoW APIs that don't exist outside the game client:

- `C_Item.GetItemInfo()`
- `C_CurrencyInfo.GetCurrencyInfo()`
- Frame creation (`CreateFrame`)
- Event registration

**Current Approach**: Mock these APIs in `_mocks/` when possible, but many can't be fully mocked.

**Future Improvement**: Consider using `wowless` when it becomes more stable.

### UI Testing

Testing UI behavior (frame positioning, animations, user interactions) is difficult without the game client.

**Current Approach**: Manual in-game testing with Test Mode.

### Integration Testing

Testing how features work together is challenging in a unit test environment.

**Current Approach**: In-game integration tests via Test Mode.

## In-Game Testing

### Test Mode

**Access**: `/rlf test` or toggle in configuration UI

**Purpose**: Generate sample loot messages to preview the loot feed

**Features**:

- Shows all loot types (items, currency, money, XP, etc.)
- Cycles through different item qualities
- Tests animations and styling
- No actual loot required

**When to Use**:

- Developing new features
- Adjusting styling or positioning
- Verifying configuration changes
- Demonstrating features to users

### GameTestRunner

**Location**: `RPGLootFeed/GameTesting/GameTestRunner.lua`

A pure-Lua test runner class used by both smoke and integration tests. Has no WoW API dependencies itself, so it can be fully busted-tested.

**API**:

```lua
local runner = G_RLF.GameTestRunner:new("Suite Name", {
    printHeader = function(msg) G_RLF:Print(msg) end,
    printLine = print,
    raiseError = error,
})

runner:reset()                                    -- Clear all state
runner:section("Group Name")                      -- Start a named section (flushes previous section's dots)
runner:assertEqual(actual, expected, "test name")  -- Record equality assertion
runner:runTestSafely(fn, "test name", ...)         -- pcall wrapper that records pass/fail
runner:displayResults()                            -- Print results, raise error if failures
```

**Sections**: When `section()` is used, each section's dot summary is printed with a label prefix. Counts accumulate across sections. Non-sectioned mode prints one flat dot line.

### Smoke Tests (Alpha Only)

**Location**: `RPGLootFeed/GameTesting/SmokeTest.lua`

**Trigger**: Runs automatically on addon load in alpha builds (`--@alpha@` preprocessor block).

**Purpose**: Quick programmatic validations that don't render UI — catch environmental and structural issues at login.

**Sections**:

| Section                   | What it validates                                                                                                                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **WoW Globals**           | WoW API functions, global strings, CVar access, item/currency info                                                                    |
| **Module Registration**   | All FeatureModule, SupportModule, and BlizzModule enum values resolve via `GetModule()`                                               |
| **Feature Enabled State** | If DB config says disabled, module reports `IsEnabled() == false`                                                                     |
| **DB Structure**          | Required top-level config tables exist, metadata fields present, each feature has `enabled` boolean                                   |
| **Migration Integrity**   | All migration versions 1..N registered with `:run()`, DB version matches highest                                                      |
| **LootDisplay Frame**     | MainLootFrame exists with correct `frameType`, party frame presence matches config                                                    |
| **TestMode Data**         | Structure of cached test items, currencies, factions (graceful with async loading)                                                    |
| **Element Constructors**  | Data-free features (XP, Money, Professions, TravelPoints) return valid elements; data-dependent (ItemLoot, Currency) tested if cached |
| **Locale**                | AceLocale table populated, critical config keys spot-checked                                                                          |
| **Event Handlers**        | Each enabled feature module has expected WoW event handler methods                                                                    |

### Integration Tests (Alpha Only)

**Location**: `RPGLootFeed/GameTesting/IntegrationTest.lua`

**Trigger**: Runs automatically after all test data is initialized (items cached, currencies loaded, factions resolved, LootDisplay ready).

**Purpose**: Visual integration tests that render loot rows in the feed for manual inspection. Allows adjusting settings and re-running to verify visual changes.

**Command**: `/rlf test integration` (re-runs on demand)

### Manual Testing Scenarios

When making changes, test these scenarios in-game:

#### Item Loot

- Kill enemies and loot items
- Test different item qualities
- Test party/raid loot
- Test loot while in different group types

#### Currency

- Complete quests or activities that award currency
- Test with multiple currencies
- Test warband currencies (if applicable)

#### Money

- Loot money from enemies
- Test different money amounts (copper, silver, gold)

#### Reputation

- Complete quests or kill mobs that grant reputation
- Test different faction standings
- Test major factions (Dragonflight+)

#### Professions

- Craft items or gather resources
- Test skill-up notifications
- Test different professions

#### Experience

- Complete quests or kill enemies
- Test with max-level characters (should not show)

#### Transmog

- Loot items with new transmog appearances
- Test transmog sound and visual effects

#### Travel Points

- Discover new flight points
- Test first discovery notification

### Integration Tests (Slash Command)

**Command**: `/rlf test integration`

Runs automated integration tests that render sample loot rows in the game client for visual inspection.

**Status**: Functional. Uses `GameTestRunner` with shared infrastructure from smoke tests. Fires after all test data (items, currencies, factions) is cached and `LootDisplay` signals readiness.

## Testing Best Practices

### When Writing Tests

1. **Test one thing per test**: Each `it()` block should verify one specific behavior
2. **Use descriptive names**: Test names should clearly state what's being tested
3. **Arrange, Act, Assert**: Structure tests with setup, execution, and verification
4. **Mock external dependencies**: Don't rely on real WoW APIs in unit tests
5. **Test edge cases**: Empty strings, nil values, boundary conditions

### When Adding Features

1. **Write tests first** (TDD) when possible: Define expected behavior before implementation
2. **Test pure functions thoroughly**: Logic without side effects is easiest to test
3. **Manual test in-game**: Always verify features work in the actual WoW client
4. **Document testing steps**: Add comments or documentation for manual testing procedures

### When Fixing Bugs

1. **Write a failing test** that reproduces the bug
2. **Fix the bug** and verify the test passes
3. **Manually verify** the fix in-game
4. **Add regression test** to prevent the bug from returning

## Future Testing Improvements

### Short Term

- [ ] Increase unit test coverage for utility functions
- [ ] Add more integration tests for configuration modules
- [ ] Improve mock system for WoW APIs
- [ ] Document manual testing procedures more thoroughly
- [ ] Add Reputation element constructor to smoke tests (requires Reputation data in TestMode)

### Long Term

- [ ] Investigate `wowless` for WoW API simulation
- [ ] Expand in-game integration test suite with more visual scenarios
- [ ] Set up continuous integration (CI) for automated test runs
- [ ] Achieve meaningful test coverage metrics (>60% for testable code)
- [ ] Add visual regression testing for UI changes

## Running Tests Locally

### Prerequisites

- Lua 5.1 or LuaJIT
- LuaRocks with busted and luacov installed (run `make lua_deps` to install from the rockspec)

### Commands

> **Important**: Do not run `busted` directly — it is installed under `~/.luarocks/bin` and is not on `$PATH`. Always use the `make` targets below.

```bash
# Run all tests
make test

# Run all tests with coverage
make test-cov

# Run a specific test file (verbose output)
make test-file FILE=RPGLootFeed_spec/utils/Utils_spec.lua

# Run tests matching a description pattern (verbose output)
make test-pattern PATTERN="Currency"

# Run only tests tagged with 'only'
make test-only

# Run tests for CI (TAP output + coverage)
make test-ci

# See all available targets
make help
```

### Interpreting Results

**Green dots (.)**: Passing tests
**Red F**: Failing tests
**Yellow P**: Pending tests (not yet implemented)

**Coverage Report**: Open `luacov-html/index.html` in a browser to see line-by-line coverage.

## Test-Driven Development (TDD) Workflow

When implementing new features using TDD:

1. **Write a failing test** describing the desired behavior
2. **Run tests** to confirm it fails (red)
3. **Implement minimal code** to make the test pass
4. **Run tests** to confirm it passes (green)
5. **Refactor** code while keeping tests passing
6. **Repeat** for next piece of functionality

**Benefits**:

- Ensures code is testable
- Provides immediate feedback
- Acts as living documentation
- Prevents regressions

**When TDD Makes Sense**:

- Utility functions and data structures
- Configuration logic
- Data parsing and formatting
- Business logic without UI dependencies

**When TDD is Difficult**:

- UI-heavy features requiring WoW client
- Features heavily dependent on WoW APIs
- Animation and visual effects
- User interaction flows

For UI-heavy features, focus on extracting testable logic into separate functions and test those in isolation.
