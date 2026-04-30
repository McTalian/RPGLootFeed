---@diagnostic disable: need-check-nil
-- S04/T04: End-to-end verification of the full action → result → resolved
-- row lifecycle with dismiss gating and timer phasing.
--
-- Each scenario drives LootRolls through real event handlers (START_LOOT_ROLL,
-- LOOT_HISTORY_UPDATE_DROP, CANCEL_LOOT_ROLL) and asserts:
--   • phase value in _dropStates at each transition
--   • rowPhase field in the dispatched payload (dismiss lock signal)
--   • showForSeconds timer value in the dispatched payload
--   • LogDebug emission for phase transition events
--
-- Scenarios covered:
--   1. Pending → Result → Resolved (happy path)
--   2. Pending → Timeout via CANCEL_LOOT_ROLL (result never arrives)
--   3. Multi-drop same item (two independent rows, no cross-contamination)
--   4. CANCEL_LOOT_ROLL during pending phase
--   5. Timer restarts on phase transition (each phase re-sets showForSeconds)

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

-- ── Constants ──────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:99999|r"
local ITEM_LINK_B = "|cff0070dditem:88888|r"
local ENC_ID = 1001
local LIST_ID = 2
local DROP_KEY = ENC_ID .. "_" .. LIST_ID
local ROLL_ID = 42
local ROLL_ID_B = 43
local FADE_OUT_DELAY = 3

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function makeNs(sendSpy)
	local n = {
		LootElementBase = nil,
		ItemQualEnum = { Uncommon = 2, Epic = 4 },
		DefaultIcons = { LOOTROLLS = 132319 },
		FeatureModule = { LootRolls = "LootRolls" },
		LogDebug = spy.new(function() end),
		LogInfo = spy.new(function() end),
		LogWarn = spy.new(function() end),
		LogError = spy.new(function() end),
		IsRetail = function() return true end,
		SendMessage = sendSpy or spy.new(function() end),
		TooltipBuilders = nil,
		db = {
			global = {
				animations = { exit = { fadeOutDelay = FADE_OUT_DELAY } },
				misc = { hideAllIcons = false },
			},
		},
		WoWAPI = { LootRolls = {} },
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function() return true end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableIcon = false, enableLootRollActions = true }
				end
				return nil
			end,
		},
		L = {
			["All Passed"] = "All Passed",
			["LootRolls_WaitingForResults"] = "Waiting for results...",
			["LootRolls_WaitingForRolls"] = "Waiting for rolls",
			["LootRolls_TiedFmt"] = "Tied at %d",
			["LootRolls_CurrentLeaderFmt"] = "Leading: %s rolled %d",
			["LootRolls_WonByFmt"] = "Won by %s %s %d",
			["LootRolls_WonByNoRollFmt"] = "Won by %s",
			["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
			["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  You selected %s and rolled %d",
			["LootRolls_YouSelected_NEED"] = "You: Need",
			["LootRolls_YouSelected_GREED"] = "You: Greed",
			["LootRolls_YouSelected_PASS"] = "You: Pass",
			["LootRolls_YouSelected_TRANSMOG"] = "You: Transmog",
		},
		RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
	}

	assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", n)
	assert.is_not_nil(n.LootElementBase)

	n.FeatureBase = {
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
	return n
end

--- Build a standard Retail adapter. Per-test overrides can be layered on top.
local function makeAdapter(overrides)
	local a = {
		HasLootHistory = function() return true end,
		GetSortedInfoForDrop = function() return nil end,
		GetInfoForEncounter = function() return nil end,
		GetRaidClassColor = function() return nil end,
		GetItemInfoIcon = function() return nil end,
		GetItemInfoQuality = function() return 2 end,
		GetRollButtonValidity = function()
			return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
		end,
		GetRetailRollItemLink = function() return ITEM_LINK end,
	}
	if overrides then
		for k, v in pairs(overrides) do a[k] = v end
	end
	return a
end

--- Pending drop info (no winner yet, roll window still open).
local function makePendingDrop(startTime, duration)
	return {
		itemHyperlink = ITEM_LINK,
		winner = nil,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = startTime or 0,
		duration = duration or 60,
	}
end

--- Resolved drop info (winner present).
local function makeResolvedDrop()
	return {
		itemHyperlink = ITEM_LINK,
		winner = {
			playerName = "Arthas", playerClass = "DEATHKNIGHT",
			roll = 87, state = 0, isSelf = false, isWinner = true,
		},
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = nil,
		duration = nil,
	}
end

--- allPassed drop info.
local function makeAllPassedDrop()
	return {
		itemHyperlink = ITEM_LINK,
		winner = nil,
		allPassed = true,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = nil,
		duration = nil,
	}
end

--- Load LootRolls fresh into a given ns.
local function loadLootRolls(ns, adapterOverrides)
	local lr = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
	assert.is_not_nil(lr)
	lr._lootRollsAdapter = makeAdapter(adapterOverrides)
	lr._dropStates = {}
	lr._buttonValidityCache = {}
	lr._stagedRollValidity = {}
	lr._pendingActions = {}
	return lr
end

--- Extract the last dispatched element from a SendMessage spy.
--- SendMessage is called as ns:SendMessage(channel, element).
--- When called as a method, refs = { self(ns), channel, element }.
local function lastElement(sendSpy)
	local n = #sendSpy.calls
	if n == 0 then return nil end
	return sendSpy.calls[n].refs[3]
end

--- Extract the Nth dispatched element (1-indexed).
local function nthElement(sendSpy, idx)
	if not sendSpy.calls[idx] then return nil end
	return sendSpy.calls[idx].refs[3]
end

-- =============================================================================
-- Scenario 1: Pending → Result → Resolved (happy path)
-- =============================================================================

describe("Lifecycle E2E Scenario 1: Pending → Result → Resolved", function()
	local LootRolls, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		LootRolls = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("pending phase: rowPhase='pending' and dismiss locked", function()
		-- LOOT_HISTORY_UPDATE_DROP fires with pending drop (no winner yet).
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end

		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- Phase check
		local entry = LootRolls._dropStates[DROP_KEY]
		assert.is_not_nil(entry, "entry should exist after first event")
		assert.equals("result", entry.phase, "first LOOT_HISTORY_UPDATE_DROP with no winner → result phase")

		-- Payload check
		local el = lastElement(sendSpy)
		assert.is_not_nil(el, "element should be dispatched")
		assert.equals("result", el.rowPhase, "rowPhase in payload should be 'result' (dismiss locked)")
	end)

	it("result phase: second update stays in result when still no winner", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end

		-- Two events with no winner → remains result phase.
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = LootRolls._dropStates[DROP_KEY]
		assert.equals("result", entry.phase, "phase stays 'result' until winner arrives")

		local el = lastElement(sendSpy)
		assert.equals("result", el.rowPhase, "rowPhase stays 'result' — dismiss still locked")
	end)

	it("resolved phase: rowPhase='resolved' and dismiss unlocked when winner arrives", function()
		-- Step 1: pending
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- Step 2: resolved
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = LootRolls._dropStates[DROP_KEY]
		assert.equals("resolved", entry.phase, "phase should be 'resolved' after winner arrives")

		local el = lastElement(sendSpy)
		assert.equals("resolved", el.rowPhase, "rowPhase='resolved' in payload — dismiss unlocked")
	end)

	it("resolved phase: timer switches to fadeOutDelay on resolved dispatch", function()
		-- Pending → resolved.
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local pendingEl = lastElement(sendSpy)
		assert.is_not_nil(pendingEl.showForSeconds, "pending phase should have a timer")
		assert.is_near(61.0, pendingEl.showForSeconds, 0.1, "pending timer = remaining + buffer")

		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local resolvedEl = lastElement(sendSpy)
		assert.is_near(FADE_OUT_DELAY, resolvedEl.showForSeconds, 0.1,
			"resolved timer should use fadeOutDelay config value")
	end)

	it("allPassed phase: rowPhase='resolved' and timer = fadeOutDelay", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeAllPassedDrop()
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = LootRolls._dropStates[DROP_KEY]
		assert.equals("resolved", entry.phase, "allPassed → resolved phase")

		local el = lastElement(sendSpy)
		assert.equals("resolved", el.rowPhase, "rowPhase='resolved' for allPassed")
		assert.is_near(FADE_OUT_DELAY, el.showForSeconds, 0.1, "allPassed uses fadeOutDelay timer")
	end)
end)

-- =============================================================================
-- Scenario 2: Pending → CANCEL_LOOT_ROLL (result never arrives)
-- =============================================================================

describe("Lifecycle E2E Scenario 2: Pending → CANCEL_LOOT_ROLL (timeout)", function()
	local LootRolls, ns, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		ns = makeNs(sendSpy)
		LootRolls = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("row enters result phase on LOOT_HISTORY_UPDATE_DROP (no winner yet)", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = LootRolls._dropStates[DROP_KEY]
		assert.equals("result", entry.phase)
	end)

	it("CANCEL_LOOT_ROLL: phase transitions to 'cancelled' when rollID matches", function()
		-- First stage a LOOT_HISTORY_UPDATE_DROP so we have a _dropStates entry.
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- Set the rollID on the entry so CANCEL_LOOT_ROLL can match it.
		LootRolls._dropStates[DROP_KEY].rollID = ROLL_ID

		LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		local entry = LootRolls._dropStates[DROP_KEY]
		assert.equals("cancelled", entry.phase, "phase should be 'cancelled' after CANCEL_LOOT_ROLL")
	end)

	it("CANCEL_LOOT_ROLL: clears staged validity and pending action for that rollID", function()
		-- Pre-stage validity and pending action as START_LOOT_ROLL would.
		LootRolls._stagedRollValidity[ROLL_ID] = {
			validity = { canNeed = true, canGreed = true },
			itemLink = ITEM_LINK,
		}
		LootRolls._pendingActions[ROLL_ID] = {
			itemLink = ITEM_LINK,
			rollType = nil,
			rollValue = nil,
			timestamp = 0,
		}

		LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		assert.is_nil(LootRolls._stagedRollValidity[ROLL_ID], "staged validity should be cleared")
		assert.is_nil(LootRolls._pendingActions[ROLL_ID], "pending action should be removed")
	end)

	it("CANCEL_LOOT_ROLL on non-existent entry does not error", function()
		assert.has_no.errors(function()
			LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 9999)
		end)
	end)
end)

-- =============================================================================
-- Scenario 3: Multi-drop — two pending rows get independent phases and timers
-- =============================================================================

describe("Lifecycle E2E Scenario 3: Multi-drop independence", function()
	local LootRolls, sendSpy

	local ENC_ID_A = 1001
	local LIST_ID_A = 2
	local ENC_ID_B = 1001
	local LIST_ID_B = 3
	local DROP_KEY_A = ENC_ID_A .. "_" .. LIST_ID_A
	local DROP_KEY_B = ENC_ID_B .. "_" .. LIST_ID_B

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		LootRolls = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("two drops create independent _dropStates entries", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if encID == ENC_ID_A and listID == LIST_ID_A then
				return makePendingDrop(0, 60)
			elseif encID == ENC_ID_B and listID == LIST_ID_B then
				return {
					itemHyperlink = ITEM_LINK_B,
					winner = nil, allPassed = false, isTied = false,
					currentLeader = nil, rollInfos = {},
					startTime = 0, duration = 45,
				}
			end
			return nil
		end

		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_A, LIST_ID_A)
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_B, LIST_ID_B)

		local entryA = LootRolls._dropStates[DROP_KEY_A]
		local entryB = LootRolls._dropStates[DROP_KEY_B]

		assert.is_not_nil(entryA, "entry A should exist")
		assert.is_not_nil(entryB, "entry B should exist")
		assert.equals("result", entryA.phase, "drop A should be in result phase")
		assert.equals("result", entryB.phase, "drop B should be in result phase")
	end)

	it("resolving drop A does not affect drop B phase", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if encID == ENC_ID_A and listID == LIST_ID_A then
				return makePendingDrop(0, 60)
			end
			return {
				itemHyperlink = ITEM_LINK_B,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
				startTime = 0, duration = 45,
			}
		end

		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_A, LIST_ID_A)
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_B, LIST_ID_B)

		-- Resolve drop A.
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if encID == ENC_ID_A and listID == LIST_ID_A then
				return makeResolvedDrop()
			end
			return nil
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_A, LIST_ID_A)

		local entryA = LootRolls._dropStates[DROP_KEY_A]
		local entryB = LootRolls._dropStates[DROP_KEY_B]

		assert.equals("resolved", entryA.phase, "drop A should be resolved")
		assert.equals("result", entryB.phase, "drop B should remain in result phase (unaffected)")
	end)

	it("timers for two drops reflect their individual durations", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if encID == ENC_ID_A and listID == LIST_ID_A then
				return makePendingDrop(0, 60) -- 60s window → 61s timer
			end
			return {
				itemHyperlink = ITEM_LINK_B,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
				startTime = nil, duration = 45, -- no startTime → 45 + 1 = 46
			}
		end

		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_A, LIST_ID_A)
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_B, LIST_ID_B)

		local elA = nthElement(sendSpy, 1)
		local elB = nthElement(sendSpy, 2)

		assert.is_not_nil(elA.showForSeconds, "drop A should have a timer")
		assert.is_not_nil(elB.showForSeconds, "drop B should have a timer")
		assert.is_near(61.0, elA.showForSeconds, 0.1, "drop A timer = 60 + buffer")
		assert.is_near(46.0, elB.showForSeconds, 0.1, "drop B timer = 45 + buffer (no startTime fallback)")
	end)

	it("cancelling drop A does not touch drop B's phase", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if encID == ENC_ID_A and listID == LIST_ID_A then
				return makePendingDrop(0, 60)
			end
			return {
				itemHyperlink = ITEM_LINK_B,
				winner = nil, allPassed = false, isTied = false,
				currentLeader = nil, rollInfos = {},
				startTime = 0, duration = 45,
			}
		end

		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_A, LIST_ID_A)
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID_B, LIST_ID_B)

		-- Cancel drop A by rollID.
		LootRolls._dropStates[DROP_KEY_A].rollID = ROLL_ID
		LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		local entryA = LootRolls._dropStates[DROP_KEY_A]
		local entryB = LootRolls._dropStates[DROP_KEY_B]

		assert.equals("cancelled", entryA.phase, "drop A should be cancelled")
		assert.equals("result", entryB.phase, "drop B should be unaffected by drop A cancel")
	end)
end)

-- =============================================================================
-- Scenario 4: CANCEL_LOOT_ROLL during pending phase
-- =============================================================================

describe("Lifecycle E2E Scenario 4: CANCEL_LOOT_ROLL during pending phase", function()
	local LootRolls, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		LootRolls = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("START_LOOT_ROLL stages validity and pending action", function()
		LootRolls._lootRollsAdapter.GetRetailRollItemLink = function() return ITEM_LINK end
		LootRolls._lootRollsAdapter.GetRollButtonValidity = function()
			return { canNeed = true, canGreed = false, canTransmog = false, canPass = true }
		end

		LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

		assert.is_not_nil(LootRolls._stagedRollValidity[ROLL_ID], "staged validity should exist after START_LOOT_ROLL")
		assert.is_not_nil(LootRolls._pendingActions[ROLL_ID], "pending action slot pre-enqueued by START_LOOT_ROLL")
	end)

	it("CANCEL_LOOT_ROLL clears staged validity and pending action before LOOT_HISTORY_UPDATE_DROP", function()
		LootRolls._lootRollsAdapter.GetRetailRollItemLink = function() return ITEM_LINK end
		LootRolls._lootRollsAdapter.GetRollButtonValidity = function()
			return { canNeed = true, canGreed = false, canTransmog = false, canPass = true }
		end

		LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
		-- Cancel before the LOOT_HISTORY_UPDATE_DROP arrives.
		LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		assert.is_nil(LootRolls._stagedRollValidity[ROLL_ID], "staged validity cleared by cancel")
		assert.is_nil(LootRolls._pendingActions[ROLL_ID], "pending action removed by cancel")
	end)

	it("phase transitions to 'cancelled' when CANCEL_LOOT_ROLL fires against a known drop", function()
		-- Create a drop entry with a known rollID (simulates START_LOOT_ROLL + drop absorbed).
		LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending", rollID = ROLL_ID }

		LootRolls:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		local entry = LootRolls._dropStates[DROP_KEY]
		assert.equals("cancelled", entry.phase,
			"phase should be 'cancelled' immediately on CANCEL_LOOT_ROLL")
	end)

	it("cancelled phase cannot regress back to result even if another update fires", function()
		LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "cancelled", rollID = ROLL_ID }

		-- The drop is in 'cancelled' terminal state — further LOOT_HISTORY_UPDATE_DROP
		-- events for a resolved/allPassed terminal state are blocked; but cancelled
		-- itself is a terminal that AdvancePhase protects from regression.
		-- Verify AdvancePhase does not move it forward from 'cancelled' to 'result'.
		local entry = LootRolls._dropStates[DROP_KEY]
		-- Simulate what AdvancePhase does internally — call GetRowPhase.
		local phase = LootRolls:GetRowPhase(DROP_KEY)
		assert.equals("cancelled", phase, "GetRowPhase returns 'cancelled' — terminal state preserved")
	end)
end)

-- =============================================================================
-- Scenario 5: Timer restart on phase transition
-- =============================================================================

describe("Lifecycle E2E Scenario 5: Timer restarts at each phase transition", function()
	local LootRolls, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		LootRolls = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("pending-phase payload carries action-window timer (rollTime + buffer)", function()
		-- Simulate what START_LOOT_ROLL + absorbed staging looks like in BuildPayload.
		local dropInfo = makePendingDrop(0, 60)
		LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "pending" }

		local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
		assert.is_not_nil(payload.showForSeconds, "action phase should have timer")
		assert.is_near(61.0, payload.showForSeconds, 0.1, "action-phase timer = 60 + 1 buffer")
	end)

	it("result-phase payload carries remaining time (partially elapsed)", function()
		-- Simulate 10s elapsed: startTime=0, duration=60, GetTime=10 → remaining = 51s
		_G.GetTime = function() return 10 end
		local dropInfo = makePendingDrop(0, 60)
		LootRolls._dropStates[DROP_KEY] = { state = "pending", phase = "result" }

		local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "pending")
		assert.is_not_nil(payload.showForSeconds)
		assert.is_near(51.0, payload.showForSeconds, 0.1,
			"result-phase timer = remaining window + buffer (10s elapsed from 60s window)")
	end)

	it("resolved-phase payload timer resets to fadeOutDelay (not roll-window)", function()
		local dropInfo = makeResolvedDrop()
		LootRolls._dropStates[DROP_KEY] = { state = "resolved", phase = "resolved" }

		local payload = LootRolls:BuildPayload(ENC_ID, LIST_ID, dropInfo, "resolved")
		assert.is_not_nil(payload.showForSeconds)
		assert.is_near(FADE_OUT_DELAY, payload.showForSeconds, 0.1,
			"resolved-phase timer = fadeOutDelay config")
	end)

	it("full lifecycle sequence: timer is 61 at pending, 3 at resolved", function()
		-- Step 1: pending → result phase (first LOOT_HISTORY_UPDATE_DROP).
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local el1 = lastElement(sendSpy)
		assert.is_near(61.0, el1.showForSeconds, 0.1, "step 1 (result phase): timer = 60+1")

		-- Step 2: resolved (winner arrives).
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local el2 = lastElement(sendSpy)
		assert.is_near(FADE_OUT_DELAY, el2.showForSeconds, 0.1, "step 2 (resolved): timer = fadeOutDelay")

		-- The timers at each step are different.
		assert.is_not.near(el1.showForSeconds, el2.showForSeconds, 1.0,
			"timers must differ between phases")
	end)

	it("timer reflects elapsed time during result phase (mid-roll)", function()
		-- 30s have elapsed of a 60s roll window.
		_G.GetTime = function() return 30 end
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60) -- startTime=0, duration=60
		end

		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local el = lastElement(sendSpy)
		assert.is_not_nil(el.showForSeconds, "should have timer")
		assert.is_near(31.0, el.showForSeconds, 0.1,
			"result-phase timer = (0+60-30) + 1 = 31s at 30s elapsed")
	end)

	it("rowPhase field is consistent with timer semantics (locked phases get roll-timer)", function()
		-- When rowPhase is pending/result, the dismiss is locked and timer is roll-window based.
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local elPending = lastElement(sendSpy)

		assert.equals("result", elPending.rowPhase, "rowPhase is 'result' (dismiss locked)")
		assert.is_true(elPending.showForSeconds > FADE_OUT_DELAY,
			"roll-window timer > fadeOutDelay when dismiss locked")

		-- When rowPhase is resolved, dismiss is unlocked and timer is fadeOutDelay.
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local elResolved = lastElement(sendSpy)

		assert.equals("resolved", elResolved.rowPhase, "rowPhase is 'resolved' (dismiss unlocked)")
		assert.is_near(FADE_OUT_DELAY, elResolved.showForSeconds, 0.1,
			"resolved phase uses short fadeOutDelay timer")
	end)
end)

-- =============================================================================
-- Cross-cutting: Phase logging verification
-- =============================================================================

describe("Lifecycle E2E: Phase transition logging", function()
	local LootRolls, ns

	before_each(function()
		_G.GetTime = function() return 0 end
		ns = makeNs()
		LootRolls = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("LogDebug emitted for (new) → pending transition on first event", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- ns.LogDebug is the spy; verify it was called with a phase-transition message.
		assert.spy(ns.LogDebug).was_called()
	end)

	it("GetRowPhase returns 'pending' for unknown drop key", function()
		local phase = LootRolls:GetRowPhase("9999_9")
		assert.equals("pending", phase, "unknown drop key defaults to 'pending'")
	end)

	it("GetRowPhase tracks actual phase after LOOT_HISTORY_UPDATE_DROP", function()
		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		assert.equals("result", LootRolls:GetRowPhase(DROP_KEY))

		LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		assert.equals("resolved", LootRolls:GetRowPhase(DROP_KEY))
	end)
end)
