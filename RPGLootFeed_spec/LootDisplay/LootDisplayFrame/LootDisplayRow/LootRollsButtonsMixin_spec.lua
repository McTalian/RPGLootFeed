local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootRollsButtonsMixin.lua"

-- ─── helpers ─────────────────────────────────────────────────────────────────

--- Build a minimal mock button frame that satisfies the mixin's calls.
--- When InitializeButtons runs, it calls CreateTexture 3× per button to create
--- tex, disabledOverlay, and highlight.  The mock tracks the last created
--- texture per overlay type via self._textures[].
local function makeMockBtn()
	local btn = {
		rollKey = nil,
		isRollEnabled = false,
		_shown = false,
		_alpha = 1,
		_scripts = {},
		_textures = {}, -- filled by CreateTexture calls during InitializeButtons
		-- Pre-set tex/disabledOverlay/highlight for tests that use withButtons=true.
		-- These are overwritten by InitializeButtons when it runs, but the tests
		-- using withButtons=true skip InitializeButtons so these stay.
		tex = {
			SetDesaturated = function() end,
			SetAtlas = function() end,
			SetAllPoints = function() end,
		},
		disabledOverlay = {
			_shown = false,
			Show = function(self)
				self._shown = true
			end,
			Hide = function(self)
				self._shown = false
			end,
		},
		highlight = {
			SetAllPoints = function() end,
			SetColorTexture = function() end,
		},
		SetSize = function() end,
		SetID = function() end,
		SetNormalAtlas = function() end,
		SetPushedAtlas = function() end,
		SetHighlightAtlas = function() end,
		ClearAllPoints = function() end,
		SetPoint = function() end,
		SetAlpha = function(self, a)
			self._alpha = a
		end,
		Enable = function(self)
			self._enabled = true
		end,
		Disable = function(self)
			self._enabled = false
		end,
		Show = function(self)
			self._shown = true
		end,
		Hide = function(self)
			self._shown = false
		end,
		EnableMouse = function() end,
		SetScript = function(self, evt, fn)
			self._scripts[evt] = fn
		end,
		SetFrameLevel = function() end,
		GetFrameLevel = function()
			return 5
		end,
		RegisterForClicks = function() end,
		GetNormalTexture = function()
			return { SetDesaturation = function() end }
		end,
	}
	btn.CreateTexture = function(self, _name, _layer)
		local t = {
			_shown = false,
			SetAllPoints = function() end,
			SetColorTexture = function() end,
			SetAtlas = function() end,
			SetDesaturated = function() end,
			Hide = function(self2)
				self2._shown = false
			end,
			Show = function(self2)
				self2._shown = true
			end,
		}
		table.insert(self._textures, t)
		return t
	end
	return btn
end

--- Build a minimal mock row table with the mixin methods applied.
--- Optionally pre-populates named buttons (NeedButton etc.) if withButtons = true.
local function buildRow(ns, withButtons)
	-- Load the mixin into the global.
	assert(loadfile(MIXIN_FILE))("TestAddon", ns)

	local row = {
		frameType = "MAIN",
		type = nil,
		rollID = nil,
		-- ClickableButton stub — must exist for InitializeButtons.
		ClickableButton = {
			_scripts = {},
			GetFrameLevel = function()
				return 5
			end,
			SetScript = function(self, evt, fn)
				self._scripts[evt] = fn
			end,
		},
		IsMouseOver = function()
			return false
		end,
		-- SetClickThrough stub — required by UpdateLootRollButtons (S04 dismiss gating).
		_isClickThrough = false,
		SetClickThrough = function(self, enabled)
			self._isClickThrough = enabled
		end,
	}

	-- Mix in mixin methods.
	for k, v in pairs(RLF_LootRollsButtonsMixin) do
		row[k] = v
	end

	-- Stub frame-level WoW methods used by the mixin.
	stub(row, "LogDebug") -- prevent missing-ns errors in tests that don't need log asserts
	-- (ns.LogDebug is already stubbed by nsMocks)

	-- Provide a minimal DbAccessor so LayoutButtons can call Sizing/Styling.
	ns.DbAccessor.Sizing = function(_, _ft)
		return { padding = 2, iconSize = 20 }
	end
	ns.DbAccessor.Styling = function(_, _ft)
		return { textAlignment = ns.TextAlignment and ns.TextAlignment.LEFT or "LEFT" }
	end
	ns.DbAccessor.AnyFeatureConfig = function(_, key)
		if key == "lootRolls" then
			return { enableLootRollActions = true }
		end
	end

	if withButtons then
		-- Pre-build named mock buttons.
		row.NeedButton = makeMockBtn()
		row.PassButton = makeMockBtn()
		row.GreedButton = makeMockBtn()
		row.TransmogButton = makeMockBtn()
	end

	return row
end

--- Minimal payload builder for testing.
local function pendingPayload(overrides)
	local p = {
		rollState = "pending",
		encounterID = 10,
		lootListID = 2,
		buttonValidity = {
			canNeed = true,
			canGreed = true,
			canTransmog = false,
			canPass = true,
		},
	}
	if overrides then
		for k, v in pairs(overrides) do
			p[k] = v
		end
	end
	return p
end

-- ─── tests ───────────────────────────────────────────────────────────────────

describe("LootRollsButtonsMixin", function()
	local ns

	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
	end)

	describe("InitializeButtons", function()
		it("creates four named button frames (NeedButton, PassButton, GreedButton, TransmogButton)", function()
			local row = buildRow(ns)

			local createdCount = 0
			_G.CreateFrame = function()
				createdCount = createdCount + 1
				return makeMockBtn()
			end

			row:InitializeButtons()

			assert.is_not_nil(row.NeedButton)
			assert.is_not_nil(row.PassButton)
			assert.is_not_nil(row.GreedButton)
			assert.is_not_nil(row.TransmogButton)
			assert.equals(4, createdCount)
		end)

		it("is idempotent — calling twice does not recreate buttons", function()
			local row = buildRow(ns)

			local createdCount = 0
			_G.CreateFrame = function()
				createdCount = createdCount + 1
				return makeMockBtn()
			end

			row:InitializeButtons()
			local firstNeed = row.NeedButton

			row:InitializeButtons()
			assert.equal(firstNeed, row.NeedButton) -- same instance
			assert.equals(4, createdCount) -- still only 4 creates
		end)
	end)

	describe("UpdateButtonStates", function()
		it("enables NEED and PASS; disables MIDDLE (GREED) when canGreed=false", function()
			local row = buildRow(ns, true)

			row:UpdateButtonStates({
				canNeed = true,
				canGreed = false,
				canTransmog = false,
				canPass = true,
			}, "GREED")

			assert.is_true(row.NeedButton._enabled)
			assert.is_false(row.GreedButton._enabled)
			assert.is_true(row.PassButton._enabled)
		end)

		it("disables TRANSMOG when canTransmog=false", function()
			local row = buildRow(ns, true)

			row:UpdateButtonStates({ canNeed = true, canGreed = true, canTransmog = false, canPass = true }, "TRANSMOG")

			assert.is_false(row.TransmogButton._enabled)
		end)

		it("enables all buttons when all validity flags are true", function()
			local row = buildRow(ns, true)

			row:UpdateButtonStates({ canNeed = true, canGreed = true, canTransmog = true, canPass = true }, "GREED")

			assert.is_true(row.NeedButton._enabled)
			assert.is_true(row.GreedButton._enabled)
			assert.is_true(row.PassButton._enabled)
		end)

		it("defaults all buttons to disabled when validity is nil", function()
			local row = buildRow(ns, true)

			row:UpdateButtonStates(nil, "GREED")

			assert.is_false(row.NeedButton._enabled)
			assert.is_false(row.GreedButton._enabled)
			assert.is_false(row.PassButton._enabled)
		end)

		it("is a no-op when buttons are not yet initialized", function()
			local row = buildRow(ns) -- no buttons
			assert.has_no.errors(function()
				row:UpdateButtonStates({ canNeed = true }, "GREED")
			end)
		end)
	end)

	describe("ShowButtons / HideButtons", function()
		it("shows Need and Pass buttons (Greed/Transmog managed by ConfigureMiddleButton)", function()
			local row = buildRow(ns, true)
			row:ShowButtons()
			assert.is_true(row.NeedButton._shown)
			assert.is_true(row.PassButton._shown)
			assert.is_false(row.GreedButton._shown)
		end)

		it("hides all four named buttons", function()
			local row = buildRow(ns, true)
			for _, btn in ipairs({ row.NeedButton, row.PassButton, row.GreedButton, row.TransmogButton }) do
				btn._shown = true
			end
			row:HideButtons()
			assert.is_false(row.NeedButton._shown)
			assert.is_false(row.PassButton._shown)
			assert.is_false(row.GreedButton._shown)
			assert.is_false(row.TransmogButton._shown)
		end)

		it("no-ops when buttons not initialized", function()
			local row = buildRow(ns)
			assert.has_no.errors(function()
				row:ShowButtons()
				row:HideButtons()
			end)
		end)
	end)

	describe("ConfigureMiddleButton", function()
		it("shows TransmogButton and hides GreedButton when middleKey is TRANSMOG", function()
			local row = buildRow(ns, true)
			row:ConfigureMiddleButton("TRANSMOG")
			assert.is_true(row.TransmogButton._shown)
			assert.is_false(row.GreedButton._shown)
		end)

		it("hides TransmogButton and shows GreedButton when middleKey is GREED", function()
			local row = buildRow(ns, true)
			row.TransmogButton._shown = true
			row:ConfigureMiddleButton("GREED")
			assert.is_false(row.TransmogButton._shown)
			assert.is_true(row.GreedButton._shown)
		end)

		it("hides TransmogButton when middleKey is DISENCHANT", function()
			local row = buildRow(ns, true)
			row.TransmogButton._shown = true
			row:ConfigureMiddleButton("DISENCHANT")
			assert.is_false(row.TransmogButton._shown)
		end)
	end)

	describe("UpdateLootRollButtons", function()
		it("hides buttons when enableLootRollActions is false", function()
			local row = buildRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, _k)
				return { enableLootRollActions = false }
			end

			row:UpdateLootRollButtons(pendingPayload())

			assert.is_false(row.NeedButton._shown)
			assert.is_false(row.PassButton._shown)
			assert.is_false(row.GreedButton._shown)
		end)

		it("hides buttons when rollState is 'resolved'", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({ rollState = "resolved" }))
			assert.is_false(row.NeedButton._shown)
			assert.is_false(row.PassButton._shown)
		end)

		it("hides buttons when rollState is 'allPassed'", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({ rollState = "allPassed" }))
			assert.is_false(row.NeedButton._shown)
		end)

		it("initializes named buttons and shows them for a pending roll", function()
			local row = buildRow(ns)

			_G.CreateFrame = function()
				return makeMockBtn()
			end

			row:UpdateLootRollButtons(pendingPayload())

			assert.is_not_nil(row.NeedButton)
			assert.is_not_nil(row.PassButton)
			assert.is_not_nil(row.GreedButton)
			assert.is_not_nil(row.TransmogButton)
			assert.is_true(row.NeedButton._shown)
			assert.is_true(row.PassButton._shown)
			assert.is_true(row.GreedButton._shown)
		end)

		it("caches lootListID as rollID from the payload", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({ lootListID = 7 }))
			assert.equals(7, row.rollID)
		end)

		it("applies button validity from the payload — disables GreedButton when canGreed=false", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({
				buttonValidity = {
					canNeed = true,
					canGreed = false,
					canTransmog = false,
					canPass = true,
				},
			}))
			assert.is_true(row.NeedButton._enabled)
			assert.is_false(row.GreedButton._enabled)
			assert.is_true(row.PassButton._enabled)
		end)

		it("handles nil buttonValidity gracefully — defaults all buttons to disabled", function()
			local row = buildRow(ns, true)
			local payload = {
				rollState = "pending",
				lootListID = 2,
			}
			row:UpdateLootRollButtons(payload)
			assert.is_false(row.NeedButton._enabled)
			assert.is_false(row.GreedButton._enabled)
			assert.is_false(row.PassButton._enabled)
		end)
	end)

	describe("ResetButtons", function()
		it("clears rollID", function()
			local row = buildRow(ns, true)
			row.rollID = 5

			row:ResetButtons()

			assert.is_nil(row.rollID)
		end)

		it("hides all buttons", function()
			local row = buildRow(ns, true)
			for _, btn in ipairs({ row.NeedButton, row.PassButton, row.GreedButton, row.TransmogButton }) do
				btn._shown = true
			end

			row:ResetButtons()

			assert.is_false(row.NeedButton._shown)
			assert.is_false(row.PassButton._shown)
			assert.is_false(row.GreedButton._shown)
			assert.is_false(row.TransmogButton._shown)
		end)

		it("is a no-op when buttons not yet initialized", function()
			local row = buildRow(ns)
			assert.has_no.errors(function()
				row:ResetButtons()
			end)
		end)
	end)
end)

describe("LootDisplayRow button integration", function()
	local ns

	before_each(function()
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
	end)

	it("loads LootDisplayRow.lua without error", function()
		assert(loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow.lua"))("TestAddon", ns)
		assert.is_not_nil(_G.LootDisplayRowMixin)
	end)

	it("LootDisplayRowMixin has UpdateLootRollButtons after mixin is loaded", function()
		assert(loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootRollsButtonsMixin.lua"))(
			"TestAddon",
			ns
		)
		assert(loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootDisplayRow.lua"))("TestAddon", ns)
		-- The mixin is mixed into the row via the XML template at runtime; in tests we
		-- just verify LootRollsButtonsMixin exposes UpdateLootRollButtons on G_RLF.
		assert.is_function(ns.RLF_LootRollsButtonsMixin.UpdateLootRollButtons)
	end)
end)
