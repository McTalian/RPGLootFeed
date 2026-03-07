local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("ProfessionConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		-- ProfessionConfig comes after ReputationConfig in features.xml
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeatureRep)
		-- Load the ProfessionConfig module
		assert(loadfile("RPGLootFeed/config/Features/ProfessionConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the profession configuration defaults", function()
		-- Check that the profession configuration is set up in the defaults
		assert.is_table(ns.defaults.global.frames["**"].features.profession)
		assert.is_boolean(ns.defaults.global.frames["**"].features.profession.enabled)
		assert.is_boolean(ns.defaults.global.frames["**"].features.profession.showSkillChange)
		assert.is_table(ns.defaults.global.frames["**"].features.profession.skillColor)
		assert.is_not_nil(ns.defaults.global.frames["**"].features.profession.skillTextWrapChar)
	end)

	it("should export a BuildProfessionArgs builder function", function()
		assert.is_function(ns.BuildProfessionArgs)
	end)

	it("should return a valid options group from BuildProfessionArgs", function()
		ns.db = {
			global = {
				frames = { [1] = { features = { profession = ns.defaults.global.frames["**"].features.profession } } },
			},
		}
		local group = ns.BuildProfessionArgs(1, 7)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(7, group.order)
		assert.is_table(group.args)
	end)

	it("should have correct color defaults for skill text", function()
		local skillColor = ns.defaults.global.frames["**"].features.profession.skillColor
		assert.is_table(skillColor)
		assert.equal(0.333, skillColor[1])
		assert.equal(0.333, skillColor[2])
		assert.equal(1.0, skillColor[3])
		assert.equal(1.0, skillColor[4])
	end)

	it("should use brackets as default wrap character for skill text", function()
		assert.equal(ns.WrapCharEnum.BRACKET, ns.defaults.global.frames["**"].features.profession.skillTextWrapChar)
	end)
end)
