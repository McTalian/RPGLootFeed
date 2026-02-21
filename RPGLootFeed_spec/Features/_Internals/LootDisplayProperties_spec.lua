local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

describe("LootDisplayProperties module", function()
	local LootModule, ns

	before_each(function()
		-- Define the global G_RLF
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		-- Load the list module before each test
		LootModule = assert(loadfile("RPGLootFeed/Features/_Internals/LootDisplayProperties.lua"))("TestAddon", ns)
	end)

	it("LootModule is not nil", function()
		assert.is_not_nil(LootModule)
	end)
end)
