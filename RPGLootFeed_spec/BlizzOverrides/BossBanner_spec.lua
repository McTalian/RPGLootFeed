local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local mock = busted.mock
local spy = busted.spy
local stub = busted.stub

describe("BossBanner module", function()
	local ns, BossBannerOverride
	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)

		BossBannerOverride = assert(loadfile("RPGLootFeed/BlizzOverrides/BossBanner.lua"))("TestAddon", ns)
	end)

	describe("OnInitialize", function()
		it("registers PLAYER_ENTERING_WORLD event", function()
			spy.on(BossBannerOverride, "RegisterEvent")
			BossBannerOverride:OnInitialize()
			assert
				.spy(BossBannerOverride.RegisterEvent).was
				.called_with(BossBannerOverride, "PLAYER_ENTERING_WORLD", "BossBannerHook")
		end)
	end)

	it("hooks BossBanner OnEvent when available", function()
		spy.on(BossBannerOverride, "RawHookScript")
		BossBannerOverride:BossBannerHook()
		assert
			.spy(BossBannerOverride.RawHookScript).was
			.called_with(BossBannerOverride, BossBanner, "OnEvent", "InterceptBossBannerAlert")
	end)

	it("does not hook BossBanner OnEvent if already hooked", function()
		spy.on(BossBannerOverride, "IsHooked")
		spy.on(BossBannerOverride, "RawHookScript")
		BossBannerOverride.IsHooked = function()
			return true
		end
		BossBannerOverride:BossBannerHook()
		assert.spy(BossBannerOverride.RawHookScript).was.not_called()
	end)

	describe("InterceptBossBannerAlert", function()
		local spyOnEvent
		before_each(function()
			BossBannerOverride.hooks = { [BossBanner] = { OnEvent = function() end } }
			spyOnEvent = spy.on(BossBannerOverride.hooks[BossBanner], "OnEvent")
		end)

		it("completely skips BossBanner alert if fully disabled", function()
			local event = "ANYTHING"
			ns.db.global.blizzOverrides.bossBannerConfig = ns.DisableBossBanner.FULLY_DISABLE
			BossBannerOverride:InterceptBossBannerAlert(nil, event, nil, nil, nil, nil, nil, nil)
			assert.spy(spyOnEvent).was.not_called()
		end)

		it("does not show any loot if loot is disabled", function()
			local event = "ENCOUNTER_LOOT_RECEIVED"
			local myName = "MyPlayer"
			local playerName = "TestPlayer"
			ns.db.global.blizzOverrides.bossBannerConfig = ns.DisableBossBanner.DISABLE_LOOT
			BossBannerOverride:InterceptBossBannerAlert(nil, event, nil, nil, nil, nil, playerName, nil)
			BossBannerOverride:InterceptBossBannerAlert(nil, event, nil, nil, nil, nil, myName, nil)
			assert.spy(spyOnEvent).was.not_called()
		end)

		it("does not show my loot if my loot is disabled", function()
			local event = "ENCOUNTER_LOOT_RECEIVED"
			local myName = "MyPlayer"
			_G.GetNameAndServerNameFromGUID = function(s)
				return myName, nil
			end

			ns.db.global.blizzOverrides.bossBannerConfig = ns.DisableBossBanner.DISABLE_MY_LOOT
			BossBannerOverride:InterceptBossBannerAlert(nil, event, nil, nil, nil, nil, myName, nil)
			assert.spy(spyOnEvent).was.not_called()
		end)

		it("does not show group loot if group loot is disabled", function()
			local event = "ENCOUNTER_LOOT_RECEIVED"
			local playerName = "TestPlayer"
			local myName = "MyPlayer"
			_G.GetNameAndServerNameFromGUID = function()
				return myName, nil
			end

			ns.db.global.blizzOverrides.bossBannerConfig = ns.DisableBossBanner.DISABLE_GROUP_LOOT
			BossBannerOverride:InterceptBossBannerAlert(nil, event, nil, nil, nil, nil, playerName, nil)
			assert.spy(spyOnEvent).was.not_called()
			BossBannerOverride:InterceptBossBannerAlert(nil, event, nil, nil, nil, nil, myName, nil)
			assert.spy(spyOnEvent).was.called(1)
		end)
	end)
end)
