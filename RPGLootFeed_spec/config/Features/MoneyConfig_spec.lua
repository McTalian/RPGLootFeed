local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("MoneyConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		-- MoneyConfig comes after CurrencyConfig in features.xml
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeatureCurrency)
		assert(loadfile("RPGLootFeed/config/common/common.lua"))("TestAddon", ns)
		-- Load the MoneyConfig module
		assert(loadfile("RPGLootFeed/config/Features/MoneyConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the money configuration defaults", function()
		-- Check that the money configuration is set up in the defaults
		assert.is_table(ns.defaults.global.frames["**"].features.money)
		assert.is_boolean(ns.defaults.global.frames["**"].features.money.enabled)
		assert.is_boolean(ns.defaults.global.frames["**"].features.money.showMoneyTotal)
		assert.is_table(ns.defaults.global.frames["**"].features.money.moneyTotalColor)
		assert.is_not_nil(ns.defaults.global.frames["**"].features.money.moneyTextWrapChar)
		assert.is_boolean(ns.defaults.global.frames["**"].features.money.abbreviateTotal)
		assert.is_boolean(ns.defaults.global.frames["**"].features.money.accountantMode)
		assert.is_boolean(ns.defaults.global.frames["**"].features.money.overrideMoneyLootSound)
		assert.is_string(ns.defaults.global.frames["**"].features.money.moneyLootSound)
	end)

	it("should export a BuildMoneyArgs builder function", function()
		assert.is_function(ns.BuildMoneyArgs)
	end)

	it("should return a valid options group from BuildMoneyArgs", function()
		ns.db = {
			global = { frames = { [1] = { features = { money = ns.defaults.global.frames["**"].features.money } } } },
		}
		local group = ns.BuildMoneyArgs(1, 4)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(4, group.order)
		assert.is_table(group.args)
	end)

	it("should have correct color defaults for money total", function()
		local totalColor = ns.defaults.global.frames["**"].features.money.moneyTotalColor
		assert.is_table(totalColor)
		assert.equal(0.333, totalColor[1])
		assert.equal(0.333, totalColor[2])
		assert.equal(1.0, totalColor[3])
		assert.equal(1.0, totalColor[4])
	end)

	it("should use bar as default wrap character", function()
		assert.equal(ns.WrapCharEnum.BAR, ns.defaults.global.frames["**"].features.money.moneyTextWrapChar)
	end)

	it("should have required sound functions", function()
		ns.db = {
			global = { frames = { [1] = { features = { money = ns.defaults.global.frames["**"].features.money } } } },
		}
		local group = ns.BuildMoneyArgs(1, 4)
		local handler = group.handler
		assert.is_table(handler)
		assert.is_function(handler.OverrideSound)
	end)
end)
