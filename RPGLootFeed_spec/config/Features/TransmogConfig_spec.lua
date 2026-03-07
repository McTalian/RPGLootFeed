local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("TransmogConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		-- TransmogConfig comes after TravelPointsConfig in features.xml
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeatureTravelPoints)
		-- Load the TransmogConfig module
		assert(loadfile("RPGLootFeed/config/Features/TransmogConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the transmog configuration defaults", function()
		assert.is_table(ns.defaults.global.frames["**"].features.transmog)
		assert.is_boolean(ns.defaults.global.frames["**"].features.transmog.enabled)
		assert.is_boolean(ns.defaults.global.frames["**"].features.transmog.enableTransmogEffect)
		assert.is_boolean(ns.defaults.global.frames["**"].features.transmog.enableBlizzardTransmogSound)
		assert.is_boolean(ns.defaults.global.frames["**"].features.transmog.enableIcon)
	end)

	it("should export a BuildTransmogArgs builder function", function()
		assert.is_function(ns.BuildTransmogArgs)
	end)

	it("should return a valid options group from BuildTransmogArgs", function()
		ns.db = {
			global = {
				frames = { [1] = { features = { transmog = ns.defaults.global.frames["**"].features.transmog } } },
			},
		}
		local group = ns.BuildTransmogArgs(1, 9)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(9, group.order)
		assert.is_table(group.args)
	end)

	it("should default transmog effect to enabled", function()
		assert.is_true(ns.defaults.global.frames["**"].features.transmog.enableTransmogEffect)
	end)

	it("should default blizzard transmog sound to enabled", function()
		assert.is_true(ns.defaults.global.frames["**"].features.transmog.enableBlizzardTransmogSound)
	end)
end)
