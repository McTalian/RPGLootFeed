local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("ItemConfig module", function()
	local ns, functionMocks
	setup(function()
		-- Define the global namespace
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeaturesInit)
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		functionMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.Functions")
		-- Load the ItemConfig module before each test
		assert(loadfile("RPGLootFeed/config/Features/ItemConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the item configuration defaults", function()
		-- Check that the item configuration is set up in the defaults
		assert.is_table(ns.defaults.global.frames["**"].features.itemLoot)
		assert.is_boolean(ns.defaults.global.frames["**"].features.itemLoot.enabled)
		assert.is_boolean(ns.defaults.global.frames["**"].features.itemLoot.itemCountTextEnabled)
		assert.is_table(ns.defaults.global.frames["**"].features.itemLoot.itemCountTextColor)
		assert.is_table(ns.defaults.global.frames["**"].features.itemLoot.itemQualitySettings)
		assert.is_table(ns.defaults.global.frames["**"].features.itemLoot.itemHighlights)
		assert.is_table(ns.defaults.global.frames["**"].features.itemLoot.sounds)
	end)

	it("should export a BuildItemLootArgs builder function", function()
		assert.is_function(ns.BuildItemLootArgs)
	end)

	it("should return a valid options group from BuildItemLootArgs", function()
		-- Set up mock per-frame DB
		ns.db = {
			global = {
				frames = { [1] = { features = { itemLoot = ns.defaults.global.frames["**"].features.itemLoot } } },
			},
		}
		local group = ns.BuildItemLootArgs(1, 5)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(5, group.order)
		assert.is_not_nil(group.name)
		assert.is_table(group.args)
	end)

	it("should set up item quality settings", function()
		-- Check that all item qualities are configured
		local qualities = ns.defaults.global.frames["**"].features.itemLoot.itemQualitySettings
		local qualityEnum = ns.ItemQualEnum

		assert.is_table(qualities[qualityEnum.Poor])
		assert.is_table(qualities[qualityEnum.Common])
		assert.is_table(qualities[qualityEnum.Uncommon])
		assert.is_table(qualities[qualityEnum.Rare])
		assert.is_table(qualities[qualityEnum.Epic])
		assert.is_table(qualities[qualityEnum.Legendary])
		assert.is_table(qualities[qualityEnum.Artifact])
		assert.is_table(qualities[qualityEnum.Heirloom])
	end)
end)
