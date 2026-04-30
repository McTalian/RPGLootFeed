---@diagnostic disable: need-check-nil
--- S03/T01 — MatchActionToResult integration tests.
---
--- Validates that:
---   1. MatchActionToResult is called within LOOT_HISTORY_UPDATE_DROP.
---   2. Matched pending actions are consumed from the queue.
---   3. Unmatched terminal drops trigger LogWarn.
---   4. Unmatched pending (non-terminal) drops do NOT trigger LogWarn.
---   5. Multi-drop routing, boundary conditions, and edge cases.
---
--- All state is reset in before_each to ensure isolation.

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

-- ── Constants ──────────────────────────────────────────────────────────────────
local ITEM_LINK = "|cff0070dditem:12345|r"
local ITEM_LINK_2 = "|cff0070dditem:99999|r"
local ENC_ID = 500
local LIST_ID = 1
local ROLL_ID = 42

-- ── Shared helpers ─────────────────────────────────────────────────────────────

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
		SendMessage = sendSpy or spy.new(function() end),
		TooltipBuilders = nil,
		db = { global = { animations = { exit = { fadeOutDelay = 3 } }, misc = { hideAllIcons = false } } },
		WoWAPI = { LootRolls = {} },
		RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
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
			["LootRolls_WaitingForResults"] = "Waiting for results",
			["LootRolls_WaitingForRolls"] = "Waiting for rolls",
			["LootRolls_TiedFmt"] = "Tied at %d",
			["LootRolls_CurrentLeaderFmt"] = "Leading: %s rolled %d",
			["LootRolls_WonByFmt"] = "Won by %s %s %d",
			["LootRolls_WonByNoRollFmt"] = "Won by %s",
			["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
			["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
			["LootRolls_YouSelected_NEED"] = "You: Need",
			["LootRolls_YouSelected_GREED"] = "You: Greed",
			["LootRolls_YouSelected_PASS"] = "You: Pass",
			["LootRolls_YouSelected_TRANSMOG"] = "You: Transmog",
		},
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

-- ── Drop fixture builders ──────────────────────────────────────────────────────

local function pendingDrop(itemLink)
	return {
		itemHyperlink = itemLink or ITEM_LINK,
		winner = nil,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = nil,
		duration = nil,
	}
end

local function resolvedDropNeed(selfRollValue, winnerRoll, itemLink)
	return {
		itemHyperlink = itemLink or ITEM_LINK,
		winner = { playerName = "Warrior", playerClass = "WARRIOR", roll = winnerRoll or selfRollValue, state = 0, isSelf = false, isWinner = true },
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{ playerName = "You", playerClass = "MAGE", roll = selfRollValue, state = 0, isSelf = true, isWinner = false },
		},
		startTime = nil,
		duration = nil,
	}
end

local function resolvedDropGreed(itemLink)
	return {
		itemHyperlink = itemLink or ITEM_LINK,
		winner = { playerName = "Mage", playerClass = "MAGE", roll = 45, state = 3, isSelf = false, isWinner = true },
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{ playerName = "You", playerClass = "WARRIOR", roll = 22, state = 3, isSelf = true, isWinner = false },
		},
		startTime = nil,
		duration = nil,
	}
end

local function resolvedDropPass(itemLink)
	return {
		itemHyperlink = itemLink or ITEM_LINK,
		winner = { playerName = "Druid", playerClass = "DRUID", roll = nil, state = 5, isSelf = false, isWinner = true },
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{ playerName = "You", playerClass = "WARRIOR", roll = nil, state = 5, isSelf = true, isWinner = false },
		},
		startTime = nil,
		duration = nil,
	}
end

local function allPassedDrop(itemLink)
	return {
		itemHyperlink = itemLink or ITEM_LINK,
		winner = nil,
		allPassed = true,
		isTied = false,
		currentLeader = nil,
		rollInfos = {},
		startTime = nil,
		duration = nil,
	}
end

-- =============================================================================
-- MatchActionToResult: direct unit tests (not going through the event handler)
-- =============================================================================

describe("MatchActionToResult", function()
	local lr

	before_each(function()
		lr = loadLootRolls(makeNs())
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── 1. Match found (NEED roll) ─────────────────────────────────────────────
	it("returns matchedRollID and matchedAction when NEED rollValue matches", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 73)

		local matchedID, matchedAction = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropNeed(73))

		assert.are.equal(ROLL_ID, matchedID)
		assert.is_not_nil(matchedAction)
		assert.are.equal("NEED", matchedAction.rollType)
		assert.are.equal(73, matchedAction.rollValue)
	end)

	-- ── 2. Match found: action consumed from queue ─────────────────────────────
	it("removes matched action from queue after match", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 55)

		lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropNeed(55))

		assert.is_nil(lr._pendingActions[ROLL_ID])
	end)

	-- ── 3. Match found (GREED roll) ────────────────────────────────────────────
	it("returns matchedRollID for GREED rollType match", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "GREED", nil)

		local matchedID, matchedAction = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropGreed())

		assert.are.equal(ROLL_ID, matchedID)
		assert.are.equal("GREED", matchedAction.rollType)
	end)

	-- ── 4. Match found (PASS roll) ─────────────────────────────────────────────
	it("returns matchedRollID for PASS rollType match", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "PASS", nil)

		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropPass())

		assert.are.equal(ROLL_ID, matchedID)
	end)

	-- ── 5. No match: itemLink mismatch ─────────────────────────────────────────
	it("returns nil when pending action itemLink does not match drop", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK_2, "GREED", nil)

		local matchedID, matchedAction = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropGreed(ITEM_LINK))

		assert.is_nil(matchedID)
		assert.is_nil(matchedAction)
		-- Pending action still in queue (not consumed)
		assert.is_not_nil(lr._pendingActions[ROLL_ID])
	end)

	-- ── 6. No match: NEED rollValue mismatch ──────────────────────────────────
	it("returns nil when pending NEED action rollValue differs from drop selfRoll", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 99)

		-- Drop has selfRollValue = 43, but pending action has rollValue = 99
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropNeed(43))

		assert.is_nil(matchedID)
		assert.is_not_nil(lr._pendingActions[ROLL_ID])
	end)

	-- ── 7. No match: outside temporal window ──────────────────────────────────
	it("returns nil when pending action is older than MATCH_WINDOW_SECONDS", function()
		-- Enqueue at t=1000; advance clock to t=1013 (13s > 12s window)
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 73)
		_G.GetTime = function() return 1013 end

		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropNeed(73))

		assert.is_nil(matchedID)
	end)

	-- ── 8. No match: empty pending queue ──────────────────────────────────────
	it("returns nil when pending queue is empty", function()
		local matchedID, matchedAction = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropNeed(33))

		assert.is_nil(matchedID)
		assert.is_nil(matchedAction)
	end)

	-- ── 9. Multi-drop routing via rollValue ────────────────────────────────────
	it("routes first drop to correct pending action when two NEED rolls differ by rollValue", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID + 1, ITEM_LINK, "NEED", 91)

		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropNeed(73))

		assert.are.equal(ROLL_ID, matchedID)
		assert.is_nil(lr._pendingActions[ROLL_ID])
		assert.is_not_nil(lr._pendingActions[ROLL_ID + 1])
	end)

	-- ── 10. Multi-drop routing: second NEED drop ───────────────────────────────
	it("routes second NEED drop to remaining rollID after first was consumed", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID + 1, ITEM_LINK, "NEED", 91)

		-- Consume the first
		lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropNeed(73))

		-- Match the second
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID + 1, resolvedDropNeed(91))

		assert.are.equal(ROLL_ID + 1, matchedID)
		assert.is_nil(lr._pendingActions[ROLL_ID + 1])
	end)

	-- ── 11. No match when pending is nil-rollType (not yet clicked) ───────────
	it("returns nil when pending action has nil rollType (not yet clicked via button)", function()
		-- Pre-enqueued by START_LOOT_ROLL before the player has clicked any button
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)

		-- A resolved GREED drop arrives
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropGreed())

		-- rollType nil != "GREED" → no match
		assert.is_nil(matchedID)
	end)

	-- ── 12. dropInfo with nil itemHyperlink returns nil ───────────────────────
	it("returns nil and does not crash when dropInfo.itemHyperlink is nil", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "GREED", nil)

		local drop = resolvedDropGreed()
		drop.itemHyperlink = nil

		local matchedID, matchedAction = lr:MatchActionToResult(ENC_ID, LIST_ID, drop)

		assert.is_nil(matchedID)
		assert.is_nil(matchedAction)
		-- Pending action should still be in queue
		assert.is_not_nil(lr._pendingActions[ROLL_ID])
	end)
end)

-- =============================================================================
-- LOOT_HISTORY_UPDATE_DROP integration: MatchActionToResult is called
-- =============================================================================

describe("LOOT_HISTORY_UPDATE_DROP integration with MatchActionToResult", function()
	local lr, ns

	before_each(function()
		ns = makeNs()
		lr = loadLootRolls(ns, {
			GetSortedInfoForDrop = function() return pendingDrop() end,
		})
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── 13. Handler calls MatchActionToResult and consumes matched action ──────
	it("consumes matching pending action when LOOT_HISTORY_UPDATE_DROP resolves", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 77)
		local resolvedDrop = resolvedDropNeed(77)
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return resolvedDrop end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- Pending action should have been consumed
		assert.is_nil(lr._pendingActions[ROLL_ID])
	end)

	-- ── 14. Unmatched terminal drop triggers LogWarn ───────────────────────────
	it("calls LogWarn when a resolved drop arrives with no pending action in queue", function()
		local resolvedDrop = resolvedDropNeed(55)
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return resolvedDrop end
		-- No pending actions enqueued

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.spy(ns.LogWarn).was.called_with(
			match._,
			"LOOT_HISTORY_UPDATE_DROP: unmatched terminal drop (no pending action found)",
			match._,
			match._,
			match._,
			match._,
			match._,
			match._
		)
	end)

	-- ── 15. Unmatched allPassed terminal drop triggers LogWarn ─────────────────
	it("calls LogWarn when allPassed drop arrives with no pending action", function()
		local apDrop = allPassedDrop()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return apDrop end

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.spy(ns.LogWarn).was_called()
	end)

	-- ── 16. Pending (non-terminal) drop does NOT trigger LogWarn ─────────────
	it("does NOT call LogWarn when pending drop arrives with no matched action", function()
		-- No pending actions, but the drop is still in pending state (not resolved)
		local pDrop = pendingDrop()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return pDrop end

		-- Reset any LogWarn calls from before_each setup
		ns.LogWarn = spy.new(function() end)

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		-- LogWarn should NOT be called for an unmatched pending (non-terminal) drop
		assert.spy(ns.LogWarn).was_not_called()
	end)

	-- ── 17. Matched resolved drop does NOT trigger LogWarn ───────────────────
	it("does NOT call LogWarn when resolved drop is matched to a pending action", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "GREED", nil)
		local resolvedDrop = resolvedDropGreed()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return resolvedDrop end

		ns.LogWarn = spy.new(function() end)

		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.spy(ns.LogWarn).was_not_called()
	end)
end)
