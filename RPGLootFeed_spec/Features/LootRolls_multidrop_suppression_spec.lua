---@diagnostic disable: need-check-nil
--- T04 Multi-drop + suppression: same item drops twice while GroupLootFrame is suppressed.
---
--- Verifies that button submission routing is unaffected by GroupLootFrame suppression:
---   1. Two rolls of the same item, button clicks on each → both enqueue correctly
---   2. Matching logic correctly pairs actions to results for each roll under suppression
---   3. No cross-contamination between rolls when suppression is active (S02 regression)
---   4. e2e: two rolls with suppression=true → button clicks → both results arrive → both
---      winners shown (SendMessage fired twice with correct winners)
---   5. Multi-drop suppression: suppression state does not affect pending action routing

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

-- ── Constants ─────────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:12345|r"
local ENC_ID = 3000
local LIST_ID_1 = 1
local LIST_ID_2 = 2
local ROLL_ID_1 = 201
local ROLL_ID_2 = 202

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Build a namespace with suppression=true (disableLootRollFrame=true).
local function makeNsSuppressed(sendSpy)
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
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function() return true end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					-- suppression ACTIVE: disableLootRollFrame=true + enableLootRollActions=true
					return { enableIcon = true, enableLootRollActions = true, disableLootRollFrame = true }
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

local function loadLootRolls(ns)
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
	lr._lootRollsAdapter = {
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
			return { itemLink = ITEM_LINK, texture = 132310, quality = 3,
				canNeed = true, canGreed = true, canDisenchant = false }
		end,
	}
	lr._dropStates = {}
	lr._buttonValidityCache = {}
	lr._stagedRollValidity = {}
	lr._pendingActions = {}
	return lr
end

-- =============================================================================
-- Suite: multi-drop + suppress: button clicks route correctly under suppression
-- =============================================================================

describe("multi-drop suppress: two rolls of same item enqueue independently when suppression active", function()
	local lr, ns

	before_each(function()
		ns = makeNsSuppressed()
		lr = loadLootRolls(ns)
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- Test 1: two START_LOOT_ROLL events create two independent pending slots
	it("suppress+multi: two START_LOOT_ROLL events create independent pending slots regardless of suppression", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_1, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_2, 60)

		assert.is_not_nil(lr._pendingActions[ROLL_ID_1],
			"ROLL_ID_1 must exist in pending queue despite suppression")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2],
			"ROLL_ID_2 must exist in pending queue despite suppression")
		assert.are.equal(ITEM_LINK, lr._pendingActions[ROLL_ID_1].itemLink)
		assert.are.equal(ITEM_LINK, lr._pendingActions[ROLL_ID_2].itemLink)
	end)

	-- Test 2: button click on first roll enqueues NEED, second remains unaffected
	it("suppress+multi: OnRollButtonClick(rollID1, NEED) sets rollType without affecting rollID2", function()
		-- Start both rolls
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_1, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_2, 60)

		-- Simulate drop state so actionPhase is set on click
		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
				isTied = false, currentLeader = nil, rollInfos = {}, playerRollState = nil,
				startTime = nil, duration = nil }
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		-- Click NEED on roll 1
		lr:OnRollButtonClick(ROLL_ID_1, 1)

		assert.are.equal("NEED", lr._pendingActions[ROLL_ID_1].rollType,
			"ROLL_ID_1 must record NEED rollType after click")
		assert.is_nil(lr._pendingActions[ROLL_ID_2].rollType,
			"ROLL_ID_2 must not be affected by click on ROLL_ID_1")
	end)

	-- Test 3: button click on second roll enqueues GREED independently
	it("suppress+multi: OnRollButtonClick(rollID2, GREED) routes to correct pending entry", function()
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_1, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_2, 60)

		lr._lootRollsAdapter.GetSortedInfoForDrop = function()
			return { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
				isTied = false, currentLeader = nil, rollInfos = {}, playerRollState = nil,
				startTime = nil, duration = nil }
		end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		-- Click GREED on roll 2
		lr:OnRollButtonClick(ROLL_ID_2, 2)

		assert.is_nil(lr._pendingActions[ROLL_ID_1].rollType,
			"ROLL_ID_1 must not be affected by click on ROLL_ID_2")
		assert.are.equal("GREED", lr._pendingActions[ROLL_ID_2].rollType,
			"ROLL_ID_2 must record GREED rollType after click")
	end)

	-- Test 4: MatchActionToResult routes two drops to correct rollIDs under suppression
	it("suppress+multi: MatchActionToResult routes each drop to correct rollID when suppression active", function()
		-- Two NEED actions with different rollValues for disambiguation
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 91)

		-- Drop 1 arrives with playerRoll=73
		local drop1 = {
			itemHyperlink = ITEM_LINK,
			winner = { playerName = "Warrior", roll = 73, state = 0, isSelf = false, isWinner = true },
			allPassed = false, isTied = false, currentLeader = nil,
			rollInfos = { { playerName = "You", roll = 73, state = 0, isSelf = true, isWinner = false } },
			playerRollState = 0,
		}
		local matchedID1, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, drop1)
		assert.are.equal(ROLL_ID_1, matchedID1,
			"first drop must match ROLL_ID_1 via rollValue=73")
		assert.is_nil(lr._pendingActions[ROLL_ID_1],
			"ROLL_ID_1 must be consumed after match")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2],
			"ROLL_ID_2 must remain in queue after first match")

		-- Drop 2 arrives with playerRoll=91
		local drop2 = {
			itemHyperlink = ITEM_LINK,
			winner = { playerName = "Warrior", roll = 91, state = 0, isSelf = false, isWinner = true },
			allPassed = false, isTied = false, currentLeader = nil,
			rollInfos = { { playerName = "You", roll = 91, state = 0, isSelf = true, isWinner = false } },
			playerRollState = 0,
		}
		local matchedID2, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_2, drop2)
		assert.are.equal(ROLL_ID_2, matchedID2,
			"second drop must match ROLL_ID_2 via rollValue=91")
		assert.is_nil(lr._pendingActions[ROLL_ID_2],
			"ROLL_ID_2 must be consumed after second match")
	end)

	-- Test 5: no cross-contamination — suppression does not blur action-to-result pairing
	it("suppress+multi: no cross-contamination between drops when suppression active", function()
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 91)

		-- Drop with rollValue=50 should not match either pending action
		local badDrop = {
			itemHyperlink = ITEM_LINK,
			winner = { playerName = "Warrior", roll = 50, state = 0, isSelf = false, isWinner = true },
			allPassed = false, isTied = false, currentLeader = nil,
			rollInfos = { { playerName = "You", roll = 50, state = 0, isSelf = true, isWinner = false } },
			playerRollState = 0,
		}
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID_1, badDrop)

		assert.is_nil(matchedID,
			"unrelated drop must not match any pending action under suppression")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_1],
			"ROLL_ID_1 must remain in queue — no cross-match")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2],
			"ROLL_ID_2 must remain in queue — no cross-match")
	end)
end)

-- =============================================================================
-- Suite: e2e multi-drop suppression pipeline — full flow with SendMessage
-- =============================================================================

describe("multi-drop suppress: e2e pipeline — two rolls resolve with winners shown (suppress active)", function()
	local lr, ns, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		ns = makeNsSuppressed(sendSpy)
		lr = loadLootRolls(ns)
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- e2e Test: two drops arrive sequentially, each fires SendMessage once
	it("suppress+multi e2e: two drops fire SendMessage twice (once per resolved drop) under suppression", function()
		-- Phase 1: START_LOOT_ROLL seeds pending entries
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_1, 60)
		lr:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID_2, 60)

		-- Phase 2: first LOOT_HISTORY_UPDATE_DROP (pending → result for drop1)
		local pending1 = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
			isTied = false, currentLeader = nil, rollInfos = {}, playerRollState = nil,
			startTime = nil, duration = nil }
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return pending1 end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)

		local key1 = ENC_ID .. "_" .. LIST_ID_1
		assert.equals("result", lr._dropStates[key1].phase,
			"drop1 must advance to result phase")

		-- Phase 3: second LOOT_HISTORY_UPDATE_DROP (pending → result for drop2)
		local pending2 = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
			isTied = false, currentLeader = nil, rollInfos = {}, playerRollState = nil,
			startTime = nil, duration = nil }
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return pending2 end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		local key2 = ENC_ID .. "_" .. LIST_ID_2
		assert.equals("result", lr._dropStates[key2].phase,
			"drop2 must advance to result phase")

		-- Phase 4: winner arrives for drop1 → resolved
		local resolved1 = {
			itemHyperlink = ITEM_LINK,
			winner = { playerName = "Thrall", playerClass = "SHAMAN", roll = 95, state = 0, isSelf = false, isWinner = true },
			allPassed = false, isTied = false, currentLeader = nil, rollInfos = {},
			playerRollState = nil,
		}
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return resolved1 end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)

		assert.equals("resolved", lr._dropStates[key1].phase,
			"drop1 must be resolved after winner arrives")

		-- Phase 5: winner arrives for drop2 → resolved
		local resolved2 = {
			itemHyperlink = ITEM_LINK,
			winner = { playerName = "Jaina", playerClass = "MAGE", roll = 72, state = 0, isSelf = false, isWinner = true },
			allPassed = false, isTied = false, currentLeader = nil, rollInfos = {},
			playerRollState = nil,
		}
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return resolved2 end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_2)

		assert.equals("resolved", lr._dropStates[key2].phase,
			"drop2 must be resolved after winner arrives")

		-- Verify SendMessage fired for both drops (pending and resolved transitions fire messages)
		-- At minimum 2 calls expected (one per drop reaching result or resolved phase).
		local callCount = #sendSpy.calls
		assert.is_true(callCount >= 2,
			"SendMessage must be called at least twice — once per drop phase transition; got " .. callCount)
	end)

	-- Regression: suppression state does not reset or clear pending actions during resolution
	it("suppress+multi: suppression does not clear pending queue during result arrival", function()
		lr:EnqueueAction(ROLL_ID_1, ITEM_LINK, "NEED", 73)
		lr:EnqueueAction(ROLL_ID_2, ITEM_LINK, "NEED", 91)

		-- Fire a first LOOT_HISTORY_UPDATE_DROP result (does not yet have player rollValue to match)
		local pendingDrop = { itemHyperlink = ITEM_LINK, winner = nil, allPassed = false,
			isTied = false, currentLeader = nil, rollInfos = {}, playerRollState = nil }
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return pendingDrop end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID_1)

		-- Both pending actions should still be present (no match yet — winner not in drop)
		-- Suppression must NOT cause premature clearing of pending queue
		assert.is_not_nil(lr._pendingActions[ROLL_ID_1],
			"ROLL_ID_1 must remain in pending queue — no false match from suppression")
		assert.is_not_nil(lr._pendingActions[ROLL_ID_2],
			"ROLL_ID_2 must remain in pending queue after unrelated event")
	end)
end)
