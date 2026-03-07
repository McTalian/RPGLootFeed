---
name: WoW API & RPGLootFeed Context
description: WoW API terminology, namespace patterns, and module map for RPGLootFeed
applyTo: "**/*.lua"
---

# WoW API & RPGLootFeed Context

## Terminology Quick Reference

- **Item Link**: Clickable item format `|Hitem:id:...|h[Name]|h`
- **Item Quality**: Enum 0–8 (Poor → Heirloom)
- **Loot Feed**: The main display showing notifications in real-time
- **Main Frame**: Player's personal loot feed (`G_RLF.Frames.MAIN`)
- **Party Frame**: Group/raid members' feed (`G_RLF.Frames.PARTY`)
- **Queue**: Pending loot messages waiting to display
- **Row**: Individual loot notification displayed in the feed
- **Test Mode**: `/rlf test` — preview mode with sample loot

See [Glossary](../docs/glossary.md) for the complete reference.

## Namespace Access

```lua
local addonName, ns = ...
local G_RLF = ns

-- Enums
local quality = G_RLF.ItemQualEnum.Epic
local frame = G_RLF.Frames.MAIN

-- Configuration
local enabled = G_RLF.db.global.currency.enabled

-- Utilities
G_RLF.Logger:Debug("Message")
G_RLF:RGBAToHexFormat(r, g, b, a)

-- Modules
G_RLF.LootDisplay:EnqueueLoot(lootData)
G_RLF.Notifications:AddNotification(title, msg)
```

## Module Directory Map

```
utils/          G_RLF.Logger, G_RLF.Queue, G_RLF.Notifications
config/         G_RLF.options, G_RLF.defaults
Features/       ItemLoot, Currency, Money, Reputation, PartyLoot, ...
LootDisplay/    LootDisplay, LootDisplayFrame, LootDisplayRow, LootHistory
BlizzOverrides/ LootToasts, MoneyAlerts, BossBanner
```

## Event Handling Pattern

```lua
-- Feature modules mix in AceEvent
local MyFeature = G_RLF.RLF:NewModule("MyFeature", "AceEvent-3.0")

function MyFeature:OnEnable()
  self:RegisterEvent("SOME_EVENT")
end

function MyFeature:SOME_EVENT(event, arg1, arg2)
  -- Handler name must match event name
  if self:ShouldProcess(arg1) then
    self:ProcessData(arg1, arg2)
  end
end
```

## Loot Message Building

```lua
local lootData = {
  icon = iconTexture,
  text = formattedText,
  color = { r, g, b, a },
  link = itemLink,
  quantity = count,
}

G_RLF.LootDisplay:EnqueueLoot(lootData, G_RLF.Frames.MAIN)
-- Use G_RLF.Frames.PARTY for party member loot
```

## See Also

- [Architecture](../docs/architecture.md)
- [Glossary](../docs/glossary.md)
- [Resources](../docs/resources.md)
- [Testing](../docs/testing.md)
- `features.instructions.md` — C\_\* APIs, loot events, group detection
- `loot-display.instructions.md` — Frame APIs, animations, row pooling
- `config.instructions.md` — AceConfig options and handler patterns
- `blizz-overrides.instructions.md` — AceHook patterns
