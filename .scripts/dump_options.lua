--- Stage 1 dump script – serialize G_RLF.options to JSON.
---
--- Implemented as a busted spec so it reuses the existing package-path setup,
--- the .busted helper (WoW global stubs), and the mock infrastructure.
---
--- Usage:
---   make options-dump
---
--- Output:
---   .scripts/.output/options_dump.json

local busted = require("busted")
local describe = busted.describe
local it = busted.it
local assert = require("luassert")

describe("options dump", function()
	it("serializes G_RLF.options with resolved locale strings", function()
		local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")

		-- Bootstrap mock infrastructure through the Utils section.
		-- This gives us: locale (G_RLF.L), all enums, lsm stub, IsRetail stub,
		-- AceAddon skeleton, PScale, etc.  No config mocks yet – we load the
		-- real config files below.
		local ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.Utils)

		-- ---------------------------------------------------------------
		-- Step 3: Enrich mocks so function-valued `values` fields can resolve.
		-- These are set up BEFORE loading config files so closures that capture
		-- `lsm` or reference `G_RLF.AuctionIntegrations` see the richer stubs.
		-- ---------------------------------------------------------------

		-- LSM: add missing MediaType entries and replace the nil-returning stub
		-- with a function that returns representative sample tables per type.
		ns.lsm.MediaType.BACKGROUND = "background"
		ns.lsm.MediaType.BORDER = "border"
		ns.lsm.MediaType.SOUND = "sound"

		local LSM_SAMPLE = {
			font = {
				["Arial Narrow"] = "Fonts/ARIALN.TTF",
				["Friz Quadrata TT"] = "Fonts/FRIZQT__.TTF",
				["Morpheus"] = "Fonts/MORPHEUS.ttf",
				["Skurri"] = "Fonts/skurri.ttf",
			},
			background = {
				["Blizzard Dialog"] = "Interface/DialogFrame/UI-DialogBox-Background",
				["Marble"] = "Interface/FrameGeneral/UI-Background-Marble",
				["Solid"] = "Interface/Buttons/WHITE8X8",
			},
			border = {
				["Blizzard Dialog"] = "Interface/DialogFrame/UI-DialogBox-Border",
				["Blizzard Tooltip"] = "Interface/Tooltips/UI-Tooltip-Border",
				["None"] = "",
			},
			sound = {
				["Auction Window Open"] = "Sound/Interface/AuctionWindowOpen.ogg",
				["None"] = "",
				["Quest Complete"] = "Sound/Interface/QuestComplete.ogg",
			},
		}
		ns.lsm.HashTable = function(_, mediaType)
			return LSM_SAMPLE[mediaType] or {}
		end

		-- WoW API: GetFonts() returns an array of font-object names.
		-- The config picker filters and builds a name→name map from them.
		_G.GetFonts = function()
			return {
				"ChatFontNormal",
				"GameFontDisable",
				"GameFontDisableSmall",
				"GameFontHighlight",
				"GameFontHighlightSmall",
				"GameFontHighlightLarge",
				"GameFontNormal",
				"GameFontNormalSmall",
				"GameFontNormalLarge",
				"NumberFont_OutlineThick_Mono_15",
				"SystemFont_Shadow_Med1",
			}
		end

		-- AuctionIntegrations: a minimal stub so ItemConfig's values/get closures
		-- that call nilIntegration:ToString() or read numActiveIntegrations don't error.
		ns.AuctionIntegrations = {
			numActiveIntegrations = 0,
			activeIntegrations = {},
			activeIntegration = nil,
			nilIntegration = {
				ToString = function(_self)
					return "None"
				end,
			},
		}

		-- ---------------------------------------------------------------
		-- Load config files in the same order as config.xml / features.xml
		-- ---------------------------------------------------------------

		-- common/ must come first: ConfigCommon, DbUtils, StylingBase
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/common/db.utils.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/common/styling.base.lua"))("TestAddon", ns)

		-- Root options table
		assert(loadfile("RPGLootFeed/config/ConfigOptions.lua"))("TestAddon", ns)

		-- General tab
		assert(loadfile("RPGLootFeed/config/General.lua"))("TestAddon", ns)

		-- Feature configs (Features.lua creates options.args.lootFeeds)
		assert(loadfile("RPGLootFeed/config/Features/Features.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/ItemConfig.lua"))("TestAddon", ns)
		-- PartyLootConfig must be loaded before Positioning/Sizing/Styling
		-- because those call G_RLF.ConfigHandlers.PartyLootConfig:Get*Options()
		assert(loadfile("RPGLootFeed/config/Features/PartyLootConfig.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/CurrencyConfig.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/MoneyConfig.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/ExperienceConfig.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/ReputationConfig.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/ProfessionConfig.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/TravelPointsConfig.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Features/TransmogConfig.lua"))("TestAddon", ns)

		-- Top-level section configs
		assert(loadfile("RPGLootFeed/config/Positioning.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Sizing.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Styling.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/Animations.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/BlizzardUI.lua"))("TestAddon", ns)
		-- DbMigrations / DbAccessors / Migrations are not needed for the options dump
		assert(loadfile("RPGLootFeed/config/About.lua"))("TestAddon", ns)

		-- ---------------------------------------------------------------
		-- Build a fake live DB from defaults so that get()/hidden()/disabled()
		-- closures that reference G_RLF.db.global.* resolve real default values
		-- rather than indexing nil.
		-- ---------------------------------------------------------------
		local function deepCopy(orig)
			local copy
			if type(orig) == "table" then
				copy = {}
				for k, v in pairs(orig) do
					copy[deepCopy(k)] = deepCopy(v)
				end
			else
				copy = orig
			end
			return copy
		end
		ns.db = deepCopy(ns.defaults)

		-- ---------------------------------------------------------------
		-- Serialize
		-- ---------------------------------------------------------------
		local serializer = assert(loadfile(".scripts/aceconfig_serializer.lua"))()
		local json = serializer.dump(ns.options)

		-- Basic sanity checks: non-empty JSON that contains real locale strings
		assert.is_not_nil(json)
		assert.is_true(#json > 500, "Expected substantial JSON output, got " .. #json .. " bytes")

		-- "Toggle Test Mode" is the English string for G_RLF.L["Toggle Test Mode"]
		-- If locale strings were NOT resolved, we'd see the raw key instead.
		assert.truthy(
			json:find("Toggle Test Mode", 1, true),
			"Expected resolved locale string 'Toggle Test Mode' in JSON – locale may not have been loaded"
		)

		-- Stage 2: function evaluation – get()/hidden()/disabled() should produce
		-- _dynamic annotations rather than the bare [function] placeholder.
		assert.truthy(
			json:find('"_dynamic"', 1, true),
			"Expected _dynamic annotations from function evaluation – step 2 may not be active"
		)

		-- At least one _value should appear (e.g. a get() that returns a boolean default)
		assert.truthy(
			json:find('"_value"', 1, true),
			"Expected _value fields from evaluated get()/hidden()/disabled() functions"
		)

		-- ---------------------------------------------------------------
		-- Write output
		-- ---------------------------------------------------------------
		local outPath = ".scripts/.output/options_dump.json"
		local f, err = io.open(outPath, "w")
		if f then
			f:write(json)
			f:close()
			print(string.format("\n[options-dump] Wrote %d bytes to %s", #json, outPath))
		else
			-- Non-fatal: the spec still passes, but we warn loudly
			print(string.format("\n[options-dump] WARNING: could not open %s for writing: %s", outPath, tostring(err)))
			print("[options-dump] First 500 chars of JSON:\n" .. json:sub(1, 500))
		end
	end)
end)
