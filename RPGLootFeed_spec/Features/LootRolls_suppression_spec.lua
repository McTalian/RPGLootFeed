---@diagnostic disable: need-check-nil
--- T01 Suppression tests: GroupLootFrame suppression + button submission independence
--- T03 Suppression tests: Phase-based dismiss gating (S04) works correctly under suppression
---
--- Verifies:
---   1. RawHook intercepts all 4 GroupLootFrame1-4 Show calls when suppression enabled
---   2. Frame is hidden (not shown) when disableLootRollFrame=true and Show is called
---   3. Frame is shown normally when disableLootRollFrame=false
---   4. Button click still enqueues action (_pendingActions populated) when suppression enabled
---   5. Pending queue populated correctly when frame is suppressed
---   6. Suppression requires enableLootRollActions=true (otherwise disableLootRollFrame is a no-op config-wise)
---   T03-1. pending phase + suppression active → dismiss locked (SetClickThrough=true)
---   T03-2. result phase + suppression active → dismiss locked (SetClickThrough=true)
---   T03-3. resolved phase + suppression active → dismiss unlocked (SetClickThrough=false)
---   T03-4. CANCEL_LOOT_ROLL releases dismiss lock even when suppression active
---   T03-5. multi-drop: two rolls with different suppression states each have independent dismiss gating
---   7. Classic frames (GroupLootFrame1-4) are all hooked
---   8. Config absent/nil falls back to allowing show (no crash)

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")

-- ── shared constants ──────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:12345|r"
local ROLL_ID = 55

-- ── LootRolls loader (mirrors LootRolls_button_submit_spec pattern) ──────────

local function makeNs(sendSpy, isRetailFn, extraConfig)
	local cfg = { enableIcon = true, enableLootRollActions = true }
	if extraConfig then
		for k, v in pairs(extraConfig) do cfg[k] = v end
	end
	return {
		LootElementBase = nil,
		ItemQualEnum = { Uncommon = 2, Epic = 4 },
		DefaultIcons = { LOOTROLLS = 132319 },
		FeatureModule = { LootRolls = "LootRolls" },
		LogDebug = spy.new(function() end),
		LogInfo = spy.new(function() end),
		LogWarn = spy.new(function() end),
		LogError = spy.new(function() end),
		IsRetail = isRetailFn or function() return true end,
		SendMessage = sendSpy or spy.new(function() end),
		TooltipBuilders = nil,
		db = { global = { animations = { exit = { fadeOutDelay = 3 } }, misc = { hideAllIcons = false } } },
		WoWAPI = { LootRolls = {} },
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function() return true end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then return cfg end
				return nil
			end,
		},
		L = {
			["All Passed"] = "All Passed",
			["LootRolls_WaitingForRolls"] = "Waiting for rolls",
			["LootRolls_TiedFmt"] = "Tied at %d",
			["LootRolls_CurrentLeaderFmt"] = "Leading: %s rolled %d",
			["LootRolls_WonByFmt"] = "Won by %s %s %d",
			["LootRolls_WonByNoRollFmt"] = "Won by %s",
			["LootRolls_YouSelected_NEED"] = "You: Need",
			["LootRolls_YouSelected_GREED"] = "You: Greed",
			["LootRolls_YouSelected_TRANSMOG"] = "You: Transmog",
			["LootRolls_YouSelected_PASS"] = "You: Pass",
			["LootRolls_WaitingForResults"] = "Waiting for results",
			["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
			["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
		},
		RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
	}
end

local function loadLootRolls(ns, adapterOverrides)
	assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
	ns.FeatureBase = {
		new = function(_, name)
			return {
				moduleName = name,
				Enable = function() end,
				Disable = function() end,
				IsEnabled = function() return true end,
				RegisterEvent = function() end,
				UnregisterAllEvents = function() end,
			}
		end,
	}
	local lr = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
	assert.is_not_nil(lr)
	ns.LootRolls = lr
	local adapter = {
		HasLootHistory = function() return true end,
		HasStartLootRollEvent = function() return true end,
		GetSortedInfoForDrop = function() return nil end,
		GetInfoForEncounter = function() return nil end,
		GetRaidClassColor = function() return nil end,
		GetItemInfoIcon = function() return 12345 end,
		GetItemInfoQuality = function() return 4 end,
		GetRollButtonValidity = function()
			return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
		end,
		GetRetailRollItemLink = function() return ITEM_LINK end,
		GetClassicRollItemInfo = function()
			return { itemLink = ITEM_LINK, texture = 132310, quality = 3, canNeed = true, canGreed = true, canDisenchant = false }
		end,
	}
	if adapterOverrides then
		for k, v in pairs(adapterOverrides) do adapter[k] = v end
	end
	lr._lootRollsAdapter = adapter
	lr._dropStates = {}
	lr._buttonValidityCache = {}
	lr._stagedRollValidity = {}
	lr._pendingActions = {}
	return lr
end

-- ── GroupLootFrameOverride loader ─────────────────────────────────────────────

local function loadGroupLootFrameOverride(ns)
	return assert(loadfile("RPGLootFeed/BlizzOverrides/GroupLootFrameOverride.lua"))("TestAddon", ns)
end

-- =============================================================================
-- Suite 1: GroupLootFrame suppression via GroupLootFrameOverride
-- =============================================================================

describe("suppression: GroupLootFrameOverride integration", function()
	local ns, glfo, rollFrames

	before_each(function()
		rollFrames = {}
		for i = 1, 4 do
			rollFrames[i] = { Hide = function() end, Show = function() end }
			_G["GroupLootFrame" .. i] = rollFrames[i]
		end

		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { disableLootRollFrame = false, enableLootRollActions = true }
			end
		end

		glfo = loadGroupLootFrameOverride(ns)
	end)

	after_each(function()
		for i = 1, 4 do
			_G["GroupLootFrame" .. i] = nil
		end
	end)

	-- Test 1: RawHook intercepts all 4 GroupLootFrame1-4 Show calls
	it("hooks all four GroupLootFrame1-4 OnShow via RawHook when called", function()
		spy.on(glfo, "RawHook")
		glfo:GroupLootFrameHook()
		assert.spy(glfo.RawHook).was.called(4)
		for i = 1, 4 do
			assert
				.spy(glfo.RawHook).was
				.called_with(glfo, rollFrames[i], "Show", "InterceptGroupLootFrame", true)
		end
	end)

	-- Test 2: Frame is hidden when disableLootRollFrame=true
	it("hides frame instead of showing when disableLootRollFrame=true", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { disableLootRollFrame = true, enableLootRollActions = true }
			end
		end
		local frame = rollFrames[1]
		local hideSpy = spy.on(frame, "Hide")
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }
		glfo:InterceptGroupLootFrame(frame)
		assert.spy(hideSpy).was.called(1)
		assert.is_false(originalCalled, "original Show must NOT be called when suppression enabled")
	end)

	-- Test 3: Frame is shown normally when disableLootRollFrame=false
	it("calls original Show when disableLootRollFrame=false", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { disableLootRollFrame = false, enableLootRollActions = true }
			end
		end
		local frame = rollFrames[2]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }
		glfo:InterceptGroupLootFrame(frame)
		assert.is_true(originalCalled, "original Show must be called when suppression disabled")
	end)

	-- Test 7: Classic frames (GroupLootFrame1-4) are all hooked
	it("hooks all four frames on Classic client (same frame names)", function()
		-- Classic and Retail both use GroupLootFrame1-4; the hook is client-agnostic
		spy.on(glfo, "RawHook")
		glfo:GroupLootFrameHook()
		-- All four must be present and hooked
		assert.spy(glfo.RawHook).was.called(4)
		for i = 1, 4 do
			assert
				.spy(glfo.RawHook).was
				.called_with(glfo, _G["GroupLootFrame" .. i], "Show", "InterceptGroupLootFrame", true)
		end
	end)

	-- Test 8: Config absent/nil falls back to allowing show (no crash)
	it("falls back to calling original Show when config is absent (nil)", function()
		ns.DbAccessor.AnyFeatureConfig = function() return nil end
		local frame = rollFrames[3]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }
		assert.has_no_errors(function()
			glfo:InterceptGroupLootFrame(frame)
		end)
		assert.is_true(originalCalled, "original Show must be called when config is nil")
	end)
end)

-- =============================================================================
-- Suite 2: Button submission works independently of frame suppression
-- =============================================================================

describe("suppression: button submission unblocked when suppression active (Retail)", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		-- enableLootRollActions=true AND disableLootRollFrame=true (suppression on)
		lr = loadLootRolls(makeNs(sendSpy, nil, { disableLootRollFrame = true }))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- Test 4: Button click still enqueues action when suppression is enabled
	it("START_LOOT_ROLL enqueues pending action even when disableLootRollFrame=true", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		local slot = lr._pendingActions[ROLL_ID]
		assert.is_not_nil(slot, "_pendingActions entry must exist regardless of suppression")
		assert.are.equal(ITEM_LINK, slot.itemLink)
		assert.is_nil(slot.rollType)
	end)

	-- Test 5: Pending queue populated correctly when frame is suppressed
	it("OnRollButtonClick populates pending queue with rollType=NEED when frame suppressed", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		-- Simulate drop state for Retail path
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK, winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {}, playerRollState = nil,
				startTime = nil, duration = nil,
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", 10, 3)
		lr:OnRollButtonClick(ROLL_ID, 1) -- Need
		assert.are.equal("NEED", lr._pendingActions[ROLL_ID].rollType)
		assert.are.equal("waiting", lr._dropStates["10_3"].actionPhase)
	end)
end)

-- =============================================================================
-- Suite 3: suppression requires enableLootRollActions=true
-- =============================================================================

describe("suppression: disableLootRollFrame config is gated on enableLootRollActions", function()
	local ns, glfo, rollFrames

	before_each(function()
		rollFrames = {}
		for i = 1, 4 do
			rollFrames[i] = { Hide = function() end, Show = function() end }
			_G["GroupLootFrame" .. i] = rollFrames[i]
		end
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)
	end)

	after_each(function()
		for i = 1, 4 do
			_G["GroupLootFrame" .. i] = nil
		end
	end)

	-- Test 6a: When enableLootRollActions=false, disableLootRollFrame has no effect on the hook
	-- (the config toggle is disabled in UI, but if someone sets it manually it should not crash)
	it("InterceptGroupLootFrame does not crash when enableLootRollActions=false and disableLootRollFrame=true", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { enableLootRollActions = false, disableLootRollFrame = true }
			end
		end
		glfo = loadGroupLootFrameOverride(ns)
		local frame = rollFrames[1]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }
		-- The module uses disableLootRollFrame directly; if true it hides regardless.
		-- The config dependency (enableLootRollActions) is enforced at the UI level, not here.
		-- This test verifies no runtime error occurs.
		assert.has_no_errors(function()
			glfo:InterceptGroupLootFrame(frame)
		end)
	end)

	-- Test 6b: When enableLootRollActions=true and disableLootRollFrame=true, suppression is active
	it("InterceptGroupLootFrame suppresses frame when enableLootRollActions=true and disableLootRollFrame=true", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { enableLootRollActions = true, disableLootRollFrame = true }
			end
		end
		glfo = loadGroupLootFrameOverride(ns)
		local frame = rollFrames[1]
		local hideSpy = spy.on(frame, "Hide")
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }
		glfo:InterceptGroupLootFrame(frame)
		assert.spy(hideSpy).was.called(1)
		assert.is_false(originalCalled)
	end)

	-- Test 6c: When enableLootRollActions=true and disableLootRollFrame=false, show passes through
	it("InterceptGroupLootFrame passes through when enableLootRollActions=true and disableLootRollFrame=false", function()
		ns.DbAccessor.AnyFeatureConfig = function(_, key)
			if key == "lootRolls" then
				return { enableLootRollActions = true, disableLootRollFrame = false }
			end
		end
		glfo = loadGroupLootFrameOverride(ns)
		local frame = rollFrames[2]
		local originalCalled = false
		glfo.hooks = { [frame] = { Show = function() originalCalled = true end } }
		glfo:InterceptGroupLootFrame(frame)
		assert.is_true(originalCalled)
	end)
end)

-- =============================================================================
-- Suite 4: Phase-based dismiss gating (S04) works correctly under suppression
-- =============================================================================
-- These tests verify the intersection of GroupLootFrame suppression (S05) and
-- the row dismiss lifecycle (S04).  The key invariant: suppress or not, a row
-- in pending/result phase MUST lock dismiss; a row in resolved/cancelled phase
-- MUST unlock dismiss.  The two systems are independent of each other.

local MIXIN_FILE = "RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayRow/LootRollsButtonsMixin.lua"
local ENC_ID_T03 = 2001
local LIST_ID_T03 = 5
local DROP_KEY_T03 = ENC_ID_T03 .. "_" .. LIST_ID_T03
local ROW_KEY_T03 = "LR_" .. DROP_KEY_T03
local ROLL_ID_T03 = 77

-- Load the mixin once at module level so _G.RLF_LootRollsButtonsMixin is available.
local _mixin_init_ns = {
	DbAccessor = {
		AnyFeatureConfig = function() return {} end,
		Sizing = function() return { padding = 2, iconSize = 20 } end,
		Styling = function() return { textAlignment = "LEFT" } end,
	},
	TextAlignment = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" },
	LogDebug = function() end,
}
assert(loadfile(MIXIN_FILE))("TestAddon", _mixin_init_ns)

--- Build a minimal mock row with SetClickThrough tracking for dismiss-lock tests.
local function buildDismissMockRow(nsArg)
	local clickThroughSpy = spy.new(function() end)
	local row = {
		frameType = "MAIN",
		type = nil,
		rollID = nil,
		_isClickThrough = false,
		ClickableButton = {
			_scripts = {},
			GetFrameLevel = function() return 5 end,
			SetScript = function(self, evt, fn) self._scripts[evt] = fn end,
		},
		IsMouseOver = function() return false end,
		SetClickThrough = function(self, enabled)
			self._isClickThrough = enabled
			clickThroughSpy(enabled)
		end,
	}

	for k, v in pairs(RLF_LootRollsButtonsMixin) do
		row[k] = v
	end

	row.LogDebug = function() end
	row.LogWarn = function() end

	nsArg.DbAccessor.Sizing = function(_, _ft) return { padding = 2, iconSize = 20 } end
	nsArg.DbAccessor.Styling = function(_, _ft) return { textAlignment = "LEFT" } end

	return row, clickThroughSpy
end

describe("suppress+phase: dismiss gating (S04) is independent of suppression state (S05)", function()
	local lr, ns2

	before_each(function()
		_G.GetTime = function() return 1000 end
		-- Build an ns with suppression ACTIVE (disableLootRollFrame=true).
		ns2 = makeNs(nil, nil, { disableLootRollFrame = true })
		lr = loadLootRolls(ns2)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- T03-1: pending phase + suppression → dismiss LOCKED
	it("dismiss is locked (SetClickThrough=true) during pending phase even when suppression active", function()
		local row, ctSpy = buildDismissMockRow(ns2)

		row:UpdateLootRollButtons({
			key = ROW_KEY_T03,
			rollState = "pending",
			rowPhase = "pending",
			lootListID = LIST_ID_T03,
			buttonValidity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
		})

		assert.is_true(row._isClickThrough,
			"suppress+pending: dismiss must be LOCKED regardless of suppression")
		assert.spy(ctSpy).was.called_with(true)
	end)

	-- T03-2: result phase + suppression → dismiss LOCKED
	it("dismiss is locked (SetClickThrough=true) during result phase even when suppression active", function()
		local row, ctSpy = buildDismissMockRow(ns2)

		-- Simulate pending → result transition in _dropStates.
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {}, startTime = nil, duration = nil,
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_T03, LIST_ID_T03)
		local entry = lr._dropStates[DROP_KEY_T03]
		assert.is_not_nil(entry, "drop state entry must be created by LOOT_HISTORY_UPDATE_DROP")
		assert.equals("result", entry.phase, "phase should advance to result on first fire")

		local payload = lr:BuildPayload(ENC_ID_T03, LIST_ID_T03, lr._lootRollsAdapter.GetSortedInfoForDrop(), "pending")
		assert.equals("result", payload.rowPhase)

		row:UpdateLootRollButtons(payload)

		assert.is_true(row._isClickThrough,
			"suppress+result: dismiss must be LOCKED in result phase regardless of suppression")
		assert.spy(ctSpy).was.called_with(true)
	end)

	-- T03-3: resolved phase + suppression → dismiss UNLOCKED
	it("dismiss is unlocked (SetClickThrough=false) after resolved phase even when suppression active", function()
		local row, ctSpy = buildDismissMockRow(ns2)

		-- First fire: pending → result
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {}, startTime = nil, duration = nil,
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_T03, LIST_ID_T03)

		-- Second fire: winner arrives → result → resolved
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return {
				itemHyperlink = ITEM_LINK,
				winner = { playerName = "Thrall", playerClass = "SHAMAN", roll = 95,
					state = 0, isSelf = false, isWinner = true },
				allPassed = false, isTied = false, currentLeader = nil, rollInfos = {},
			}
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_T03, LIST_ID_T03)

		local entry = lr._dropStates[DROP_KEY_T03]
		assert.equals("resolved", entry.phase, "phase must be resolved after winner arrives")

		local payload = lr:BuildPayload(ENC_ID_T03, LIST_ID_T03,
			lr._lootRollsAdapter.GetSortedInfoForDrop(), "resolved")
		assert.equals("resolved", payload.rowPhase)

		row:UpdateLootRollButtons(payload)

		assert.is_false(row._isClickThrough,
			"suppress+resolved: dismiss must be UNLOCKED after resolution regardless of suppression")
		assert.spy(ctSpy).was.called_with(false)
	end)

	-- T03-4: CANCEL_LOOT_ROLL releases dismiss lock even when suppression active
	it("CANCEL_LOOT_ROLL releases dismiss lock (phase=cancelled) even when suppression active", function()
		-- Pre-seed a pending entry linked to ROLL_ID_T03.
		lr._dropStates[DROP_KEY_T03] = {
			state = "pending",
			phase = "result",
			rollID = ROLL_ID_T03,
		}

		lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID_T03)

		assert.equals("cancelled", lr._dropStates[DROP_KEY_T03].phase,
			"CANCEL_LOOT_ROLL must advance phase to cancelled under suppression")

		-- A subsequent UpdateLootRollButtons call must unlock dismiss.
		local row, ctSpy = buildDismissMockRow(ns2)
		local payload = lr:BuildPayload(ENC_ID_T03, LIST_ID_T03,
			{ itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
			  isTied = false, currentLeader = nil, rollInfos = {} },
			"pending")
		assert.equals("cancelled", payload.rowPhase)

		row:UpdateLootRollButtons(payload)

		assert.is_false(row._isClickThrough,
			"cancelled phase must unlock dismiss (SetClickThrough=false) even with suppression active")
		assert.spy(ctSpy).was.called_with(false)
	end)

	-- T03-5: multi-drop — two rolls with independent dismiss gating states
	it("multi-drop: two concurrent rows have independent dismiss gating regardless of suppression", function()
		local ENC2, LIST2 = 2002, 6
		local KEY2 = ENC2 .. "_" .. LIST2

		-- Drop A: still in result phase (dismiss LOCKED)
		lr._dropStates[DROP_KEY_T03] = { state = "pending", phase = "result", rollID = 100 }
		-- Drop B: already resolved (dismiss UNLOCKED)
		lr._dropStates[KEY2] = { state = "resolved", phase = "resolved", rollID = 101 }

		local rowA, spyA = buildDismissMockRow(ns2)
		local rowB, spyB = buildDismissMockRow(ns2)

		local payloadA = lr:BuildPayload(ENC_ID_T03, LIST_ID_T03,
			{ itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
			  isTied = false, currentLeader = nil, rollInfos = {} }, "pending")
		local payloadB = lr:BuildPayload(ENC2, LIST2,
			{ itemHyperlink = ITEM_LINK,
			  winner = { playerName = "Jaina", playerClass = "MAGE", roll = 42,
			             state = 0, isSelf = false, isWinner = true },
			  allPassed = false, isTied = false, currentLeader = nil, rollInfos = {} }, "resolved")

		rowA:UpdateLootRollButtons(payloadA)
		rowB:UpdateLootRollButtons(payloadB)

		assert.is_true(rowA._isClickThrough,
			"drop A in result phase must have dismiss LOCKED")
		assert.is_false(rowB._isClickThrough,
			"drop B in resolved phase must have dismiss UNLOCKED")
		assert.spy(spyA).was.called_with(true)
		assert.spy(spyB).was.called_with(false)
	end)
end)
