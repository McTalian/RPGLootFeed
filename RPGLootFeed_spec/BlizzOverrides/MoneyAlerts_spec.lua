local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

describe("MoneyAlerts module", function()
	local ns, MoneyAlertOverride
	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)

		MoneyAlertOverride = assert(loadfile("RPGLootFeed/BlizzOverrides/MoneyAlerts.lua"))("TestAddon", ns)
	end)

	describe("OnInitialize", function()
		it("registers PLAYER_ENTERING_WORLD event", function()
			spy.on(MoneyAlertOverride, "RegisterEvent")
			MoneyAlertOverride:OnInitialize()
			assert
				.spy(MoneyAlertOverride.RegisterEvent).was
				.called_with(MoneyAlertOverride, "PLAYER_ENTERING_WORLD", "MoneyAlertHook")
		end)
	end)

	it("hooks MoneyWonAlertSystem AddAlert when available", function()
		spy.on(MoneyAlertOverride, "RawHook")
		MoneyAlertOverride:MoneyAlertHook()
		assert
			.spy(MoneyAlertOverride.RawHook).was
			.called_with(MoneyAlertOverride, MoneyWonAlertSystem, "AddAlert", "InterceptMoneyAddAlert", true)
	end)

	it("does not hook MoneyWonAlertSystem AddAlert if already hooked", function()
		spy.on(MoneyAlertOverride, "IsHooked")
		spy.on(MoneyAlertOverride, "RawHook")
		MoneyAlertOverride.IsHooked = function()
			return true
		end
		MoneyAlertOverride:MoneyAlertHook()
		assert.spy(MoneyAlertOverride.RawHook).was.not_called()
	end)

	describe("InterceptMoneyAddAlert", function()
		before_each(function()
			MoneyAlertOverride.hooks = { [MoneyWonAlertSystem] = { AddAlert = function() end } }
			spy.on(MoneyAlertOverride.hooks[MoneyWonAlertSystem], "AddAlert")
		end)

		it("completely skips MoneyWonAlertSystem alert if disabled", function()
			ns.db.global.blizzOverrides.disableBlizzMoneyAlerts = true
			local addAlertSpy = spy.on(MoneyAlertOverride.hooks[MoneyWonAlertSystem], "AddAlert")
			MoneyAlertOverride:InterceptMoneyAddAlert(nil)
			assert.spy(addAlertSpy).was.not_called()
		end)

		it("calls the original AddAlert function if not disabled", function()
			ns.db.global.blizzOverrides.disableBlizzMoneyAlerts = false
			local addAlertSpy = spy.on(MoneyAlertOverride.hooks[MoneyWonAlertSystem], "AddAlert")
			MoneyAlertOverride:InterceptMoneyAddAlert(nil)
			assert.spy(addAlertSpy).was.called(1)
		end)
	end)
end)
