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
			assert.is_function(RLF_RowTextMixin.ShowAmountText)
			assert.is_function(RLF_RowTextMixin.ShowItemCountText)
			assert.is_function(RLF_RowTextMixin.UpdateSecondaryText)
			assert.is_function(RLF_RowTextMixin.CreatePrimaryLineLayout)
			assert.is_function(RLF_RowTextMixin.LayoutPrimaryLine)
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
			assert.stub(row.AmountText.SetFont).was.called(1)
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

			it("calls SetFontObject on all four text elements", function()
				RLF_RowTextMixin.StyleText(row)
				assert.stub(row.PrimaryText.SetFontObject).was.called(1)
				assert.stub(row.AmountText.SetFontObject).was.called(1)
				assert.stub(row.ItemCountText.SetFontObject).was.called(1)
				assert.stub(row.SecondaryText.SetFontObject).was.called(1)
			end)
		end)

		it("calls SetJustifyH on PrimaryText", function()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryText.SetJustifyH).was.called(1)
		end)

		it("calls SetPoint on PrimaryLineLayout (icon anchor) based on layout", function()
			RLF_RowTextMixin.StyleText(row)
			assert.stub(row.PrimaryLineLayout.SetPoint).was.called()
		end)

		it("sets PrimaryLineLayout.childLayoutDirection to nil when leftAlign is true", function()
			RLF_RowTextMixin.StyleText(row)
			assert.is_nil(row.PrimaryLineLayout.childLayoutDirection)
		end)

		it("sets PrimaryLineLayout.childLayoutDirection to rightToLeft when leftAlign is false", function()
			local db = makeDefaultStylingDb()
			db.leftAlign = false
			stub(ns.DbAccessor, "Styling").returns(db)
			RLF_RowTextMixin.StyleText(row)
			assert.equal("rightToLeft", row.PrimaryLineLayout.childLayoutDirection)
		end)

		it("sets PrimaryLineLayout.spacing to iconSize/4", function()
			RLF_RowTextMixin.StyleText(row)
			assert.equal(8, row.PrimaryLineLayout.spacing) -- iconSize=32, 32/4=8
		end)
	end)

	-- ── ShowText ───────────────────────────────────────────────────────────

	describe("ShowText", function()
		before_each(function()
			stub(ns.DbAccessor, "Styling").returns({
				enabledSecondaryRowText = false,
			})
			stub(ns.DbAccessor, "Sizing").returns({ iconSize = 32, feedWidth = 200, padding = 4 })
			-- Stub LayoutPrimaryLine so ShowText tests focus on text/color logic only.
			-- LayoutPrimaryLine has its own dedicated describe block below.
			stub(row, "LayoutPrimaryLine")
		end)

		it("calls SetText on PrimaryText", function()
			RLF_RowTextMixin.ShowText(row, "Hello World")
			assert.stub(row.PrimaryText.SetText).was.called_with(row.PrimaryText, "Hello World")
		end)

		it("stores the raw text in rawPrimaryText", function()
			RLF_RowTextMixin.ShowText(row, "Hello World")
			assert.equal("Hello World", row.rawPrimaryText)
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

		it("calls LayoutPrimaryLine to drive the layout pass", function()
			RLF_RowTextMixin.ShowText(row, "Foo")
			assert.stub(row.LayoutPrimaryLine).was.called(1)
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
	-- ── ShowAmountText ───────────────────────────────────────────────────────

	describe("ShowAmountText", function()
		before_each(function()
			stub(ns.DbAccessor, "Sizing").returns({ iconSize = 32, feedWidth = 200 })
			-- Isolate ShowAmountText from LayoutPrimaryLine.
			stub(row, "LayoutPrimaryLine")
			row.AmountText.IsShown = function()
				return false
			end
			row.ItemCountText.IsShown = function()
				return false
			end
			row.rawPrimaryText = "Some Item"
		end)

		it("shows AmountText and sets text when amountText is non-empty", function()
			RLF_RowTextMixin.ShowAmountText(row, "x3", 1, 1, 1, 1)
			assert.stub(row.AmountText.Show).was.called(1)
			assert.stub(row.AmountText.SetText).was.called_with(row.AmountText, "x3")
		end)

		it("sets text color matching the provided r/g/b/a", function()
			RLF_RowTextMixin.ShowAmountText(row, "x2", 0.5, 0.2, 0.8, 1)
			assert.stub(row.AmountText.SetTextColor).was.called_with(row.AmountText, 0.5, 0.2, 0.8, 1)
		end)

		it("hides AmountText when amountText is an empty string", function()
			RLF_RowTextMixin.ShowAmountText(row, "", 1, 1, 1, 1)
			assert.stub(row.AmountText.Hide).was.called(1)
			assert.stub(row.AmountText.Show).was_not.called()
		end)

		it("hides AmountText when amountText is nil", function()
			RLF_RowTextMixin.ShowAmountText(row, nil, 1, 1, 1, 1)
			assert.stub(row.AmountText.Hide).was.called(1)
			assert.stub(row.AmountText.Show).was_not.called()
		end)

		it("calls LayoutPrimaryLine after updating visibility", function()
			RLF_RowTextMixin.ShowAmountText(row, "x2", 1, 1, 1, 1)
			assert.stub(row.LayoutPrimaryLine).was.called(1)
		end)

		it("calls LayoutPrimaryLine even when hiding", function()
			RLF_RowTextMixin.ShowAmountText(row, "", 1, 1, 1, 1)
			assert.stub(row.LayoutPrimaryLine).was.called(1)
		end)
	end)
	-- ── ShowItemCountText ──────────────────────────────────────────────────

	describe("ShowItemCountText", function()
		before_each(function()
			stub(ns.DbAccessor, "Sizing").returns({ iconSize = 32, feedWidth = 200, padding = 4 })
			-- Isolate ShowItemCountText from LayoutPrimaryLine - tested separately.
			stub(row, "LayoutPrimaryLine")
		end)
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

		it("calls LayoutPrimaryLine after updating ItemCountText", function()
			RLF_RowTextMixin.ShowItemCountText(row, 5, { color = "|cffffffff" })
			assert.stub(row.LayoutPrimaryLine).was.called(1)
		end)
	end)

	-- ── LayoutPrimaryLine ──────────────────────────────────────────────

	describe("LayoutPrimaryLine", function()
		-- iconSize=32, feedWidth=200
		-- iconOffset = iconSize/4 + iconSize + iconSize/4 = 8+32+8 = 48
		-- availableWidth = 200 - 48 = 152 (no portrait)
		local ICON_SIZE = 32
		local FEED_WIDTH = 200
		local AVAILABLE_WIDTH = FEED_WIDTH - (ICON_SIZE + 2 * (ICON_SIZE / 4)) -- 152
		local SPACING = ICON_SIZE / 4 -- 8

		before_each(function()
			stub(ns.DbAccessor, "Sizing").returns({ iconSize = ICON_SIZE, feedWidth = FEED_WIDTH })
			row.rawPrimaryText = "Some Item Name"
			row.ItemCountText.IsShown = function()
				return false
			end
			row.ItemCountText.GetUnboundedStringWidth = function()
				return 40
			end
			row.AmountText.IsShown = function()
				return false
			end
			row.AmountText.GetUnboundedStringWidth = function()
				return 30
			end
			row.PrimaryLineLayout.spacing = SPACING
		end)

		-- ── Natural width fits within available space ──────────────────────

		it("uses natural width when text fits (no ItemCountText)", function()
			local NATURAL = 80 -- fits within 152
			row.PrimaryText.GetUnboundedStringWidth = function()
				return NATURAL
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryText.SetWidth).was.called_with(row.PrimaryText, NATURAL)
		end)

		it("uses natural width when text fits with ItemCountText shown", function()
			local COUNT_WIDTH = 40
			local NATURAL = 80 -- fits within 152-40-8 = 104
			row.ItemCountText.IsShown = function()
				return true
			end
			row.ItemCountText.GetUnboundedStringWidth = function()
				return COUNT_WIDTH
			end
			row.PrimaryText.GetUnboundedStringWidth = function()
				return NATURAL
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryText.SetWidth).was.called_with(row.PrimaryText, NATURAL)
		end)

		it("uses natural width when text fits with AmountText shown", function()
			local AMOUNT_WIDTH = 30
			local NATURAL = 80 -- fits within 152-30-8 = 114
			row.AmountText.IsShown = function()
				return true
			end
			row.AmountText.GetUnboundedStringWidth = function()
				return AMOUNT_WIDTH
			end
			row.PrimaryText.GetUnboundedStringWidth = function()
				return NATURAL
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryText.SetWidth).was.called_with(row.PrimaryText, NATURAL)
		end)

		-- ── Natural width exceeds budget → truncate ────────────────────────

		it("caps PrimaryText at availableWidth when text is wider than the row", function()
			local NATURAL = 200 -- wider than 152
			row.PrimaryText.GetUnboundedStringWidth = function()
				return NATURAL
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryText.SetWidth).was.called_with(row.PrimaryText, AVAILABLE_WIDTH)
		end)

		it("caps PrimaryText when ItemCountText is shown and text overflows remaining space", function()
			local COUNT_WIDTH = 40
			local MAX_PRIMARY = AVAILABLE_WIDTH - COUNT_WIDTH - SPACING -- 104
			local NATURAL = 150 -- wider than 104
			row.ItemCountText.IsShown = function()
				return true
			end
			row.ItemCountText.GetUnboundedStringWidth = function()
				return COUNT_WIDTH
			end
			row.PrimaryText.GetUnboundedStringWidth = function()
				return NATURAL
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryText.SetWidth).was.called_with(row.PrimaryText, MAX_PRIMARY)
		end)

		it("caps PrimaryText when AmountText is shown and text overflows remaining space", function()
			local AMOUNT_WIDTH = 30
			local MAX_PRIMARY = AVAILABLE_WIDTH - AMOUNT_WIDTH - SPACING -- 114
			local NATURAL = 150 -- wider than 114
			row.AmountText.IsShown = function()
				return true
			end
			row.AmountText.GetUnboundedStringWidth = function()
				return AMOUNT_WIDTH
			end
			row.PrimaryText.GetUnboundedStringWidth = function()
				return NATURAL
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryText.SetWidth).was.called_with(row.PrimaryText, MAX_PRIMARY)
		end)

		it("accounts for both AmountText and ItemCountText when both are shown", function()
			local AMOUNT_WIDTH = 30
			local COUNT_WIDTH = 40
			local MAX_PRIMARY = AVAILABLE_WIDTH - AMOUNT_WIDTH - SPACING - COUNT_WIDTH - SPACING -- 66
			local NATURAL = 150
			row.AmountText.IsShown = function()
				return true
			end
			row.AmountText.GetUnboundedStringWidth = function()
				return AMOUNT_WIDTH
			end
			row.ItemCountText.IsShown = function()
				return true
			end
			row.ItemCountText.GetUnboundedStringWidth = function()
				return COUNT_WIDTH
			end
			row.PrimaryText.GetUnboundedStringWidth = function()
				return NATURAL
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryText.SetWidth).was.called_with(row.PrimaryText, MAX_PRIMARY)
		end)

		-- ── Container and layout ───────────────────────────────────────────

		it("always sets PrimaryLineLayout.fixedWidth to availableWidth", function()
			row.PrimaryText.GetUnboundedStringWidth = function()
				return 80
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.equal(AVAILABLE_WIDTH, row.PrimaryLineLayout.fixedWidth)
		end)

		it("calls PrimaryLineLayout:Layout()", function()
			row.PrimaryText.GetUnboundedStringWidth = function()
				return 80
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.PrimaryLineLayout.Layout).was.called(1)
		end)

		-- ── ClickableButton ────────────────────────────────────────────────

		it("sets ClickableButton anchor and size when link is set", function()
			row.link = "|Hitem:123|h[Foo]|h"
			row.PrimaryText.GetUnboundedStringWidth = function()
				return 80
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.ClickableButton.SetSize).was.called(1)
			assert.stub(row.ClickableButton.SetPoint).was.called(1)
		end)

		it("does not touch ClickableButton when link is nil", function()
			row.link = nil
			row.PrimaryText.GetUnboundedStringWidth = function()
				return 80
			end
			RLF_RowTextMixin.LayoutPrimaryLine(row)
			assert.stub(row.ClickableButton.SetSize).was_not.called()
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
