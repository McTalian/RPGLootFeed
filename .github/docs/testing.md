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
make test        # Run all tests
make test-watch  # Auto-run tests on file changes
make coverage    # Generate coverage report
```

### Mock System

**Location**: `RPGLootFeed_spec/_mocks/`

Contains mocks for WoW APIs and the addon namespace.

**Key Mock**: `Internal/addonNamespace.lua` - Provides a mock version of `G_RLF` with controlled load order simulation.

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

Feature modules expose their full dependency surface as locals at the top of the file and use `FeatureBase:new()` instead of `G_RLF.RLF:NewModule()` directly. This means tests can build `ns` as a plain hand-crafted table with **zero reliance on the `nsMocks` framework**. See `TravelPoints_spec.lua` and `Transmog_spec.lua` as reference implementations.

```lua
require("RPGLootFeed_spec._mocks.LuaCompat") -- unpack, format polyfills
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

- `require("RPGLootFeed_spec._mocks.LuaCompat")` at the top — provides `unpack` / `format` polyfills without loading anything else
- Build `ns` as a plain table — include only what the feature's "External dependency locals" block references
- `SendMessage` and `LogWarn` should be `spy.new(function() end)` so event tests can assert against them without needing stub cleanup
- Methods that some tests override (e.g. `IsRetail`) can be plain `function() end` — tests use `stub(ns, "IsRetail").returns(...)` and revert afterward
- Provide `ns.db` manually — never rely on AceDB being initialised
- Inline `ns.FeatureBase` stub so AceAddon is never invoked
- Inject fresh adapter tables _after_ `loadfile` (they're module-level fields, not captured locals)
- `G_RLF.db` is intentionally excluded from dependency locals in feature files — always runtime

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
make coverage
```

Opens an HTML report showing which lines are covered by tests.

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

**Command**: `/rlf test integration` (if implemented)

Runs automated integration tests within the game client.

**Status**: Currently limited. Future enhancement opportunity.

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

### Long Term

- [ ] Investigate `wowless` for WoW API simulation
- [ ] Develop in-game automated integration test suite
- [ ] Set up continuous integration (CI) for automated test runs
- [ ] Achieve meaningful test coverage metrics (>60% for testable code)
- [ ] Add visual regression testing for UI changes

## Running Tests Locally

### Prerequisites

- Lua 5.1 or LuaJIT
- Busted (install via LuaRocks: `luarocks install busted`)
- LuaCov (for coverage: `luarocks install luacov`)

### Commands

```bash
# Run all tests
make test

# Run tests in watch mode (auto-rerun on changes)
make test-watch

# Generate coverage report
make coverage

# Run specific test file
busted RPGLootFeed_spec/utils/Utils_spec.lua

# Run tests with verbose output
busted -v

# Run tests matching a pattern
busted --filter="Currency"
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
