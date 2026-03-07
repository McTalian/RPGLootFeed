---
name: Config — AceConfig Patterns
description: Configuration defaults, options tables, and handler patterns for RPGLootFeed config modules
applyTo: "RPGLootFeed/config/**/*.lua"
---

# AceConfig Patterns

## Defaults

```lua
---@class RLF_ConfigMyFeature
G_RLF.defaults.global.myFeature = {
  enabled = true,
  color = { 1, 1, 1, 1 },
  enableIcon = true,
}
```

## Options Table

```lua
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
        -- Trigger downstream updates if needed
      end,
    },
  },
}
```

## Handler Pattern

```lua
local MyFeatureConfig = {}

function MyFeatureConfig:GetEnabled()
  return G_RLF.db.global.myFeature.enabled
end

function MyFeatureConfig:SetEnabled(info, value)
  G_RLF.db.global.myFeature.enabled = value
  G_RLF.LootDisplay:UpdateRowStyles()
end
```

## Localization in Config

All `name`, `desc`, and display strings must use `G_RLF.L`:

```lua
name = G_RLF.L["Enable My Feature"],
desc = G_RLF.L["EnableMyFeatureDesc"],
```

See `locale/` for the string definitions.

## Migrations

Any change to the DB schema **must** have a corresponding migration script in `config/Migrations/`. See existing migrations for the pattern. This is required to avoid data loss on existing installations.
