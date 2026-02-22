local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local rowFrameMocks = require("RPGLootFeed_spec._mocks.Internal.LootDisplayRowFrame")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local stub = busted.stub

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowUnitPortraitMixin.lua"

describe("RLF_RowUnitPortraitMixin", function()
	local ns, row

	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		assert(loadfile(MIXIN_FILE))("TestAddon", ns)
		row = rowFrameMocks.new()
	end)

	describe("load order", function()
		it("loads the file and exposes the global mixin table", function()
			assert.is_not_nil(_G.RLF_RowUnitPortraitMixin)
			assert.is_function(RLF_RowUnitPortraitMixin.StyleUnitPortrait)
		end)
	end)

	-- ── StyleUnitPortrait ──────────────────────────────────────────────────

	describe("StyleUnitPortrait", function()
		local sizingDb, stylingDb

		before_each(function()
			sizingDb = { iconSize = 40 }
			stylingDb = { leftAlign = true }
			stub(ns.DbAccessor, "Sizing").returns(sizingDb)
			stub(ns.DbAccessor, "Styling").returns(stylingDb)
		end)

		it("calls SetSize on UnitPortrait on the first call", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			assert.stub(row.UnitPortrait.SetSize).was.called(1)
		end)

		it("calls SetSize on RLFUser on the first call", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			assert.stub(row.RLFUser.SetSize).was.called(1)
		end)

		it("calls PerfPixel.PScale to derive portrait and icon sizes", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			-- PScale is called at least twice: once for portraitSize, once for rlfIconSize.
			assert.stub(nsMocks.PerfPixel.PScale).was.called()
		end)

		it("skips SetSize on a re-call with the same cached values", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			row.UnitPortrait.SetSize:clear()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			assert.stub(row.UnitPortrait.SetSize).was_not.called()
		end)

		it("calls SetSize again when iconSize changes", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			row.UnitPortrait.SetSize:clear()
			sizingDb.iconSize = 64
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			assert.stub(row.UnitPortrait.SetSize).was.called(1)
		end)

		it("calls SetSize again when leftAlign changes", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			row.UnitPortrait.SetSize:clear()
			stylingDb.leftAlign = false
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			assert.stub(row.UnitPortrait.SetSize).was.called(1)
		end)

		it("calls SetPoint on UnitPortrait to anchor it next to the Icon", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			assert.stub(row.UnitPortrait.SetPoint).was.called(1)
		end)

		it("calls ClearAllPoints on UnitPortrait when size changes", function()
			RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
			assert.stub(row.UnitPortrait.ClearAllPoints).was.called(1)
		end)

		describe("when self.unit is nil (no unit assigned)", function()
			it("hides UnitPortrait", function()
				row.unit = nil
				RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
				assert.stub(row.UnitPortrait.Hide).was.called(1)
			end)

			it("hides RLFUser", function()
				row.unit = nil
				RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
				assert.stub(row.RLFUser.Hide).was.called(1)
			end)
		end)

		describe("when self.unit is set and enablePartyAvatar is true", function()
			before_each(function()
				row.unit = "party1"
				ns.db.global.partyLoot.enablePartyAvatar = true
			end)

			it("shows UnitPortrait", function()
				RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
				assert.stub(row.UnitPortrait.Show).was.called(1)
			end)

			it("calls SetPortraitTexture via RunNextFrame", function()
				local fnMocks = require("RPGLootFeed_spec._mocks.WoWGlobals.Functions")
				fnMocks.SetPortraitTexture:clear()
				RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
				assert.stub(fnMocks.SetPortraitTexture).was.called(1)
			end)
		end)

		describe("when self.unit is set and enablePartyAvatar is false", function()
			before_each(function()
				row.unit = "party1"
				ns.db.global.partyLoot.enablePartyAvatar = false
			end)

			it("hides UnitPortrait", function()
				RLF_RowUnitPortraitMixin.StyleUnitPortrait(row)
				assert.stub(row.UnitPortrait.Hide).was.called(1)
			end)
		end)
	end)
end)
