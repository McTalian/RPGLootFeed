---@diagnostic disable: need-check-nil
--- T05 End-to-end integration: button click → queue → match → result display.
---
--- These tests simulate the full Retail flow:
---   Player clicks Need button
---   → EnqueueAction called (START_LOOT_ROLL pre-enqueues; OnRollButtonClick updates)
---   → MAIN_SPEC_NEED_ROLL updates rollValue on the pending action
---   → LOOT_HISTORY_UPDATE_DROP fires with winner
---   → MatchActionToResult finds match and removes action from queue
---   → BuildPayload returns resolved state with winner text
---
--- Also tests the unmatched path (player used built-in UI, no pending action).

local assert = require("luassert")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy

-- ── Constants ─────────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:99999|r"
local ENC_ID = 500
local LIST_ID = 7
local ROLL_ID = 42
local DROP_KEY = ENC_ID .. "_" .. LIST_ID

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

local function pendingDropInfo()
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

--- Resolved drop: winner is "Warrior", player also rolled NEED with given value.
local function resolvedDropNeed(selfRollValue)
	return {
		itemHyperlink = ITEM_LINK,
		winner = { playerName = "Warrior", playerClass = "WARRIOR", roll = selfRollValue, state = 0, isSelf = false, isWinner = true },
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

--- Resolved drop where the player did NOT roll (no isSelf entry).
local function resolvedDropUnmatched()
	return {
		itemHyperlink = ITEM_LINK,
		winner = { playerName = "Mage", playerClass = "MAGE", roll = 88, state = 3, isSelf = false, isWinner = true },
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = {
			{ playerName = "Mage", playerClass = "MAGE", roll = 88, state = 3, isSelf = false, isWinner = true },
		},
		playerRollState = nil,
		startTime = nil,
		duration = nil,
	}
end

-- =============================================================================
-- Phase 1: EnqueueAction + queue lifecycle
-- =============================================================================

describe("e2e: EnqueueAction populates pending queue correctly", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("EnqueueAction stores itemLink and timestamp in _pendingActions", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)
		local entry = lr._pendingActions[ROLL_ID]
		assert.is_not_nil(entry)
		assert.are.equal(ITEM_LINK, entry.itemLink)
		assert.are.equal(1000, entry.timestamp)
	end)

	it("EnqueueAction with rollType=nil allows later update", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)
		assert.is_nil(lr._pendingActions[ROLL_ID].rollType)

		-- Simulate OnRollButtonClick(ROLL_ID, 1) updating the slot
		lr:OnRollButtonClick(ROLL_ID, 1) -- 1 = NEED
		assert.are.equal("NEED", lr._pendingActions[ROLL_ID].rollType)
	end)

	it("MAIN_SPEC_NEED_ROLL sets rollValue on existing pending action", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", nil)
		lr:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", ROLL_ID, 73)
		assert.are.equal(73, lr._pendingActions[ROLL_ID].rollValue)
	end)
end)

-- =============================================================================
-- Phase 2: Full matched flow (button submitted → drop arrives → match)
-- =============================================================================

describe("e2e: button click → queue → match → resolved state (matched path)", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("full NEED flow: pending action is consumed when drop matches", function()
		-- Step 1: START_LOOT_ROLL pre-enqueues slot
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)
		-- Step 2: Player clicks Need (OnRollButtonClick updates rollType)
		lr:OnRollButtonClick(ROLL_ID, 1) -- 1=NEED
		-- Step 3: MAIN_SPEC_NEED_ROLL sets numeric rollValue
		lr:MAIN_SPEC_NEED_ROLL("MAIN_SPEC_NEED_ROLL", ROLL_ID, 73)

		assert.are.equal("NEED", lr._pendingActions[ROLL_ID].rollType)
		assert.are.equal(73, lr._pendingActions[ROLL_ID].rollValue)

		-- Step 4: LOOT_HISTORY_UPDATE_DROP arrives with matching result
		local drop = resolvedDropNeed(73)
		local matchedID, action = lr:MatchActionToResult(ENC_ID, LIST_ID, drop)

		assert.are.equal(ROLL_ID, matchedID)
		assert.are.equal("NEED", action.rollType)
		assert.is_nil(lr._pendingActions[ROLL_ID]) -- consumed
	end)

	it("matched flow: BuildPayload returns 'resolved' rollState after match", function()
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, "NEED", 73)

		-- Set up drop state to resolved
		lr._dropStates[DROP_KEY] = { state = "resolved", actionPhase = nil, playerSelection = nil }

		local drop = resolvedDropNeed(73)
		local payload = lr:BuildPayload(ENC_ID, LIST_ID, drop, "resolved")

		assert.is_not_nil(payload)
		assert.are.equal("resolved", payload.rollState)
	end)

	it("matched flow: BuildPayload secondary text contains winner name after resolution", function()
		lr._dropStates[DROP_KEY] = { state = "resolved", actionPhase = nil, playerSelection = nil }

		local drop = resolvedDropNeed(73)
		local payload = lr:BuildPayload(ENC_ID, LIST_ID, drop, "resolved")

		assert.is_not_nil(payload.secondaryText)
		-- secondaryText should contain winner name
		assert.is_truthy(payload.secondaryText:find("Warrior") or payload.secondaryText:find("Won by"))
	end)

	it("actionPhase transitions to 'waiting' after button click", function()
		-- Simulate the actionPhase update that OnRollButtonClick performs
		lr:EnqueueAction(ROLL_ID, ITEM_LINK, nil, nil)
		lr._dropStates[DROP_KEY] = { state = "pending", rollID = ROLL_ID }
		lr:OnRollButtonClick(ROLL_ID, 1)

		assert.are.equal("waiting", lr._dropStates[DROP_KEY].actionPhase)
	end)

	it("BuildPayload shows 'Waiting for results' when actionPhase='waiting'", function()
		lr._dropStates[DROP_KEY] = { state = "pending", actionPhase = "waiting", playerSelection = "NEED" }

		local drop = pendingDropInfo()
		local payload = lr:BuildPayload(ENC_ID, LIST_ID, drop, "pending")

		assert.is_not_nil(payload)
		assert.is_truthy(payload.secondaryText:find("Waiting for results") or payload.secondaryText:find("You: Need"))
	end)

	it("SendMessage is called when LOOT_HISTORY_UPDATE_DROP fires (row dispatched)", function()
		local drop = pendingDropInfo()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return drop end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.spy(sendSpy).was.called()
	end)
end)

-- =============================================================================
-- Phase 3: Unmatched path (player used built-in Blizzard UI, no pending action)
-- =============================================================================

describe("e2e: unmatched path (player used built-in UI, no pending action)", function()
	local lr, sendSpy

	before_each(function()
		sendSpy = spy.new(function() end)
		lr = loadLootRolls(makeNs(sendSpy))
		_G.GetTime = function() return 1000 end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	it("MatchActionToResult returns nil when no pending actions exist", function()
		-- Queue is empty (player didn't use RPGLootFeed button)
		local matchedID, _ = lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropUnmatched())
		assert.is_nil(matchedID)
	end)

	it("LogWarn is NOT called for unmatched drop — result still displays", function()
		-- Unmatched drops are a valid code path (built-in UI) — only LogDebug, not LogWarn
		-- (The implementation logs debug, not warn, for the no-match case)
		local ns = makeNs(sendSpy)
		lr = loadLootRolls(ns)
		_G.GetTime = function() return 1000 end

		lr:MatchActionToResult(ENC_ID, LIST_ID, resolvedDropUnmatched())
		-- LogWarn should not be called for a normal no-match (player used built-in UI)
		-- (warn is only for nil itemHyperlink in dropInfo)
		assert.spy(ns.LogWarn).was_not.called()
	end)

	it("BuildPayload still works for resolved drop with no matched pending action", function()
		lr._dropStates[DROP_KEY] = { state = "resolved", actionPhase = nil, playerSelection = nil }
		local drop = resolvedDropUnmatched()

		local payload = lr:BuildPayload(ENC_ID, LIST_ID, drop, "resolved")
		assert.is_not_nil(payload)
		assert.are.equal("resolved", payload.rollState)
	end)

	it("LOOT_HISTORY_UPDATE_DROP still dispatches row when no pending action matches", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return resolvedDropUnmatched() end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		assert.spy(sendSpy).was.called()
	end)

	it("queue remains empty after LOOT_HISTORY_UPDATE_DROP with no pending action", function()
		lr._lootRollsAdapter.GetSortedInfoForDrop = function() return resolvedDropUnmatched() end
		lr:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENC_ID, LIST_ID)

		local count = 0
		for _ in pairs(lr._pendingActions) do count = count + 1 end
		assert.are.equal(0, count)
	end)
end)
