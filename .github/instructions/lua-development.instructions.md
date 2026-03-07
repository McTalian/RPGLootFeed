---
name: Lua Development Conventions
description: Core Lua coding standards and conventions for RPGLootFeed
applyTo: "**/*.lua"
---

# Lua Development Conventions

## File Path Convention

Always use forward slashes (`/`) in file paths — the WoW client interprets them correctly on all platforms.

```lua
local path = "Interface/AddOns/RPGLootFeed/file.lua"  -- correct
local path = "Interface\\AddOns\\RPGLootFeed\\file.lua"  -- wrong
```

## Guard Clause Convention

Use guards for **runtime concerns** only — not loading order.

**TOC loading**: Function definitions don't execute at load time. All TOC files finish loading before any function is _called_, so internal modules are always available when functions run.

### Use guards for:

- ✅ Blizzard APIs that may not exist in all client versions (`if C_TransmogCollection then`)
- ✅ Optional library dependencies (`if G_RLF.Masque then`)
- ✅ Async data not yet available from the server (`if not itemName then`)

### Don't guard:

- ❌ Our own modules — missing means a load order bug; let it error loudly
- ❌ Internal dependencies — guard hides the bug

### Quick Reference

| Check                             | Type       | Reasoning                               |
| --------------------------------- | ---------- | --------------------------------------- |
| `if not GetItemInfo(itemID) then` | ✅ Runtime | Async server load                       |
| `if C_CurrencyInfo then`          | ✅ Runtime | API may not exist in all versions       |
| `if G_RLF.Masque then`            | ✅ Runtime | Optional library                        |
| `if not G_RLF.LootDisplay then`   | ❌ Loading | LootDisplay.lua loads before Core.lua   |
| `if not G_RLF.db then`            | ❌ Loading | DB initialized in Core.lua OnInitialize |
| `if not G_RLF.Currency then`      | ❌ Loading | Currency.lua loads before most files    |

## Module Pattern

```lua
---@type string, table
local addonName, ns = ...

---@class G_RLF
local G_RLF = ns

---@class MyModule
local MyModule = {}

local someState = {}  -- private module state

function MyModule:PublicFunction()
  -- Implementation
end

local function privateHelper()  -- file-local, not exposed
end

G_RLF.MyModule = MyModule  -- register for cross-module access
```

## Accessing Shared Utilities

```lua
-- Logging
G_RLF.Logger:Debug("message", value)
G_RLF.Logger:Info("message")
G_RLF.Logger:Error("message")

-- Notifications
G_RLF.Notifications:AddNotification("Title", "Message", "info")

-- Enums
local quality = G_RLF.ItemQualEnum.Epic
local frameType = G_RLF.Frames.MAIN

-- Utils
local hex = G_RLF:RGBAToHexFormat(r, g, b, a)
local itemID = G_RLF:GetItemIDFromLink(itemLink)

-- Database
local enabled = G_RLF.db.global.currency.enabled

-- LootDisplay
G_RLF.LootDisplay:EnqueueLoot(lootData, G_RLF.Frames.MAIN)
```

## Error Handling

```lua
-- Validate input at system boundaries
if not itemLink or type(itemLink) ~= "string" then
  G_RLF.Logger:Error("Invalid item link")
  return
end

-- Guard against missing external APIs
if not C_CurrencyInfo then
  return
end

-- Handle async item data
local itemName = C_Item.GetItemInfo(itemID)
if not itemName then
  C_Timer.After(0.5, function() self:ProcessItem(itemID) end)
  return
end
```

## Coding Style

- Variable and function names: `camelCase`
- Class and module names: `PascalCase`
- Constants/enums: `UPPER_SNAKE_CASE`
- Tabs for indentation
- No semicolons at end of statements
- Forward slashes in all file paths

## Localization

Use `G_RLF.L` for all user-facing strings:

```lua
-- Define in locale files
L["Enable Currency in Feed"] = "Enable Currency in Feed"

-- Use in code
local label = G_RLF.L["Enable Currency in Feed"]
local msg = string.format(G_RLF.L["You looted %s"], itemLink)
```

## Performance

- Cache repeated DB/table lookups; don't traverse deep paths in loops
- Use `table.concat` rather than string concatenation in loops
- Use AceBucket for rapid events — see `features.instructions.md`
- Pool and reuse frames — see `loot-display.instructions.md`

```lua
-- Good
local db = G_RLF.db.global.currency
local enabled = db.enabled

-- Bad - repeated table traversal
if G_RLF.db.global.currency.enabled then
  local color = G_RLF.db.global.currency.currencyTotalTextColor
end
```

## Validating Changes

```bash
make toc_check   # validate TOC file paths match disk
make dev         # build + copy to WoW (git-tracked files only; git add new files first)
make watch       # watch mode: auto-rebuild on change
make test        # run test suite
```

Run `make toc_check` after adding/removing files or changing XML imports. Use `make watch` during active development.

## See Also

- [Architecture](../docs/architecture.md)
- [Resources](../docs/resources.md)
- [Testing](../docs/testing.md)
- [Glossary](../docs/glossary.md) - WoW and addon terminology
