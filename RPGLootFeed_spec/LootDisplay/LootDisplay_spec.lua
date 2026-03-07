local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("LootDisplay module", function()
	local LootDisplayModule, ns

	local function makeFrameWithRow()
		local row = {
			UpdateQuantity = spy.new(function() end),
			BootstrapFromElement = spy.new(function() end),
		}
		local frame = {
			Load = spy.new(function(self, id)
				self.frameType = id
			end),
			GetRow = spy.new(function()
				return row
			end),
			LeaseRow = spy.new(function()
				return nil
			end),
			UpdateQueueLabel = spy.new(function() end),
			-- Broker method: checks this frame's per-feature config
			IsFeatureEnabled = function(self, element)
				return LootDisplayFrameMixin.IsFeatureEnabled(self, element)
			end,
		}
		return frame, row
	end

	before_each(function()
		-- Define the global G_RLF
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)

		-- Load the LootDisplayFrame mixin so IsFeatureEnabled is available
		assert(loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayFrame.lua"))("TestAddon", ns)

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

	it("routes OnLootReady rows only to frames subscribed to that feature", function()
		local frame1, row1 = makeFrameWithRow()
		local frame2, row2 = makeFrameWithRow()

		local createCount = 0
		_G.CreateFrame = function()
			createCount = createCount + 1
			if createCount == 1 then
				return frame1
			end
			return frame2
		end

		ns.db.global.frames = {
			[ns.Frames.MAIN] = {
				features = {
					itemLoot = { enabled = true },
					partyLoot = { enabled = false },
				},
			},
			[2] = {
				features = {
					itemLoot = { enabled = false },
					partyLoot = { enabled = true },
				},
			},
		}

		LootDisplayModule:InitFrame(ns.Frames.MAIN)
		LootDisplayModule:InitFrame(2)

		local element = {
			type = ns.FeatureModule.ItemLoot,
			key = "sample_item",
			IsEnabled = function()
				return true
			end,
		}

		LootDisplayModule:OnLootReady(nil, element)

		assert.spy(row1.UpdateQuantity).was.called(1)
		assert.spy(row2.UpdateQuantity).was.called(0)
	end)

	it("routes party loot through unified OnLootReady to subscribed frames", function()
		local frame1, row1 = makeFrameWithRow()
		local frame2, row2 = makeFrameWithRow()

		local createCount = 0
		_G.CreateFrame = function()
			createCount = createCount + 1
			if createCount == 1 then
				return frame1
			end
			return frame2
		end

		ns.db.global.frames = {
			[ns.Frames.MAIN] = {
				features = {
					itemLoot = { enabled = true },
					partyLoot = { enabled = true },
				},
			},
			[2] = {
				features = {
					itemLoot = { enabled = false },
					partyLoot = { enabled = true },
				},
			},
		}

		LootDisplayModule:InitFrame(ns.Frames.MAIN)
		LootDisplayModule:InitFrame(2)

		local element = {
			type = ns.FeatureModule.PartyLoot,
			key = "sample_party",
			IsEnabled = function()
				return true
			end,
		}

		LootDisplayModule:OnLootReady(nil, element)

		assert.spy(row1.UpdateQuantity).was.called(1)
		assert.spy(row2.UpdateQuantity).was.called(1)
	end)

	it("ignores unknown loot element types in OnLootReady", function()
		local frame1, row1 = makeFrameWithRow()

		_G.CreateFrame = function()
			return frame1
		end

		ns.db.global.frames = {
			[ns.Frames.MAIN] = {
				features = {
					itemLoot = { enabled = true },
					partyLoot = { enabled = true },
				},
			},
		}

		LootDisplayModule:InitFrame(ns.Frames.MAIN)

		local element = {
			type = "UNKNOWN_FEATURE",
			key = "sample_unknown",
			IsEnabled = function()
				return true
			end,
		}

		LootDisplayModule:OnLootReady(nil, element)

		assert.spy(row1.UpdateQuantity).was.called(0)
	end)

	it("processes queued rows only for frame IDs passed to OnRowReturn", function()
		local frame1, row1 = makeFrameWithRow()
		local frame2, row2 = makeFrameWithRow()

		local createCount = 0
		_G.CreateFrame = function()
			createCount = createCount + 1
			if createCount == 1 then
				return frame1
			end
			return frame2
		end

		local elementMain = {
			type = ns.FeatureModule.ItemLoot,
			key = "queued_main",
			IsEnabled = function()
				return true
			end,
		}
		local elementParty = {
			type = ns.FeatureModule.ItemLoot,
			key = "queued_party",
			IsEnabled = function()
				return true
			end,
		}

		local mainDequeueSpy = spy.new(function()
			return elementMain
		end)
		local partyDequeueSpy = spy.new(function()
			return elementParty
		end)

		local mainQueue = {
			enqueue = spy.new(function() end),
			dequeue = mainDequeueSpy,
			peek = spy.new(function() end),
			isEmpty = spy.new(function()
				return false
			end),
			size = spy.new(function()
				return 1
			end),
		}
		local partyQueue = {
			enqueue = spy.new(function() end),
			dequeue = partyDequeueSpy,
			peek = spy.new(function() end),
			isEmpty = spy.new(function()
				return false
			end),
			size = spy.new(function()
				return 1
			end),
		}
		ns.Queue.new = function(_, _)
			if not mainQueue._claimed then
				mainQueue._claimed = true
				return mainQueue
			end
			return partyQueue
		end

		ns.db.global.frames = {
			[ns.Frames.MAIN] = {
				features = {
					itemLoot = { enabled = true },
					partyLoot = { enabled = true },
				},
			},
			[2] = {
				features = {
					itemLoot = { enabled = true },
					partyLoot = { enabled = true },
				},
			},
		}

		LootDisplayModule:InitFrame(ns.Frames.MAIN)
		LootDisplayModule:InitFrame(2)

		LootDisplayModule:OnRowReturn({ [ns.Frames.MAIN] = 1 })

		assert.spy(mainDequeueSpy).was.called(1)
		assert.spy(partyDequeueSpy).was.called(0)
		assert.spy(row1.UpdateQuantity).was.called(1)
		assert.spy(row2.UpdateQuantity).was.called(0)
	end)
end)
