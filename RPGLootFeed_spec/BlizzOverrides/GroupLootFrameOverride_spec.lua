local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("GroupLootFrameOverride module", function()
	local ns, GroupLootFrameOverride

	-- GroupLootFrame1–4 are the roll popup frames on both Retail and Classic.
	local rollFrames = {}
	before_each(function()
		for i = 1, 4 do
			rollFrames[i] = { Hide = function() end, Show = function() end }
			_G["GroupLootFrame" .. i] = rollFrames[i]
		end

		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		-- Default: feature config has disableLootRollFrame = false
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { disableLootRollFrame = false }
			end
		end

		GroupLootFrameOverride =
			assert(loadfile("RPGLootFeed/BlizzOverrides/GroupLootFrameOverride.lua"))("TestAddon", ns)
	end)

	after_each(function()
		for i = 1, 4 do
			_G["GroupLootFrame" .. i] = nil
		end
	end)

	describe("OnInitialize", function()
		it("registers PLAYER_ENTERING_WORLD on both clients", function()
			spy.on(GroupLootFrameOverride, "RegisterEvent")
			GroupLootFrameOverride:OnInitialize()
			assert
				.spy(GroupLootFrameOverride.RegisterEvent).was
				.called_with(GroupLootFrameOverride, "PLAYER_ENTERING_WORLD", "GroupLootFrameHook")
		end)

		it("registers LOOT_HISTORY_UPDATE_DROP for Retail lazy hook", function()
			spy.on(GroupLootFrameOverride, "RegisterEvent")
			GroupLootFrameOverride:OnInitialize()
			assert
				.spy(GroupLootFrameOverride.RegisterEvent).was
				.called_with(GroupLootFrameOverride, "LOOT_HISTORY_UPDATE_DROP", "AttemptLazyHook")
		end)

		it("registers START_LOOT_ROLL for Classic lazy hook", function()
			spy.on(GroupLootFrameOverride, "RegisterEvent")
			GroupLootFrameOverride:OnInitialize()
			assert
				.spy(GroupLootFrameOverride.RegisterEvent).was
				.called_with(GroupLootFrameOverride, "START_LOOT_ROLL", "AttemptLazyHook")
		end)
	end)

	describe("GroupLootFrameHook", function()
		it("hooks all four GroupLootFrame1-4 OnShow when available", function()
			spy.on(GroupLootFrameOverride, "RawHook")
			GroupLootFrameOverride:GroupLootFrameHook()
			assert.spy(GroupLootFrameOverride.RawHook).was.called(4)
			for i = 1, 4 do
				assert
					.spy(GroupLootFrameOverride.RawHook).was
					.called_with(GroupLootFrameOverride, rollFrames[i], "Show", "InterceptGroupLootFrame", true)
			end
		end)

		it("skips frames that are already hooked", function()
			spy.on(GroupLootFrameOverride, "RawHook")
			GroupLootFrameOverride.IsHooked = function(self, frame, event)
				return frame == rollFrames[2] and event == "Show"
			end
			GroupLootFrameOverride:GroupLootFrameHook()
			-- Only frames 1, 3, 4 should be hooked
			assert.spy(GroupLootFrameOverride.RawHook).was.called(3)
			assert
				.spy(GroupLootFrameOverride.RawHook).was
				.called_with(GroupLootFrameOverride, rollFrames[1], "Show", "InterceptGroupLootFrame", true)
			assert
				.spy(GroupLootFrameOverride.RawHook).was
				.called_with(GroupLootFrameOverride, rollFrames[3], "Show", "InterceptGroupLootFrame", true)
			assert
				.spy(GroupLootFrameOverride.RawHook).was
				.called_with(GroupLootFrameOverride, rollFrames[4], "Show", "InterceptGroupLootFrame", true)
		end)

		it("retries when no frames are available yet", function()
			for i = 1, 4 do
				_G["GroupLootFrame" .. i] = nil
			end
			local retryHookCalled = false
			ns.retryHook = function(...)
				retryHookCalled = true
				return 1
			end
			spy.on(GroupLootFrameOverride, "RawHook")
			GroupLootFrameOverride:GroupLootFrameHook()
			assert.spy(GroupLootFrameOverride.RawHook).was.not_called()
			assert.is_true(retryHookCalled)
		end)

		it("unregisters PLAYER_ENTERING_WORLD after successfully hooking", function()
			spy.on(GroupLootFrameOverride, "UnregisterEvent")
			GroupLootFrameOverride:GroupLootFrameHook()
			assert
				.spy(GroupLootFrameOverride.UnregisterEvent).was
				.called_with(GroupLootFrameOverride, "PLAYER_ENTERING_WORLD")
		end)
	end)

	describe("InterceptGroupLootFrame", function()
		it("suppresses OnShow when disableLootRollFrame is true", function()
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { disableLootRollFrame = true }
				end
			end
			local frame1 = rollFrames[1]
			local originalCalled = false
			GroupLootFrameOverride.hooks =
				{ [frame1] = {
					Show = function()
						originalCalled = true
					end,
				} }
			GroupLootFrameOverride:InterceptGroupLootFrame(frame1)
			assert.is_false(originalCalled)
		end)

		it("calls original OnShow when disableLootRollFrame is false", function()
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { disableLootRollFrame = false }
				end
			end
			local frame2 = rollFrames[2]
			local originalCalled = false
			GroupLootFrameOverride.hooks =
				{ [frame2] = {
					Show = function()
						originalCalled = true
					end,
				} }
			GroupLootFrameOverride:InterceptGroupLootFrame(frame2)
			assert.is_true(originalCalled)
		end)

		it("calls original OnShow when feature config is absent", function()
			ns.DbAccessor.AnyFeatureConfig = function()
				return nil
			end
			local frame1 = rollFrames[1]
			local originalCalled = false
			GroupLootFrameOverride.hooks =
				{ [frame1] = {
					Show = function()
						originalCalled = true
					end,
				} }
			GroupLootFrameOverride:InterceptGroupLootFrame(frame1)
			assert.is_true(originalCalled)
		end)
	end)
end)
