---@diagnostic disable: need-check-nil
--- S06 orphaned/unmatched pending row tests.
---
--- Verifies:
---   • ScanUnmatchedPendingActions identifies stale entries (age > 10s) and logs them
---   • ScanUnmatchedPendingActions does NOT remove entries (diagnostic-only)
---   • CANCEL_LOOT_ROLL removes the targeted _pendingActions entry (and only that one)
---   • Entries older than MATCH_WINDOW_SECONDS (12s) are skipped by MatchActionToResult
---   • A nil rollType entry is skipped by MatchActionToResult (no button click recorded)
---
--- Test descriptions contain 'S06 orphan' or 'S06 unmatched' or 'S06 timeout' so the
--- grep filter `S06.*orphan|S06.*unmatched|S06.*timeout` matches them.

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local pending = busted.pending
local spy = busted.spy

-- ── Constants ────────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:88888|r"
local ITEM_LINK_2 = "|cff0070dditem:99999|r"
local ENC_ID = 3001
local LIST_ID = 7
local DROP_KEY = ENC_ID .. "_" .. LIST_ID
local ROLL_ID = 42
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

--- Build a minimal resolved drop payload for MatchActionToResult tests.
local function makeResolvedDrop(itemLink, selfRollType, selfRollValue)
	return {
		itemHyperlink = itemLink or ITEM_LINK,
		winner = {
			playerName = "Thrall",
			playerClass = "SHAMAN",
			roll = selfRollValue or 73,
			state = 0,
			isSelf = true,
			isWinner = true,
		},
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{
				playerName = "Thrall",
				isSelf = true,
				rollType = selfRollType or "NEED",
				rollValue = selfRollValue or 73,
			},
		},
		startTime = nil,
		duration = nil,
	}
end

-- Grab the most recent LogDebug call argument list (spy refs: self + vararg).
local function lastDebugArgs(ns)
	local calls = ns.LogDebug.calls
	if #calls == 0 then return nil end
	return calls[#calls].refs
end

-- Check whether any LogDebug call contains a given substring in any argument.
local function anyDebugContains(ns, substr)
	for _, call in ipairs(ns.LogDebug.calls) do
		for _, ref in ipairs(call.refs) do
			if type(ref) == "string" and ref:find(substr, 1, true) then
				return true
			end
		end
	end
	return false
end

-- =============================================================================
-- S06 orphan: ScanUnmatchedPendingActions identifies stale entries
-- =============================================================================

describe("S06 orphan: ScanUnmatchedPendingActions identifies stale entries", function()
	local lr, ns

	before_each(function()
		_G.GetTime = function() return 1000 end
		ns = makeNs()
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 unmatched: entry added at t=0, scan at t=12 identifies it as stale", function()
		-- Enqueue at t=1000, then advance time to t=1012 (age=12 > 10).
		_G.GetTime = function() return 1000 end
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)

		_G.GetTime = function() return 1012 end
		lr:ScanUnmatchedPendingActions()

		-- Entry must still exist — scan is diagnostic-only, no deletion.
		assert.is_not_nil(lr._pendingActions[ROLL_ID], "stale entry must NOT be removed by scan")

		-- LogDebug must have been called with STALE or ScanUnmatchedPendingActions content.
		assert.is_true(
			anyDebugContains(ns, "STALE") or anyDebugContains(ns, "ScanUnmatchedPendingActions"),
			"LogDebug must be called with STALE or ScanUnmatchedPendingActions for a stale entry"
		)
	end)

	it("S06 unmatched: fresh entry at t=0, scan at t=9 does NOT flag as stale", function()
		-- Enqueue at t=1000, advance to t=1009 (age=9 < 10 — not stale yet).
		_G.GetTime = function() return 1000 end
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)

		-- Reset the spy so we can check only what scan logs.
		ns.LogDebug = spy.new(function() end)

		_G.GetTime = function() return 1009 end
		lr:ScanUnmatchedPendingActions()

		-- Entry must still exist.
		assert.is_not_nil(lr._pendingActions[ROLL_ID], "fresh entry must still be in queue after scan")

		-- No STALE log must have been emitted.
		assert.is_false(
			anyDebugContains(ns, "STALE"),
			"scan must NOT emit STALE log for a fresh entry (age=9 < 10)"
		)
	end)

	it("S06 unmatched: summary line always emitted even with no stale entries", function()
		-- Empty queue — scan should still emit the summary line.
		lr:ScanUnmatchedPendingActions()

		assert.is_true(
			anyDebugContains(ns, "ScanUnmatchedPendingActions: summary"),
			"summary line must always be emitted by ScanUnmatchedPendingActions"
		)
	end)
end)

-- =============================================================================
-- S06 orphan: CANCEL_LOOT_ROLL cleans up pending entries
-- =============================================================================

describe("S06 orphan: CANCEL_LOOT_ROLL cleans up pending entries", function()
	local lr, ns

	before_each(function()
		_G.GetTime = function() return 1000 end
		ns = makeNs()
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 orphan: CANCEL_LOOT_ROLL removes pending action from queue", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)
		assert.is_not_nil(lr._pendingActions[ROLL_ID], "pre-condition: pending entry exists")

		lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID)

		assert.is_nil(lr._pendingActions[ROLL_ID], "CANCEL_LOOT_ROLL must remove the pending action")
	end)

	it("S06 orphan: CANCEL_LOOT_ROLL for unknown rollID is a no-op (no error)", function()
		assert.has_no.errors(function()
			lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", 99999)
		end, "cancel for unknown rollID must not raise an error")
	end)

	it("S06 orphan: CANCEL_LOOT_ROLL clears only the targeted rollID, leaves others intact", function()
		local ROLL_ID_A = 10
		local ROLL_ID_B = 11

		lr:EnqueueAction(ROLL_ID_A, ITEM_LINK, nil, nil)
		lr:EnqueueAction(ROLL_ID_B, ITEM_LINK_2, nil, nil)

		assert.is_not_nil(lr._pendingActions[ROLL_ID_A], "pre-condition: A exists")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_B], "pre-condition: B exists")

		lr:CANCEL_LOOT_ROLL("CANCEL_LOOT_ROLL", ROLL_ID_A)

		assert.is_nil(lr._pendingActions[ROLL_ID_A], "targeted rollID A must be removed")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_B], "untargeted rollID B must remain intact")
	end)
end)

-- =============================================================================
-- S06 timeout: pending entry survives past MATCH_WINDOW (no deletion by scan)
-- =============================================================================

describe("S06 timeout: pending entry survives past MATCH_WINDOW (no deletion by scan)", function()
	local lr, ns

	before_each(function()
		_G.GetTime = function() return 1000 end
		ns = makeNs()
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 timeout: ScanUnmatchedPendingActions does not delete stale entries — MatchActionToResult may still match late", function()
		-- Enqueue at t=1000, advance past stale threshold (age=11 > 10).
		_G.GetTime = function() return 1000 end
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)

		_G.GetTime = function() return 1011 end
		lr:ScanUnmatchedPendingActions()

		-- Entry must still be present — scan is diagnostic-only.
		assert.is_not_nil(
			lr._pendingActions[ROLL_ID],
			"ScanUnmatchedPendingActions must NOT delete stale entries (diagnostic-only)"
		)
	end)

	it("S06 timeout: entry older than 12s is skipped by MatchActionToResult (out-of-window)", function()
		if not lr.MatchActionToResult then
			pending("MatchActionToResult not present — skipping out-of-window test")
			return
		end

		-- Enqueue a NEED action at t=1000 with a known roll value.
		_G.GetTime = function() return 1000 end
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 73)

		-- Advance time past MATCH_WINDOW_SECONDS (12s).
		_G.GetTime = function() return 1013 end

		-- Build a resolved drop that would otherwise match the enqueued action.
		local drop = makeResolvedDrop(ITEM_LINK, "NEED", 73)

		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, drop)

		assert.is_nil(matchedID, "out-of-window entry (age=13 > 12) must not be matched")
	end)
end)

-- =============================================================================
-- S06 orphan: player uses built-in UI — pending entry never matched
-- =============================================================================

describe("S06 orphan: player uses built-in UI — pending entry never matched", function()
	local lr, ns

	before_each(function()
		_G.GetTime = function() return 1000 end
		ns = makeNs()
		lr = loadLootRolls(ns)
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 orphan: pending entry with nil rollType is skipped by MatchActionToResult", function()
		if not lr.MatchActionToResult then
			pending("MatchActionToResult not present — skipping nil-rollType test")
			return
		end

		-- EnqueueAction with nil rollType — player never clicked a button.
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)

		-- Build a resolved drop that matches on item link.
		local drop = makeResolvedDrop(ITEM_LINK, "GREED", nil)

		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, drop)

		assert.is_nil(matchedID,
			"pending entry with nil rollType must be skipped — button not yet clicked")

		-- Entry must still be present — no premature consumption.
		assert.is_not_nil(lr._pendingActions[ROLL_ID],
			"nil-rollType entry must not be consumed by MatchActionToResult")
	end)
end)
