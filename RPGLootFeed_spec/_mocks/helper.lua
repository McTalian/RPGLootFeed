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

-- _G.Constants table (Constants.CurrencyConsts, etc.)
require("RPGLootFeed_spec._mocks.WoWGlobals.Constants")

-- WoW C_* namespace stubs (available as cache hits when specs capture
-- return values for spy access, e.g. itemMocks = require(...)).
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_Item")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_CurrencyInfo")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_TransmogCollection")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_CVar")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_ClassColor")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_GossipInfo")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_MajorFactions")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_PerksActivities")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_Reputation")
require("RPGLootFeed_spec._mocks.WoWGlobals.namespaces.C_DelvesUI")
