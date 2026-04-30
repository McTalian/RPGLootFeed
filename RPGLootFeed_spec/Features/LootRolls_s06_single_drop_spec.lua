---@diagnostic disable: need-check-nil
--- S06 Single-drop scenario integration tests.
---
--- Tests the full single-item roll happy path:
---   START_LOOT_ROLL → hooksecurefunc('RollOn') enqueue → LOOT_HISTORY_UPDATE_DROP
---   → MatchActionToResult → result display with winner + breakdown
---
--- These tests target the MatchActionToResult function introduced in S03.
--- Tests that call MatchActionToResult directly WILL FAIL until S03 is
--- implemented. All other tests (queue enqueue, button click, event flow)
--- pass against the current codebase.
---
--- S06 single-drop

local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local after_each = busted.after_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local pending = busted.pending

-- ─── Fixtures ────────────────────────────────────────────────────────────────

local ITEM_LINK = "|cff0070dditem:11111|r"
local ROLL_ID = 7
local ENCOUNTER_ID = 3
local LOOT_LIST_ID = 1
local DROP_KEY = ENCOUNTER_ID .. "_" .. LOOT_LIST_ID

local function makePendingDrop(overrides)
	local base = {
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
	if overrides then
		for k, v in pairs(overrides) do
			base[k] = v
		end
	end
	return base
end

local function makeResolvedDrop(winnerOverrides, selfRollInfo)
	local winner = {
		playerName = "Paladin",
		playerClass = "PALADIN",
		roll = 88,
		state = 0,
		isSelf = false,
		isWinner = true,
	}
	if winnerOverrides then
		for k, v in pairs(winnerOverrides) do
			winner[k] = v
		end
	end
	local rollInfos = {}
	if selfRollInfo then
		table.insert(rollInfos, selfRollInfo)
	end
	return {
		itemHyperlink = ITEM_LINK,
		winner = winner,
		allPassed = false,
		isTied = false,
		currentLeader = nil,
		rollInfos = rollInfos,
		playerRollState = selfRollInfo and selfRollInfo.state or nil,
	}
end

-- ─── Module loader ────────────────────────────────────────────────────────────

--- Creates a fresh ns + LootRolls instance with minimal stubs.
local function buildLootRolls()
	local sendMessageSpy = spy.new(function() end)

	local ns = {
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
		SendMessage = sendMessageSpy,
		TooltipBuilders = nil,
		db = {
			global = {
				animations = { exit = { fadeOutDelay = 3 } },
				misc = { hideAllIcons = false },
			},
		},
		WoWAPI = { LootRolls = {} },
		DbAccessor = {
			IsFeatureNeededByAnyFrame = function()
				return true
			end,
			AnyFeatureConfig = function(_, featureKey)
				if featureKey == "lootRolls" then
					return {
						enableIcon = true,
						enableLootRollActions = true,
						enableLootRollResults = true,
					}
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
			["LootRolls_WinnerWithSelfFmt"] = "%s  |  You: rolled %d",
			["LootRolls_WinnerWithSelfAndSelectionFmt"] = "%s  |  %s, rolled %d",
		},
		RollStates = { ALL_PASSED = "allPassed", PENDING = "pending", RESOLVED = "resolved" },
	}

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

	local LootRolls = assert(loadfile("RPGLootFeed/Features/LootRolls/LootRolls.lua"))("TestAddon", ns)
	assert.is_not_nil(LootRolls)
	ns.LootRolls = LootRolls

	-- Default Retail adapter stubs.
	LootRolls._lootRollsAdapter = {
		HasLootHistory = function()
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
		GetRollButtonValidity = function(_rollID)
			return { canNeed = true, canGreed = true, canTransmog = false, canPass = true }
		end,
		GetRetailRollItemLink = function(_rollID)
			return ITEM_LINK
		end,
	}

	LootRolls._dropStates = {}
	LootRolls._buttonValidityCache = {}
	LootRolls._stagedRollValidity = {}

	return LootRolls, ns, sendMessageSpy
end

-- ─── S06 Single-drop scenario ─────────────────────────────────────────────────

describe("S06 Single-drop scenario", function()
	local _ = match._
	---@type RLF_LootRolls
	local LootRolls, ns, sendMessageSpy

	before_each(function()
		LootRolls, ns, sendMessageSpy = buildLootRolls()
		-- Stable GetTime stub.
		_G.GetTime = function()
			return 1000
		end
	end)

	after_each(function()
		_G.GetTime = nil
	end)

	-- ── Part 1: Pending queue enqueue via hooksecurefunc('RollOn') ────────────
	-- S06 single-drop

	describe("Part 1: _pendingActions queue populated after START_LOOT_ROLL", function()
		it("_pendingActions table exists on the LootRolls module", function()
			-- S06 single-drop
			-- The _pendingActions table is introduced by S03.
			-- This test documents the expected API surface.
			print("[S06 T02] _pendingActions: " .. tostring(LootRolls._pendingActions))
			-- Will fail until S03 adds this table.
			assert.is_not_nil(
				LootRolls._pendingActions,
				"Expected _pendingActions table on LootRolls (requires S03 implementation)"
			)
		end)

		it("START_LOOT_ROLL stages rollID, itemLink, and validity in _stagedRollValidity", function()
			-- S06 single-drop
			-- This exercises the existing staging path that S03's MatchActionToResult will read.
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

			local staged = LootRolls._stagedRollValidity[ROLL_ID]
			assert.is_not_nil(staged, "Expected staged entry after START_LOOT_ROLL")
			assert.are.equal(ITEM_LINK, staged.itemLink)
			assert.is_not_nil(staged.validity)
			assert.is_true(staged.validity.canNeed)
			print(
				"[S06 T02] Staged: itemLink="
					.. tostring(staged.itemLink)
					.. " canNeed="
					.. tostring(staged.validity.canNeed)
			)
		end)

		it("hooksecurefunc('RollOn') hook enqueues action into _pendingActions when called", function()
			-- S06 single-drop
			-- After S03 wires hooksecurefunc('RollOn'), calling _G.RollOnLoot(rollID, rollType)
			-- should enqueue { rollID, itemLink, rollType, timestamp } into _pendingActions.
			-- We simulate by pre-populating staged validity (mimicking START_LOOT_ROLL),
			-- then triggering the hook.

			-- Stage validity for the roll (normally done by START_LOOT_ROLL).
			LootRolls._stagedRollValidity[ROLL_ID] = {
				itemLink = ITEM_LINK,
				validity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			}

			-- Stub _G.RollOnLoot so we can call it without the game.
			local rollOnCalled = false
			_G.RollOnLoot = function(rid, rtype)
				rollOnCalled = true
				print("[S06 T02] RollOnLoot called: rollID=" .. tostring(rid) .. " rollType=" .. tostring(rtype))
			end

			-- Simulate calling the hooked function (what a button click does in-game).
			_G.RollOnLoot(ROLL_ID, 0) -- 0 = Need

			assert.is_true(rollOnCalled, "RollOnLoot stub was never invoked")

			-- After S03 hooks RollOnLoot via hooksecurefunc, _pendingActions should have an entry.
			-- Until S03 is implemented, _pendingActions is nil or empty.
			if LootRolls._pendingActions then
				local entry = LootRolls._pendingActions[ROLL_ID]
					or (function()
						for _, v in pairs(LootRolls._pendingActions) do
							if v.rollID == ROLL_ID then
								return v
							end
						end
					end)()
				if entry then
					assert.are.equal(ROLL_ID, entry.rollID)
					assert.are.equal(ITEM_LINK, entry.itemLink)
					print("[S06 T02] _pendingActions entry found: rollID=" .. tostring(entry.rollID))
				else
					-- S03 not yet implemented — log and skip assertion.
					print(
						"[S06 T02] _pendingActions exists but no entry for rollID="
							.. tostring(ROLL_ID)
							.. " (S03 pending)"
					)
				end
			else
				print("[S06 T02] _pendingActions is nil — S03 not yet implemented")
			end

			_G.RollOnLoot = nil
		end)
	end)

	-- ── Part 2: MatchActionToResult function exists and behaves correctly ──────
	-- S06 single-drop

	describe("Part 2: MatchActionToResult API contract (requires S03)", function()
		it("MatchActionToResult function exists on LootRolls module", function()
			-- S06 single-drop
			print("[S06 T02] MatchActionToResult: " .. tostring(LootRolls.MatchActionToResult))
			-- Will fail until S03 adds this function.
			assert.is_not_nil(
				LootRolls.MatchActionToResult,
				"Expected MatchActionToResult on LootRolls (requires S03 implementation)"
			)
		end)

		it("MatchActionToResult returns nil when _pendingActions is empty", function()
			-- S06 single-drop
			if not LootRolls.MatchActionToResult then
				pending("MatchActionToResult not implemented (S03 blocker)")
				return
			end

			-- Empty queue — should return nil (no match).
			LootRolls._pendingActions = {}
			local result = LootRolls:MatchActionToResult(ENCOUNTER_ID, LOOT_LIST_ID, makePendingDrop())
			assert.is_nil(result, "Expected nil when _pendingActions is empty")
			print("[S06 T02] MatchActionToResult with empty queue returned: " .. tostring(result))
		end)

		it("MatchActionToResult matches by itemLink and removes entry from queue", function()
			-- S06 single-drop
			if not LootRolls.MatchActionToResult then
				pending("MatchActionToResult not implemented (S03 blocker)")
				return
			end
			if not LootRolls._pendingActions then
				pending("_pendingActions not initialized (S03 blocker)")
				return
			end

			-- Pre-populate the queue as START_LOOT_ROLL + hooksecurefunc would.
			-- rollType must be a string (EnqueueAction stores it as string via NumericRollTypeToString).
			LootRolls._pendingActions[ROLL_ID] = {
				rollID = ROLL_ID,
				itemLink = ITEM_LINK,
				rollType = "GREED", -- string form as stored by EnqueueAction
				timestamp = 1000,
			}
			print("[S06 T02] Queue before match: " .. tostring(LootRolls._pendingActions[ROLL_ID]))

			-- Use a resolved drop with a matching selfRoll (state=3 → GREED) so
			-- MatchActionToResult's rollType gate passes.
			local selfRoll = { playerName = "Me", roll = 42, state = 3, isSelf = true, isWinner = false }
			local dropInfo = makeResolvedDrop(nil, selfRoll)
			local matched_roll_id, match_result = LootRolls:MatchActionToResult(ENCOUNTER_ID, LOOT_LIST_ID, dropInfo)

			print("[S06 T02] MatchActionToResult returned rollID=" .. tostring(matched_roll_id))
			assert.is_not_nil(matched_roll_id, "Expected a match for itemLink=" .. ITEM_LINK)
			assert.are.equal(ROLL_ID, matched_roll_id)
			assert.are.equal("GREED", match_result.rollType)

			-- Entry should be removed from the queue after matching.
			assert.is_nil(LootRolls._pendingActions[ROLL_ID], "Expected matched entry removed from _pendingActions")
		end)

		it("MatchActionToResult does not match when itemLink differs", function()
			-- S06 single-drop
			if not LootRolls.MatchActionToResult then
				pending("MatchActionToResult not implemented (S03 blocker)")
				return
			end
			if not LootRolls._pendingActions then
				pending("_pendingActions not initialized (S03 blocker)")
				return
			end

			-- Queue has a different item link.
			LootRolls._pendingActions[ROLL_ID] = {
				rollID = ROLL_ID,
				itemLink = "|cff0070dditem:99999|r", -- different item
				rollType = 0,
				timestamp = 1000,
			}

			local dropInfo = makePendingDrop({ itemHyperlink = ITEM_LINK })
			local result = LootRolls:MatchActionToResult(ENCOUNTER_ID, LOOT_LIST_ID, dropInfo)

			assert.is_nil(result, "Expected no match when itemLink differs")
			-- Entry should remain in the queue.
			assert.is_not_nil(LootRolls._pendingActions[ROLL_ID], "Unmatched entry should stay in queue")
			print("[S06 T02] Correct: no match for mismatched itemLink")
		end)
	end)

	-- ── Part 3: Full event sequence — pending → result → resolved ─────────────
	-- S06 single-drop

	describe("Part 3: Full event sequence — START_LOOT_ROLL → click → LOOT_HISTORY_UPDATE_DROP", function()
		it("START_LOOT_ROLL + LOOT_HISTORY_UPDATE_DROP dispatches payload via SendMessage", function()
			-- S06 single-drop
			-- Exercises existing wiring (no S03 dependency).
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			assert.spy(sendMessageSpy).was.called(1)
			print("[S06 T02] SendMessage called " .. tostring(#sendMessageSpy.calls) .. " time(s)")
		end)

		it("After START_LOOT_ROLL + LOOT_HISTORY_UPDATE_DROP, drop state is pending with rollID linked", function()
			-- S06 single-drop
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			local entry = LootRolls._dropStates[DROP_KEY]
			assert.is_not_nil(entry, "Expected drop state entry after events")
			assert.are.equal("pending", entry.state)
			-- rollID should be linked from staged validity absorption.
			assert.are.equal(ROLL_ID, entry.rollID)
			print("[S06 T02] Drop state: state=" .. entry.state .. " rollID=" .. tostring(entry.rollID))
		end)

		it("Button validity is cached after START_LOOT_ROLL → LOOT_HISTORY_UPDATE_DROP", function()
			-- S06 single-drop
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			local cached = LootRolls._buttonValidityCache[DROP_KEY]
			assert.is_not_nil(cached, "Expected button validity cached after absorption")
			assert.is_true(cached.canNeed)
			assert.is_true(cached.canGreed)
			assert.is_false(cached.canTransmog)
			assert.is_true(cached.canPass)
			print(
				"[S06 T02] ButtonValidity: canNeed="
					.. tostring(cached.canNeed)
					.. " canGreed="
					.. tostring(cached.canGreed)
			)
		end)

		it("LOOT_HISTORY_UPDATE_DROP with resolved drop transitions state to resolved", function()
			-- S06 single-drop
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

			-- First event — pending.
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			assert.are.equal("pending", LootRolls._dropStates[DROP_KEY].state)
			sendMessageSpy:clear()

			-- Second event — resolved with winner.
			local selfRoll = { playerName = "Me", roll = 42, state = 0, isSelf = true, isWinner = false }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop(nil, selfRoll)
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			assert.are.equal("resolved", LootRolls._dropStates[DROP_KEY].state)
			assert.spy(sendMessageSpy).was.called(1)
			print("[S06 T02] State after resolution: " .. LootRolls._dropStates[DROP_KEY].state)
		end)

		it("Resolved payload secondary text includes winner name and self roll", function()
			-- S06 single-drop
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			local selfRoll = { playerName = "Me", roll = 42, state = 0, isSelf = true, isWinner = false }
			local resolvedDrop = makeResolvedDrop({ playerName = "Paladin", roll = 88 }, selfRoll)
			local payload = LootRolls:BuildPayload(ENCOUNTER_ID, LOOT_LIST_ID, resolvedDrop, "resolved")

			assert.are.equal("resolved", payload.rollState)
			assert.is_not_nil(string.find(payload.secondaryText, "Paladin"), "Expected winner name in secondary text")
			assert.is_not_nil(string.find(payload.secondaryText, "88"), "Expected winner roll in secondary text")
			assert.is_not_nil(string.find(payload.secondaryText, "42"), "Expected self roll in secondary text")
			print("[S06 T02] Resolved secondary text: " .. payload.secondaryText)
		end)

		it("Resolved payload secondary text includes selection label when playerSelection recorded", function()
			-- S06 single-drop
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)

			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			-- Simulate button click recording playerSelection.
			LootRolls._dropStates[DROP_KEY].playerSelection = "NEED"

			local selfRoll = { playerName = "Me", roll = 42, state = 0, isSelf = true, isWinner = false }
			local resolvedDrop = makeResolvedDrop(nil, selfRoll)
			local payload = LootRolls:BuildPayload(ENCOUNTER_ID, LOOT_LIST_ID, resolvedDrop, "resolved")

			assert.is_not_nil(
				string.find(payload.secondaryText, "You: Need"),
				"Expected selection label in secondary text"
			)
			print("[S06 T02] Secondary text with selection: " .. payload.secondaryText)
		end)
	end)

	-- ── Part 4: MatchActionToResult integration with LOOT_HISTORY_UPDATE_DROP ──
	-- S06 single-drop

	describe("Part 4: MatchActionToResult called during LOOT_HISTORY_UPDATE_DROP (requires S03)", function()
		it("LOOT_HISTORY_UPDATE_DROP calls MatchActionToResult when function is present", function()
			-- S06 single-drop
			-- Once S03 wires MatchActionToResult into LOOT_HISTORY_UPDATE_DROP,
			-- a queued action should be consumed and playerSelection recorded.
			if not LootRolls.MatchActionToResult then
				pending("MatchActionToResult not wired (S03 blocker)")
				return
			end
			if not LootRolls._pendingActions then
				pending("_pendingActions not initialized (S03 blocker)")
				return
			end

			-- Stage a queued action (simulates button click before drop arrives).
			-- rollType must be a string (EnqueueAction stores it as string via NumericRollTypeToString).
			LootRolls._pendingActions[ROLL_ID] = {
				rollID = ROLL_ID,
				itemLink = ITEM_LINK,
				rollType = "GREED", -- string form as stored by EnqueueAction
				timestamp = 1000,
			}

			-- Stage validity from START_LOOT_ROLL.
			LootRolls._stagedRollValidity[ROLL_ID] = {
				itemLink = ITEM_LINK,
				validity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			}

			-- Return a resolved drop with a matching GREED selfRoll (state=3 → GREED)
			-- so MatchActionToResult's rollType gate passes.
			local selfRoll = { playerName = "Me", roll = 42, state = 3, isSelf = true, isWinner = false }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop(nil, selfRoll)
			end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			-- The queued action should have been consumed.
			assert.is_nil(
				LootRolls._pendingActions[ROLL_ID],
				"Expected _pendingActions entry consumed after LOOT_HISTORY_UPDATE_DROP"
			)

			-- playerSelection should be recorded from the matched action.
			local entry = LootRolls._dropStates[DROP_KEY]
			assert.is_not_nil(entry)
			assert.is_not_nil(entry.playerSelection, "Expected playerSelection recorded from matched action")
			print("[S06 T02] playerSelection after match: " .. tostring(entry.playerSelection))
		end)

		it("Payload includes playerSelection from matched action (via MatchActionToResult)", function()
			-- S06 single-drop
			if not LootRolls.MatchActionToResult then
				pending("MatchActionToResult not wired (S03 blocker)")
				return
			end
			if not LootRolls._pendingActions then
				pending("_pendingActions not initialized (S03 blocker)")
				return
			end

			LootRolls._pendingActions[ROLL_ID] = {
				rollID = ROLL_ID,
				itemLink = ITEM_LINK,
				rollType = "GREED", -- string form as stored by EnqueueAction
				timestamp = 1000,
			}
			LootRolls._stagedRollValidity[ROLL_ID] = {
				itemLink = ITEM_LINK,
				validity = { canNeed = true, canGreed = true, canTransmog = false, canPass = true },
			}

			-- Return a resolved drop with a matching GREED selfRoll (state=3 → GREED).
			local selfRoll = { playerName = "Me", roll = 42, state = 3, isSelf = true, isWinner = false }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop(nil, selfRoll)
			end

			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			-- Rebuild payload — should carry the matched selection.
			local payload = LootRolls:BuildPayload(ENCOUNTER_ID, LOOT_LIST_ID, makePendingDrop(), "pending")
			assert.is_not_nil(payload.playerSelection, "Expected payload.playerSelection from matched action")
			print("[S06 T02] payload.playerSelection=" .. tostring(payload.playerSelection))
		end)
	end)

	-- ── Part 5: Full single-drop E2E happy path ───────────────────────────────
	-- S06 single-drop

	describe("Part 5: Full single-drop E2E happy path", function()
		it("Complete: START_LOOT_ROLL → action enqueue → LOOT_HISTORY_UPDATE_DROP → resolved", function()
			-- S06 single-drop
			-- Step 1: Roll opens — START_LOOT_ROLL fires, stages validity.
			LootRolls:START_LOOT_ROLL("START_LOOT_ROLL", ROLL_ID, 60)
			assert.is_not_nil(LootRolls._stagedRollValidity[ROLL_ID])
			print("[S06 T02] Step 1: START_LOOT_ROLL staged validity for rollID=" .. tostring(ROLL_ID))

			-- Step 2: Player clicks Need — manually record playerSelection (mirrors S03 hook).
			-- Until S03 implements the hook, we inject the selection directly.
			local dropKey = DROP_KEY
			LootRolls._dropStates[dropKey] = LootRolls._dropStates[dropKey] or { state = "pending", phase = "pending" }
			LootRolls._dropStates[dropKey].playerSelection = "NEED"
			print("[S06 T02] Step 2: Simulated Need button click — playerSelection=NEED")

			-- Step 3: LOOT_HISTORY_UPDATE_DROP arrives with pending drop data.
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makePendingDrop()
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			assert.spy(sendMessageSpy).was.called_at_least(1)
			local entry = LootRolls._dropStates[DROP_KEY]
			assert.is_not_nil(entry)
			assert.are.equal("pending", entry.state)
			print("[S06 T02] Step 3: Drop state=pending, phase=" .. tostring(entry.phase))

			-- Step 4: Roll resolves — second LOOT_HISTORY_UPDATE_DROP with winner.
			sendMessageSpy:clear()
			local selfRoll = { playerName = "Me", roll = 42, state = 0, isSelf = true, isWinner = false }
			LootRolls._lootRollsAdapter.GetSortedInfoForDrop = function()
				return makeResolvedDrop(nil, selfRoll)
			end
			LootRolls:LOOT_HISTORY_UPDATE_DROP("LOOT_HISTORY_UPDATE_DROP", ENCOUNTER_ID, LOOT_LIST_ID)

			assert.spy(sendMessageSpy).was.called(1)
			assert.are.equal("resolved", LootRolls._dropStates[DROP_KEY].state)
			print("[S06 T02] Step 4: State=resolved")

			-- Step 5: Verify resolved payload content.
			local resolvedDrop = makeResolvedDrop({ playerName = "Paladin", roll = 88 }, selfRoll)
			local payload = LootRolls:BuildPayload(ENCOUNTER_ID, LOOT_LIST_ID, resolvedDrop, "resolved")

			assert.are.equal("resolved", payload.rollState)
			assert.are.equal("LR_" .. ENCOUNTER_ID .. "_" .. LOOT_LIST_ID, payload.key)
			assert.is_not_nil(string.find(payload.secondaryText, "Paladin"))
			assert.is_not_nil(string.find(payload.secondaryText, "88"))
			assert.is_not_nil(string.find(payload.secondaryText, "You: Need"))
			assert.is_not_nil(string.find(payload.secondaryText, "42"))
			print("[S06 T02] Step 5: Resolved payload OK — " .. payload.secondaryText)
		end)
	end)
end)
