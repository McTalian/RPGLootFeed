---
name: Lua Development Conventions
description: Lua coding standards and WoW addon patterns for RPGLootFeed
applyTo: "**/*.lua"
---

# Lua Development Conventions

## File Path Convention

**Always use forward slashes (`/`)** for file paths regardless of OS. The WoW client correctly interprets them on all platforms.

```lua
-- Good
local path = "Interface/AddOns/RPGLootFeed/file.lua"

-- Bad (breaks cross-platform)
local path = "Interface\\AddOns\\RPGLootFeed\\file.lua"
```

## Guard Clause Convention

Use guards strategically to handle **runtime concerns**, not loading order issues.

### TOC Loading Behavior

**Critical Understanding**: TOC files execute only root-level code when loading. Function definitions are just that - definitions. Functions execute later when called, after all TOC files have loaded.

```lua
-- This RUNS during file load (root-level code)
local addonName, ns = ...
local G_RLF = ns
local MyModule = {}

-- This is just DEFINED, doesn't execute until called
function MyModule:DoSomething()
  G_RLF.LootDisplay:Show()  -- Safe! LootDisplay loaded when this executes
end

-- This RUNS during file load (in Core.lua typically)
function RLF:OnInitialize()
  -- Initialization code that runs after all files loaded
end
```

**Load Order Strategy**:

- Early files (utils, config base): Define modules and functions
- Mid files (config modules, features): Define modules, register events, may call into earlier modules from functions
- **Core.lua loads LAST**: Executes root-level initialization chain

### Use Guards For (Runtime Concerns):

- ✅ **External APIs** - Blizzard APIs that may not exist in all client versions
- ✅ **Optional dependencies** - Libraries or addons that might not be loaded
- ✅ **Lazy UI elements** - Frames created on-demand, may not exist yet
- ✅ **Async data** - Item info that loads asynchronously from server

### Don't Use Guards For (Loading Order):

- ❌ **Our own modules** - If missing, it's a load order bug that should error immediately
- ❌ **Internal dependencies** - Let it error during testing to catch TOC ordering issues
- ❌ **Core initialization** - SavedVariables, database setup - initialize properly instead

### Why Let Internal Dependencies Error?

**Fail fast during testing** - If `G_RLF.LootDisplay` is nil when called, it means:

1. TOC file order is wrong (LootDisplay files should load earlier)
2. Root-level code is calling functions before modules are loaded (move to Core.lua OnInitialize)
3. A module wasn't properly registered in the namespace

Guarding would **hide the bug** and make it harder to diagnose. Let it error loudly during development.

**Examples:**

```lua
-- ✅ Good - external API guard (runtime concern)
if C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
  local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
end

-- ✅ Good - optional library guard (runtime concern)
if G_RLF.Masque then
  G_RLF.iconGroup:AddButton(button)
end

-- ✅ Good - async item data guard (runtime concern)
local itemName = C_Item.GetItemInfo(itemID)
if itemName then
  -- Item data loaded from server
else
  -- Still loading, handle gracefully
end

-- ✅ Good - no guard for internal modules (fail fast on bugs)
function MyFeature:ProcessLoot()
  G_RLF.LootDisplay:EnqueueLoot(lootData)  -- Let it error if LootDisplay isn't loaded
  G_RLF.Logger:Debug("Loot processed")     -- Let it error if Logger isn't loaded
end

-- ❌ Bad - hides loading order bug
function MyFeature:ProcessLoot()
  if not G_RLF.LootDisplay then  -- Masks real bug!
    return
  end
  G_RLF.LootDisplay:EnqueueLoot(lootData)
end
```

### Quick Reference: Runtime vs Loading Checks

| Check                             | Type       | Reasoning                                     |
| --------------------------------- | ---------- | --------------------------------------------- |
| `if not GetItemInfo(itemID) then` | ✅ Runtime | Item data loads async from server             |
| `if C_CurrencyInfo then`          | ✅ Runtime | API may not exist in all WoW versions         |
| `if G_RLF.Masque then`            | ✅ Runtime | Optional library dependency                   |
| `if not G_RLF.LootDisplay then`   | ❌ Loading | LootDisplay.lua loads before Core.lua         |
| `if not G_RLF.db then`            | ❌ Loading | Database initialized in Core.lua OnInitialize |
| `if not G_RLF.Currency then`      | ❌ Loading | Currency.lua loads before most files          |

**Rule of thumb**: If it's created by us during initialization or defined in our codebase, don't guard it. If it's external, optional, or loads asynchronously, guard it.

## Module Pattern

RPGLootFeed uses a namespace pattern for module organization:

```lua
---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class MyModule
local MyModule = {}

-- Module-local variables (private)
local someState = {}

-- Public API
function MyModule:PublicFunction()
  -- Implementation
end

-- Private helper (local to this file)
local function privateHelper()
  -- Not exposed outside module
end

-- Register in namespace if needed for cross-module access
G_RLF.MyModule = MyModule

return MyModule
```

## Accessing Shared Utilities

Common utilities are available in the G_RLF namespace:

```lua
local addonName, ns = ...
local G_RLF = ns

-- Logging
G_RLF.Logger:Debug("Debug message", value)
G_RLF.Logger:Info("Info message")
G_RLF.Logger:Error("Error message")

-- Notifications
G_RLF.Notifications:AddNotification("Title", "Message", "info")

-- Enums
local itemQuality = G_RLF.ItemQualEnum.Epic
local frameType = G_RLF.Frames.MAIN

-- Utils
local hex = G_RLF:RGBAToHexFormat(1, 0.5, 0, 1)
local itemID = G_RLF:GetItemIDFromLink(itemLink)

-- Database
local enabled = G_RLF.db.global.currency.enabled
G_RLF.db.global.positioning.xOffset = 100

-- LootDisplay
G_RLF.LootDisplay:EnqueueLoot(lootData, G_RLF.Frames.MAIN)
G_RLF.LootDisplay:UpdateRowStyles()
```

## WoW API Best Practices

### Event Registration with AceEvent

```lua
-- Register events in module's OnEnable
function MyFeature:OnEnable()
  self:RegisterEvent("CHAT_MSG_LOOT")
  self:RegisterEvent("CHAT_MSG_CURRENCY")
end

-- Event handler (method name matches event name)
function MyFeature:CHAT_MSG_LOOT(event, message, ...)
  -- Handle loot message
  local itemLink = message:match("|H(item:%d+:.-)|h")
  if itemLink then
    self:ProcessItem(itemLink)
  end
end
```

### Using AceBucket for Performance

```lua
-- Bucket rapid events for performance
function MyFeature:OnEnable()
  self:RegisterBucketEvent("CHAT_MSG_LOOT", 0.1, "ProcessLootBucket")
end

-- Handler receives table of all events in bucket
function MyFeature:ProcessLootBucket(events)
  for event, args in pairs(events) do
    local message = args[1]
    -- Process message
  end
end
```

### Delayed Execution with AceTimer

```lua
-- Schedule one-time delayed action
self:ScheduleTimer(function()
  -- Executes after 2 seconds
end, 2)

-- Schedule repeating timer
local timerHandle = self:ScheduleRepeatingTimer(function()
  -- Executes every 5 seconds
end, 5)

-- Cancel timer
self:CancelTimer(timerHandle)
```

### Hooking Blizzard Functions with AceHook

```lua
-- Secure hook (runs after original)
self:SecureHook("BlizzardFunction", function(...)
  -- Your code runs after BlizzardFunction
end)

-- Hook with method
self:SecureHook("BlizzardFunction", "MyMethod")
function MyFeature:MyMethod(...)
  -- Handle hook
end

-- Unhook when done
self:Unhook("BlizzardFunction")
```

### API Availability Checks

```lua
-- Check namespace exists
if not C_CurrencyInfo then
  return -- API not available in this client version
end

-- Check specific function (added in later patches)
if C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
  local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
end

-- Check for optional libraries
if G_RLF.Masque then
  -- Use Masque for button styling
end
```

## Error Handling

Always handle potential failures gracefully:

```lua
-- Protect API calls that might fail
local success, result = pcall(function()
  return C_Item.GetItemInfo(itemID)
end)
if success and result then
  -- Use result
else
  G_RLF.Logger:Debug("Item info not available yet")
end

-- Validate data before use
if not lootData or type(lootData) ~= "table" then
  G_RLF.Logger:Error("Invalid loot data")
  return
end

-- Check for required fields
if not lootData.itemLink or not lootData.count then
  G_RLF.Logger:Warn("Incomplete loot data")
  return
end
```

## Performance Considerations

- **Avoid excessive string concatenation** in loops (use table.concat)
- **Cache repeated lookups** (GetItemInfo, UnitName, etc.)
- **Use AceBucket** for rapid events (CHAT_MSG_LOOT in raids)
- **Pool and reuse frames** (LootDisplay uses row pooling)
- **Use locals** for frequently accessed values

```lua
-- Good - cache lookups
local db = G_RLF.db.global.currency
local enabled = db.enabled
local color = db.currencyTotalTextColor

-- Bad - repeated table lookups
if G_RLF.db.global.currency.enabled then
  local color = G_RLF.db.global.currency.currencyTotalTextColor
end

-- Good - build strings efficiently
local parts = {}
for i = 1, 100 do
  parts[i] = "item" .. i
end
local result = table.concat(parts, ",")

-- Bad - string concatenation in loop
local result = ""
for i = 1, 100 do
  result = result .. "item" .. i .. ","
end
```

## Coding Style

Follow RPGLootFeed conventions:

```lua
-- Variables and functions: camelCase
local itemCount = 5
local function processItem() end

-- Classes and modules: PascalCase
local ItemLoot = {}
local CurrencyConfig = {}

-- Constants: UPPER_SNAKE_CASE (in enums)
G_RLF.ItemQualEnum.EPIC

-- Tabs for indentation (configured in editor)
function MyFunction()
	local value = 10
	if value > 5 then
		DoSomething()
	end
end

-- No semicolons
local x = 5
local y = 10

-- Forward slashes in paths
local path = "Interface/AddOns/RPGLootFeed/Icons/logo.blp"
```

## Localization

Use `G_RLF.L` for all user-facing strings:

```lua
-- Define in locale files
L["Currency Config"] = "Currency Config"
L["Enable Currency in Feed"] = "Enable Currency in Feed"

-- Use in code
local optionName = G_RLF.L["Currency Config"]
local description = G_RLF.L["Enable Currency in Feed"]

-- String formatting with locale
local message = string.format(G_RLF.L["You looted %s"], itemLink)
```

## Configuration Best Practices

Follow established patterns for configuration:

```lua
-- Define defaults
---@class RLF_ConfigMyFeature
G_RLF.defaults.global.myFeature = {
	enabled = true,
	color = { 1, 1, 1, 1 },
	enableIcon = true,
}

-- Define options
G_RLF.options.args.features.args.myFeatureConfig = {
	type = "group",
	handler = MyFeatureConfig,
	name = G_RLF.L["My Feature Config"],
	order = G_RLF.mainFeatureOrder.MyFeature,
	args = {
		enabled = {
			type = "toggle",
			name = G_RLF.L["Enable My Feature"],
			desc = G_RLF.L["EnableMyFeatureDesc"],
			get = function()
				return G_RLF.db.global.myFeature.enabled
			end,
			set = function(_, value)
				G_RLF.db.global.myFeature.enabled = value
			end,
		},
	},
}
```

## Validating Changes

After editing Lua files, validate your changes before testing in-game:

**Quick validation** (syntax and structure):

```bash
make toc_check
```

- Validates TOC file paths match files on disk
- Checks for missing files in TOC tree
- Reports "orphaned" files not referenced in TOC

**Full validation** (build and copy to game):

```bash
make dev
```

- Runs `make toc_check` automatically
- Builds the addon
- Copies to WoW Addons directory
- **Important**: Only copies git-tracked files (run `git add` first for new files)

**Watch mode** (automatic rebuild):

```bash
make watch
```

- Watches for file changes
- Automatically runs `make dev` when changes detected
- Useful for rapid iteration during development
- Keep running in background while developing

**Best practice**:

- Run `make toc_check` after adding/removing files or changing XML imports
- Run `make dev` before testing in-game
- Use `make watch` during active development for instant feedback

## Testing

### Test Mode

Use Test Mode to preview features without actual loot:

```lua
-- In WoW client
/rlf test

-- Generates sample loot messages
-- Useful for:
-- - Previewing styling changes
-- - Testing animations
-- - Verifying configuration options
-- - Demonstrating features
```

### Manual Testing Checklist

- Test in solo, party, and raid contexts (if applicable)
- Test with different item qualities
- Test edge cases (nil values, missing data)
- Verify configuration options work
- Check for LUA errors with BugGrabber
- Test performance with high loot volume

## See Also

- [Architecture](../docs/architecture.md) - Full project structure and conventions
- [Resources](../docs/resources.md) - WoW API references and patterns
- [Testing](../docs/testing.md) - Testing strategy and guidelines
- [Glossary](../docs/glossary.md) - WoW and addon terminology
