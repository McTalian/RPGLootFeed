---
name: BlizzOverrides — Hook Patterns
description: AceHook patterns and override conventions for Blizzard UI override modules
applyTo: "RPGLootFeed/BlizzOverrides/**/*.lua"
---

# Blizzard UI Override Patterns

## Module Purposes

| File              | Purpose                                       |
| ----------------- | --------------------------------------------- |
| `LootToasts.lua`  | Suppresses default Blizzard loot toast popups |
| `MoneyAlerts.lua` | Suppresses default money gain chat messages   |
| `BossBanner.lua`  | Modifies the boss kill/encounter banner       |
| `retryHook.lua`   | Retry logic for hooks that fire before load   |

## AceHook Patterns

```lua
-- Secure hook: your code runs AFTER the original function
self:SecureHook("BlizzardFunction", function(...)
  -- Additional behavior
end)

-- Hook with a named method
self:SecureHook("BlizzardFunction", "MyMethod")
function MyOverride:MyMethod(...)
  -- Handle hook
end

-- Unhook when disabling
self:Unhook("BlizzardFunction")
```

## API Availability

Always guard Blizzard functions that may not exist in all client versions:

```lua
if BlizzardFunction then
  self:SecureHook("BlizzardFunction", function(...) end)
end
```

Use `retryHook.lua` utilities when the target frame or function loads after the addon initializes.
