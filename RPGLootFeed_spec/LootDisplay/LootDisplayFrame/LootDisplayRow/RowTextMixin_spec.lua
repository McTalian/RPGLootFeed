local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local rowFrameMocks = require("RPGLootFeed_spec._mocks.Internal.LootDisplayRowFrame")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local stub = busted.stub

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/RowTextMixin.lua"

describe("RLF_RowTextMixin", function()
	local ns, row

	-- Full styling/sizing db used by StyleText.  Fields listed match every
	-- property read by StyleText, StyleTopLeftText, and the layout section.
	local function makeDefaultStylingDb()
		return {
			fontFace = "Fonts/FRIZQT__.TTF",
			useFontObjects = false,
			font = {},
			fontSize = 14,
			secondaryFontSize = 11,
			topLeftIconFontSize = 10,
			fontShadowColor = { 0, 0, 0, 1 },
			fontShadowOffsetX = 1,
			fontShadowOffsetY = -1,
			leftAlign = true,
			enabledSecondaryRowText = false,
		}
	end

	local function makeDefaultSizingDb()
		return { padding = 4, iconSize = 32 }
	end

	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		assert(loadfile(MIXIN_FILE))("TestAddon", ns)
		row = rowFrameMocks.new()
		-- Mix mixin methods into the row so self:Method() calls inside the
		-- mixin (e.g. StyleText → CreateTopLeftText → StyleTopLeftText) resolve.
		for k, v in pairs(RLF_RowTextMixin) do
			row[k] = v
		end
		-- RGBAToHexFormat must return a string so ShowItemCountText can concat it.
		nsMocks.RGBAToHexFormat.returns("|cffffffff")
	end)

	-- ── Load order ─────────────────────────────────────────────────────────

	describe("load order", function()
		it("loads the file and exposes the global mixin table", function()
			assert.is_not_nil(_G.RLF_RowTextMixin)
			assert.is_function(RLF_RowTextMixin.StyleText)
			assert.is_function(RLF_RowTextMixin.ShowText)
			assert.is_function(RLF_RowTextMixin.ShowItemCountText)
			assert.is_function(RLF_RowTextMixin.UpdateSecondaryText)
		end)
	end)

	-- ── StyleText ──────────────────────────────────────────────────────────

	describe("StyleText", function()
		before_each(function()
			stub(ns.DbAccessor, "Styling").returns(makeDefaultStylingDb())
			stub(ns.DbAccessor, "Sizing").returns(makeDefaultSizingDb())
		end)

		it("calls SetFont on PrimaryText on the first call when not using font objects", function()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryText.SetFont).was.called(1)
		end)

		it("calls SetFont on all font strings on the first call", function()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryText.SetFont).was.called(1)
			assert.stub(row.ItemCountText.SetFont).was.called(1)
			assert.stub(row.SecondaryText.SetFont).was.called(1)
		end)

		it("skips SetFont on a re-call with identical values (cache hit)", function()
			RLF_RowTextMixin.StyleText(row)
			row.PrimaryText.SetFont:clear()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryText.SetFont).was_not.called()
		end)

		it("calls SetFont again when fontSize changes", function()
			RLF_RowTextMixin.StyleText(row)
			row.PrimaryText.SetFont:clear()
			ns.DbAccessor.Styling.returns(makeDefaultStylingDb())
			local db = makeDefaultStylingDb()
			db.fontSize = 18
			stub(ns.DbAccessor, "Styling").returns(db)
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryText.SetFont).was.called(1)
		end)

		describe("when useFontObjects is true", function()
			before_each(function()
				local db = makeDefaultStylingDb()
				db.useFontObjects = true
				db.font = {}
				stub(ns.DbAccessor, "Styling").returns(db)
			end)

			it("calls SetFontObject instead of SetFont on PrimaryText", function()
				RLF_RowTextMixin.StyleText(row)
				assert.stub(row.PrimaryText.SetFontObject).was.called(1)
				assert.stub(row.PrimaryText.SetFont).was_not.called()
			end)

			it("calls SetFontObject on all three text elements", function()
				RLF_RowTextMixin.StyleText(row)
				assert.stub(row.PrimaryText.SetFontObject).was.called(1)
				assert.stub(row.ItemCountText.SetFontObject).was.called(1)
				assert.stub(row.SecondaryText.SetFontObject).was.called(1)
			end)
		end)

		it("calls SetJustifyH on PrimaryText", function()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryText.SetJustifyH).was.called(1)
		end)

		it("calls SetPoint on PrimaryText based on layout", function()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryText.SetPoint).was.called()
		end)

		it("calls ItemCountText:SetPoint to anchor it relative to PrimaryText", function()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.ItemCountText.SetPoint).was.called(1)
		end)
	end)

	-- ── ShowText ───────────────────────────────────────────────────────────

	describe("ShowText", function()
		before_each(function()
			stub(ns.DbAccessor, "Styling").returns({
				enabledSecondaryRowText = false,
			})
		end)

		it("calls SetText on PrimaryText", function()
			RLF_RowTextMixin.ShowText(row, "Hello World")
			assert.stub(row.PrimaryText.SetText).was.called_with(row.PrimaryText, "Hello World")
		end)

		it("calls SetTextColor on PrimaryText", function()
			RLF_RowTextMixin.ShowText(row, "Hello", 0.5, 0.5, 0.5, 1)
			assert.stub(row.PrimaryText.SetTextColor).was.called(1)
		end)

		it("uses default white color when no color args are given", function()
			local r, g, b
			stub(row.PrimaryText, "SetTextColor", function(_, rr, gg, bb)
				r, g, b = rr, gg, bb
			end)
			RLF_RowTextMixin.ShowText(row, "Hello")
			assert.equal(1, r)
			assert.equal(1, g)
			assert.equal(1, b)
		end)

		it("uses red color when amount is negative and no color is given", function()
			local r, g, b
			stub(row.PrimaryText, "SetTextColor", function(_, rr, gg, bb)
				r, g, b = rr, gg, bb
			end)
			row.amount = -5
			RLF_RowTextMixin.ShowText(row, "-5g")
			assert.equal(1, r)
			assert.equal(0, g)
			assert.equal(0, b)
		end)

		it("sizes ClickableButton to match PrimaryText when link is set", function()
			row.link = "|Hitem:123|h[Foo]|h"
			RLF_RowTextMixin.ShowText(row, "Foo")
			assert.stub(row.ClickableButton.SetSize).was.called(1)
		end)

		it("does not resize ClickableButton when link is nil", function()
			row.link = nil
			RLF_RowTextMixin.ShowText(row, "Foo")
			assert.stub(row.ClickableButton.SetSize).was_not.called()
		end)

		it("shows SecondaryText when enabledSecondaryRowText is true and secondaryText is set", function()
			stub(ns.DbAccessor, "Styling").returns({ enabledSecondaryRowText = true })
			row.secondaryText = "Bonus"
			RLF_RowTextMixin.ShowText(row, "Main")
			assert.stub(row.SecondaryText.Show).was.called(1)
		end)

		it("hides SecondaryText when enabledSecondaryRowText is false", function()
			RLF_RowTextMixin.ShowText(row, "Main")
			assert.stub(row.SecondaryText.Hide).was.called(1)
		end)
	end)

	-- ── ShowItemCountText ──────────────────────────────────────────────────

	describe("ShowItemCountText", function()
		it("shows ItemCountText when count is a number greater than 1", function()
			RLF_RowTextMixin.ShowItemCountText(row, 5, { color = "|cffffffff" })
			assert.stub(row.ItemCountText.Show).was.called(1)
		end)

		it("does not show ItemCountText when count is 1 (no showSign)", function()
			RLF_RowTextMixin.ShowItemCountText(row, 1, { color = "|cffffffff" })
			assert.stub(row.ItemCountText.Show).was_not.called()
		end)

		it("shows ItemCountText when count is 1 and showSign is true", function()
			RLF_RowTextMixin.ShowItemCountText(row, 1, { color = "|cffffffff", showSign = true })
			assert.stub(row.ItemCountText.Show).was.called(1)
		end)

		it("includes a '+' prefix when showSign is true", function()
			local capturedText
			stub(row.ItemCountText, "SetText", function(_, t)
				capturedText = t
			end)
			RLF_RowTextMixin.ShowItemCountText(row, 5, { color = "|cffffffff", showSign = true })
			assert.truthy(capturedText:find("%+"))
		end)

		it("hides ItemCountText when count is nil", function()
			RLF_RowTextMixin.ShowItemCountText(row, nil, { color = "|cffffffff" })
			assert.stub(row.ItemCountText.Hide).was.called(1)
		end)

		it("shows ItemCountText when count is a non-empty string", function()
			RLF_RowTextMixin.ShowItemCountText(row, "Veteran", { color = "|cffffffff" })
			assert.stub(row.ItemCountText.Show).was.called(1)
		end)

		it("does not show ItemCountText when count is an empty string", function()
			RLF_RowTextMixin.ShowItemCountText(row, "", { color = "|cffffffff" })
			assert.stub(row.ItemCountText.Show).was_not.called()
		end)
	end)

	-- ── UpdateSecondaryText ────────────────────────────────────────────────

	describe("UpdateSecondaryText", function()
		it("sets secondaryText to nil when enabledSecondaryRowText is false", function()
			stub(ns.DbAccessor, "Styling").returns({ enabledSecondaryRowText = false })
			row.secondaryText = "stale"
			RLF_RowTextMixin.UpdateSecondaryText(row, nil)
			assert.is_nil(row.secondaryText)
		end)

		it("uses elementSecondaryText when present (ignores fn)", function()
			stub(ns.DbAccessor, "Styling").returns({ enabledSecondaryRowText = true })
			row.elementSecondaryText = "Soulbound"
			RLF_RowTextMixin.UpdateSecondaryText(row, function()
				return "from fn"
			end)
			assert.equal("Soulbound", row.secondaryText)
		end)

		it("uses the result of secondaryTextFn when elementSecondaryText is absent", function()
			stub(ns.DbAccessor, "Styling").returns({ enabledSecondaryRowText = true })
			row.amount = 100
			RLF_RowTextMixin.UpdateSecondaryText(row, function(amount)
				return tostring(amount) .. "g"
			end)
			assert.equal("100g", row.secondaryText)
		end)

		it("sets secondaryText to nil when secondaryTextFn returns empty string", function()
			stub(ns.DbAccessor, "Styling").returns({ enabledSecondaryRowText = true })
			RLF_RowTextMixin.UpdateSecondaryText(row, function()
				return ""
			end)
			assert.is_nil(row.secondaryText)
		end)

		it("sets secondaryText to nil when secondaryTextFn returns nil", function()
			stub(ns.DbAccessor, "Styling").returns({ enabledSecondaryRowText = true })
			RLF_RowTextMixin.UpdateSecondaryText(row, function()
				return nil
			end)
			assert.is_nil(row.secondaryText)
		end)
	end)

	-- ── CreateTopLeftText ──────────────────────────────────────────────────

	describe("CreateTopLeftText", function()
		before_each(function()
			stub(ns.DbAccessor, "Styling").returns(makeDefaultStylingDb())
		end)

		it("hides Icon.topLeftText after creation/styling", function()
			RLF_RowTextMixin.CreateTopLeftText(row)
			assert.stub(row.Icon.topLeftText.Hide).was.called(1)
		end)

		it("does not call CreateFontString when topLeftText already exists", function()
			RLF_RowTextMixin.CreateTopLeftText(row)
			assert.stub(row.Icon.CreateFontString).was_not.called()
		end)

		it("calls CreateFontString when topLeftText is nil (fresh row)", function()
			row.Icon.topLeftText = nil
			-- CreateFontString stub returns a fresh FontString mock so the
			-- follow-up SetPoint call on the result does not error.
			RLF_RowTextMixin.CreateTopLeftText(row)
			assert.stub(row.Icon.CreateFontString).was.called(1)
		end)
	end)
end)
