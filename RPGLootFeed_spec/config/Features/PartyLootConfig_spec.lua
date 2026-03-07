local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("PartyLootConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeatureItemLoot)
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/common/db.utils.lua"))("TestAddon", ns)
		assert(loadfile("RPGLootFeed/config/common/styling.base.lua"))("TestAddon", ns)
		-- Load the PartyLootConfig module before each test
		assert(loadfile("RPGLootFeed/config/Features/PartyLootConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the party loot configuration defaults", function()
		-- Check that the party loot configuration is set up in the defaults
		local partyLootDefaults = ns.defaults.global.frames["**"].features.partyLoot
		assert.is_table(partyLootDefaults)
		assert.is_boolean(partyLootDefaults.enabled)
		assert.is_table(partyLootDefaults.itemQualityFilter)
		assert.is_table(partyLootDefaults.ignoreItemIds)
	end)

	it("should export a BuildPartyLootArgs builder function", function()
		assert.is_function(ns.BuildPartyLootArgs)
	end)

	it("should return a valid options group from BuildPartyLootArgs", function()
		-- Set up mock per-frame DB
		local partyLootDefaults = ns.defaults.global.frames["**"].features.partyLoot
		ns.db = { global = { frames = { [1] = { features = { partyLoot = partyLootDefaults } } } } }
		local group = ns.BuildPartyLootArgs(1, 3)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(3, group.order)
		assert.is_table(group.args)
		assert.is_table(group.args.partyLootOptions)
		-- Ensure no legacy separate frame option blocks
		assert.is_nil(group.args.partyLootOptions.args.positioning)
		assert.is_nil(group.args.partyLootOptions.args.sizing)
		assert.is_nil(group.args.partyLootOptions.args.styling)
	end)

	it("should register the PartyLootConfig handler", function()
		-- Check that the handler is registered
		assert.is_table(ns.ConfigHandlers.PartyLootConfig)
	end)
end)
