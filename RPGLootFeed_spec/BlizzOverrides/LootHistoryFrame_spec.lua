local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("LootHistoryFrame module", function()
	local ns, LootHistoryFrameOverride
	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		-- Ensure the global mock has Show/Hide methods for hooking.
		GroupLootHistoryFrame.Show = GroupLootHistoryFrame.Show or function() end
		GroupLootHistoryFrame.Hide = GroupLootHistoryFrame.Hide or function() end

		LootHistoryFrameOverride = assert(loadfile("RPGLootFeed/BlizzOverrides/LootHistoryFrame.lua"))("TestAddon", ns)
	end)

	describe("OnInitialize", function()
		it("registers PLAYER_ENTERING_WORLD event on Retail", function()
			ns.IsRetail = function()
				return true
			end
			spy.on(LootHistoryFrameOverride, "RegisterEvent")
			LootHistoryFrameOverride:OnInitialize()
			assert
				.spy(LootHistoryFrameOverride.RegisterEvent).was
				.called_with(LootHistoryFrameOverride, "PLAYER_ENTERING_WORLD", "LootHistoryFrameHook")
		end)

		it("registers LOOT_HISTORY_UPDATE_DROP for lazy hook on Retail", function()
			ns.IsRetail = function()
				return true
			end
			spy.on(LootHistoryFrameOverride, "RegisterEvent")
			LootHistoryFrameOverride:OnInitialize()
			assert
				.spy(LootHistoryFrameOverride.RegisterEvent).was
				.called_with(LootHistoryFrameOverride, "LOOT_HISTORY_UPDATE_DROP", "LootHistoryFrameHook")
		end)

		it("does not register event on non-Retail", function()
			ns.IsRetail = function()
				return false
			end
			spy.on(LootHistoryFrameOverride, "RegisterEvent")
			LootHistoryFrameOverride:OnInitialize()
			assert.spy(LootHistoryFrameOverride.RegisterEvent).was.not_called()
		end)
	end)

	it("hooks GroupLootHistoryFrame Show when available", function()
		spy.on(LootHistoryFrameOverride, "RawHook")
		LootHistoryFrameOverride:LootHistoryFrameHook()
		assert
			.spy(LootHistoryFrameOverride.RawHook).was
			.called_with(LootHistoryFrameOverride, GroupLootHistoryFrame, "Show", "InterceptGroupLootHistoryFrame", true)
	end)

	it("does not hook GroupLootHistoryFrame Show if already hooked", function()
		spy.on(LootHistoryFrameOverride, "RawHook")
		LootHistoryFrameOverride.IsHooked = function(_, frame, method)
			return frame == GroupLootHistoryFrame and method == "Show"
		end
		LootHistoryFrameOverride:LootHistoryFrameHook()
		assert.spy(LootHistoryFrameOverride.RawHook).was.not_called()
	end)

	it("hides the frame immediately after hooking when suppression is enabled", function()
		ns.db.global.blizzOverrides.disableGroupLootHistoryFrame = true
		local hideCalled = false
		GroupLootHistoryFrame.Hide = function()
			hideCalled = true
		end
		LootHistoryFrameOverride:LootHistoryFrameHook()
		assert.is_true(hideCalled)
	end)

	describe("InterceptGroupLootHistoryFrame", function()
		before_each(function()
			LootHistoryFrameOverride.hooks = { [GroupLootHistoryFrame] = { Show = function() end } }
		end)

		it("suppresses Show if disabled — does not call through", function()
			ns.db.global.blizzOverrides.disableGroupLootHistoryFrame = true
			local hideCalled = false
			GroupLootHistoryFrame.Hide = function()
				hideCalled = true
			end
			local showSpy = spy.on(LootHistoryFrameOverride.hooks[GroupLootHistoryFrame], "Show")
			LootHistoryFrameOverride:InterceptGroupLootHistoryFrame(GroupLootHistoryFrame)
			assert.spy(showSpy).was.not_called()
			assert.is_true(hideCalled)
		end)

		it("calls the original Show if not disabled", function()
			ns.db.global.blizzOverrides.disableGroupLootHistoryFrame = false
			local showSpy = spy.on(LootHistoryFrameOverride.hooks[GroupLootHistoryFrame], "Show")
			LootHistoryFrameOverride:InterceptGroupLootHistoryFrame(GroupLootHistoryFrame)
			assert.spy(showSpy).was.called(1)
		end)
	end)
end)
