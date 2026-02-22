--- Shared mock row-frame builder for RowXxxMixin unit tests.
---
--- Constructs a fully-stubbed "self" table that satisfies the frame-element
--- surface expected by RowBackdropMixin, RowIconMixin, RowTextMixin,
--- RowUnitPortraitMixin, and RowTooltipMixin.
---
--- Usage:
---   local rowFrameMocks = require("RPGLootFeed_spec._mocks.Internal.LootDisplayRowFrame")
---
---   local row = rowFrameMocks.new()     -- frameType defaults to "MAIN"
---   local row = rowFrameMocks.new("PARTY")
---
--- All sub-elements are plain tables whose WoW methods are busted stubs, so
--- tests can assert against them:
---   assert.stub(row.Background.SetGradient).was.called()
---   assert.stub(row.SetBackdrop).was.called_with(match._)

local busted = require("busted")
local stub = busted.stub

local M = {}

--- Stubs a list of method names onto `tbl`, creating no-op functions as needed.
--- Returns `tbl` for chaining.
local function stubMethods(tbl, names)
	for _, name in ipairs(names) do
		if tbl[name] == nil then
			tbl[name] = function() end
		end
		stub(tbl, name)
	end
	return tbl
end

--- Minimal WoW layout/visibility methods shared by Texture, FontString, Frame.
local LAYOUT = {
	"SetSize",
	"SetPoint",
	"ClearAllPoints",
	"Show",
	"Hide",
	"SetShown",
	"SetAlpha",
}

--- Extra methods present on FontString elements.
local FONT = {
	"SetFont",
	"SetFontObject",
	"SetShadowColor",
	"SetShadowOffset",
	"SetTextColor",
	"SetText",
	"GetStringWidth",
	"GetStringHeight",
	"SetJustifyH",
}

--- Creates a mock Texture/Frame element with layout stubs.
local function mockTexture()
	return stubMethods({}, LAYOUT)
end

--- Creates a mock FontString element with layout + font stubs.
--- GetStringWidth/GetStringHeight return sensible defaults.
local function mockFontString()
	local fs = {}
	stubMethods(fs, LAYOUT)
	stubMethods(fs, FONT)
	fs.GetStringWidth:returns(100)
	fs.GetStringHeight:returns(20)
	return fs
end

--- Creates a mock AnimationGroup with Stop/Play/IsPlaying stubs,
--- plus optional sub-animation tables (noop, fadeOut) with SetStartDelay.
local function mockAnimationGroup()
	local ag = stubMethods({}, { "Stop", "Play", "IsPlaying" })
	ag.noop = stubMethods({}, { "SetStartDelay" })
	ag.fadeOut = stubMethods({}, { "SetStartDelay" })
	return ag
end

--- Creates a mock ItemButton (Icon) with all icon-specific stubs,
--- plus .topLeftText (FontString), .IconBorder (Texture).
local function mockItemButton()
	local btn = stubMethods({}, {
		-- Frame layout
		"SetSize",
		"SetPoint",
		"ClearAllPoints",
		"SetShown",
		-- Event handling (used by RowTooltipMixin)
		"SetScript",
		"RegisterEvent",
		"UnregisterEvent",
		-- ItemButton API
		"SetItem",
		"SetItemButtonTexture",
		"SetItemButtonQuality",
		"ClearDisabledTexture",
		"ClearNormalTexture",
		"ClearPushedTexture",
		"ClearHighlightTexture",
	})
	-- CreateFontString is called by RowTextMixin:CreateTopLeftText when
	-- topLeftText does not yet exist.  Stub with an implementation that returns
	-- a real FontString mock so callers can chain method calls on the result.
	stub(btn, "CreateFontString", function(_self, ...)
		return mockFontString()
	end)
	btn.topLeftText = mockFontString()
	btn.IconBorder = mockTexture()
	-- IconOverlay and ProfessionQualityOverlay are optional in-game (may be nil).
	-- Provide them here so tests that exercise UpdateIcon don't need to special-case.
	btn.IconOverlay = mockTexture()
	btn.ProfessionQualityOverlay = mockTexture()
	return btn
end

--- Creates a mock Button (ClickableButton) used by RowTooltipMixin.
local function mockButton()
	return stubMethods({}, {
		"SetSize",
		"SetPoint",
		"ClearAllPoints",
		"Show",
		"Hide",
		"SetScript",
		"RegisterEvent",
		"UnregisterEvent",
	})
end

--- Builds a fully-stubbed mock row frame suitable for testing all RowXxxMixins.
---
--- The returned table IS the "self" that mixin methods operate on.
--- Sub-element spy references are accessible by field name, e.g.:
---   row.Background.SetGradient   — Texture spy
---   row.Icon.SetSize             — ItemButton spy
---   row.PrimaryText.SetFont      — FontString spy
---   row.SetBackdrop              — BackdropTemplate-style self spy
---
--- @param frameType? string  Defaults to "MAIN"
--- @return table
function M.new(frameType)
	local row = {}
	row.frameType = frameType or "MAIN"

	-- ── Backdrop sub-elements (RowBackdropMixin) ──────────────────────────
	row.Background = stubMethods(mockTexture(), { "SetGradient" })
	row.HighlightBGOverlay = mockTexture()
	row.HighlightBorderTop = mockTexture()
	row.HighlightBorderBottom = mockTexture()
	row.HighlightBorderLeft = mockTexture()
	row.HighlightBorderRight = mockTexture()

	-- BackdropTemplate methods (provided by XML BackdropTemplateMixin in-game;
	-- the row frame inherits them via LootDisplayRowTemplate).
	stubMethods(row, { "SetBackdrop", "ClearBackdrop", "SetBackdropColor", "SetBackdropBorderColor" })

	-- ── Icon sub-element (RowIconMixin) ───────────────────────────────────
	row.Icon = mockItemButton()

	-- ── Text sub-elements (RowTextMixin) ──────────────────────────────────
	row.PrimaryText = mockFontString()
	row.ItemCountText = mockFontString()
	row.SecondaryText = mockFontString()

	-- ── Portrait sub-elements (RowUnitPortraitMixin) ──────────────────────
	row.UnitPortrait = mockTexture()
	row.RLFUser = mockTexture()

	-- ── Tooltip sub-element (RowTooltipMixin) ─────────────────────────────
	row.ClickableButton = mockButton()

	-- Animation groups referenced by RowTooltipMixin (OnEnter/OnLeave).
	row.ExitAnimation = mockAnimationGroup()
	row.HighlightAnimation = mockAnimationGroup()

	-- ── Row-level helpers referenced by mixins ────────────────────────────
	row.ResetHighlightBorder = function() end
	stub(row, "ResetHighlightBorder")

	return row
end

return M
