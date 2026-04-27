local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("ExperienceConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		-- ExperienceConfig comes after MoneyConfig in features.xml
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeatureMoney)
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		-- Load the ExperienceConfig module
		assert(loadfile("RPGLootFeed/config/Features/ExperienceConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the experience configuration defaults", function()
		-- Check that the experience configuration is set up in the defaults
		assert.is_table(ns.defaults.global.frames["**"].features.experience)
		assert.is_boolean(ns.defaults.global.frames["**"].features.experience.enabled)
		assert.is_table(ns.defaults.global.frames["**"].features.experience.experienceTextColor)
		assert.is_boolean(ns.defaults.global.frames["**"].features.experience.showCurrentLevel)
		assert.is_table(ns.defaults.global.frames["**"].features.experience.currentLevelColor)
		assert.is_not_nil(ns.defaults.global.frames["**"].features.experience.currentLevelTextWrapChar)
	end)

	it("should export a BuildExperienceArgs builder function", function()
		assert.is_function(ns.BuildExperienceArgs)
	end)

	it("should return a valid options group from BuildExperienceArgs", function()
		ns.db = {
			global = {
				frames = { [1] = { features = { experience = ns.defaults.global.frames["**"].features.experience } } },
			},
		}
		local group = ns.BuildExperienceArgs(1, 5)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(5, group.order)
		assert.is_table(group.args)
	end)

	it("should have correct color defaults for experience text", function()
		local textColor = ns.defaults.global.frames["**"].features.experience.experienceTextColor
		assert.is_table(textColor)
		assert.equal(1, textColor[1])
		assert.equal(0, textColor[2])
		assert.equal(1, textColor[3])
		assert.equal(0.8, textColor[4])
	end)

	it("should have correct color defaults for current level", function()
		local levelColor = ns.defaults.global.frames["**"].features.experience.currentLevelColor
		assert.is_table(levelColor)
		assert.equal(0.749, levelColor[1])
		assert.equal(0.737, levelColor[2])
		assert.equal(0.012, levelColor[3])
		assert.equal(1, levelColor[4])
	end)

	it("should use angle brackets as default wrap character for current level", function()
		assert.equal(
			ns.WrapCharEnum.ANGLE,
			ns.defaults.global.frames["**"].features.experience.currentLevelTextWrapChar
		)
	end)
end)
