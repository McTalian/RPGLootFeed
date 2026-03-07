local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it

describe("ConfigOptions module", function()
	local ns

	before_each(function()
		-- Define the global G_RLF
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.Utils)
		-- Load the list module before each test
		assert(loadfile("RPGLootFeed/config/ConfigOptions.lua"))("TestAddon", ns)
	end)

	describe("frames wildcard defaults", function()
		local wildcard

		before_each(function()
			wildcard = ns.defaults.global.frames["**"]
		end)

		it("registers a '**' wildcard key under defaults.global.frames", function()
			assert.is_not_nil(wildcard)
			assert.is_table(wildcard)
		end)

		it("provides a default name of empty string", function()
			assert.are.equal("", wildcard.name)
		end)

		describe("positioning defaults", function()
			it("has all positioning keys", function()
				local p = wildcard.positioning
				assert.is_not_nil(p)
				assert.are.equal("UIParent", p.relativePoint)
				assert.are.equal("BOTTOMLEFT", p.anchorPoint)
				assert.are.equal(720, p.xOffset)
				assert.are.equal(375, p.yOffset)
				assert.are.equal("MEDIUM", p.frameStrata)
			end)
		end)

		describe("sizing defaults", function()
			it("has all sizing keys", function()
				local s = wildcard.sizing
				assert.is_not_nil(s)
				assert.are.equal(330, s.feedWidth)
				assert.are.equal(10, s.maxRows)
				assert.are.equal(22, s.rowHeight)
				assert.are.equal(2, s.padding)
				assert.are.equal(18, s.iconSize)
			end)
		end)

		describe("styling defaults", function()
			it("has core styling keys", function()
				local s = wildcard.styling
				assert.is_not_nil(s)
				assert.are.equal(false, s.enabledSecondaryRowText)
				assert.are.equal("LEFT", s.textAlignment)
				assert.are.equal(true, s.growUp)
				assert.are.equal(1, s.rowBackgroundType)
				assert.are.equal("Friz Quadrata TT", s.fontFace)
				assert.are.equal(10, s.fontSize)
				assert.are.equal(8, s.secondaryFontSize)
			end)

			it("has font flags", function()
				local ff = wildcard.styling.fontFlags
				assert.is_not_nil(ff)
				assert.are.equal(true, ff[""])
				assert.are.equal(false, ff["OUTLINE"])
				assert.are.equal(false, ff["THICKOUTLINE"])
				assert.are.equal(false, ff["MONOCHROME"])
			end)
		end)

		describe("animations defaults", function()
			it("has enter animation defaults", function()
				local a = wildcard.animations
				assert.is_not_nil(a)
				assert.are.equal("fade", a.enter.type)
				assert.are.equal(0.3, a.enter.duration)
				assert.are.equal("left", a.enter.slide.direction)
			end)

			it("has exit animation defaults", function()
				local a = wildcard.animations
				assert.are.equal(false, a.exit.disable)
				assert.are.equal("fade", a.exit.type)
				assert.are.equal(1, a.exit.duration)
				assert.are.equal(5, a.exit.fadeOutDelay)
			end)

			it("has hover animation defaults", function()
				local a = wildcard.animations
				assert.are.equal(true, a.hover.enabled)
				assert.are.equal(0.25, a.hover.alpha)
				assert.are.equal(0.3, a.hover.baseDuration)
			end)

			it("has update animation defaults", function()
				local a = wildcard.animations
				assert.are.equal(false, a.update.disableHighlight)
				assert.are.equal(0.2, a.update.duration)
				assert.are.equal(false, a.update.loop)
			end)
		end)

		describe("feature defaults", function()
			it("has all 9 feature keys", function()
				local f = wildcard.features
				assert.is_not_nil(f)
				assert.is_not_nil(f.itemLoot)
				assert.is_not_nil(f.partyLoot)
				assert.is_not_nil(f.currency)
				assert.is_not_nil(f.money)
				assert.is_not_nil(f.experience)
				assert.is_not_nil(f.reputation)
				assert.is_not_nil(f.profession)
				assert.is_not_nil(f.travelPoints)
				assert.is_not_nil(f.transmog)
			end)

			it("defaults all features to disabled (Q13)", function()
				local f = wildcard.features
				assert.are.equal(false, f.itemLoot.enabled)
				assert.are.equal(false, f.partyLoot.enabled)
				assert.are.equal(false, f.currency.enabled)
				assert.are.equal(false, f.money.enabled)
				assert.are.equal(false, f.experience.enabled)
				assert.are.equal(false, f.reputation.enabled)
				assert.are.equal(false, f.profession.enabled)
				assert.are.equal(false, f.travelPoints.enabled)
				assert.are.equal(false, f.transmog.enabled)
			end)

			it("itemLoot has all sub-settings", function()
				local il = wildcard.features.itemLoot
				assert.are.equal(true, il.itemCountTextEnabled)
				assert.are.equal(2, il.itemCountTextWrapChar)
				assert.is_not_nil(il.itemQualitySettings)
				assert.is_not_nil(il.itemHighlights)
				assert.are.equal("None", il.auctionHouseSource)
				assert.are.equal("vendor", il.pricesForSellableItems)
				assert.is_not_nil(il.sounds)
				assert.is_not_nil(il.textStyleOverrides)
				assert.are.equal(true, il.enableIcon)
			end)

			it("partyLoot has all sub-settings", function()
				local pl = wildcard.features.partyLoot
				assert.is_not_nil(pl.itemQualityFilter)
				assert.are.equal(false, pl.hideServerNames)
				assert.are.equal(true, pl.onlyEpicAndAboveInRaid)
				assert.are.equal(true, pl.onlyEpicAndAboveInInstance)
				assert.are.equal(true, pl.enableIcon)
				assert.are.equal(true, pl.enablePartyAvatar)
			end)

			it("currency has all sub-settings", function()
				local c = wildcard.features.currency
				assert.are.equal(true, c.currencyTotalTextEnabled)
				assert.are.equal(2, c.currencyTotalTextWrapChar)
				assert.are.equal(0.7, c.lowerThreshold)
				assert.are.equal(0.9, c.upperThreshold)
				assert.are.equal(true, c.enableIcon)
			end)

			it("money has all sub-settings", function()
				local m = wildcard.features.money
				assert.are.equal(true, m.showMoneyTotal)
				assert.are.equal(6, m.moneyTextWrapChar)
				assert.are.equal(true, m.abbreviateTotal)
				assert.are.equal(false, m.accountantMode)
				assert.are.equal(false, m.onlyIncome)
				assert.are.equal(true, m.enableIcon)
			end)

			it("experience has all sub-settings", function()
				local x = wildcard.features.experience
				assert.are.equal(true, x.showCurrentLevel)
				assert.are.equal(5, x.currentLevelTextWrapChar)
				assert.are.equal(true, x.enableIcon)
			end)

			it("reputation has all sub-settings", function()
				local r = wildcard.features.reputation
				assert.are.equal(0.7, r.secondaryTextAlpha)
				assert.are.equal(true, r.enableRepLevel)
				assert.are.equal(5, r.repLevelTextWrapChar)
				assert.are.equal(true, r.enableIcon)
			end)

			it("profession has all sub-settings", function()
				local p = wildcard.features.profession
				assert.are.equal(true, p.showSkillChange)
				assert.are.equal(3, p.skillTextWrapChar)
				assert.are.equal(true, p.enableIcon)
			end)

			it("travelPoints has all sub-settings", function()
				local tp = wildcard.features.travelPoints
				assert.is_not_nil(tp.textColor)
				assert.are.equal(true, tp.enableIcon)
			end)

			it("transmog has all sub-settings", function()
				local t = wildcard.features.transmog
				assert.are.equal(true, t.enableTransmogEffect)
				assert.are.equal(true, t.enableBlizzardTransmogSound)
				assert.are.equal(true, t.enableIcon)
			end)
		end)
	end)
end)
