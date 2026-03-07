local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

describe("HistoryService", function()
	local HistoryService, mainFrame, partyFrame, G_RLF

	before_each(function()
		-- Set up a fake G_RLF environment
		G_RLF = {
			db = { global = { lootHistory = { enabled = true } } },
		}
		--
		mainFrame = {
			historyVisible = false,
			ShowHistoryFrame = function(self)
				self.historyVisible = true
			end,
			HideHistoryFrame = function(self)
				self.historyVisible = false
			end,
		}
		partyFrame = {
			historyVisible = false,
			ShowHistoryFrame = function(self)
				self.historyVisible = true
			end,
			HideHistoryFrame = function(self)
				self.historyVisible = false
			end,
		}
		G_RLF.RLF_MainLootFrame = mainFrame
		-- Provide LootDisplay:GetAllFrames() so HistoryService can iterate frames
		G_RLF.LootDisplay = {
			GetAllFrames = function()
				return pairs({ [1] = mainFrame, [2] = partyFrame })
			end,
		}

		-- Create a copy of HistoryService for testing
		assert(loadfile("RPGLootFeed/utils/HistoryService.lua"))("TestAddon", G_RLF)
		HistoryService = G_RLF.HistoryService
	end)

	it("toggles historyShown from false to true", function()
		HistoryService.historyShown = false
		mainFrame.historyVisible = false
		partyFrame.historyVisible = false

		HistoryService:ToggleHistoryFrame()

		assert.is_true(HistoryService.historyShown)
		assert.is_true(mainFrame.historyVisible)
		assert.is_true(partyFrame.historyVisible)
	end)

	it("toggles historyShown from true to false", function()
		HistoryService.historyShown = true
		mainFrame.historyVisible = true
		partyFrame.historyVisible = true

		HistoryService:ToggleHistoryFrame()

		assert.is_false(HistoryService.historyShown)
		assert.is_false(mainFrame.historyVisible)
		assert.is_false(partyFrame.historyVisible)
	end)

	it("does nothing when lootHistory is disabled", function()
		G_RLF.db.global.lootHistory.enabled = false
		HistoryService.historyShown = false
		mainFrame.historyVisible = false
		partyFrame.historyVisible = false

		HistoryService:ToggleHistoryFrame()

		assert.is_false(HistoryService.historyShown)
		assert.is_false(mainFrame.historyVisible)
		assert.is_false(partyFrame.historyVisible)
	end)

	it("hides history properly when HideHistoryFrame is called", function()
		HistoryService.historyShown = true
		mainFrame.historyVisible = true
		partyFrame.historyVisible = true

		HistoryService:HideHistoryFrame()

		assert.is_false(HistoryService.historyShown)
		assert.is_false(mainFrame.historyVisible)
		assert.is_false(partyFrame.historyVisible)
	end)
end)
