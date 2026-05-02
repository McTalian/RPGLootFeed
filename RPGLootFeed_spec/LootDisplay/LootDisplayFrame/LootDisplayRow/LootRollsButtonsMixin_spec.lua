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
		ClearAllPoints = function() end,
		SetPoint = function() end,
		SetAlpha = function(self, a)
			self._alpha = a
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
--- Optionally pre-populates _lootRollButtons if withButtons = true.
local function buildRow(ns, withButtons)
	-- Load the mixin into the global.
	assert(loadfile(MIXIN_FILE))("TestAddon", ns)

	local row = {
		frameType = "MAIN",
		type = nil,
		_lootRollButtons = nil,
		_lootRollEncounterID = nil,
		_lootRollLootListID = nil,
		_lootRollRollState = nil,
		_lootRollDisableFrame = nil,
		_lootRollButtonsWidth = nil,
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
		-- Pre-build four mock buttons indexed by roll key.
		local buttons = {}
		for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
			buttons[key] = makeMockBtn()
			buttons[key].rollKey = key
		end
		row._lootRollButtons = buttons
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
		it("creates four button frames", function()
			local row = buildRow(ns)

			-- Override CreateFrame to return a proper mock button.
			local createdCount = 0
			_G.CreateFrame = function(_type, _name, _parent)
				createdCount = createdCount + 1
				return makeMockBtn()
			end

			row:InitializeButtons()

			assert.is_not_nil(row._lootRollButtons)
			assert.is_not_nil(row._lootRollButtons["NEED"])
			assert.is_not_nil(row._lootRollButtons["MIDDLE"])
			assert.is_not_nil(row._lootRollButtons["MIDDLE"])
			assert.is_not_nil(row._lootRollButtons["PASS"])
			assert.equals(3, createdCount)
		end)

		it("is idempotent — calling twice does not recreate buttons", function()
			local row = buildRow(ns)

			local createdCount = 0
			_G.CreateFrame = function()
				createdCount = createdCount + 1
				return makeMockBtn()
			end

			row:InitializeButtons()
			local firstButtons = row._lootRollButtons

			row:InitializeButtons()
			assert.equal(firstButtons, row._lootRollButtons) -- same table
			assert.equals(3, createdCount) -- still only 4 creates
		end)

		it("assigns slotKey to each button", function()
			local row = buildRow(ns)
			_G.CreateFrame = function()
				return makeMockBtn()
			end
			row:InitializeButtons()
			assert.equal("NEED", row._lootRollButtons["NEED"].slotKey)
			assert.equal("MIDDLE", row._lootRollButtons["MIDDLE"].slotKey)
			assert.equal("PASS", row._lootRollButtons["PASS"].slotKey)
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

			assert.is_true(row._lootRollButtons["NEED"].isRollEnabled)
			assert.is_false(row._lootRollButtons["MIDDLE"].isRollEnabled)
			assert.is_true(row._lootRollButtons["PASS"].isRollEnabled)
		end)

		it("shows disabled overlay on invalid buttons", function()
			local row = buildRow(ns, true)

			row:UpdateButtonStates({ canNeed = false, canGreed = false, canTransmog = false, canPass = false }, "GREED")

			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_true(
					row._lootRollButtons[key].disabledOverlay._shown,
					"disabled overlay should be shown for " .. key
				)
			end
		end)

		it("hides disabled overlay on valid buttons", function()
			local row = buildRow(ns, true)

			row:UpdateButtonStates({ canNeed = true, canGreed = true, canTransmog = true, canPass = true }, "GREED")

			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_false(
					row._lootRollButtons[key].disabledOverlay._shown,
					"disabled overlay should be hidden for " .. key
				)
			end
		end)

		it("handles nil validity — defaults all buttons to enabled", function()
			local row = buildRow(ns, true)

			row:UpdateButtonStates(nil, "GREED")

			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_true(
					row._lootRollButtons[key].isRollEnabled,
					"button " .. key .. " should be enabled when validity is nil"
				)
			end
		end)

		it("is a no-op when buttons are not yet initialized", function()
			local row = buildRow(ns) -- no buttons
			assert.has_no.errors(function()
				row:UpdateButtonStates({ canNeed = true }, "GREED")
			end)
		end)
	end)

	describe("ShowButtons / HideButtons", function()
		it("shows all buttons", function()
			local row = buildRow(ns, true)
			row:ShowButtons()
			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_true(row._lootRollButtons[key]._shown)
			end
		end)

		it("hides all buttons", function()
			local row = buildRow(ns, true)
			-- Show first, then hide.
			for _, btn in pairs(row._lootRollButtons) do
				btn._shown = true
			end
			row:HideButtons()
			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_false(row._lootRollButtons[key]._shown)
			end
		end)

		it("no-ops when buttons not initialized", function()
			local row = buildRow(ns)
			assert.has_no.errors(function()
				row:ShowButtons()
				row:HideButtons()
			end)
		end)
	end)

	describe("OnButtonClick", function()
		it("calls the correct LootRolls Submit method for NEED", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = 10
			row._lootRollLootListID = 2
			row._lootRollsFeature = { SubmitNeed = function() end }
			local s = spy.on(row._lootRollsFeature, "SubmitNeed")
			row:OnButtonClick("NEED")
			assert.spy(s).was.called_with(row._lootRollsFeature, 10, 2)
		end)

		it("calls SubmitGreed for GREED", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = 10
			row._lootRollLootListID = 2
			row._lootRollsFeature = { SubmitGreed = function() end }
			local s = spy.on(row._lootRollsFeature, "SubmitGreed")
			row:OnButtonClick("GREED")
			assert.spy(s).was.called_with(row._lootRollsFeature, 10, 2)
		end)

		it("calls SubmitTransmog for TRANSMOG", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = 10
			row._lootRollLootListID = 2
			row._lootRollsFeature = { SubmitTransmog = function() end }
			local s = spy.on(row._lootRollsFeature, "SubmitTransmog")
			row:OnButtonClick("TRANSMOG")
			assert.spy(s).was.called_with(row._lootRollsFeature, 10, 2)
		end)

		it("calls SubmitPass for PASS", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = 10
			row._lootRollLootListID = 2
			row._lootRollsFeature = { SubmitPass = function() end }
			local s = spy.on(row._lootRollsFeature, "SubmitPass")
			row:OnButtonClick("PASS")
			assert.spy(s).was.called_with(row._lootRollsFeature, 10, 2)
		end)

		it("does not submit when encounterID is nil", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = nil
			row._lootRollLootListID = 2
			row._lootRollsFeature = { SubmitNeed = function() end }
			local s = spy.on(row._lootRollsFeature, "SubmitNeed")
			row:OnButtonClick("NEED")
			assert.spy(s).was.not_called()
		end)

		it("does not submit when lootListID is nil", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = 10
			row._lootRollLootListID = nil
			row._lootRollsFeature = { SubmitNeed = function() end }
			local s = spy.on(row._lootRollsFeature, "SubmitNeed")
			row:OnButtonClick("NEED")
			assert.spy(s).was.not_called()
		end)

		it("logs a warning for unknown rollKey", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = 10
			row._lootRollLootListID = 2
			row._lootRollsFeature = {}
			assert.has_no.errors(function()
				row:OnButtonClick("INVALID")
			end)
		end)
	end)

	describe("UpdateLootRollButtons", function()
		it("hides buttons when enableLootRollActions is false", function()
			local row = buildRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, _k)
				return { enableLootRollActions = false }
			end

			row:UpdateLootRollButtons(pendingPayload())

			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_false(row._lootRollButtons[key]._shown)
			end
		end)

		it("hides buttons when rollState is 'resolved'", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({ rollState = "resolved" }))
			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_false(row._lootRollButtons[key]._shown)
			end
		end)

		it("hides buttons when rollState is 'allPassed'", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({ rollState = "allPassed" }))
			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_false(row._lootRollButtons[key]._shown)
			end
		end)

		it("initializes buttons and shows them for a pending roll", function()
			local row = buildRow(ns)

			-- Make CreateFrame return proper mock buttons.
			_G.CreateFrame = function()
				return makeMockBtn()
			end

			row:UpdateLootRollButtons(pendingPayload())

			assert.is_not_nil(row._lootRollButtons)
			-- All buttons visible.
			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_true(row._lootRollButtons[key]._shown)
			end
		end)

		it("caches encounterID and lootListID from the payload", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({ encounterID = 42, lootListID = 7 }))
			assert.equals(42, row._lootRollEncounterID)
			assert.equals(7, row._lootRollLootListID)
		end)

		it("applies button validity from the payload", function()
			local row = buildRow(ns, true)
			row:UpdateLootRollButtons(pendingPayload({
				buttonValidity = {
					canNeed = true,
					canGreed = false,
					canTransmog = false,
					canPass = true,
				},
			}))
			assert.is_true(row._lootRollButtons["NEED"].isRollEnabled)
			assert.is_false(row._lootRollButtons["MIDDLE"].isRollEnabled)
			assert.is_true(row._lootRollButtons["PASS"].isRollEnabled)
		end)

		it("handles nil buttonValidity gracefully — defaults all buttons to enabled", function()
			local row = buildRow(ns, true)
			local payload = {
				rollState = "pending",
				encounterID = 10,
				lootListID = 2,
				-- buttonValidity intentionally absent (nil)
			}
			row:UpdateLootRollButtons(payload)
			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_true(
					row._lootRollButtons[key].isRollEnabled,
					"button " .. key .. " should be enabled when buttonValidity is nil"
				)
			end
		end)
	end)

	describe("ResetButtons", function()
		it("clears encounterID and lootListID", function()
			local row = buildRow(ns, true)
			row._lootRollEncounterID = 5
			row._lootRollLootListID = 3

			row:ResetButtons()

			assert.is_nil(row._lootRollEncounterID)
			assert.is_nil(row._lootRollLootListID)
		end)

		it("clears rollState and disableFrame flags", function()
			local row = buildRow(ns, true)
			row._lootRollRollState = "pending"
			row._lootRollDisableFrame = true

			row:ResetButtons()

			assert.is_nil(row._lootRollRollState)
			assert.is_nil(row._lootRollDisableFrame)
		end)

		it("hides all buttons", function()
			local row = buildRow(ns, true)
			for _, btn in pairs(row._lootRollButtons) do
				btn._shown = true
			end

			row:ResetButtons()

			for _, key in ipairs({ "NEED", "MIDDLE", "PASS" }) do
				assert.is_false(row._lootRollButtons[key]._shown)
			end
		end)

		it("is a no-op when buttons not yet initialized", function()
			local row = buildRow(ns)
			assert.has_no.errors(function()
				row:ResetButtons()
			end)
		end)
	end)

	describe("OnAltClick escape hatch", function()
		local function buildAltClickRow(ns2, rollState, disableFrame)
			local row = buildRow(ns2, true)
			row._lootRollRollState = rollState or "pending"
			row._lootRollDisableFrame = disableFrame
			row._lootRollLootListID = 5
			return row
		end

		it("shows GroupLootFrame when disableLootRollFrame=true and roll is pending", function()
			local row = buildAltClickRow(ns, "pending", true)
			local shown = false
			_G.GroupLootFrame1 = {
				rollID = 5,
				Show = function()
					shown = true
				end,
			}

			row:OnAltClick()

			assert.is_true(shown)
		end)

		it("does not show GroupLootFrame when disableLootRollFrame=false", function()
			local row = buildAltClickRow(ns, "pending", false)
			local shown = false
			_G.GroupLootFrame1 = {
				rollID = 5,
				Show = function()
					shown = true
				end,
			}

			row:OnAltClick()

			assert.is_false(shown)
		end)

		it("does not show GroupLootFrame when disableLootRollFrame is nil", function()
			local row = buildAltClickRow(ns, "pending", nil)
			local shown = false
			_G.GroupLootFrame1 = {
				rollID = 5,
				Show = function()
					shown = true
				end,
			}

			row:OnAltClick()

			assert.is_false(shown)
		end)

		it("does not show GroupLootFrame when rollState is resolved", function()
			local row = buildAltClickRow(ns, "resolved", true)
			local shown = false
			_G.GroupLootFrame1 = {
				rollID = 5,
				Show = function()
					shown = true
				end,
			}

			row:OnAltClick()

			assert.is_false(shown)
		end)

		it("does not show GroupLootFrame when rollState is allPassed", function()
			local row = buildAltClickRow(ns, "allPassed", true)
			local shown = false
			_G.GroupLootFrame1 = {
				rollID = 5,
				Show = function()
					shown = true
				end,
			}

			row:OnAltClick()

			assert.is_false(shown)
		end)

		it("logs a warning when GroupLootFrame is nil", function()
			local row = buildAltClickRow(ns, "pending", true)
			_G.GroupLootFrame = nil
			-- Should not error even if GroupLootFrame is unavailable.
			assert.has_no.errors(function()
				row:OnAltClick()
			end)
		end)

		it("button OnClick with Alt held calls OnAltClick", function()
			local row = buildRow(ns)

			-- Create buttons with InitializeButtons.
			_G.CreateFrame = function()
				return makeMockBtn()
			end
			row:InitializeButtons()

			row._lootRollRollState = "pending"
			row._lootRollDisableFrame = true

			-- Stub OnAltClick to track calls.
			local altClickCalled = false
			row.OnAltClick = function(_self)
				altClickCalled = true
			end

			-- Simulate IsAltKeyDown = true.
			_G.IsAltKeyDown = function()
				return true
			end

			-- Fire OnMouseUp on the NEED button with LeftButton.
			local btn = row._lootRollButtons["NEED"]
			btn._scripts["OnClick"](btn, "LeftButton")

			assert.is_true(altClickCalled)
		end)

		it("button OnClick without Alt held does NOT call OnAltClick (calls OnButtonClick instead)", function()
			local row = buildRow(ns)

			_G.CreateFrame = function()
				return makeMockBtn()
			end
			row:InitializeButtons()

			row._lootRollRollState = "pending"
			row._lootRollDisableFrame = true

			local altClickCalled = false
			row.OnAltClick = function(_self)
				altClickCalled = true
			end

			local buttonClickKey = nil
			row.OnButtonClick = function(_self, key)
				buttonClickKey = key
			end

			-- Alt NOT held.
			_G.IsAltKeyDown = function()
				return false
			end

			-- NEED button is enabled.
			local btn = row._lootRollButtons["NEED"]
			btn.isRollEnabled = true
			btn._scripts["OnClick"](btn, "LeftButton")

			assert.is_false(altClickCalled)
			assert.equals("NEED", buttonClickKey)
		end)

		it("UpdateLootRollButtons caches disableLootRollFrame from config", function()
			local row = buildRow(ns, true)
			ns.DbAccessor.AnyFeatureConfig = function(_, key)
				if key == "lootRolls" then
					return { enableLootRollActions = true, disableLootRollFrame = true }
				end
			end

			row:UpdateLootRollButtons(pendingPayload())

			assert.is_true(row._lootRollDisableFrame)
		end)

		it("UpdateLootRollButtons caches rollState from payload", function()
			local row = buildRow(ns, true)

			row:UpdateLootRollButtons(pendingPayload())

			assert.equals("pending", row._lootRollRollState)
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
