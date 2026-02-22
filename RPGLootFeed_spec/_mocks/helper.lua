--- Busted suite-wide helper — loaded once before any spec runs.
---
--- Establishes global polyfills and WoW API stubs that every spec needs,
--- so individual spec files don't have to repeat these requires.

-- Lua 5.1 compatibility shims (unpack, format globals).
require("RPGLootFeed_spec._mocks.LuaCompat")

-- Core WoW global stubs (BossBanner, EventRegistry, LootAlertSystem,
-- CreateColor, ACCOUNT_WIDE_FONT_COLOR, etc.)
require("RPGLootFeed_spec._mocks.WoWGlobals")

-- WoW global function stubs (RunNextFrame, CreateFrame, UnitClass,
-- GetExpansionLevel, errorhandler, etc.)
require("RPGLootFeed_spec._mocks.WoWGlobals.Functions")

-- _G.Enum table (Enum.ItemQuality, Enum.ItemBind, etc.)
require("RPGLootFeed_spec._mocks.WoWGlobals.Enum")
