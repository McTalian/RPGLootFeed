---@diagnostic disable: need-check-nil
--- T04 Multi-drop matching: same item drops twice, correct winner routing.
---
--- These tests verify that when the same item drops twice in the same encounter
--- (two separate LOOT_HISTORY_UPDATE_DROP events with different lootListIDs),
--- each result matches to the correct pending action — no cross-contamination.
---
--- Key architectural fix being validated:
---   - Two separate pending actions exist in queue, keyed by distinct rollIDs.
---   - Two separate drop keys (encounterID_lootListID1 vs _lootListID2) are used.
---   - NEED rolls are disambiguated by numeric rollValue (unique per player).
---   - Non-NEED rolls are disambiguated by rollType string equality.
---   - After matching, both actions are consumed (removed from queue).

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

-- ── Constants ─────────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:12345|r"
local ENC_ID = 1200
local LIST_ID_1 = 1
local LIST_ID_2 = 2
local ROLL_ID_1 = 101
local ROLL_ID_2 = 102

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
		IsRetail = function() return true end,
		SendMessage = sendSpy,
		TooltipBuilders = nil,
		db = { global = { animations = { exit = { fadeOutDelay = 3 } }, misc = { hideAllIcons = false } } },
		WoWAPI = { LootRolls = {} },
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function() return true end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return { enableIcon = true, enableLootRollActions = true }
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
		for k, v in pairs(adapterOverrides) do
			adapter[k] = v
		end
	end
	lr._lootRollsAdapter = adapter
	lr._dropStates = {}
	lr._buttonValidityCache = {}
	lr._stagedRollValidity = {}
	lr._pendingActions = {}
	return lr
end

--- Build a resolved drop for the player who rolled 'selfRollValue' (NEED, state=0).
local function resolvedDropNeed(selfRollValue, winnerRoll)
	return {
		itemHyperlink = ITEM_LINK,
		winner = { playerName = "Warrior", playerClass = "WARRIOR", roll = winnerRoll or selfRollValue, state = 0, isSelf = false, isWinner = true },
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{ playerName = "You", playerClass = "WARRIOR", roll = selfRollValue, state = 0, isSelf = true, isWinner = false },
		},
		playerRollState = 0,
		startTime = nil,
		duration = nil,
	}
end

--- Build a resolved drop for a GREED roll (state=3).
local function resolvedDropGreed()
	return {
		itemHyperlink = ITEM_LINK,
		winner = { playerName = "Mage", playerClass = "MAGE", roll = 45, state = 3, isSelf = false, isWinner = true },
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{ playerName = "You", playerClass = "WARRIOR", roll = 22, state = 3, isSelf = true, isWinner = false },
		},
		playerRollState = 3,
		startTime = nil,
		duration = nil,
	}
end

-- =============================================================================
-- Multi-drop: same item drops twice (two separate NEED rolls by same player)
-- =============================================================================

describe("multi-drop matching: same item drops twice (two NEED rolls)", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("two separate pending actions exist in queue keyed by distinct rollIDs", function()
		-- Simulate two START_LOOT_ROLL events (same item, different rollID slots)
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 91)

		assert.is_not_nil(lr._pendingActions[ROLL_ID_1])
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2])
		assert.are.equal(73, lr._pendingActions[ROLL_ID_1].rollValue)
		assert.are.equal(91, lr._pendingActions[ROLL_ID_2].rollValue)
	end)

	it("MatchActionToResult routes first drop to correct rollID via rollValue", function()
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 91)

		-- First drop: player rolled 73 (NEED, state=0)
		local drop1 = resolvedDropNeed(73)
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, drop1)

		assert.are.equal(ROLL_ID_1, matchedID)
		-- ROLL_ID_1 consumed, ROLL_ID_2 still in queue
		assert.is_nil(lr._pendingActions[ROLL_ID_1])
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2])
	end)

	it("MatchActionToResult routes second drop to remaining rollID", function()
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 91)

		-- First drop consumed ROLL_ID_1
		lr:MatchActionToResult(ENC_ID, LIST_ID_1, resolvedDropNeed(73))

		-- Second drop: player rolled 91
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_2, resolvedDropNeed(91))

		assert.are.equal(ROLL_ID_2, matchedID)
		assert.is_nil(lr._pendingActions[ROLL_ID_2])
	end)

	it("no cross-contamination: wrong rollValue returns no match", function()
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 91)

		-- Drop with rollValue=50 should not match either NEED action
		local drop = resolvedDropNeed(50)
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, drop)

		assert.is_nil(matchedID)
		-- Both actions remain in queue
		assert.is_not_nil(lr._pendingActions[ROLL_ID_1])
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2])
	end)

	it("two separate drop keys created for two drops of same item", function()
		local drop = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
			isTied = false, currentLeader = nil, rollInfos = {}, playerRollState = nil,
			startTime = 1000, duration = 60 }

		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return drop end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		local key1 = ENC_ID .. "_" .. LIST_ID_1
		local key2 = ENC_ID .. "_" .. LIST_ID_2
		assert.is_not_nil(lr._dropStates[key1])
		assert.is_not_nil(lr._dropStates[key2])
	end)
end)

-- =============================================================================
-- Multi-drop: same item drops twice (different roll types)
-- =============================================================================

describe("multi-drop matching: same item drops twice (different roll types)", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("NEED action matches NEED drop, GREED action matches GREED drop independently", function()
		-- Two drops of the same item: player went NEED on first, GREED on second
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "GREED", nil)

		-- NEED drop arrives first
		local matchedID1, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, resolvedDropNeed(73))
		assert.are.equal(ROLL_ID_1, matchedID1)

		-- GREED drop arrives second
		local matchedID2, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_2, resolvedDropGreed())
		assert.are.equal(ROLL_ID_2, matchedID2)
	end)

	it("NEED drop does not match GREED pending action", function()
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "GREED", nil)

		-- A NEED drop should not match a GREED pending action
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, resolvedDropNeed(73))
		assert.is_nil(matchedID)
		assert.is_not_nil(lr._pendingActions[ROLL_ID_1])
	end)

	it("GREED drop does not match NEED pending action", function()
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)

		-- A GREED drop should not match a NEED pending action
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, resolvedDropGreed())
		assert.is_nil(matchedID)
		assert.is_not_nil(lr._pendingActions[ROLL_ID_1])
	end)
end)

-- =============================================================================
-- Multi-drop: temporal window enforcement
-- =============================================================================

describe("multi-drop matching: temporal window prevents stale cross-drop matches", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("pending action outside 12s window is not matched even when itemLink + rollValue agree", function()
		-- Enqueue at t=0
		_G.GetTime = function() return 0 end
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)

		-- Drop arrives at t=13 (outside 12s window)
		_G.GetTime = function() return 13 end
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, resolvedDropNeed(73))

		assert.is_nil(matchedID)
	end)

	it("pending action within 12s window is matched correctly", function()
		_G.GetTime = function() return 0 end
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)

		-- Drop arrives at t=11 (within window)
		_G.GetTime = function() return 11 end
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, resolvedDropNeed(73))

		assert.are.equal(ROLL_ID_1, matchedID)
	end)
end)
