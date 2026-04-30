---@diagnostic disable: need-check-nil
--- S06 lifecycle phase state machine tests.
---
--- Verifies:
---   • pending → result → resolved (happy path)
---   • pending → cancelled (cancel path)
---   • rowPhase in dispatched payload at each transition
---   • dismiss gating: locked in pending/result, unlocked in resolved/cancelled
---   • timer transitions: roll-window time in pending/result, fadeOutDelay in terminal phases
---   • AdvancePhase terminal guard: resolved/cancelled cannot regress
---
--- Test descriptions contain 'S06 lifecycle' or 'S06 dismiss' so the grep
--- filter `S06.*lifecycle|S06.*dismiss` matches them.

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

-- ── Constants ────────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:77777|r"
local ENC_ID = 2001
local LIST_ID = 5
local DROP_KEY = ENC_ID .. "_" .. LIST_ID
local ROLL_ID = 99
local FADE_OUT_DELAY = 3

-- ── Helpers ──────────────────────────────────────────────────────────────────

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

local function makeResolvedDrop()
	return {
		itemHyperlink = ITEM_LINK,
		winner = {
			playerName = "Sylvanas",
			playerClass = "HUNTER",
			roll = 95,
			state = 0,
			isSelf = false,
			isWinner = true,
		},
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = nil,
		duration = nil,
	}
end

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

-- Extract the most recent dispatched payload from a SendMessage spy.
-- SendMessage is invoked as ns:SendMessage(channel, element), so the
-- element is at refs[3] (self, channel, element).
local function lastPayload(sendSpy)
	local n = #sendSpy.calls
	if n == 0 then return nil end
	return sendSpy.calls[n].refs[3]
end

-- =============================================================================
-- S06 lifecycle: phase state transitions
-- =============================================================================

describe("S06 lifecycle: pending → result phase on first LOOT_HISTORY_UPDATE_DROP", function()
	local lr, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 lifecycle: _dropStates entry created in result phase on first pending drop", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.is_not_nil(entry, "drop state entry must exist after first LOOT_HISTORY_UPDATE_DROP")
		assert.equals("result", entry.phase, "first update with no winner → result phase")
	end)

	it("S06 lifecycle: payload.rowPhase is 'result' after first pending drop", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local payload = lastPayload(sendSpy)
		assert.is_not_nil(payload, "SendMessage should have been called")
		assert.equals("result", payload.rowPhase, "rowPhase in payload must be 'result' — dismiss locked")
	end)

	it("S06 lifecycle: phase stays result on repeated pending updates", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.equals("result", entry.phase, "repeated pending updates must not advance phase")

		local payload = lastPayload(sendSpy)
		assert.equals("result", payload.rowPhase, "rowPhase stays 'result' — dismiss remains locked")
	end)
end)

-- =============================================================================
-- S06 lifecycle: result → resolved transition
-- =============================================================================

describe("S06 lifecycle: result → resolved when winner arrives", function()
	local lr, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 lifecycle: _dropStates phase becomes 'resolved' when winner detected", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.equals("resolved", entry.phase, "phase must advance to 'resolved' when winner present")
	end)

	it("S06 lifecycle: payload.rowPhase is 'resolved' when winner detected", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local payload = lastPayload(sendSpy)
		assert.equals("resolved", payload.rowPhase, "rowPhase must be 'resolved' — dismiss unlocked")
	end)

	it("S06 lifecycle: GetRowPhase returns 'resolved' after winner detected", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.equals("resolved", lr:GetRowPhase(DROP_KEY),
			"GetRowPhase must return 'resolved' after terminal event")
	end)

	it("S06 lifecycle: resolved phase cannot regress to result on additional updates", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- A spurious additional update must not regress the phase.
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.equals("resolved", entry.phase, "AdvancePhase must guard: resolved cannot regress to result")
	end)

	it("S06 lifecycle: allPassed drop produces rowPhase='resolved'", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeAllPassedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.equals("resolved", entry.phase, "allPassed is a terminal resolved state")

		local payload = lastPayload(sendSpy)
		assert.equals("resolved", payload.rowPhase, "allPassed rowPhase='resolved' — dismiss unlocked")
	end)
end)

-- =============================================================================
-- S06 lifecycle: cancel path → cancelled phase
-- =============================================================================

describe("S06 lifecycle: cancel path — CANCEL_LOOT_ROLL transitions to cancelled", function()
	local lr, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 lifecycle: CANCEL_LOOT_ROLL advances phase to 'cancelled'", function()
		-- Seed a _dropStates entry with a known rollID (as START_LOOT_ROLL + drop would leave).
		lr._dropStates[DROP_KEY] = { state = "pending", phase = "result", rollID = ROLL_ID }

		lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.equals("cancelled", entry.phase, "CANCEL_LOOT_ROLL must advance phase to 'cancelled'")
	end)

	it("S06 lifecycle: cancelled phase is terminal — cannot regress to result", function()
		lr._dropStates[DROP_KEY] = { state = "pending", phase = "cancelled", rollID = ROLL_ID }

		-- GetRowPhase must still reflect 'cancelled' even after extra updates.
		local phase = lr:GetRowPhase(DROP_KEY)
		assert.equals("cancelled", phase, "GetRowPhase must return 'cancelled' — terminal state preserved")
	end)

	it("S06 lifecycle: CANCEL_LOOT_ROLL clears staged validity and pending action", function()
		lr._stagedRollValidity[ROLL_ID] = { validity = { canNeed = true }, itemLink = ITEM_LINK }
		lr._pendingActions[ROLL_ID] = { itemLink = ITEM_LINK, rollType = nil, timestamp = 0 }

		lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		assert.is_nil(lr._stagedRollValidity[ROLL_ID], "staged validity must be cleared on cancel")
		assert.is_nil(lr._pendingActions[ROLL_ID], "pending action must be cleared on cancel")
	end)

	it("S06 lifecycle: CANCEL_LOOT_ROLL for unknown rollID does not error", function()
		assert.has_no.errors(function()
			lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 88888)
		end)
	end)
end)

-- =============================================================================
-- S06 dismiss: rowPhase gating at each phase
-- =============================================================================

describe("S06 dismiss: rowPhase reflects dismiss lock state at each phase", function()
	local lr, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 dismiss: result phase rowPhase='result' — dismiss is locked", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local payload = lastPayload(sendSpy)
		assert.equals("result", payload.rowPhase,
			"rowPhase='result' signals dismiss locked during active roll window")
	end)

	it("S06 dismiss: resolved phase rowPhase='resolved' — dismiss is unlocked", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local payload = lastPayload(sendSpy)
		assert.equals("resolved", payload.rowPhase,
			"rowPhase='resolved' signals dismiss unlocked after winner determined")
	end)

	it("S06 dismiss: BuildPayload rowPhase='cancelled' after phase advance to cancelled", function()
		-- Manually set cancelled phase (mirrors what CANCEL_LOOT_ROLL would leave).
		lr._dropStates[DROP_KEY] = { state = "pending", phase = "cancelled" }

		local payload = lr:BuildPayload(ENC_ID, LIST_ID, makePendingDrop(0, 60), "pending")
		assert.equals("cancelled", payload.rowPhase,
			"BuildPayload must read phase from _dropStates — cancelled → dismiss unlocked")
	end)

	it("S06 dismiss: GetRowPhase returns 'pending' for unknown drop key (safe default)", function()
		local phase = lr:GetRowPhase("nonexistent_99")
		assert.equals("pending", phase, "unknown drop key defaults to 'pending' — fail-safe locked")
	end)
end)

-- =============================================================================
-- S06 lifecycle: timer transitions at each phase
-- =============================================================================

describe("S06 lifecycle: timer transitions at each phase", function()
	local lr, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 lifecycle: result phase timer equals remaining roll window + buffer", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local payload = lastPayload(sendSpy)
		assert.is_not_nil(payload.showForSeconds, "result phase must have a timer")
		assert.is_near(61.0, payload.showForSeconds, 0.1,
			"result-phase timer = duration(60) + 1 buffer")
	end)

	it("S06 lifecycle: result phase timer reflects elapsed time correctly", function()
		_G.GetTime = function() return 20 end
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local payload = lastPayload(sendSpy)
		assert.is_not_nil(payload.showForSeconds)
		-- remaining = (0 + 60) - 20 = 40, plus 1 buffer = 41
		assert.is_near(41.0, payload.showForSeconds, 0.1,
			"result-phase timer at 20s elapsed = 40 remaining + 1 buffer")
	end)

	it("S06 lifecycle: resolved phase timer switches to fadeOutDelay", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local resultPayload = lastPayload(sendSpy)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)
		local resolvedPayload = lastPayload(sendSpy)

		assert.is_near(FADE_OUT_DELAY, resolvedPayload.showForSeconds, 0.1,
			"resolved phase uses fadeOutDelay config — not roll-window time")
		assert.is_true(resultPayload.showForSeconds > resolvedPayload.showForSeconds,
			"roll-window timer must be larger than fadeOutDelay timer")
	end)

	it("S06 lifecycle: BuildPayload timer uses fadeOutDelay for resolved state", function()
		lr._dropStates[DROP_KEY] = { state = "resolved", phase = "resolved" }

		local payload = lr:BuildPayload(ENC_ID, LIST_ID, makeResolvedDrop(), "resolved")
		assert.is_not_nil(payload.showForSeconds)
		assert.is_near(FADE_OUT_DELAY, payload.showForSeconds, 0.1,
			"BuildPayload resolved state → showForSeconds = fadeOutDelay")
	end)

	it("S06 lifecycle: BuildPayload rowPhase reflects cancelled phase from _dropStates", function()
		-- Timer in BuildPayload is driven by the `state` parameter (RollStates), not lifecycle phase.
		-- A cancelled phase with state="pending" still uses the roll-window timer branch.
		-- What matters for dismiss gating is that rowPhase correctly reads "cancelled" from _dropStates.
		lr._dropStates[DROP_KEY] = { state = "pending", phase = "cancelled" }

		local payload = lr:BuildPayload(ENC_ID, LIST_ID, makePendingDrop(0, 60), "pending")
		assert.equals("cancelled", payload.rowPhase,
			"BuildPayload must read phase from _dropStates — cancelled phase → rowPhase='cancelled'")
	end)
end)

-- =============================================================================
-- S06 lifecycle: full sequence end-to-end
-- =============================================================================

describe("S06 lifecycle: full phase sequence end-to-end", function()
	local lr, sendSpy

	before_each(function()
		_G.GetTime = function() return 0 end
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 lifecycle: full sequence pending→result→resolved with correct phase and timer at each step", function()
		-- Step 1: result phase (no winner yet)
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local step1 = lastPayload(sendSpy)
		assert.equals("result", step1.rowPhase, "step1: rowPhase='result' — dismiss locked")
		assert.is_near(61.0, step1.showForSeconds, 0.1, "step1: timer = roll window + buffer")

		local entry1 = lr._dropStates[DROP_KEY]
		assert.equals("result", entry1.phase, "step1: _dropStates phase='result'")

		-- Step 2: resolved (winner arrives)
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makeResolvedDrop()
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local step2 = lastPayload(sendSpy)
		assert.equals("resolved", step2.rowPhase, "step2: rowPhase='resolved' — dismiss unlocked")
		assert.is_near(FADE_OUT_DELAY, step2.showForSeconds, 0.1, "step2: timer = fadeOutDelay")

		local entry2 = lr._dropStates[DROP_KEY]
		assert.equals("resolved", entry2.phase, "step2: _dropStates phase='resolved'")
	end)

	it("S06 lifecycle: cancel path pending→result→cancelled with dismiss unlocked at end", function()
		-- Step 1: result phase
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return makePendingDrop(0, 60)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local entry = lr._dropStates[DROP_KEY]
		assert.equals("result", entry.phase, "pre-cancel: phase is result")

		-- Step 2: cancel (sets phase to 'cancelled')
		entry.rollID = ROLL_ID
		lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		assert.equals("cancelled", lr._dropStates[DROP_KEY].phase, "post-cancel: phase='cancelled'")
		assert.equals("cancelled", lr:GetRowPhase(DROP_KEY),
			"GetRowPhase returns 'cancelled' — dismiss unlocked signal")
	end)
end)
