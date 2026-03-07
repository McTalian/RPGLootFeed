local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local describe = busted.describe
local it = busted.it
local setup = busted.setup

describe("CurrencyConfig module", function()
	local ns
	setup(function()
		-- Define the global namespace
		-- CurrencyConfig comes after PartyLootConfig in features.xml
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.ConfigFeaturePartyLoot)
		-- Load the CurrencyConfig module
		assert(loadfile("RPGLootFeed/config/Features/CurrencyConfig.lua"))("TestAddon", ns)
	end)

	it("should set up the currency configuration defaults", function()
		-- Check that the currency configuration is set up in the defaults
		assert.is_table(ns.defaults.global.frames["**"].features.currency)
		assert.is_boolean(ns.defaults.global.frames["**"].features.currency.enabled)
		assert.is_boolean(ns.defaults.global.frames["**"].features.currency.currencyTotalTextEnabled)
		assert.is_table(ns.defaults.global.frames["**"].features.currency.currencyTotalTextColor)
		assert.is_not_nil(ns.defaults.global.frames["**"].features.currency.currencyTotalTextWrapChar)
		assert.is_number(ns.defaults.global.frames["**"].features.currency.lowerThreshold)
		assert.is_number(ns.defaults.global.frames["**"].features.currency.upperThreshold)
		assert.is_table(ns.defaults.global.frames["**"].features.currency.lowestColor)
		assert.is_table(ns.defaults.global.frames["**"].features.currency.midColor)
		assert.is_table(ns.defaults.global.frames["**"].features.currency.upperColor)
	end)

	it("should export a BuildCurrencyArgs builder function", function()
		assert.is_function(ns.BuildCurrencyArgs)
	end)

	it("should return a valid options group from BuildCurrencyArgs", function()
		ns.db = {
			global = {
				frames = { [1] = { features = { currency = ns.defaults.global.frames["**"].features.currency } } },
			},
		}
		local group = ns.BuildCurrencyArgs(1, 7)
		assert.is_table(group)
		assert.equal("group", group.type)
		assert.equal(7, group.order)
		assert.is_table(group.args)
	end)

	it("should have correct color defaults for currency text", function()
		local textColor = ns.defaults.global.frames["**"].features.currency.currencyTotalTextColor
		assert.is_table(textColor)
		assert.equal(0.737, textColor[1])
		assert.equal(0.737, textColor[2])
		assert.equal(0.737, textColor[3])
		assert.equal(1, textColor[4])
	end)

	it("should have correct threshold values", function()
		assert.equal(0.7, ns.defaults.global.frames["**"].features.currency.lowerThreshold)
		assert.equal(0.9, ns.defaults.global.frames["**"].features.currency.upperThreshold)
	end)

	it("should use parenthesis as default wrap character", function()
		assert.equal(
			ns.WrapCharEnum.PARENTHESIS,
			ns.defaults.global.frames["**"].features.currency.currencyTotalTextWrapChar
		)
	end)
end)
