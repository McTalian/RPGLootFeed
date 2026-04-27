local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("TravelPointsConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		-- TravelPointsConfig comes after ProfessionConfig in features.xml
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeatureSkills)
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		-- Load the TravelPointsConfig module
		assert(loadfile("RPGLootFeed/config/Features/TravelPointsConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the travel points configuration defaults", function()
		assert.is_table(ns.defaults.global.frames["**"].features.travelPoints)
		assert.is_boolean(ns.defaults.global.frames["**"].features.travelPoints.enabled)
		assert.is_table(ns.defaults.global.frames["**"].features.travelPoints.textColor)
		assert.is_boolean(ns.defaults.global.frames["**"].features.travelPoints.enableIcon)
	end)

	it("should export a BuildTravelPointsArgs builder function", function()
		assert.is_function(ns.BuildTravelPointsArgs)
	end)

	it("should return a valid options group from BuildTravelPointsArgs", function()
		ns.db = {
			global = {
				frames = {
					[1] = { features = { travelPoints = ns.defaults.global.frames["**"].features.travelPoints } },
				},
			},
		}
		local group = ns.BuildTravelPointsArgs(1, 8)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(8, group.order)
		assert.is_table(group.args)
	end)

	it("should have correct color defaults for travel points text", function()
		local textColor = ns.defaults.global.frames["**"].features.travelPoints.textColor
		assert.is_table(textColor)
		assert.equal(1, textColor[1])
		assert.equal(0.988, textColor[2])
		assert.equal(0.498, textColor[3])
		assert.equal(1, textColor[4])
	end)
end)
