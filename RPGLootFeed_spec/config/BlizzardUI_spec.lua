local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

describe("BlizzardUI module", function()
	local ns
	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		assert(loadfile("RPGLootFeed/config/BlizzardUI.lua"))("TestAddon", ns)
	end)

	describe("defaults", function()
		it("sets enableAutoLoot to false", function()
			assert.is_false(ns.defaults.global.blizzOverrides.enableAutoLoot)
		end)

		it("sets disableBlizzLootToasts to false", function()
			assert.is_false(ns.defaults.global.blizzOverrides.disableBlizzLootToasts)
		end)

		it("sets disableBlizzMoneyAlerts to false", function()
			assert.is_false(ns.defaults.global.blizzOverrides.disableBlizzMoneyAlerts)
		end)

		it("sets disableGroupLootHistoryFrame to false", function()
			assert.is_false(ns.defaults.global.blizzOverrides.disableGroupLootHistoryFrame)
		end)

		it("sets bossBannerConfig to ENABLED", function()
			assert.are.equal(ns.DisableBossBanner.ENABLED, ns.defaults.global.blizzOverrides.bossBannerConfig)
		end)
	end)

	describe("options structure", function()
		it("creates the blizz options group at order 2", function()
			local blizz = ns.options.args.blizz
			assert.is_not_nil(blizz)
			assert.are.equal("group", blizz.type)
			assert.are.equal(2, blizz.order)
		end)

		it("has a lootBehavior inline group", function()
			local lootBehavior = ns.options.args.blizz.args.lootBehavior
			assert.is_not_nil(lootBehavior)
			assert.are.equal("group", lootBehavior.type)
			assert.is_true(lootBehavior.inline)
		end)

		it("has a chatFilters inline group", function()
			local chatFilters = ns.options.args.blizz.args.chatFilters
			assert.is_not_nil(chatFilters)
			assert.are.equal("group", chatFilters.type)
			assert.is_true(chatFilters.inline)
		end)
	end)

	describe("lootBehavior args", function()
		local function lootBehaviorArgs()
			return ns.options.args.blizz.args.lootBehavior.args
		end

		it("has enableAutoLoot toggle", function()
			assert.is_not_nil(lootBehaviorArgs().enableAutoLoot)
			assert.are.equal("toggle", lootBehaviorArgs().enableAutoLoot.type)
		end)

		it("has disableLootToast toggle", function()
			assert.is_not_nil(lootBehaviorArgs().disableLootToast)
			assert.are.equal("toggle", lootBehaviorArgs().disableLootToast.type)
		end)

		it("has disableMoneyAlert toggle", function()
			assert.is_not_nil(lootBehaviorArgs().disableMoneyAlert)
			assert.are.equal("toggle", lootBehaviorArgs().disableMoneyAlert.type)
		end)

		it("has disableGroupLootHistoryFrame toggle", function()
			assert.is_not_nil(lootBehaviorArgs().disableGroupLootHistoryFrame)
			assert.are.equal("toggle", lootBehaviorArgs().disableGroupLootHistoryFrame.type)
		end)

		it("has bossBanner select", function()
			assert.is_not_nil(lootBehaviorArgs().bossBanner)
			assert.are.equal("select", lootBehaviorArgs().bossBanner.type)
		end)
	end)

	describe("enableAutoLoot", function()
		local toggle
		before_each(function()
			toggle = ns.options.args.blizz.args.lootBehavior.args.enableAutoLoot
		end)

		it("get returns current db value", function()
			ns.db.global.blizzOverrides.enableAutoLoot = true
			assert.is_true(toggle.get({}))
		end)

		it("set updates db and calls SetCVar", function()
			local setCVarSpy = spy.on(C_CVar, "SetCVar")
			toggle.set({}, true)
			assert.is_true(ns.db.global.blizzOverrides.enableAutoLoot)
			assert.spy(setCVarSpy).was.called_with("autoLootDefault", "1")
		end)

		it("set to false calls SetCVar with 0", function()
			local setCVarSpy = spy.on(C_CVar, "SetCVar")
			toggle.set({}, false)
			assert.is_false(ns.db.global.blizzOverrides.enableAutoLoot)
			assert.spy(setCVarSpy).was.called_with("autoLootDefault", "0")
		end)
	end)

	describe("disableLootToast", function()
		local toggle
		before_each(function()
			toggle = ns.options.args.blizz.args.lootBehavior.args.disableLootToast
		end)

		it("get returns current db value", function()
			ns.db.global.blizzOverrides.disableBlizzLootToasts = true
			assert.is_true(toggle.get({}))
		end)

		it("set updates db value", function()
			toggle.set({}, true)
			assert.is_true(ns.db.global.blizzOverrides.disableBlizzLootToasts)
			toggle.set({}, false)
			assert.is_false(ns.db.global.blizzOverrides.disableBlizzLootToasts)
		end)
	end)

	describe("disableMoneyAlert", function()
		local toggle
		before_each(function()
			toggle = ns.options.args.blizz.args.lootBehavior.args.disableMoneyAlert
		end)

		it("get returns current db value", function()
			ns.db.global.blizzOverrides.disableBlizzMoneyAlerts = true
			assert.is_true(toggle.get({}))
		end)

		it("set updates db value", function()
			toggle.set({}, true)
			assert.is_true(ns.db.global.blizzOverrides.disableBlizzMoneyAlerts)
			toggle.set({}, false)
			assert.is_false(ns.db.global.blizzOverrides.disableBlizzMoneyAlerts)
		end)
	end)

	describe("disableGroupLootHistoryFrame", function()
		local toggle
		before_each(function()
			toggle = ns.options.args.blizz.args.lootBehavior.args.disableGroupLootHistoryFrame
		end)

		it("get returns current db value", function()
			ns.db.global.blizzOverrides.disableGroupLootHistoryFrame = true
			assert.is_true(toggle.get({}))
		end)

		it("set updates db value", function()
			toggle.set({}, true)
			assert.is_true(ns.db.global.blizzOverrides.disableGroupLootHistoryFrame)
			toggle.set({}, false)
			assert.is_false(ns.db.global.blizzOverrides.disableGroupLootHistoryFrame)
		end)

		it("is hidden on non-Retail", function()
			stub(ns, "IsRetail").returns(false)
			assert.is_true(toggle.hidden())
		end)

		it("is visible on Retail", function()
			-- IsRetail already returns true in the mock
			assert.is_false(toggle.hidden())
		end)
	end)

	describe("bossBanner", function()
		local select
		before_each(function()
			select = ns.options.args.blizz.args.lootBehavior.args.bossBanner
		end)

		it("get returns current db value", function()
			ns.db.global.blizzOverrides.bossBannerConfig = ns.DisableBossBanner.FULLY_DISABLE
			assert.are.equal(ns.DisableBossBanner.FULLY_DISABLE, select.get({}))
		end)

		it("set updates db value", function()
			select.set({}, ns.DisableBossBanner.DISABLE_LOOT)
			assert.are.equal(ns.DisableBossBanner.DISABLE_LOOT, ns.db.global.blizzOverrides.bossBannerConfig)
		end)

		it("has all five values", function()
			assert.is_not_nil(select.values[ns.DisableBossBanner.ENABLED])
			assert.is_not_nil(select.values[ns.DisableBossBanner.FULLY_DISABLE])
			assert.is_not_nil(select.values[ns.DisableBossBanner.DISABLE_LOOT])
			assert.is_not_nil(select.values[ns.DisableBossBanner.DISABLE_MY_LOOT])
			assert.is_not_nil(select.values[ns.DisableBossBanner.DISABLE_GROUP_LOOT])
		end)
	end)
end)
