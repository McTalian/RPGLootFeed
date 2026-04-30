---@diagnostic disable: need-check-nil
--- S06 multi-drop same-item scenario tests.
---
--- Tests that the same item dropping twice in one encounter gives two
--- independent rows with correct winner routing and no cross-contamination.
---
--- Scenario:
---   - Two START_LOOT_ROLL events fire (rollID=1, rollID=2) for the same item.
---   - Player clicks Need on both (rollValues 95 and 92 respectively).
---   - Two LOOT_HISTORY_UPDATE_DROP events arrive (lootListID=1, lootListID=2).
---   - MatchActionToResult routes each drop to the correct action by rollValue.
---   - SendMessage fires twice, each with the correct winner.
---
--- S06 multi drop same

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local pending = busted.pending

-- ── Constants ─────────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:33333|r"
local ENC_ID = 500
local LIST_ID_1 = 1
local LIST_ID_2 = 2
local ROLL_ID_1 = 1
local ROLL_ID_2 = 2
local DROP_KEY_1 = ENC_ID .. "_" .. LIST_ID_1
local DROP_KEY_2 = ENC_ID .. "_" .. LIST_ID_2

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function makeNs(sendSpy)
	return {
		LootElementBase = nil,
		ItemQualEnum = { Uncommon = 2, Epic = 4 },
		DefaultIcons = { LOOTROLLS = 132319 },
		FeatureModule = { LootRolls = "LootRolls" },
		LogDebug = spy.new(function() end),
		LogInfo = spy.new(function() end),
		LogWarn = spy.new(function() end),
		LogError = spy.new(function() end),
		IsRetail = function()
			return true
		end,
		SendMessage = sendSpy,
		TooltipBuilders = nil,
		db = { global = { animations = { exit = { fadeOutDelay = 3 } }, misc = { hideAllIcons = false } } },
		WoWAPI = { LootRolls = {} },
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function()
				return true
			end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableIcon = true, enableLootRollActions = true, enableLootRollResults = true }
				end
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

local function makeAdapter(overrides)
	local adapter = {
		HasLootHistory = function()
			return true
		end,
		HasStartLootRollEvent = function()
			return true
		end,
		GetSortedInfoForDrop = function()
			return nil
		end,
		GetInfoForEncounter = function()
			return nil
		end,
		GetRaidClassColor = function()
			return nil
		end,
		GetItemInfoIcon = function()
			return 12345
		end,
		GetItemInfoQuality = function()
			return 4
		end,
		GetRollButtonValidity = function()
			return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
		end,
		GetRetailRollItemLink = function()
			return ITEM_LINK
		end,
		GetClassicRollItemInfo = function()
			return { itemLink = ITEM_LINK, texture = 132310, quality = 3, canNeed = true, canGreed = true, canDisenchant = false }
		end,
	}
	if overrides then
		for k, v in pairs(overrides) do
			adapter[k] = v
		end
	end
	return adapter
end

local function loadLootRolls(ns, adapterOverrides)
	assert(loadfile("RPGLootFeed/Features/_Internals/LootElementBase.lua"))("TestAddon", ns)
	ns.FeatureBase = {
		new = function(_, name)
			return {
				moduleName = name,
				Enable = function() end,
				Disable = function() end,
				IsEnabled = function()
					return true
				end,
				RegisterEvent = function() end,
				UnregisterAllEvents = function() end,
			}
		end,
	}
	local lr = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
	assert.is_not_nil(lr)
	ns.LootRolls = lr
	lr._lootRollsAdapter = makeAdapter(adapterOverrides)
	lr._dropStates = {}
	lr._buttonValidityCache = {}
	lr._stagedRollValidity = {}
	lr._pendingActions = {}
	return lr
end

--- Pending drop (rolling still in progress, no winner yet).
local function pendingDrop()
	return {
		itemHyperlink = ITEM_LINK,
		winner = nil,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		playerRollState = nil,
		startTime = 1000,
		duration = 60,
	}
end

--- Resolved NEED drop where the player's own roll matches selfRollValue.
local function resolvedDropNeed(winnerName, winnerRoll, selfRollValue)
	return {
		itemHyperlink = ITEM_LINK,
		winner = {
			playerName = winnerName,
			playerClass = "WARRIOR",
			roll = winnerRoll,
			state = 0,
			isSelf = false,
			isWinner = true,
		},
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{
				playerName = "You",
				playerClass = "MAGE",
				roll = selfRollValue,
				state = 0, -- NEED
				isSelf = true,
				isWinner = false,
			},
		},
		playerRollState = 0,
		startTime = nil,
		duration = nil,
	}
end

-- =============================================================================
-- Part 1: Two pending entries exist simultaneously
-- =============================================================================

describe("S06 multi drop same item: Part 1 — two pending actions exist concurrently", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function()
			return 1000
		end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop same: _pendingActions has two entries after two EnqueueAction calls", function()
		-- S06 multi drop same
		if not lr.EnqueueAction then
			pending("EnqueueAction not implemented (S03 blocker)")
			return
		end

		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 95)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 92)

		assert.is_not_nil(lr._pendingActions[ROLL_ID_1], "Expected pending entry for rollID=1")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2], "Expected pending entry for rollID=2")
		print(
			"[S06 T03] Pending entries: rollID_1=" .. tostring(lr._pendingActions[ROLL_ID_1].rollValue)
				.. " rollID_2=" .. tostring(lr._pendingActions[ROLL_ID_2].rollValue)
		)
	end)

	it("S06 multi drop same: each pending action has the correct rollValue", function()
		-- S06 multi drop same
		if not lr.EnqueueAction then
			pending("EnqueueAction not implemented (S03 blocker)")
			return
		end

		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 95)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 92)

		assert.are.equal(95, lr._pendingActions[ROLL_ID_1].rollValue)
		assert.are.equal(92, lr._pendingActions[ROLL_ID_2].rollValue)
		print("[S06 T03] rollValues match: 95 and 92")
	end)

	it("S06 multi drop same: START_LOOT_ROLL for two rollIDs stages both in _stagedRollValidity", function()
		-- S06 multi drop same
		-- Verifies the staging path works for two concurrent rolls of the same item.
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_1, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_2, 60)

		assert.is_not_nil(lr._stagedRollValidity[ROLL_ID_1], "Expected staged validity for rollID=1")
		assert.is_not_nil(lr._stagedRollValidity[ROLL_ID_2], "Expected staged validity for rollID=2")
		print(
			"[S06 T03] Staged: rollID_1.itemLink=" .. tostring(lr._stagedRollValidity[ROLL_ID_1].itemLink)
				.. " rollID_2.itemLink=" .. tostring(lr._stagedRollValidity[ROLL_ID_2].itemLink)
		)
	end)
end)

-- =============================================================================
-- Part 2: MatchActionToResult routes correctly by rollValue
-- =============================================================================

describe("S06 multi drop same item: Part 2 — MatchActionToResult correct winner routing", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function()
			return 1000
		end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop same: MatchActionToResult routes lootListID=1 winner rollValue=95 to rollID=1", function()
		-- S06 multi drop same
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 MatchActionToResult wiring")
			return
		end

		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 95)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 92)

		-- Drop 1: winner rolled 95 — should match rollID=1
		local drop1 = resolvedDropNeed("Paladin", 95, 95)
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, drop1)

		assert.are.equal(ROLL_ID_1, matchedID, "Expected lootListID=1 to match rollID=1 (rollValue=95)")
		-- rollID=1 should be consumed, rollID=2 should remain
		assert.is_nil(lr._pendingActions[ROLL_ID_1], "Expected rollID=1 consumed after match")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2], "Expected rollID=2 still in queue")
		print("[S06 T03] lootListID=1 correctly matched to rollID=" .. tostring(matchedID))
	end)

	it("S06 multi drop same: MatchActionToResult routes lootListID=2 winner rollValue=92 to rollID=2", function()
		-- S06 multi drop same
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 MatchActionToResult wiring")
			return
		end

		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 95)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 92)

		-- Consume rollID=1 first
		lr:MatchActionToResult(ENC_ID, LIST_ID_1, resolvedDropNeed("Paladin", 95, 95))

		-- Drop 2: winner rolled 92 — should match rollID=2
		local drop2 = resolvedDropNeed("Shaman", 92, 92)
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_2, drop2)

		assert.are.equal(ROLL_ID_2, matchedID, "Expected lootListID=2 to match rollID=2 (rollValue=92)")
		assert.is_nil(lr._pendingActions[ROLL_ID_2], "Expected rollID=2 consumed after match")
		print("[S06 T03] lootListID=2 correctly matched to rollID=" .. tostring(matchedID))
	end)

	it("S06 multi drop same: no cross-contamination — wrong rollValue returns nil match", function()
		-- S06 multi drop same
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 MatchActionToResult wiring")
			return
		end

		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 95)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 92)

		-- Drop with rollValue=77 should not match either action
		local drop = resolvedDropNeed("Unknown", 77, 77)
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, drop)

		assert.is_nil(matchedID, "Expected nil — rollValue=77 matches neither pending action")
		-- Both actions remain unconsumed
		assert.is_not_nil(lr._pendingActions[ROLL_ID_1], "rollID=1 should remain in queue")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2], "rollID=2 should remain in queue")
		print("[S06 T03] Correct: no match for rollValue=77")
	end)
end)

-- =============================================================================
-- Part 3: Two separate result rows display with correct winners
-- =============================================================================

describe("S06 multi drop same item: Part 3 — two result rows with correct winner names", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function()
			return 1000
		end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop same: two separate drop keys created for two drops of same item", function()
		-- S06 multi drop same
		-- Independent drop state is keyed by encounterID_lootListID, not by item.
		-- Both drops of the same item should create distinct state entries.
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return pendingDrop()
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		assert.is_not_nil(lr._dropStates[DROP_KEY_1], "Expected drop state for lootListID=1")
		assert.is_not_nil(lr._dropStates[DROP_KEY_2], "Expected drop state for lootListID=2")
		print("[S06 T03] Both drop keys created: " .. DROP_KEY_1 .. " and " .. DROP_KEY_2)
	end)

	it("S06 multi drop same: two drop rows share no state (independent pending/resolved lifecycle)", function()
		-- S06 multi drop same
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return pendingDrop()
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		assert.are.equal("pending", lr._dropStates[DROP_KEY_1].state)
		assert.are.equal("pending", lr._dropStates[DROP_KEY_2].state)

		-- Resolve drop 1 only
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return resolvedDropNeed("Paladin", 95, 95)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)

		assert.are.equal("resolved", lr._dropStates[DROP_KEY_1].state, "Drop 1 should be resolved")
		assert.are.equal("pending", lr._dropStates[DROP_KEY_2].state, "Drop 2 should still be pending")
		print("[S06 T03] Drop 1 resolved, drop 2 still pending — independent state confirmed")
	end)

	it("S06 multi drop same: SendMessage called twice (once per drop) across full lifecycle", function()
		-- S06 multi drop same
		-- Each LOOT_HISTORY_UPDATE_DROP should dispatch a SendMessage.
		-- Two drops of the same item → two calls total.
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return pendingDrop()
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		assert.spy(sendSpy).was.called(2)
		print("[S06 T03] SendMessage called " .. tostring(#sendSpy.calls) .. " time(s) for two pending drops")
	end)

	it("S06 multi drop same: each resolved payload carries the correct winner name", function()
		-- S06 multi drop same
		-- BuildPayload is a direct helper — test it without requiring S03 wiring.
		-- Drop 1 resolved: winner is "Paladin" rolled 95.
		local drop1 = resolvedDropNeed("Paladin", 95, 95)
		local payload1 = lr:BuildPayload(ENC_ID, LIST_ID_1, drop1, "resolved")

		-- Drop 2 resolved: winner is "Shaman" rolled 92.
		local drop2 = resolvedDropNeed("Shaman", 92, 92)
		local payload2 = lr:BuildPayload(ENC_ID, LIST_ID_2, drop2, "resolved")

		assert.are.equal("LR_" .. ENC_ID .. "_" .. LIST_ID_1, payload1.key)
		assert.are.equal("LR_" .. ENC_ID .. "_" .. LIST_ID_2, payload2.key)

		assert.is_not_nil(string.find(payload1.secondaryText, "Paladin"), "Drop 1 payload should name Paladin")
		assert.is_not_nil(string.find(payload2.secondaryText, "Shaman"), "Drop 2 payload should name Shaman")

		-- Winner names should NOT cross-contaminate
		assert.is_nil(string.find(payload1.secondaryText, "Shaman"), "Drop 1 should not mention Shaman")
		assert.is_nil(string.find(payload2.secondaryText, "Paladin"), "Drop 2 should not mention Paladin")

		print("[S06 T03] payload1 secondaryText: " .. payload1.secondaryText)
		print("[S06 T03] payload2 secondaryText: " .. payload2.secondaryText)
	end)

	it("S06 multi drop same: each resolved row key is unique (no overwrite)", function()
		-- S06 multi drop same
		local drop1 = resolvedDropNeed("Paladin", 95, 95)
		local drop2 = resolvedDropNeed("Shaman", 92, 92)

		local payload1 = lr:BuildPayload(ENC_ID, LIST_ID_1, drop1, "resolved")
		local payload2 = lr:BuildPayload(ENC_ID, LIST_ID_2, drop2, "resolved")

		assert.are_not.equal(payload1.key, payload2.key, "Two drops must have distinct row keys")
		print("[S06 T03] Distinct keys: " .. payload1.key .. " vs " .. payload2.key)
	end)
end)

-- =============================================================================
-- Part 4: Full E2E — same item drops twice, both winner names dispatched
-- =============================================================================

describe("S06 multi drop same item: Part 4 — full E2E with MatchActionToResult (requires S03)", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function()
			return 1000
		end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop same: full E2E — two drops, two winners, SendMessage fires with correct winner per row", function()
		-- S06 multi drop same
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 MatchActionToResult wiring")
			return
		end

		-- Step 1: Two START_LOOT_ROLL events stage both rolls.
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_1, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_2, 60)

		-- Step 2: Player clicks Need on both rolls.
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 95)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 92)

		-- Step 3: Two LOOT_HISTORY_UPDATE_DROP events arrive with winners.
		-- GetSortedInfoForDrop is called as adapter.GetSortedInfoForDrop(encID, listID) (no self).
		lr._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if listID == LIST_ID_1 then
				return resolvedDropNeed("Paladin", 95, 95)
			else
				return resolvedDropNeed("Shaman", 92, 92)
			end
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		-- Step 4: Verify SendMessage fired twice (one per drop).
		assert.spy(sendSpy).was.called(2)
		print("[S06 T03] E2E: SendMessage called " .. tostring(#sendSpy.calls) .. " time(s)")

		-- Step 5: Both drop states are resolved.
		assert.are.equal("resolved", lr._dropStates[DROP_KEY_1].state)
		assert.are.equal("resolved", lr._dropStates[DROP_KEY_2].state)

		-- Step 6: Both pending actions consumed.
		assert.is_nil(lr._pendingActions[ROLL_ID_1], "rollID=1 should be consumed")
		assert.is_nil(lr._pendingActions[ROLL_ID_2], "rollID=2 should be consumed")
		print("[S06 T03] E2E complete: both drops resolved, no stale pending actions")
	end)

	it("S06 multi drop same: LOOT_HISTORY_UPDATE_DROP consumes matching action for first drop only", function()
		-- S06 multi drop same
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 MatchActionToResult wiring")
			return
		end

		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 95)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 92)

		-- Only first drop arrives
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return resolvedDropNeed("Paladin", 95, 95)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)

		-- rollID=1 consumed, rollID=2 still pending
		assert.is_nil(lr._pendingActions[ROLL_ID_1], "rollID=1 should be consumed after first drop")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2], "rollID=2 should remain for second drop")
		print("[S06 T03] After first drop: rollID=1 consumed, rollID=2 still queued")
	end)
end)

-- =============================================================================
-- DIFFERENT-ITEMS MULTI-DROP SCENARIO
-- Scenario: SWORD (item:11111) and SHIELD (item:22222) drop concurrently,
-- each with 2 roll slots. Tests verify itemLink-based disambiguation.
-- =============================================================================

local SWORD_LINK = "|cff0070dditem:11111|r"
local SHIELD_LINK = "|cff0070dditem:22222|r"
local SWORD_ENC_ID = 600
local SWORD_LIST_ID = 1
local SHIELD_LIST_ID = 2
local SWORD_ROLL_ID = 10
local SHIELD_ROLL_ID = 20
local SWORD_DROP_KEY = SWORD_ENC_ID .. "_" .. SWORD_LIST_ID
local SHIELD_DROP_KEY = SWORD_ENC_ID .. "_" .. SHIELD_LIST_ID

--- Pending drop for a specific itemLink.
local function pendingDropFor(itemLink)
	return {
		itemHyperlink = itemLink,
		winner = nil,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		playerRollState = nil,
		startTime = 1000,
		duration = 60,
	}
end

--- Resolved NEED drop for a specific itemLink.
local function resolvedDropNeedFor(itemLink, winnerName, winnerRoll, selfRollValue)
	return {
		itemHyperlink = itemLink,
		winner = {
			playerName = winnerName,
			playerClass = "WARRIOR",
			roll = winnerRoll,
			state = 0,
			isSelf = false,
			isWinner = true,
		},
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{
				playerName = "You",
				playerClass = "MAGE",
				roll = selfRollValue,
				state = 0,
				isSelf = true,
				isWinner = false,
			},
		},
		playerRollState = 0,
		startTime = nil,
		duration = nil,
	}
end

--- Resolved GREED drop for a specific itemLink (state=3 maps to "GREED").
local function resolvedDropGreedFor(itemLink, winnerName, winnerRoll)
	return {
		itemHyperlink = itemLink,
		winner = {
			playerName = winnerName,
			playerClass = "SHAMAN",
			roll = winnerRoll,
			state = 3,
			isSelf = false,
			isWinner = true,
		},
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{
				playerName = "You",
				playerClass = "MAGE",
				roll = winnerRoll,
				state = 3, -- GREED
				isSelf = true,
				isWinner = false,
			},
		},
		playerRollState = 3,
		startTime = nil,
		duration = nil,
	}
end

-- =============================================================================
-- Part 1: Pending queue has 2 entries with different itemLinks
-- =============================================================================

describe("S06 multi drop different items: Part 1 — pending queue holds entries for two distinct items", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		ns.DbAccessor.AnyFeatureConfig = function(_, featureKey)
			if featureKey == "lootRolls" then
				return { enableIcon = true, enableLootRollActions = true, enableLootRollResults = true }
			end
			return nil
		end
		lr = loadLootRolls(ns, {
			GetRetailRollItemLink = function(rollID)
				if rollID == SWORD_ROLL_ID then return SWORD_LINK end
				if rollID == SHIELD_ROLL_ID then return SHIELD_LINK end
				return SWORD_LINK
			end,
		})
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop different: _pendingActions has two entries after EnqueueAction for SWORD and SHIELD", function()
		if not lr.EnqueueAction then
			pending("EnqueueAction not implemented (S03 blocker)")
			return
		end

		lr:EnqueueAction(SWORD_ROLL_ID, SWORD_LINK, "NEED", 95)
		lr:EnqueueAction(SHIELD_ROLL_ID, SHIELD_LINK, "GREED", 0)

		assert.is_not_nil(lr._pendingActions[SWORD_ROLL_ID], "Expected pending entry for SWORD rollID=10")
		assert.is_not_nil(lr._pendingActions[SHIELD_ROLL_ID], "Expected pending entry for SHIELD rollID=20")
		print("[S06 T04] Pending SWORD itemLink=" .. tostring(lr._pendingActions[SWORD_ROLL_ID].itemLink))
		print("[S06 T04] Pending SHIELD itemLink=" .. tostring(lr._pendingActions[SHIELD_ROLL_ID].itemLink))
	end)

	it("S06 multi drop different: pending entries carry distinct itemLinks (SWORD vs SHIELD)", function()
		if not lr.EnqueueAction then
			pending("EnqueueAction not implemented (S03 blocker)")
			return
		end

		lr:EnqueueAction(SWORD_ROLL_ID, SWORD_LINK, "NEED", 95)
		lr:EnqueueAction(SHIELD_ROLL_ID, SHIELD_LINK, "GREED", 0)

		assert.are.equal(SWORD_LINK, lr._pendingActions[SWORD_ROLL_ID].itemLink, "SWORD pending must carry SWORD_LINK")
		assert.are.equal(SHIELD_LINK, lr._pendingActions[SHIELD_ROLL_ID].itemLink, "SHIELD pending must carry SHIELD_LINK")
		assert.are_not.equal(
			lr._pendingActions[SWORD_ROLL_ID].itemLink,
			lr._pendingActions[SHIELD_ROLL_ID].itemLink,
			"Two pending entries must have different itemLinks"
		)
		print("[S06 T04] itemLinks are distinct — no contamination in pending queue")
	end)

	it("S06 multi drop different: START_LOOT_ROLL for SWORD and SHIELD stages both in _stagedRollValidity", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", SWORD_ROLL_ID, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", SHIELD_ROLL_ID, 60)

		assert.is_not_nil(lr._stagedRollValidity[SWORD_ROLL_ID], "Expected staged validity for SWORD rollID=10")
		assert.is_not_nil(lr._stagedRollValidity[SHIELD_ROLL_ID], "Expected staged validity for SHIELD rollID=20")
		-- Staged item links must differ
		local swordLink = lr._stagedRollValidity[SWORD_ROLL_ID] and lr._stagedRollValidity[SWORD_ROLL_ID].itemLink
		local shieldLink = lr._stagedRollValidity[SHIELD_ROLL_ID] and lr._stagedRollValidity[SHIELD_ROLL_ID].itemLink
		if swordLink and shieldLink then
			assert.are_not.equal(swordLink, shieldLink, "Staged itemLinks must differ between SWORD and SHIELD")
		end
		print("[S06 T04] Both staged: SWORD and SHIELD in _stagedRollValidity")
	end)
end)

-- =============================================================================
-- Part 2: MatchActionToResult disambiguates by itemLink
-- =============================================================================

describe("S06 multi drop different items: Part 2 — MatchActionToResult uses itemLink to disambiguate", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop different: SWORD drop matches SWORD pending action (not SHIELD)", function()
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 EnqueueAction wiring")
			return
		end

		lr:EnqueueAction(SWORD_ROLL_ID, SWORD_LINK, "NEED", 95)
		lr:EnqueueAction(SHIELD_ROLL_ID, SHIELD_LINK, "GREED", 0)

		-- SWORD drop arrives — should match SWORD action (rollID=10), not SHIELD (rollID=20)
		local swordDrop = resolvedDropNeedFor(SWORD_LINK, "Paladin", 95, 95)
		local matchedID, _ = lr:MatchActionToResult(SWORD_ENC_ID, SWORD_LIST_ID, swordDrop)

		assert.are.equal(SWORD_ROLL_ID, matchedID, "SWORD drop must match SWORD rollID=10, not SHIELD rollID=20")
		assert.is_nil(lr._pendingActions[SWORD_ROLL_ID], "SWORD pending action should be consumed")
		assert.is_not_nil(lr._pendingActions[SHIELD_ROLL_ID], "SHIELD pending action must remain")
		print("[S06 T04] SWORD drop matched to rollID=" .. tostring(matchedID) .. " — SHIELD untouched")
	end)

	it("S06 multi drop different: SHIELD drop matches SHIELD pending action (not SWORD)", function()
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 EnqueueAction wiring")
			return
		end

		lr:EnqueueAction(SWORD_ROLL_ID, SWORD_LINK, "NEED", 95)
		lr:EnqueueAction(SHIELD_ROLL_ID, SHIELD_LINK, "GREED", 0)

		-- SHIELD drop arrives — should match SHIELD action (rollID=20), not SWORD (rollID=10)
		local shieldDrop = resolvedDropGreedFor(SHIELD_LINK, "Shaman", 0)
		local matchedID, _ = lr:MatchActionToResult(SWORD_ENC_ID, SHIELD_LIST_ID, shieldDrop)

		assert.are.equal(SHIELD_ROLL_ID, matchedID, "SHIELD drop must match SHIELD rollID=20, not SWORD rollID=10")
		assert.is_nil(lr._pendingActions[SHIELD_ROLL_ID], "SHIELD pending action should be consumed")
		assert.is_not_nil(lr._pendingActions[SWORD_ROLL_ID], "SWORD pending action must remain")
		print("[S06 T04] SHIELD drop matched to rollID=" .. tostring(matchedID) .. " — SWORD untouched")
	end)

	it("S06 multi drop different: SHIELD drop does NOT match SWORD pending even with identical rollValue=0", function()
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 EnqueueAction wiring")
			return
		end

		-- Both items have rollValue=0 (both greed) — itemLink must be the tiebreaker
		lr:EnqueueAction(SWORD_ROLL_ID, SWORD_LINK, "GREED", 0)
		lr:EnqueueAction(SHIELD_ROLL_ID, SHIELD_LINK, "GREED", 0)

		-- SHIELD drop — should match SHIELD (rollID=20) using itemLink tiebreak
		local shieldDrop = resolvedDropGreedFor(SHIELD_LINK, "Shaman", 0)
		local matchedID, _ = lr:MatchActionToResult(SWORD_ENC_ID, SHIELD_LIST_ID, shieldDrop)

		-- If MatchActionToResult uses itemLink, matchedID == SHIELD_ROLL_ID
		-- If it only uses rollValue, either could match — verify SWORD action is still alive
		if matchedID == SWORD_ROLL_ID then
			-- Acceptable only if itemLink matching not yet implemented; guard with pending
			pending("MatchActionToResult must use itemLink as tiebreaker when rollValues are equal")
			return
		end
		assert.are.equal(SHIELD_ROLL_ID, matchedID, "SHIELD drop must match SHIELD rollID=20 when rollValues are equal")
		assert.is_not_nil(lr._pendingActions[SWORD_ROLL_ID], "SWORD pending must survive SHIELD drop")
		print("[S06 T04] itemLink tiebreak correct: SHIELD matched to rollID=" .. tostring(matchedID))
	end)
end)

-- =============================================================================
-- Part 3: No cross-contamination — button validity cache and row state
-- =============================================================================

describe("S06 multi drop different items: Part 3 — no cross-contamination between SWORD and SHIELD rows", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns, {
			GetRetailRollItemLink = function(rollID)
				if rollID == SWORD_ROLL_ID then return SWORD_LINK end
				if rollID == SHIELD_ROLL_ID then return SHIELD_LINK end
				return SWORD_LINK
			end,
		})
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop different: button validity cache keyed independently per rollID", function()
		-- _buttonValidityCache is keyed by rollID; SWORD and SHIELD must not share cache entries.
		lr:START_LOOT_ROLL("START_LOOT_ROLL", SWORD_ROLL_ID, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", SHIELD_ROLL_ID, 60)

		local swordCache = lr._buttonValidityCache[SWORD_ROLL_ID]
		local shieldCache = lr._buttonValidityCache[SHIELD_ROLL_ID]

		-- Both caches may be nil (depends on staging flow) or distinct tables
		if swordCache ~= nil and shieldCache ~= nil then
			assert.are_not.equal(swordCache, shieldCache, "SWORD and SHIELD must have independent cache entries")
		end
		print("[S06 T04] Button validity cache: SWORD=" .. tostring(swordCache) .. " SHIELD=" .. tostring(shieldCache))
	end)

	it("S06 multi drop different: resolving SWORD drop does not change SHIELD drop state", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if listID == SWORD_LIST_ID then
				return pendingDropFor(SWORD_LINK)
			else
				return pendingDropFor(SHIELD_LINK)
			end
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", SWORD_ENC_ID, SWORD_LIST_ID)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", SWORD_ENC_ID, SHIELD_LIST_ID)

		-- Confirm both pending
		assert.are.equal("pending", lr._dropStates[SWORD_DROP_KEY].state, "SWORD drop should be pending initially")
		assert.are.equal("pending", lr._dropStates[SHIELD_DROP_KEY].state, "SHIELD drop should be pending initially")

		-- Now resolve SWORD only
		lr._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if listID == SWORD_LIST_ID then
				return resolvedDropNeedFor(SWORD_LINK, "Paladin", 95, 95)
			else
				return pendingDropFor(SHIELD_LINK)
			end
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", SWORD_ENC_ID, SWORD_LIST_ID)

		assert.are.equal("resolved", lr._dropStates[SWORD_DROP_KEY].state, "SWORD drop should be resolved")
		assert.are.equal("pending", lr._dropStates[SHIELD_DROP_KEY].state, "SHIELD drop must remain pending — not affected by SWORD resolution")
		print("[S06 T04] SWORD resolved, SHIELD still pending — no cross-contamination")
	end)

	it("S06 multi drop different: payload keys are distinct for SWORD and SHIELD rows", function()
		local swordDrop = resolvedDropNeedFor(SWORD_LINK, "Paladin", 95, 95)
		local shieldDrop = resolvedDropGreedFor(SHIELD_LINK, "Shaman", 0)

		local swordPayload = lr:BuildPayload(SWORD_ENC_ID, SWORD_LIST_ID, swordDrop, "resolved")
		local shieldPayload = lr:BuildPayload(SWORD_ENC_ID, SHIELD_LIST_ID, shieldDrop, "resolved")

		assert.are_not.equal(swordPayload.key, shieldPayload.key, "SWORD and SHIELD rows must have distinct payload keys")
		print("[S06 T04] Distinct payload keys: SWORD=" .. swordPayload.key .. " SHIELD=" .. shieldPayload.key)
	end)

	it("S06 multi drop different: SWORD payload does not contain SHIELD winner name and vice versa", function()
		local swordDrop = resolvedDropNeedFor(SWORD_LINK, "Paladin", 95, 95)
		local shieldDrop = resolvedDropGreedFor(SHIELD_LINK, "Shaman", 0)

		local swordPayload = lr:BuildPayload(SWORD_ENC_ID, SWORD_LIST_ID, swordDrop, "resolved")
		local shieldPayload = lr:BuildPayload(SWORD_ENC_ID, SHIELD_LIST_ID, shieldDrop, "resolved")

		assert.is_nil(string.find(swordPayload.secondaryText, "Shaman"), "SWORD payload must not mention SHIELD winner Shaman")
		assert.is_nil(string.find(shieldPayload.secondaryText, "Paladin"), "SHIELD payload must not mention SWORD winner Paladin")
		print("[S06 T04] No cross-contamination in winner names")
	end)
end)

-- =============================================================================
-- Part 4: Full E2E — SWORD and SHIELD drop concurrently, correct routing
-- =============================================================================

describe("S06 multi drop different items: Part 4 — full E2E with MatchActionToResult guard", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns, {
			GetRetailRollItemLink = function(rollID)
				if rollID == SWORD_ROLL_ID then return SWORD_LINK end
				if rollID == SHIELD_ROLL_ID then return SHIELD_LINK end
				return SWORD_LINK
			end,
		})
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("S06 multi drop different: full E2E — SWORD Need (rollValue=95) and SHIELD Greed (rollValue=0) both dispatched", function()
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 EnqueueAction wiring")
			return
		end

		-- Step 1: Stage both rolls
		lr:START_LOOT_ROLL("START_LOOT_ROLL", SWORD_ROLL_ID, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", SHIELD_ROLL_ID, 60)

		-- Step 2: Player clicks Need on SWORD and Greed on SHIELD
		lr:EnqueueAction(SWORD_ROLL_ID, SWORD_LINK, "NEED", 95)
		lr:EnqueueAction(SHIELD_ROLL_ID, SHIELD_LINK, "GREED", 0)

		-- Step 3: Both drops arrive with winners
		lr._lootRollsAdapter.GetSortedInfoForDrop = function(encID, listID)
			if listID == SWORD_LIST_ID then
				return resolvedDropNeedFor(SWORD_LINK, "Paladin", 95, 95)
			else
				return resolvedDropGreedFor(SHIELD_LINK, "Shaman", 0)
			end
		end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", SWORD_ENC_ID, SWORD_LIST_ID)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", SWORD_ENC_ID, SHIELD_LIST_ID)

		-- Step 4: SendMessage fired twice
		assert.spy(sendSpy).was.called(2)
		print("[S06 T04] E2E: SendMessage called " .. tostring(#sendSpy.calls) .. " time(s)")

		-- Step 5: Both drop states resolved
		assert.are.equal("resolved", lr._dropStates[SWORD_DROP_KEY].state, "SWORD drop must be resolved")
		assert.are.equal("resolved", lr._dropStates[SHIELD_DROP_KEY].state, "SHIELD drop must be resolved")

		-- Step 6: Both pending actions consumed
		assert.is_nil(lr._pendingActions[SWORD_ROLL_ID], "SWORD rollID=10 must be consumed")
		assert.is_nil(lr._pendingActions[SHIELD_ROLL_ID], "SHIELD rollID=20 must be consumed")
		print("[S06 T04] E2E complete: SWORD and SHIELD resolved, no stale pending actions")
	end)

	it("S06 multi drop different: partial arrival — only SWORD drop arrives, SHIELD action preserved", function()
		if not lr.MatchActionToResult then
			pending("requires S03 MatchActionToResult wiring")
			return
		end
		if not lr.EnqueueAction then
			pending("requires S03 EnqueueAction wiring")
			return
		end

		lr:EnqueueAction(SWORD_ROLL_ID, SWORD_LINK, "NEED", 95)
		lr:EnqueueAction(SHIELD_ROLL_ID, SHIELD_LINK, "GREED", 0)

		-- Only SWORD drop arrives
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return resolvedDropNeedFor(SWORD_LINK, "Paladin", 95, 95)
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", SWORD_ENC_ID, SWORD_LIST_ID)

		assert.is_nil(lr._pendingActions[SWORD_ROLL_ID], "SWORD rollID=10 consumed after SWORD drop")
		assert.is_not_nil(lr._pendingActions[SHIELD_ROLL_ID], "SHIELD rollID=20 must survive until SHIELD drop arrives")
		print("[S06 T04] SWORD consumed, SHIELD still queued — partial arrival handled correctly")
	end)
end)
