local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("ReputationConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		-- ReputationConfig comes after ExperienceConfig in features.xml
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeatureXP)
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		-- Load the ReputationConfig module
		assert(loadfile("RPGLootFeed/config/Features/ReputationConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the reputation configuration defaults", function()
		-- Check that the reputation configuration is set up in the defaults
		assert.is_table(ns.defaults.global.frames["**"].features.reputation)
		assert.is_boolean(ns.defaults.global.frames["**"].features.reputation.enabled)
		assert.is_table(ns.defaults.global.frames["**"].features.reputation.defaultRepColor)
		assert.is_number(ns.defaults.global.frames["**"].features.reputation.secondaryTextAlpha)
		assert.is_boolean(ns.defaults.global.frames["**"].features.reputation.enableRepLevel)
		assert.is_table(ns.defaults.global.frames["**"].features.reputation.repLevelColor)
		assert.is_not_nil(ns.defaults.global.frames["**"].features.reputation.repLevelTextWrapChar)
	end)

	it("should export a BuildReputationArgs builder function", function()
		assert.is_function(ns.BuildReputationArgs)
	end)

	it("should return a valid options group from BuildReputationArgs", function()
		ns.db = {
			global = {
				frames = { [1] = { features = { reputation = ns.defaults.global.frames["**"].features.reputation } } },
			},
		}
		local group = ns.BuildReputationArgs(1, 6)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(6, group.order)
		assert.is_table(group.args)
	end)

	it("should have correct color defaults for reputation text", function()
		local repColor = ns.defaults.global.frames["**"].features.reputation.defaultRepColor
		assert.is_table(repColor)
		assert.equal(0.5, repColor[1])
		assert.equal(0.5, repColor[2])
		assert.equal(1, repColor[3])
	end)

	it("should have correct color defaults for reputation level text", function()
		local levelColor = ns.defaults.global.frames["**"].features.reputation.repLevelColor
		assert.is_table(levelColor)
		assert.equal(0.5, levelColor[1])
		assert.equal(0.5, levelColor[2])
		assert.equal(1, levelColor[3])
		assert.equal(1, levelColor[4])
	end)

	it("should have correct secondary text alpha", function()
		assert.equal(0.7, ns.defaults.global.frames["**"].features.reputation.secondaryTextAlpha)
	end)

	it("should use angle brackets as default wrap character for reputation level", function()
		assert.equal(ns.WrapCharEnum.ANGLE, ns.defaults.global.frames["**"].features.reputation.repLevelTextWrapChar)
	end)
end)
