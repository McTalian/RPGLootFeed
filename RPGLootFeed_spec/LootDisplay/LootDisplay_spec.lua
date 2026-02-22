local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("LootDisplay module", function()
	local LootDisplayModule, ns
	before_each(function()
		-- Define the global G_RLF
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		local mockQueue = {
			enqueue = spy.new(function() end),
			dequeue = spy.new(function() end),
			peek = spy.new(function() end),
			isEmpty = spy.new(function()
				return true
			end),
			size = spy.new(function()
				return 0
			end),
		}
		nsMocks.Queue.new.returns(mockQueue)

		-- Load the list module before each test
		LootDisplayModule = assert(loadfile("RPGLootFeed/LootDisplay/LootDisplay.lua"))("TestAddon", ns)
	end)

	it("creates the module", function()
		assert.is_not_nil(LootDisplayModule)
	end)
end)
