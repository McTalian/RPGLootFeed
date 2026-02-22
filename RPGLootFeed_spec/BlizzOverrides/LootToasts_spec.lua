local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("LootToasts module", function()
	local ns, LootToastOverride
	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)

		LootToastOverride = assert(loadfile("RPGLootFeed/BlizzOverrides/LootToasts.lua"))("TestAddon", ns)
	end)

	describe("OnInitialize", function()
		it("registers PLAYER_ENTERING_WORLD event", function()
			spy.on(LootToastOverride, "RegisterEvent")
			LootToastOverride:OnInitialize()
			assert
				.spy(LootToastOverride.RegisterEvent).was
				.called_with(LootToastOverride, "PLAYER_ENTERING_WORLD", "LootToastHook")
		end)
	end)

	it("hooks LootAlertSystem AddAlert when available", function()
		spy.on(LootToastOverride, "RawHook")
		LootToastOverride:LootToastHook()
		assert
			.spy(LootToastOverride.RawHook).was
			.called_with(LootToastOverride, LootAlertSystem, "AddAlert", "InterceptAddAlert", true)
	end)

	it("does not hook LootAlertSystem AddAlert if already hooked", function()
		spy.on(LootToastOverride, "IsHooked")
		spy.on(LootToastOverride, "RawHook")
		LootToastOverride.IsHooked = function()
			return true
		end
		LootToastOverride:LootToastHook()
		assert.spy(LootToastOverride.RawHook).was.not_called()
	end)

	describe("InterceptAddAlert", function()
		before_each(function()
			LootToastOverride.hooks = { [LootAlertSystem] = { AddAlert = function() end } }
			spy.on(LootToastOverride.hooks[LootAlertSystem], "AddAlert")
		end)

		it("completely skips LootAlertSystem alert if disabled", function()
			ns.db.global.blizzOverrides.disableBlizzLootToasts = true
			local addAlertSpy = spy.on(LootToastOverride.hooks[LootAlertSystem], "AddAlert")
			LootToastOverride:InterceptAddAlert(nil)
			assert.spy(addAlertSpy).was.not_called()
		end)

		it("calls the original AddAlert function if not disabled", function()
			ns.db.global.blizzOverrides.disableBlizzLootToasts = false
			local addAlertSpy = spy.on(LootToastOverride.hooks[LootAlertSystem], "AddAlert")
			LootToastOverride:InterceptAddAlert(nil)
			assert.spy(addAlertSpy).was.called(1)
		end)
	end)
end)
